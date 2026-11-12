import 'dart:async';
import 'package:media_kit/media_kit.dart';

abstract interface class EmergencyAlarmAudio {
  bool get isPlaying;
  Stream<bool> get playingChanges;

  /// Başarılı sonuç oynatıcının playing olayını gerektirir; sesi kişinin duyduğunu kanıtlamaz.
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// Web oynatıcısını kullanıcı etkileşiminde sessizce açar; alarm veya test sesi üretmez.
abstract interface class EmergencyAlarmAudioPreparation {
  Future<void> prepare();
}

class BundledEmergencyAlarmAudio
    implements EmergencyAlarmAudio, EmergencyAlarmAudioPreparation {
  Player? _player;
  final _changes = StreamController<bool>.broadcast();
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _failed = false;
  @override
  bool get isPlaying => !_failed && (_player?.state.playing ?? false);
  @override
  Stream<bool> get playingChanges => _changes.stream;
  @override
  Future<void> prepare() async {
    MediaKit.ensureInitialized();
    final player = _player ??= Player(
      configuration: const PlayerConfiguration(title: 'Site acil alarmı'),
    );
    await player.setVolume(0);
    try {
      await start();
      await stop();
    } finally {
      await player.setVolume(100);
    }
  }

  @override
  Future<void> start() async {
    MediaKit.ensureInitialized();
    final player = _player ??= Player(
      configuration: const PlayerConfiguration(title: 'Site acil alarmı'),
    );
    _playingSubscription ??= player.stream.playing.listen((value) {
      if (value) _failed = false;
      if (!_changes.isClosed) _changes.add(value);
    });
    _errorSubscription ??= player.stream.error.listen((_) {
      _failed = true;
      if (!_changes.isClosed) _changes.add(false);
    });
    if (isPlaying) return;
    if (_failed) {
      await player.stop();
      _failed = false;
    }
    final started = Completer<void>();
    final playing = player.stream.playing.listen((value) {
      if (value && !started.isCompleted) started.complete();
    });
    final errors = player.stream.error.listen((_) {
      if (!started.isCompleted) {
        started.completeError(StateError('Alarm sesi başlatılamadı.'));
      }
    });
    // Web play() hatası Future yerine error stream'e gelir. Dinleyiciler open'dan önce kurulur.
    // Future.wait hata dinleyicilerini open tamamlanmadan kurar; takılan open
    // işlenmemiş bir timeout Future'ı bırakmaz.
    try {
      await Future.wait<void>([
        () async {
          await player.setPlaylistMode(PlaylistMode.single);
          await player.open(Media('asset:///assets/audio/emergency_alarm.wav'));
        }(),
        started.future.timeout(const Duration(seconds: 5)),
      ], eagerError: true);
    } catch (_) {
      await player.stop();
      rethrow;
    } finally {
      await playing.cancel();
      await errors.cancel();
    }
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    await _playingSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _player?.dispose();
    _player = null;
    await _changes.close();
  }
}
