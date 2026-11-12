import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/views/emergency_view.dart';
import 'people_fixtures.dart';

class AlarmFakeService extends EmergencyService {
  AlarmFakeService() : super(authService: PeopleFakeAuth());
  List<EmergencySite> sites = const [
    EmergencySite(siteCode: 11, siteName: 'Gül Sitesi', canCreate: true),
  ];
  List<EmergencyElevator> elevators = const [
    EmergencyElevator(
      id: 71,
      name: 'A Blok Asansörü',
      location: 'A Blok giriş',
    ),
  ];
  List<EmergencyLocation> locations = const [
    EmergencyLocation(id: 'site', name: 'Ortak alan'),
    EmergencyLocation(id: 'block:34', name: 'A Blok'),
    EmergencyLocation(id: 'block:35', name: 'B Blok'),
  ];
  final List<
    ({int site, String kind, int? equipment, String? location, String key})
  >
  requests = [];
  Object? failure;
  Completer<void>? gate;
  Completer<List<EmergencyLocation>>? locationGate;
  Completer<List<EmergencyElevator>>? elevatorGate;
  Object? elevatorFailure;
  int locationCalls = 0;
  @override
  Future<List<EmergencySite>> listAlarmSites() async => sites;
  @override
  Future<List<EmergencyElevator>> listElevators(int siteCode) async {
    if (elevatorFailure != null) throw elevatorFailure!;
    return elevatorGate?.future ?? elevators;
  }

  @override
  Future<List<EmergencyLocation>> listLocations(int siteCode) async {
    locationCalls++;
    return locationGate?.future ?? locations;
  }

  @override
  Future<EmergencyAlarmReceipt> createAlarm({
    required int siteCode,
    required String kind,
    int? equipmentId,
    String? locationId,
    required String idempotencyKey,
  }) async {
    requests.add((
      site: siteCode,
      kind: kind,
      equipment: equipmentId,
      location: locationId,
      key: idempotencyKey,
    ));
    await gate?.future;
    if (failure != null) throw failure!;
    return EmergencyAlarmReceipt(
      alarm: EmergencyAlarm(id: 81, siteCode: siteCode, kind: kind),
      securityAssigned: 1,
      managerNotified: 1,
    );
  }
}

const boundaryKey = ValueKey('emergency_test_render');
Future<void> loadAlarmReviewFont() async {
  final loader = FontLoader('ReviewRoboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

ThemeData alarmReviewTheme(bool dark) {
  final base = dark ? AppTheme.dark() : AppTheme.light();
  ButtonStyle? withFont(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => (style.textStyle?.resolve(states) ?? const TextStyle())
          .copyWith(fontFamily: 'ReviewRoboto'),
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'ReviewRoboto'),
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF8FAFC),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'ReviewRoboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: withFont(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: withFont(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: withFont(base.textButtonTheme.style),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      titleTextStyle: base.dialogTheme.titleTextStyle?.copyWith(
        fontFamily: 'ReviewRoboto',
      ),
    ),
  );
}

Future<void> pumpAlarm(
  WidgetTester t,
  AlarmFakeService service, {
  double width = 400,
  double scale = 1,
  bool dark = false,
  int? preferredSiteCode,
}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: alarmReviewTheme(dark),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: alarmReviewTheme(dark).scaffoldBackgroundColor,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: EmergencyView(
                  authService: service.authService,
                  service: service,
                  preferredSiteCode: preferredSiteCode,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 250));
}

