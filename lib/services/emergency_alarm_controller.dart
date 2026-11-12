import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/services/emergency_alarm_audio.dart';

/// Her platformda oturum boyunca çalışır; site menüsüne ya da sakin moduna bağlı değildir.
/// Kapalı uygulama için arka plan hizmeti değildir. Başarısız ağ kontrolü görünür kalır.
class EmergencyAlarmController extends ChangeNotifier {
  EmergencyAlarmController({
    required this.authService,
    required this.service,
    required this.audio,
    bool? soundInitiallyEnabled,
    this.pollInterval = const Duration(seconds: 5),
  }) : soundEnabled = soundInitiallyEnabled ?? !kIsWeb;
  final AuthService authService;
  final EmergencyService service;
  final EmergencyAlarmAudio audio;
  final Duration pollInterval;
  EmergencyAlarmFeed feed = const EmergencyAlarmFeed();
  String? error;
  String? soundError;
  bool soundEnabled;
  bool playing = false;
  bool _disposed = false,
      _started = false,
      _fetching = false,
      _testSound = false;
  int _generation = 0, _audioRevision = 0;
  int _failures = 0;
  String? _authScope;
  String? get _currentAuthScope {
    final session = authService.session;
    return session == null
        ? null
        : '${session.id}:${session.role.name}:${session.isActive}:${session.mustChangePassword}:${session.token}';
  }

  Timer? _timer, _testTimer;
  Future<void> _audioQueue = Future.value();
  final Set<int> _received = {}, _played = {};
  // Başarılı kişisel ACK, o sırada yoldaki eski GET ile geri alınamaz.
  final Set<int> _acknowledgedIds = {};
  final Set<int> _receivedInFlight = {}, _playedInFlight = {};
  StreamSubscription<bool>? _audioChanges;
  bool _startingAudio = false, _stoppingAudio = false;
  Future<void>? _refreshInFlight;
  bool get canReceive => feed.canReceive;
  bool get canSound => feed.canReceive && feed.canSound;
  List<EmergencyAlarm> get alarms => feed.canReceive ? feed.alarms : const [];
  bool get _eligible =>
      authService.session != null &&
      authService.session!.role != UserRole.superUser;
  bool get _wantsSound =>
      canSound &&
      soundEnabled &&
      (_testSound || alarms.any((a) => a.soundEnabled));

  void start() {
    if (_started) return;
    _started = true;
    _authScope = _currentAuthScope;
    authService.addListener(_onAuth);
    _audioChanges = audio.playingChanges.listen((value) {
      if (_disposed) return;
      if (!value) {
        playing = false;
        if (_wantsSound && !_startingAudio && !_stoppingAudio) {
          soundError = 'Oynatıcı durdu; alarm sesi yeniden başlatılıyor.';
          unawaited(_syncAudio());
        }
      }
      _notify();
    });
    unawaited(refresh());
  }

  void _onAuth() {
    if (_authScope == _currentAuthScope && _eligible) return;
    _authScope = _currentAuthScope;
    ++_generation;
    _fetching = false;
    _timer?.cancel();
    _testTimer?.cancel();
    feed = const EmergencyAlarmFeed();
    _testSound = false;
    error = null;
    _received.clear();
    _played.clear();
    _acknowledgedIds.clear();
    _receivedInFlight.clear();
    _playedInFlight.clear();
    _notify();
    unawaited(_syncAudio());
    if (_eligible) unawaited(refresh());
  }

  Future<void> refresh() {
    if (_disposed || _fetching || !_eligible) return Future<void>.value();
    final result = _refreshNow();
    _refreshInFlight = result;
    return result;
  }

  /// A push may arrive while an older feed is still in flight. Wait for it and
  /// fetch once more; the push body itself never grants access to an alarm.
  Future<void> refreshFromPush() async {
    final scope = _currentAuthScope;
    if (_fetching) await _refreshInFlight;
    if (_disposed || scope != _currentAuthScope) return;
    await refresh();
  }

