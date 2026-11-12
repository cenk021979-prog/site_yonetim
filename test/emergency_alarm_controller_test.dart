import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/emergency_alarm_audio.dart';
import 'package:site_kapi_kontrol/services/emergency_alarm_controller.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'screens/people_fixtures.dart';

class FakeAlarmAudio implements EmergencyAlarmAudio {
  final events = StreamController<bool>.broadcast(sync: true);
  int starts = 0, stops = 0;
  bool playing = false, fail = false;
  @override
  bool get isPlaying => playing;
  @override
  Stream<bool> get playingChanges => events.stream;
  @override
  Future<void> start() async {
    starts++;
    if (fail) throw StateError('blocked');
    playing = true;
    events.add(true);
  }

  @override
  Future<void> stop() async {
    stops++;
    playing = false;
    events.add(false);
  }

  @override
  Future<void> dispose() async {
    await events.close();
  }

  void unexpectedStop() {
    playing = false;
    events.add(false);
  }
}

class FakeAlarmFeedService extends EmergencyService {
  FakeAlarmFeedService() : super(authService: PeopleFakeAuth());
  EmergencyAlarmFeed feed = const EmergencyAlarmFeed();
  int played = 0, received = 0, acknowledgements = 0;
  bool receivedFail = false, playedFail = false;
  Object? feedError;
  Completer<EmergencyAlarmFeed>? feedGate;
  Completer<void>? ackGate;
  bool mutateOnAck = true;
  @override
  Future<EmergencyAlarmFeed> alarmFeed() async {
    if (feedError != null) throw feedError!;
    return feedGate?.future ?? feed;
  }

  @override
  Future<void> noteAlarmReceived(int id) async {
    received++;
    if (receivedFail) throw StateError('offline');
  }

  @override
  Future<void> noteAlarmPlayed(int id) async {
    played++;
    if (playedFail) throw StateError('offline');
  }

  @override
  Future<void> acknowledgeAlarm(int id) async {
    await ackGate?.future;
    acknowledgements++;
    if (mutateOnAck) {
      feed = EmergencyAlarmFeed(
        canReceive: feed.canReceive,
        canSound: feed.canSound,
      );
    }
  }
}

class _MutableAlarmAuth extends PeopleFakeAuth {
  UserSession value = pplSession(UserRole.apartmentOwner);
  @override
  UserSession get session => value;
  void replace(UserSession next) {
    value = next;
    notifyListeners();
  }
}

EmergencyAlarmFeed alarmFeed({bool sound = true}) => EmergencyAlarmFeed(
  canReceive: true,
  canSound: sound,
  alarms: [
    EmergencyAlarm(
      id: 1,
      siteCode: 11,
      kind: 'elevator',
      equipmentName: 'A Blok',
      soundEnabled: sound,
    ),
  ],
);

