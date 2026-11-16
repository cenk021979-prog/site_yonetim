import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/widgets/resident_welcome_hero.dart';

import '../design/harness.dart';
import 'g4_test_support.dart';

Widget _hero({
  VoidCallback? onOpen,
  VoidCallback? onQr,
  VoidCallback? onGuest,
}) => SizedBox(
  width: double.infinity,
  child: ResidentWelcomeHero(
    fullName: 'Ahmet Ceylan',
    homeLabel: 'Güneş Sitesi - A Blok / Daire 12',
    apartmentCount: 1,
    doorCount: 3,
    onlineDoorCount: 2,
    pendingRequestCount: 1,
    primaryDoor: g4Door(),
    isOpening: false,
    onOpenDoor: onOpen,
    onShowQr: onQr,
    onGuestPass: onGuest,
  ),
);

void main() {
  testWidgets('gerçek sakin ve kapı özetini gösterir; eylemleri iletir', (
    t,
  ) async {
    var opened = 0;
    var qr = 0;
    var guest = 0;
    await pumpAt(
      t,
      _hero(onOpen: () => opened++, onQr: () => qr++, onGuest: () => guest++),
      width: 412,
      height: 900,
      scale: 1,
    );

    expect(find.byKey(const ValueKey('resident_welcome_hero')), findsOneWidget);
    expect(find.textContaining('Ahmet'), findsOneWidget);
    expect(find.text('Güneş Sitesi - A Blok / Daire 12'), findsOneWidget);
    expect(find.text('3 kapı'), findsOneWidget);
    expect(find.text('2 çevrimiçi'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('resident_primary_door_action')));
    await t.tap(find.text('QR Göster'));
    await t.tap(find.text('Misafir Geçişi'));
    expect((opened, qr, guest), (1, 1, 1));
  });

  for (final dark in const [false, true]) {
    testWidgets('320 px ve 2x yazıda taşmaz (dark=$dark)', (t) async {
      await pumpAt(
        t,
        _hero(onOpen: () {}, onQr: () {}, onGuest: () {}),
        width: 320,
        height: 1300,
        scale: 2,
        dark: dark,
      );
    });
  }
}