  Future<void> _refreshNow() async {
    if (_disposed || _fetching || !_eligible) return;
    _timer?.cancel();
    _fetching = true;
    final generation = _generation;
    try {
      final next = await service.alarmFeed();
      if (_disposed || generation != _generation) return;
      feed = EmergencyAlarmFeed(
        alarms: next.alarms
            .where((alarm) => !_acknowledgedIds.contains(alarm.id))
            .toList(),
        canReceive: next.canReceive,
        canSound: next.canSound,
      );
      error = null;
      _failures = 0;
      for (final alarm in alarms) {
        _report(alarm.id, played: false);
      }
      _notify();
      await _syncAudio();
    } catch (e) {
      if (!_disposed && generation == _generation) {
        if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
          feed = const EmergencyAlarmFeed();
          _testSound = false;
          await _syncAudio();
        }
        _failures++;
        error =
            'Alarm bağlantısı doğrulanamıyor. Son alınan kayıtlar korunuyor; yenileyin.';
        _notify();
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _fetching = false;
        _timer = Timer(
          error != null
              ? Duration(
                  seconds: const [
                    5,
                    10,
                    20,
                    40,
                    60,
                  ][(_failures - 1).clamp(0, 4)],
                )
              : canReceive
              ? pollInterval
              : const Duration(minutes: 1),
          () => unawaited(refresh()),
        );
      }
    }
  }

  void _report(int id, {required bool played}) {
    final done = played ? _played : _received;
    final inFlight = played ? _playedInFlight : _receivedInFlight;
    if (done.contains(id) || !inFlight.add(id)) return;
    final generation = _generation;
    unawaited(() async {
      try {
        if (played) {
          await service.noteAlarmPlayed(id);
        } else {
          await service.noteAlarmReceived(id);
        }
        if (!_disposed && generation == _generation) done.add(id);
      } catch (_) {
        /* Sonraki feed turunda yeniden denenir; alarm akışı engellenmez. */
      } finally {
        if (generation == _generation) inFlight.remove(id);
      }
    }());
  }

  Future<void> enableAndTestSound() async {
    if (!canSound) return;
    soundEnabled = true;
    soundError = null;
    _testSound = true;
    _testTimer?.cancel();
    _notify();
    await _syncAudio();
    if (_disposed) return;
    _testTimer = Timer(const Duration(seconds: 2), () {
      _testSound = false;
      unawaited(_syncAudio());
    });
  }

  /// SOS etkileşimi yalnız gerçek alarmların sesini açar; deneme alarmı üretmez.
  Future<void> enableSound() async {
    if (!canSound) return;
    soundEnabled = true;
    soundError = null;
    _testSound = false;
    _testTimer?.cancel();
    _notify();
    await _syncAudio(prepare: kIsWeb);
  }

  Future<void> muteHere() async {
    soundEnabled = false;
    _testSound = false;
    _testTimer?.cancel();
    _notify();
    await _syncAudio();
  }

  Future<void> acknowledge(int id) async {
    final generation = _generation;
    await service.acknowledgeAlarm(id);
    if (_disposed || generation != _generation) return;
    _acknowledgedIds.add(id);
    _testSound = false;
    _testTimer?.cancel();
    feed = EmergencyAlarmFeed(
      alarms: alarms.where((a) => a.id != id).toList(),
      canReceive: canReceive,
      canSound: canSound,
    );
    _notify();
    await _syncAudio();
    await refresh();
  }

  Future<void> _syncAudio({bool prepare = false}) {
    final revision = ++_audioRevision;
    _audioQueue = _audioQueue
        .then((_) async {
          if (revision != _audioRevision) return;
          if (prepare &&
              !_disposed &&
              canSound &&
              soundEnabled &&
              alarms.isEmpty &&
              audio is EmergencyAlarmAudioPreparation) {
            try {
              await (audio as EmergencyAlarmAudioPreparation).prepare();
            } catch (_) {
              soundEnabled = false;
              soundError =
                  'Ses izni açılamadı. SOS simgesine yeniden dokunun; cihaz sesini ve tarayıcı izinlerini kontrol edin.';
            }
            if (_disposed || revision != _audioRevision) {
              await audio.stop();
              return;
            }
          }
          if (_disposed || !_wantsSound) {
            _stoppingAudio = true;
            try {
              await audio.stop();
            } finally {
              _stoppingAudio = false;
            }
            playing = false;
            _notify();
            return;
          }
          try {
            _startingAudio = true;
            try {
              if (!playing || !audio.isPlaying) await audio.start();
            } finally {
              _startingAudio = false;
            }
            if (_disposed || revision != _audioRevision) {
              await audio.stop();
              playing = false;
              return;
            }
            if (!audio.isPlaying) throw StateError('Oynatıcı durdu.');
            playing = true;
            soundError = null;
            for (final alarm in alarms.where((a) => a.soundEnabled)) {
              _report(alarm.id, played: true);
            }
          } catch (_) {
            playing = false;
            soundEnabled = false;
            _testSound = false;
            soundError =
                'Ses başlatılamadı. SOS simgesine dokunun; cihaz sesini ve tarayıcı izinlerini kontrol edin.';
          }
          _notify();
        })
        .catchError((_) {
          if (!_disposed) {
            playing = false;
            soundEnabled = false;
            soundError = 'Alarm sesi kullanılamıyor.';
            _notify();
          }
        });
    return _audioQueue;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    ++_audioRevision;
    _timer?.cancel();
    _testTimer?.cancel();
    authService.removeListener(_onAuth);
    unawaited(_audioChanges?.cancel());
    unawaited(
      _audioQueue.then((_) async {
        await audio.stop();
        await audio.dispose();
      }),
    );
    super.dispose();
  }
}