void main() {
  testWidgets(
    'eski GET yanıtı başarılı ACKi geri alamaz; diğer kayıt ve yetki bayrakları korunur',
    (t) async {
      final service = FakeAlarmFeedService()..feed = alarmFeed();
      final audio = FakeAlarmAudio();
      final controller = EmergencyAlarmController(
        authService: service.authService,
        service: service,
        audio: audio,
      );
      controller.start();
      await t.pump();
      expect(audio.starts, 1);
      service.feedGate = Completer<EmergencyAlarmFeed>();
      final oldGet = controller.refresh();
      await t.pump();
      await controller.acknowledge(1);
      expect(controller.alarms, isEmpty);
      expect(audio.isPlaying, isFalse);
      service.feedGate!.complete(
        const EmergencyAlarmFeed(
          canReceive: true,
          canSound: true,
          alarms: [
            EmergencyAlarm(
              id: 1,
              siteCode: 11,
              kind: 'elevator',
              soundEnabled: true,
            ),
            EmergencyAlarm(
              id: 2,
              siteCode: 22,
              kind: 'fire',
              soundEnabled: false,
            ),
          ],
        ),
      );
      await oldGet;
      await t.pump();
      expect(controller.alarms.map((a) => a.id), [2]);
      expect(controller.canSound, isTrue);
      expect(audio.starts, 1);
      expect(audio.isPlaying, isFalse);
      service.feedGate = null;
      service.feed = const EmergencyAlarmFeed();
      await controller.refresh();
      expect(controller.canReceive, isFalse);
      expect(controller.canSound, isFalse);
      expect(controller.alarms, isEmpty);
      controller.dispose();
      await t.pump();
    },
  );
  testWidgets('403 yetki iptalinde eski kayıt ve ses bırakılmaz', (t) async {
    final service = FakeAlarmFeedService()..feed = alarmFeed();
    final audio = FakeAlarmAudio();
    final controller = EmergencyAlarmController(
      authService: service.authService,
      service: service,
      audio: audio,
    );
    controller.start();
    await t.pump();
    expect(controller.playing, isTrue);
    service.feedError = ApiException('Yetki kaldırıldı.', statusCode: 403);
    await controller.refresh();
    await t.pump();
    expect(controller.alarms, isEmpty);
    expect(controller.canSound, isFalse);
    expect(audio.isPlaying, isFalse);
    controller.dispose();
    await t.pump();
  });
  testWidgets(
    'aynı kullanıcı token/rol değişiminde eski ACK yanıtı yeni feedi silemez',
    (t) async {
      final auth = _MutableAlarmAuth();
      final service = FakeAlarmFeedService()
        ..feed = alarmFeed()
        ..ackGate = Completer<void>()
        ..mutateOnAck = false;
      final audio = FakeAlarmAudio();
      final controller = EmergencyAlarmController(
        authService: auth,
        service: service,
        audio: audio,
      );
      controller.start();
      await t.pump();
      final oldAck = controller.acknowledge(1);
      service.feed = const EmergencyAlarmFeed(
        canReceive: true,
        canSound: false,
        alarms: [EmergencyAlarm(id: 1, siteCode: 22, kind: 'fire')],
      );
      auth.replace(
        auth.value.copyWith(token: 'new-token', role: UserRole.siteManager),
      );
      await t.pump();
      service.ackGate!.complete();
      await oldAck;
      await t.pump();
      expect(controller.alarms.single.siteCode, 22);
      expect(controller.canSound, isFalse);
      expect(audio.isPlaying, isFalse);
      controller.dispose();
      await t.pump();
    },
  );
  testWidgets(
    'ilk bağlantı hatası görünür; beş saniye sonra kurtarır ve yetki gelmeden ses yok',
    (t) async {
      final service = FakeAlarmFeedService()
        ..feedError = StateError('offline')
        ..feed = alarmFeed();
      final audio = FakeAlarmAudio();
      final controller = EmergencyAlarmController(
        authService: service.authService,
        service: service,
        audio: audio,
      );
      controller.start();
      await t.pump();
      expect(controller.error, isNotNull);
      expect(controller.canReceive, isFalse);
      expect(audio.starts, 0);
      service.feedError = null;
      await t.pump(const Duration(seconds: 5));
      await t.pump();
      expect(controller.canReceive, isTrue);
      expect(controller.error, isNull);
      expect(audio.starts, 1);
      controller.dispose();
      await t.pump();
    },
  );
  testWidgets('yönetici yalnız görsel bildirim; ses ve played yok', (t) async {
    final service = FakeAlarmFeedService()..feed = alarmFeed(sound: false);
    final audio = FakeAlarmAudio();
    final controller = EmergencyAlarmController(
      authService: service.authService,
      service: service,
      audio: audio,
    );
    controller.start();
    await t.pump();
    expect(controller.alarms.length, 1);
    expect(audio.starts, 0);
    expect(service.played, 0);
    expect(service.received, 1);
    controller.dispose();
    await t.pump();
  });
  testWidgets(
    'web ses kapalıyken görsel alarm var, played yok; etkileşimle ses açılır',
    (t) async {
      final service = FakeAlarmFeedService()..feed = alarmFeed();
      final audio = FakeAlarmAudio();
      final controller = EmergencyAlarmController(
        authService: service.authService,
        service: service,
        audio: audio,
        soundInitiallyEnabled: false,
      );
      controller.start();
      await t.pump();
      expect(controller.alarms.length, 1);
      expect(audio.starts, 0);
      expect(service.played, 0);
      await controller.enableAndTestSound();
      await t.pump();
      expect(controller.playing, isTrue);
      expect(service.played, 1);
      await controller.refresh();
      expect(service.played, 1);
      expect(audio.starts, 1);
      await controller.acknowledge(1);
      await t.pump(const Duration(seconds: 3));
      expect(controller.alarms, isEmpty);
      expect(controller.playing, isFalse);
      controller.dispose();
      await t.pump();
    },
  );
  testWidgets('SOS boşta ses üretmez; gelen gerçek alarmı çalar', (t) async {
    final service = FakeAlarmFeedService()
      ..feed = const EmergencyAlarmFeed(canReceive: true, canSound: true);
    final audio = FakeAlarmAudio();
    final controller = EmergencyAlarmController(
      authService: service.authService,
      service: service,
      audio: audio,
      soundInitiallyEnabled: false,
    );
    controller.start();
    await t.pump();
    await controller.enableSound();
    expect(audio.starts, 0);
    expect(service.played, 0);
    service.feed = alarmFeed();
    await controller.refresh();
    await t.pump();
    expect(audio.starts, 1);
    expect(service.played, 1);
    controller.dispose();
    await t.pump();
  });
  testWidgets('ses engeli başarı diye raporlanmaz; tekrar sına ile düzelir', (
    t,
  ) async {
    final service = FakeAlarmFeedService()..feed = alarmFeed();
    final audio = FakeAlarmAudio()..fail = true;
    final controller = EmergencyAlarmController(
      authService: service.authService,
      service: service,
      audio: audio,
    );
    controller.start();
    await t.pump();
    expect(controller.playing, isFalse);
    expect(controller.soundEnabled, isFalse);
    expect(controller.soundError, isNotNull);
    expect(service.played, 0);
    audio.fail = false;
    await controller.enableAndTestSound();
    await t.pump();
    expect(controller.playing, isTrue);
    expect(service.played, 1);
    controller.dispose();
    await t.pump();
  });
  testWidgets(
    'oynatıcı sonradan durursa yeniden başlar; başarısız teslim izleri sonraki turda denenir',
    (t) async {
      final service = FakeAlarmFeedService()
        ..feed = alarmFeed()
        ..receivedFail = true
        ..playedFail = true;
      final audio = FakeAlarmAudio();
      final controller = EmergencyAlarmController(
        authService: service.authService,
        service: service,
        audio: audio,
      );
      controller.start();
      await t.pump();
      expect(audio.starts, 1);
      service.receivedFail = false;
      service.playedFail = false;
      await controller.refresh();
      await t.pump();
      expect(service.received, 2);
      expect(service.played, 2);
      audio.unexpectedStop();
      await t.pump();
      expect(audio.starts, 2);
      expect(controller.playing, isTrue);
      controller.dispose();
      await t.pump();
    },
  );
}