Future<void> renderProof(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('work/emergency-simple-2026-11-09');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadAlarmReviewFont);
  testWidgets(
    'kesin ret yeni seçime izin verir; belirsiz ağ sonucundan farklıdır',
    (t) async {
      final service = AlarmFakeService()
        ..failure = ApiException('Asansör kaldırıldı.', statusCode: 404);
      await pumpAlarm(t, service);
      await t.tap(find.text('Asansör'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('emergency_elevator_71')));
      await t.pump();
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const ValueKey('emergency_quick_fire')),
            )
            .onPressed,
        isNotNull,
      );
      service.failure = null;
      await t.tap(find.text('Yangın'));
      await t.pump();
      await t.ensureVisible(
        find.byKey(const ValueKey('emergency_location_site')),
      );
      await t.tap(find.byKey(const ValueKey('emergency_location_site')));
      await t.pump();
      await t.pump();
      expect(service.requests.last.location, 'site');
      expect(service.requests.last.key, isNot(service.requests.first.key));
    },
  );
  testWidgets(
    'yenilemede site kaldırılırsa eski konumlar ve geç gelen yanıt görünmez',
    (t) async {
      final service = AlarmFakeService()
        ..locationGate = Completer<List<EmergencyLocation>>();
      await pumpAlarm(t, service);
      await t.tap(find.text('Yangın'));
      await t.pump();
      service.sites = [];
      final state = t.state<EmergencyViewState>(find.byType(EmergencyView));
      await state.reload();
      await t.pump();
      service.locationGate!.complete(const [
        EmergencyLocation(id: 'block:34', name: 'ESKİ BLOK'),
      ]);
      await t.pump();
      expect(find.text('ESKİ BLOK'), findsNothing);
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const ValueKey('emergency_quick_fire')),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'yalnız iki düğme; 112 rehberi yok, asansör seçimi anında alarm',
    (t) async {
      final service = AlarmFakeService();
      await pumpAlarm(t, service);
      expect(find.text('Asansör'), findsOneWidget);
      expect(find.text('Yangın'), findsOneWidget);
      expect(find.textContaining('112'), findsNothing);
      await t.tap(find.byKey(const ValueKey('emergency_quick_elevator')));
      await t.pump();
      expect(service.requests, isEmpty);
      await t.tap(find.byKey(const ValueKey('emergency_elevator_71')));
      await t.pump();
      await t.pump();
      expect(service.requests.single.kind, 'elevator');
      expect(service.requests.single.equipment, 71);
      expect(find.text('Alarm #81 kaydedildi.'), findsOneWidget);
      expect(find.textContaining('duyduğu anlamına gelmez'), findsOneWidget);
    },
  );
  testWidgets('yangın önce konum; seçilen blok sunucuya gider', (t) async {
    final service = AlarmFakeService();
    await pumpAlarm(t, service);
    await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
    await t.pump();
    expect(service.requests, isEmpty);
    expect(find.text('Yangın nerede?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('emergency_location_block:34')));
    await t.pump();
    await t.pump();
    expect(service.requests.single.kind, 'fire');
    expect(service.requests.single.location, 'block:34');
  });
  testWidgets('hızlı çift seçimde tek POST, hata sonrası aynı anahtar', (
    t,
  ) async {
    final service = AlarmFakeService()
      ..gate = Completer<void>()
      ..failure = ApiException('Bağlantı kesildi.');
    await pumpAlarm(t, service);
    await t.tap(find.byKey(const ValueKey('emergency_quick_elevator')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('emergency_elevator_71')));
    await t.tap(find.byKey(const ValueKey('emergency_elevator_71')));
    await t.pump();
    expect(service.requests.length, 1);
    final key = service.requests.single.key;
    service.gate!.complete();
    await t.pump();
    expect(find.byKey(const ValueKey('emergency_receipt')), findsNothing);
    service.failure = null;
    service.gate = null;
    await t.ensureVisible(find.text('Tekrar dene'));
    await t.tap(find.text('Tekrar dene'));
    await t.pump();
    await t.pump();
    expect(service.requests.length, 2);
    expect(service.requests.last.key, key);
    expect(find.text('Alarm #81 kaydedildi.'), findsOneWidget);
  });
  testWidgets('asansör yoksa düğme gizlenir; eklenince yenilemede gelir', (
    t,
  ) async {
    final service = AlarmFakeService()..elevators = [];
    await pumpAlarm(t, service);
    expect(
      find.byKey(const ValueKey('emergency_quick_elevator')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('emergency_quick_fire')), findsOneWidget);
    service.elevators = const [EmergencyElevator(id: 72, name: 'Yeni asansör')];
    await t.state<EmergencyViewState>(find.byType(EmergencyView)).reload();
    await t.pump();
    expect(
      find.byKey(const ValueKey('emergency_quick_elevator')),
      findsOneWidget,
    );
    expect(service.requests, isEmpty);
  });
  testWidgets('asansör yüklemesi ve hatası yokmuş gibi yorumlanmaz', (t) async {
    final service = AlarmFakeService()
      ..elevatorGate = Completer<List<EmergencyElevator>>();
    await pumpAlarm(t, service);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(service.requests, isEmpty);
    service.elevatorGate!.completeError(
      ApiException('Asansör bağlantısı kesildi.'),
    );
    await t.pump();
    expect(find.text('Asansör bağlantısı kesildi.'), findsOneWidget);
    service.elevatorGate = null;
    await t.tap(find.text('Tekrar dene'));
    await t.pump();
    expect(
      find.byKey(const ValueKey('emergency_quick_elevator')),
      findsOneWidget,
    );
  });
  for (final onlyBlock in [false, true]) {
    testWidgets(
      '${onlyBlock ? 'tek blok' : 'bloksuz site'} yangını tek dokunuşla doğru kapsama gönderir',
      (t) async {
        final service = AlarmFakeService()
          ..locations = [
            const EmergencyLocation(id: 'site', name: 'Tüm site / Ortak alan'),
            if (onlyBlock)
              const EmergencyLocation(id: 'block:34', name: 'A Blok'),
          ];
        await pumpAlarm(t, service);
        expect(service.requests, isEmpty);
        await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
        await t.pump();
        await t.pump();
        expect(
          service.requests.single.location,
          onlyBlock ? 'block:34' : 'site',
        );
        expect(find.text('Yangın nerede?'), findsNothing);
        expect(find.byKey(const ValueKey('emergency_receipt')), findsOneWidget);
      },
    );
  }
  testWidgets(
    'yangın tıklaması taze blok sayısını kullanır; yenileme kendi kendine alarm üretmez',
    (t) async {
      final service = AlarmFakeService();
      await pumpAlarm(t, service);
      await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
      await t.pump();
      expect(find.text('Yangın nerede?'), findsOneWidget);
      expect(service.requests, isEmpty);
      service.locations = const [
        EmergencyLocation(id: 'block:34', name: 'A Blok'),
      ];
      await t.state<EmergencyViewState>(find.byType(EmergencyView)).reload();
      await t.pump();
      expect(
        service.requests,
        isEmpty,
        reason: 'Yalnız kullanıcının Yangın dokunuşu alarm başlatır.',
      );
      await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
      await t.pump();
      await t.pump();
      expect(service.requests.single.location, 'block:34');
    },
  );
  testWidgets(
    'tek blok yangın çift dokunma ve belirsiz ağda ikinci alarm üretmez',
    (t) async {
      final service = AlarmFakeService()
        ..locations = const [EmergencyLocation(id: 'block:34', name: 'A Blok')]
        ..locationGate = Completer<List<EmergencyLocation>>()
        ..failure = ApiException('Bağlantı kesildi.');
      await pumpAlarm(t, service);
      final fire = find.byKey(const ValueKey('emergency_quick_fire'));
      await t.tap(fire);
      await t.tap(fire);
      expect(service.locationCalls, 1);
      service.locationGate!.complete(service.locations);
      await t.pump();
      await t.pump();
      expect(service.requests.length, 1);
      final key = service.requests.single.key;
      service.failure = null;
      await t.ensureVisible(find.text('Tekrar dene'));
      await t.tap(find.text('Tekrar dene'));
      await t.pump();
      await t.pump();
      expect(service.requests.length, 2);
      expect(service.requests.last.key, key);
      expect(service.requests.last.location, 'block:34');
    },
  );
  testWidgets('boş konum cevabı site geneli yangın alarmına dönüşmez', (
    t,
  ) async {
    final service = AlarmFakeService()..locations = [];
    await pumpAlarm(t, service);
    await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
    await t.pump();
    expect(service.requests, isEmpty);
    expect(find.textContaining('Yangın konumu doğrulanamadı'), findsOneWidget);
  });
  testWidgets(
    'Yangın beklerken Asansör seçimi eski otomatik alarm niyetini iptal eder',
    (t) async {
      final service = AlarmFakeService()
        ..locationGate = Completer<List<EmergencyLocation>>();
      await pumpAlarm(t, service);
      await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('emergency_quick_elevator')));
      await t.pump();
      service.locationGate!.complete(const [
        EmergencyLocation(id: 'block:34', name: 'GECİKMİŞ'),
      ]);
      await t.pump();
      expect(service.requests, isEmpty);
      expect(find.text('GECİKMİŞ'), findsNothing);
      expect(
        find.byKey(const ValueKey('emergency_elevator_71')),
        findsOneWidget,
      );
    },
  );
  testWidgets('Yangın beklerken yenileme eski tekblok yanıtını alarm yapmaz', (
    t,
  ) async {
    final service = AlarmFakeService()
      ..locationGate = Completer<List<EmergencyLocation>>();
    await pumpAlarm(t, service);
    await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
    await t.pump();
    await t.state<EmergencyViewState>(find.byType(EmergencyView)).reload();
    service.locationGate!.complete(const [
      EmergencyLocation(id: 'block:34', name: 'GECİKMİŞ'),
    ]);
    await t.pump();
    expect(service.requests, isEmpty);
    expect(find.text('GECİKMİŞ'), findsNothing);
  });
  testWidgets(
    'tercih edilen site değişirse önceki tekblok yanıtı gönderilmez',
    (t) async {
      final service = AlarmFakeService()
        ..sites = const [
          EmergencySite(siteCode: 11, siteName: 'A', canCreate: true),
          EmergencySite(siteCode: 22, siteName: 'B', canCreate: true),
        ]
        ..locationGate = Completer<List<EmergencyLocation>>();
      await pumpAlarm(t, service, preferredSiteCode: 11);
      await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
      await t.pump();
      await pumpAlarm(t, service, preferredSiteCode: 22);
      service.locationGate!.complete(const [
        EmergencyLocation(id: 'block:34', name: 'GECİKMİŞ A'),
      ]);
      await t.pump();
      expect(service.requests, isEmpty);
      expect(find.text('GECİKMİŞ A'), findsNothing);
    },
  );
  testWidgets(
    'belirsiz alarm sonucunda tercih edilen site değişse de tekrar aynı payload ve anahtarı korur',
    (t) async {
      final service = AlarmFakeService()
        ..sites = const [
          EmergencySite(siteCode: 11, siteName: 'A', canCreate: true),
          EmergencySite(siteCode: 22, siteName: 'B', canCreate: true),
        ]
        ..locations = const [EmergencyLocation(id: 'block:34', name: 'A Blok')]
        ..failure = ApiException('Belirsiz ağ sonucu');
      await pumpAlarm(t, service, preferredSiteCode: 11);
      await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
      await t.pump();
      await t.pump();
      final first = service.requests.single;
      await pumpAlarm(t, service, preferredSiteCode: 22);
      service.failure = null;
      await t.ensureVisible(find.text('Tekrar dene'));
      await t.tap(find.text('Tekrar dene'));
      await t.pump();
      await t.pump();
      expect(service.requests.last, first);
    },
  );
  testWidgets('gerçek sakin yetkisi yoksa düğmeler pasif', (t) async {
    final service = AlarmFakeService()
      ..sites = const [
        EmergencySite(siteCode: 11, siteName: 'Gül', canCreate: false),
      ];
    await pumpAlarm(t, service);
    expect(
      t
          .widget<FilledButton>(
            find.byKey(const ValueKey('emergency_quick_fire')),
          )
          .onPressed,
      isNull,
    );
  });
  for (final dark in [false, true]) {
    for (final oneBlock in [false, true]) {
      testWidgets(
        '320px yazı2 ${dark ? 'koyu' : 'açık'} asansörsüz ${oneBlock ? 'tek blok' : 'bloksuz'} sade yangın',
        (t) async {
          final service = AlarmFakeService()
            ..elevators = []
            ..locations = [
              const EmergencyLocation(
                id: 'site',
                name: 'Tüm site / Ortak alan',
              ),
              if (oneBlock)
                const EmergencyLocation(id: 'block:34', name: 'A Blok'),
            ];
          await pumpAlarm(t, service, width: 320, scale: 2, dark: dark);
          expect(find.text('Asansör'), findsNothing);
          expect(t.takeException(), isNull);
          final suffix =
              '${oneBlock ? 'tekblok' : 'bloksuz'}-${dark ? 'koyu' : 'acik'}';
          await renderProof(t, 'asansor-yok-$suffix-320');
          await t.tap(find.byKey(const ValueKey('emergency_quick_fire')));
          await t.pump();
          await t.pump();
          expect(
            service.requests.single.location,
            oneBlock ? 'block:34' : 'site',
          );
          expect(find.text('Yangın nerede?'), findsNothing);
          expect(t.takeException(), isNull);
          await renderProof(t, 'yangin-direkt-$suffix-320');
        },
      );
    }
    testWidgets(
      '320px yazı2 ${dark ? 'koyu' : 'açık'} iki düğme ve konum taşmaz',
      (t) async {
        final service = AlarmFakeService();
        await pumpAlarm(t, service, width: 320, scale: 2, dark: dark);
        expect(t.takeException(), isNull);
        await renderProof(t, 'acil-320-${dark ? 'koyu' : 'acik'}');
        final fire = find.byKey(const ValueKey('emergency_quick_fire'));
        await t.ensureVisible(fire);
        await t.tap(fire);
        await t.pump();
        expect(t.takeException(), isNull);
        await renderProof(t, 'yangin-konum-320-${dark ? 'koyu' : 'acik'}');
      },
    );
  }
}
