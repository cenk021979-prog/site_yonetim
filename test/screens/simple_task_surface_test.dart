import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/ui/widgets/simple_task_surface.dart';
import 'simple_appearance_home_test.dart'
    show loadSimpleReviewFonts, simpleReviewTheme;

void main() {
  setUpAll(loadSimpleReviewFonts);
  for (final mode in ListViewMode.values) {
    testWidgets('keyboard order follows visible row-major tasks ${mode.name}', (
      t,
    ) async {
      t.view.physicalSize = const Size(1366, 768);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final opened = <int>[];
      await t.pumpWidget(
        MaterialApp(
          theme: simpleReviewTheme(false),
          home: Scaffold(
            body: SimpleTaskSurface(
              mode: mode,
              entries: [
                for (var i = 0; i < 6; i++)
                  SimpleTaskEntry(
                    id: 'keyboard_task_$i',
                    title: 'İşlem $i',
                    description: 'Görev açıklaması',
                    group: 'İletişim',
                    icon: Icons.home_outlined,
                    onTap: () => opened.add(i),
                  ),
              ],
            ),
          ),
        ),
      );
      await t.pump();
      for (var i = 0; i < 6; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
      }
      expect(opened, [0, 1, 2, 3, 4, 5]);
      expect(t.takeException(), isNull);
    });
  }
}
