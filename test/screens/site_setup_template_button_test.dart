import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_setup_template_button.dart';

import '../bulk_fakes.dart';
import '../design/harness.dart';
import 'dialog_layout_harness.dart';

void main() {
  testWidgets(
    'çift indirme engellenir; kaydetme hatası görünür, tekrar deneme aynı boş dosyayı verir',
    (t) async {
      final delivery = FakeDelivery()
        ..gate = Completer<void>()
        ..error = StateError('disk');
      await pumpAt(
        t,
        SingleChildScrollView(
          child: SiteSetupTemplateButton(delivery: delivery),
        ),
        width: 400,
        height: 900,
      );
      final button = find.byKey(
        const ValueKey<String>('site_setup_blank_template'),
      );
      await t.tap(button);
      await t.pump();
      await t.tap(button);
      await t.pump();
      expect(delivery.files, hasLength(1));
      expect(delivery.files.single.fileName, 'site_kurulum_bos_sablon.xlsx');
      expect(delivery.origins.single, isNotNull);
      delivery.gate!.complete();
      await settleFor(t, 100);
      expect(find.textContaining('Şablon hazırlanamadı'), findsOneWidget);
      expect(find.textContaining('Şablon hazır.'), findsNothing);
      delivery.error = null;
      await t.tap(button);
      await settleFor(t, 100);
      expect(delivery.files, hasLength(2));
      expect(find.textContaining('Şablon hazırlanamadı'), findsNothing);
      expect(find.textContaining('Şablon hazır.'), findsOneWidget);
    },
  );

  layoutMatrix('Boş Excel indirme ve uzun açıklaması', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    await pumpAt(
      t,
      SingleChildScrollView(
        child: SiteSetupTemplateButton(delivery: FakeDelivery()),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    expect(
      find.textContaining('Kişiler > Toplu Yükle > Hepsi bir arada'),
      findsOneWidget,
    );
    await t.tap(
      find.byKey(const ValueKey<String>('site_setup_blank_template')),
    );
    await settleFor(t, 100);
    expect(find.textContaining('Şablon hazır.'), findsOneWidget);
  });
}
