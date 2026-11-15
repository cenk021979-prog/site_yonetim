import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/ui/views/platform_modules_view.dart';

import '../design/harness.dart';
import 'modules_fixtures.dart';

class _DelayedPlatformAuth extends ModulesFakeAuth {
  _DelayedPlatformAuth({
    required List<PlatformModule> initialModules,
    required this.staleFuture,
  }) {
    platformModules = List<PlatformModule>.from(initialModules);
  }

  final Future<List<PlatformModule>> staleFuture;
  bool _firstCall = true;

  @override
  Future<List<PlatformModule>> getPlatformModules() async {
    if (_firstCall) {
      _firstCall = false;
      // İlk istek (loadData) gecikmeli ağ cevabı simüle eder
      return staleFuture;
    }
    return List<PlatformModule>.from(platformModules ?? const <PlatformModule>[]);
  }
}

List<PlatformModule> _sampleModules() => <PlatformModule>[
      const PlatformModule(
        code: 'people',
        name: 'Kişi ve Daire Kayıtları',
        description: 'Blok, daire, sakin ve görevli kayıtlarının tutulması.',
        core: true,
        isPlatformActive: true,
      ),
      const PlatformModule(
        code: 'finance',
        name: 'Aidat ve Finans',
        description: 'Aidat, borç ve alacak takibi; gelir ve gider kayıtları.',
        core: true,
        isPlatformActive: true,
      ),
      const PlatformModule(
        code: 'door_control',
        name: 'Geçiş Kontrol (SmartKeyPass)',
        description: 'Telefondan kapı açma, karekod ve misafir geçişi.',
        core: false,
        isPlatformActive: false,
      ),
      const PlatformModule(
        code: 'plate_recognition',
        name: 'Plaka Tanıma ve Kapı Açma',
        description: 'Kameralarla araç plakasını okuyarak kapıları otomatik açma.',
        core: false,
        isPlatformActive: false,
      ),
    ];

