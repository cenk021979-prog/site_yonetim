// FAZ 5 / A2-G5: VoiceControlModal (alt sayfa) taşma testi (AGENTS.md kural 6).
//
// `showModalBottomSheet` ile açılır (alt sayfa tipi KORUNUR). Açılışta otomatik dinleme başlar;
// mikrofon nabzı YALNIZ dinlerken döner (durağan durumda ticker yok) ve hareket azaltmada çevrilmez.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/voice_control_modal.dart';

import '../design/harness.dart' show recordHaptics;
import 'dialog_layout_harness.dart';
import 'voice_fake.dart';

/// Durumun beklenen küre tonu (sözleşme: dinliyor/başarı success, işleniyor primary, hata danger, boşta info).
AppTone _toneFor(VoiceStatus status) => switch (status) {
  VoiceStatus.listening || VoiceStatus.success => AppTone.success,
  VoiceStatus.processing => AppTone.primary,
  VoiceStatus.error => AppTone.danger,
  VoiceStatus.initializing || VoiceStatus.idle => AppTone.info,
};

class _ControlledVoice extends FakeVoiceDoorService {
  VoiceStatus? forcedStatus;

  @override
  VoiceStatus get status => forcedStatus ?? super.status;

  @override
  bool get isListening => status == VoiceStatus.listening;

  void changeStatus(VoiceStatus value) {
    forcedStatus = value;
    notifyListeners();
  }
}

