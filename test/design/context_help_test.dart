import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/context_help.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'harness.dart';

const _message =
    'Dairenizin güncel borç ve alacak durumunu, vadeleri ve son hareketleri buradan görebilirsiniz.';

Widget _header({Widget? action}) => SizedBox(
  width: double.infinity,
  child: PageHeaderCard(
    title: 'Finans',
    icon: Icons.account_balance_wallet_rounded,
    help: _message,
    action: action,
  ),
);

void main() {
  testWidgets('genel açıklama gövdeyi doldurmaz, dokunmada tamamı açılır', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    await pumpAt(t, _header(), width: 320, height: 480, scale: 2);
    expect(find.text(_message), findsNothing);
    final help = find.byType(ContextHelp);
    expect(t.getSize(help).width, greaterThanOrEqualTo(48));
    expect(t.getSize(help).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('Finans hakkında bilgi'), findsOneWidget);
    await t.tap(help);
    await t.pumpAndSettle();
    expect(find.text(_message), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('Kapat'));
    await t.tap(find.text('Kapat'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    semantics.dispose();
  });

  testWidgets('fareyle aynı açıklama görünür ve klavyeden açılabilir', (
    t,
  ) async {
    await pumpAt(t, _header(), width: 820, height: 600, scale: 1);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.byType(ContextHelp)));
    await t.pump(const Duration(seconds: 1));
    expect(find.text(_message), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await mouse.removePointer();
    await t.pump(const Duration(seconds: 1));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(_message), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 480),
      const Size(640, 320),
      const Size(1000, 600),
    ]) {
      testWidgets('başlık + bilgi + eylem taşmaz $size dark=$dark', (t) async {
        await pumpAt(
          t,
          _header(
            action: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Yeni kayıt'),
            ),
          ),
          width: size.width,
          height: size.height,
          scale: 2,
          dark: dark,
        );
        await t.tap(find.byType(ContextHelp));
        await t.pumpAndSettle();
        expect(find.text(_message), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }
}