Future<void> _pumpView(
  WidgetTester t, {
  required ModulesFakeAuth auth,
  bool? showOnlyActive,
  double width = 1200,
  double height = 800,
  double scale = 1.0,
  bool dark = false,
}) async {
  await pumpAt(
    t,
    SingleChildScrollView(
      child: PlatformModulesView(
        authService: auth,
        showOnlyActive: showOnlyActive,
      ),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await t.pumpAndSettle();
}

void main() {
  group('PlatformModulesView master-detail yerleşim ve davranış testleri', () {
    testWidgets('geniş ekranda (1200x800) modül listesi ve detay paneli yan yana yerleşir', (t) async {
      final auth = ModulesFakeAuth()..platformModules = _sampleModules();
      await _pumpView(t, auth: auth, width: 1200, height: 800);

      // Sol panel başlığı ve filtreler
      expect(find.text('Modül Listesi (4 Modül)'), findsOneWidget);
      expect(find.text('Tümü (4)'), findsOneWidget);
      expect(find.text('Devrede (2)'), findsOneWidget);
      expect(find.text('Devre Dışı (2)'), findsOneWidget);
      expect(find.text('Temel (2)'), findsOneWidget);
      expect(find.text('Ek (2)'), findsOneWidget);

      // Sağ panel başlığı (ilk modül seçilidir)
      expect(find.text('Kişi ve Daire Kayıtları Yönetimi'), findsOneWidget);
      expect(find.text('Modül Kodu: people'), findsOneWidget);
      expect(find.text('Platform Genelinde Devrede'), findsOneWidget);
      expect(find.text('Otomatik Dağıtım'), findsOneWidget);
    });

    testWidgets('modül seçimi sağ detay panelini günceller', (t) async {
      final auth = ModulesFakeAuth()..platformModules = _sampleModules();
      await _pumpView(t, auth: auth, width: 1200, height: 800);

      expect(find.text('Kişi ve Daire Kayıtları Yönetimi'), findsOneWidget);

      // 'Geçiş Kontrol (SmartKeyPass)' modülüne dokun
      await t.tap(find.text('Geçiş Kontrol (SmartKeyPass)'));
      await t.pumpAndSettle();

      // Sağ panel güncellendi
      expect(find.text('Geçiş Kontrol (SmartKeyPass) Yönetimi'), findsOneWidget);
      expect(find.text('Modül Kodu: door_control'), findsOneWidget);
      expect(find.text('Platform Genelinde Devre Dışı'), findsOneWidget);
      expect(find.text('Talep Usulü'), findsOneWidget);
    });

    testWidgets('filtre çipleri listeyi süzer', (t) async {
      final auth = ModulesFakeAuth()..platformModules = _sampleModules();
      await _pumpView(t, auth: auth, width: 1200, height: 800);

      // Başlangıçta 4 modül de listede
      expect(find.byKey(const ValueKey('module_card_people')), findsOneWidget);
      expect(find.byKey(const ValueKey('module_card_door_control')), findsOneWidget);

      // Yalnız Devre Dışı modülleri filtrele
      await t.tap(find.text('Devre Dışı (2)'));
      await t.pumpAndSettle();

      expect(find.text('2 Adet'), findsOneWidget);
      expect(find.byKey(const ValueKey('module_card_door_control')), findsOneWidget);
      expect(find.byKey(const ValueKey('module_card_plate_recognition')), findsOneWidget);
      expect(find.byKey(const ValueKey('module_card_people')), findsNothing);

      // Temel modülleri filtrele
      await t.tap(find.text('Temel (2)'));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('module_card_people')), findsOneWidget);
      expect(find.byKey(const ValueKey('module_card_finance')), findsOneWidget);
      expect(find.byKey(const ValueKey('module_card_door_control')), findsNothing);
    });

    testWidgets('sağ paneldeki açma/kapama butonu modülü günceller', (t) async {
      final auth = ModulesFakeAuth()..platformModules = _sampleModules();
      await _pumpView(t, auth: auth, width: 1200, height: 800);

      // people modülü devrede -> Pasife Al butonuna dokun
      expect(find.text('Modülü Pasife Al'), findsOneWidget);
      await t.tap(find.text('Modülü Pasife Al'));
      await t.pumpAndSettle();

      expect(auth.toggleCalls, hasLength(1));
      expect(auth.toggleCalls.first.code, 'people');
      expect(auth.toggleCalls.first.active, isFalse);
    });

    testWidgets('dar ekranda (360x640) taşma (overflow) olmadan alt alta yerleşir', (t) async {
      final auth = ModulesFakeAuth()..platformModules = _sampleModules();
      await _pumpView(t, auth: auth, width: 360, height: 640, dark: true);

      expect(find.text('Modül Listesi (4 Modül)'), findsOneWidget);
      expect(find.text('Kişi ve Daire Kayıtları Yönetimi'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Devreye Alınmamış modül filtresinde durum değişince sağdaki detay filtredeki modüle geçer', (t) async {
      final auth = ModulesFakeAuth()..platformModules = _sampleModules();
      await _pumpView(t, auth: auth, width: 1200, height: 800);

      // Devre Dışı (Devreye Alınmamış) filtresini seç
      await t.tap(find.text('Devre Dışı (2)'));
      await t.pumpAndSettle();

      // İlk seçili olan: door_control (Geçiş Kontrol)
      expect(find.text('Geçiş Kontrol (SmartKeyPass) Yönetimi'), findsOneWidget);

      // door_control modülünü Devreye Al
      expect(find.text('Modülü Devreye Al'), findsOneWidget);
      await t.tap(find.text('Modülü Devreye Al'));
      await t.pumpAndSettle();

      // door_control filtre dışına çıktı, kalan tek modül: plate_recognition (Plaka Tanıma)
      // Sağ detay paneli artık filtrede kalan modülü (Plaka Tanıma) göstermeli, door_control'de kalmamalıdır
      expect(find.text('Plaka Tanıma ve Kapı Açma Yönetimi'), findsOneWidget);
      expect(find.text('Modül Kodu: plate_recognition'), findsOneWidget);
    });

    testWidgets('ters sırada dönen eski ağ yanıtı güncel modül durumunu geri almaz', (t) async {
      final modules = _sampleModules();
      final staleList = List<PlatformModule>.from(modules);
      final completer = Completer<List<PlatformModule>>();

      // İlk istek (yükleme) bekletilsin
      final auth = _DelayedPlatformAuth(
        initialModules: modules,
        staleFuture: completer.future,
      );

      // View'ı pump et ama ilk yükleme tamamlanmadan önce UI'ı çizdir
      await pumpAt(
        t,
        SingleChildScrollView(
          child: PlatformModulesView(authService: auth),
        ),
        width: 1200,
        height: 800,
      );
      await t.pump();

      // View state'ine doğrudan erişip ilk yükleme dönmeden bir toggle başlatalım
      final state = t.state<PlatformModulesViewState>(find.byType(PlatformModulesView));
      // State'te başlangıç listesi verip toggle çağıralım
      state.setStateForTesting(() {
        state.setModulesForTesting(List<PlatformModule>.from(modules));
      });
      await t.pumpAndSettle();

      // people modülünü pasife al
      expect(find.text('Modülü Pasife Al'), findsOneWidget);
      await t.tap(find.text('Modülü Pasife Al'));
      await t.pumpAndSettle();

      // Artık people 'Devre Dışı' oldu
      var peopleCard = find.byKey(const ValueKey('module_card_people'));
      expect(find.descendant(of: peopleCard, matching: find.text('Devre Dışı')), findsOneWidget);

      // Şimdi ilk baştaki geciken eski loadData cevabı geç gelsin (stale response)
      completer.complete(staleList);
      await t.pumpAndSettle();

      // Yeni durum (pasife alınmış) korunmalı, eski devrede durumuyla ezilmemelidir
      peopleCard = find.byKey(const ValueKey('module_card_people'));
      expect(find.descendant(of: peopleCard, matching: find.text('Devre Dışı')), findsOneWidget);
    });

    testWidgets('küçük ekranda (320x640 x2.0) taşma hatası oluşmaz (Kural 6)', (t) async {
      final auth = ModulesFakeAuth()..platformModules = _sampleModules();
      await _pumpView(t, auth: auth, width: 320, height: 640, scale: 2.0, dark: false);

      expect(find.text('Modül Listesi (4 Modül)'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