void main() {
  for (final c in <(String, VoiceStatus, String)>[
    ('boşta', VoiceStatus.idle, ''),
    ('başlatılıyor', VoiceStatus.initializing, ''),
    (
      'dinliyor',
      VoiceStatus.listening,
      'Dinleniyor... "Kapıyı aç" diyebilirsiniz.',
    ),
    ('komut işleniyor', VoiceStatus.processing, '"kapıyı aç"'),
    (
      'hata',
      VoiceStatus.error,
      'Mikrofon izni verilmediği için komut dinlenemiyor; lütfen ayarlardan izin verin.',
    ),
  ]) {
    layoutMatrix('VoiceControlModal (${c.$1})', (
      t,
      width,
      height,
      scale,
      dark,
    ) async {
      final voice = FakeVoiceDoorService(
        startStatus: c.$2 == VoiceStatus.idle ? null : c.$2,
        startFeedback: c.$3,
      );
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: width,
        height: height,
        scale: scale,
        dark: dark,
      );

      expect(find.text('Sesli Kapı Kontrolü'), findsOneWidget);
      // Dinleme göstergesi: tek cilalı küre (IconOrb), durumun tonunda; düzene girmeyen aura statiktir.
      expect(find.byType(IconOrb), findsOneWidget);
      expect(t.widget<IconOrb>(find.byType(IconOrb)).tone, _toneFor(c.$2));
      expect(t.widget<IconOrb>(find.byType(IconOrb)).size, 92);
      expect(find.text('Kapat'), findsOneWidget);
      expect(
        find.text(c.$2 == VoiceStatus.listening ? 'Durdur' : 'Dinle'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('voice_listening_toggle')),
        findsOneWidget,
      );
      expect(find.byType(TextButton), findsOneWidget);
      expect(
        find.byType(ElevatedButton).hitTestable(),
        findsNothing,
        reason: 'alt kısımda ikinci dinleme düğmesi yok',
      );
      if (c.$3.isNotEmpty) {
        expect(find.text(c.$3), findsOneWidget);
      }
      await scrollTo(t, find.text('Kapat'));

      // Hata durumunda alt sayfa 2,5 sn sonra kendiliğinden kapanır; bekleyen zamanlayıcı kalmasın.
      await t.pump(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'VoiceControlModal: mikrofon düğmesi dinlemeyi durdurur; nabız yalnız dinlerken döner',
    (t) async {
      final voice = FakeVoiceDoorService(startStatus: VoiceStatus.listening);
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      expect(voice.startCalls, 1, reason: 'açılışta otomatik dinleme başlar');
      expect(voice.isListening, isTrue);
      // Dinlerken nabız ticker'ı çalışır.
      expect(t.hasRunningAnimations, isTrue);

      await t.tap(find.text('Durdur'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(voice.stopCalls, greaterThanOrEqualTo(1));
      // Boşta: ticker kalmaz (modalın nabzı durdu).
      voice.notifyListeners();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Dinle'), findsOneWidget);
      // Durum değişimi küre ve durum metni için tek seferlik belirme (Pop, 200 ms) başlatır: o sonlu
      // animasyon bitince durağan durumda ticker KALMAMALIDIR (iddia aynı: nabız durdu, süs döngüsü yok).
      await t.pump(const Duration(milliseconds: 400));
      expect(t.hasRunningAnimations, isFalse);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('tek dinleme kontrolü Enter ve Space ile bir kez çalışır', (
    t,
  ) async {
    final voice = _ControlledVoice();
    await openDialogAt(
      t,
      (context) => VoiceControlModal.show(context, voiceService: voice),
      width: 400,
      height: 900,
      scale: 1,
      dark: false,
      reduce: true,
    );
    expect(voice.startCalls, 1);
    final control = find.byKey(const ValueKey('voice_listening_toggle'));
    expect(t.getSize(control).width, greaterThanOrEqualTo(48));
    expect(t.getSize(control).height, greaterThanOrEqualTo(48));
    Focus.of(t.element(find.byType(IconOrb))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(voice.startCalls, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(voice.startCalls, 3);
    expect(find.byType(TextButton), findsOneWidget);

    // Even a callback retained before the redraw checks the latest service state.
    final staleTap = t.widget<TextButton>(control).onPressed!;
    voice.changeStatus(VoiceStatus.processing);
    staleTap();
    await t.pump();
    expect(voice.startCalls, 3);
    expect(t.widget<TextButton>(control).onPressed, isNull);
    expect(find.text('Komut İşleniyor...'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final status in [VoiceStatus.initializing, VoiceStatus.processing]) {
    testWidgets('$status sırasında yeni dinleme başlatılmaz', (t) async {
      final voice = FakeVoiceDoorService(startStatus: status);
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: 320,
        height: 640,
        scale: 2,
        dark: false,
        reduce: true,
      );
      final control = find.byKey(const ValueKey('voice_listening_toggle'));
      expect(t.widget<TextButton>(control).onPressed, isNull);
      await t.tap(control);
      await t.pump();
      expect(voice.startCalls, 1);
      expect(voice.stopCalls, 0);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('sesli yanıt ve Kapat ayrı işlevler olarak kalır', (t) async {
    final voice = FakeVoiceDoorService();
    await openDialogAt(
      t,
      (context) => VoiceControlModal.show(context, voiceService: voice),
      width: 400,
      height: 900,
      scale: 1,
      dark: false,
      reduce: true,
    );
    await t.tap(find.byTooltip('Sesli Yanıtı Kapat'));
    await t.pump();
    expect(voice.ttsEnabled, isFalse);
    expect(voice.startCalls, 1);
    expect(find.byTooltip('Sesli Yanıtı Aç'), findsOneWidget);
    expect(
      ModalRoute.of(t.element(find.byType(VoiceControlModal)))!.isFirst,
      isFalse,
      reason: 'gerçek alt sayfa, alttaki kök rotanın üstünde açılmıştır',
    );
    await t.tap(find.text('Kapat'));
    // First frame starts the real route's reverse transition; elapsed time
    // must advance after that frame, rather than on its first tick.
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(VoiceControlModal), findsNothing);
    expect(find.text('Aç'), findsOneWidget);
    expect(voice.stopCalls, 1, reason: 'mevcut dispose durdurması korunur');
  });

  for (final dark in [false, true]) {
    testWidgets('yatay 640x320 2x dark=$dark tek kontrol taşmaz', (t) async {
      final voice = FakeVoiceDoorService(startStatus: VoiceStatus.processing);
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: 640,
        height: 320,
        scale: 2,
        dark: dark,
        reduce: true,
      );
      expect(
        find.byKey(const ValueKey('voice_listening_toggle')),
        findsOneWidget,
      );
      await t.ensureVisible(find.text('Kapat'));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'VoiceControlModal: komut gönderildi (başarı) anında bir kez hafif haptik; sonra kendiliğinden kapanır',
    (t) async {
      final haptics = recordHaptics(t);
      final voice = FakeVoiceDoorService(
        startStatus: VoiceStatus.success,
        startFeedback: 'Ana kapı için açma komutu gönderildi.',
      );
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
      );
      // Dürüst dil (P1-15): başarı = komutun sunucuca kabulü; kapının açıldığı iddia edilmez.
      expect(find.text('Komut Gönderildi'), findsOneWidget);
      expect(
        find.text('Ana kapı için açma komutu gönderildi.'),
        findsOneWidget,
      );
      expect(find.textContaining('Açıldı'), findsNothing);
      expect(find.textContaining('açıldı'), findsNothing);
      expect(
        haptics.where((h) => h.contains('lightImpact')),
        hasLength(1),
        reason: 'başarıya geçişte tek haptik',
      );
      // Aynı durumda tekrar bildirim ikinci haptik üretmez.
      voice.notifyListeners();
      await t.pump(const Duration(milliseconds: 100));
      expect(haptics.where((h) => h.contains('lightImpact')), hasLength(1));
      await t.pump(const Duration(seconds: 3));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'VoiceControlModal: hareket azaltmada dinlerken de nabız çevrilmez',
    (t) async {
      final voice = FakeVoiceDoorService(startStatus: VoiceStatus.listening);
      await openDialogAt(
        t,
        (context) => VoiceControlModal.show(context, voiceService: voice),
        width: 400,
        height: 900,
        scale: 1.0,
        dark: false,
        reduce: true,
      );
      expect(voice.isListening, isTrue);
      expect(t.hasRunningAnimations, isFalse);
      expect(t.takeException(), isNull);
    },
  );
}
