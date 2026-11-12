import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/views/neighbor_board_view.dart';

import 'emergency_view_test.dart' show loadAlarmReviewFont, alarmReviewTheme;
import 'list_fixtures.dart' show tapFinder;
import 'neighbor_board_fixtures.dart';

// Uses the existing review-only font/theme loader, never production/network data.
void main() {
  setUpAll(loadAlarmReviewFont);
  for (final (width, height, keyboard) in <(double, double, double)>[(320, 640, 280), (640, 360, 180)]) {
    for (final dark in <bool>[false, true]) {
      for (final newPost in <bool>[true, false]) {
        testWidgets('real fonts keyboard ${width.toInt()} ${dark ? 'dark' : 'light'} ${newPost ? 'new' : 'report'}', (t) async {
          final rig = NeighborRig(posts: [nbPost(1)]);
          const boundaryKey = ValueKey('neighbor_keyboard_review');
          t.view.physicalSize = Size(width, height);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(MaterialApp(
            theme: alarmReviewTheme(dark),
            builder: (context, child) => RepaintBoundary(
              key: boundaryKey,
              child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)), child: child!),
            ),
            home: Scaffold(body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: NeighborBoardView(authService: rig.auth, service: rig.service, sites: rig.sites),
            )),
          ));
          await nbSettle(t);
          await tapFinder(t, find.text(newPost ? 'Yeni ilan' : 'Şikayet et'));
          t.view.viewInsets = FakeViewPadding(bottom: keyboard);
          await t.pump(const Duration(milliseconds: 50));
          await t.pump(const Duration(milliseconds: 400));
          await t.enterText(nbDialogField(0), newPost ? 'Çocuk bahçesi etkinliği' : 'İlan bilgisi güncel değil. Kontrol edilmesini rica ederim.');
          if (newPost) await t.enterText(nbDialogField(1), 'Cumartesi bahçede komşularımızla buluşuyoruz. Katılmak isteyenleri bekleriz.');
          await t.pump(const Duration(milliseconds: 50));
          await t.pump(const Duration(milliseconds: 400));
          expect(t.takeException(), isNull);
          final name = 'neighbor-${newPost ? 'new' : 'report'}-${width.toInt()}-${dark ? 'dark' : 'light'}';
          Future<void> capture(String state) async {
            final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
            await t.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
              await File('work/emergency-simple-2026-11-09/$name-$state.png').writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          final activeField = nbDialogField(newPost ? 1 : 0);
          await t.ensureVisible(activeField);
          await t.showKeyboard(activeField);
          final editableFinder = find.descendant(of: activeField, matching: find.byType(EditableText));
          final editableState = t.state<EditableTextState>(editableFinder);
          editableState.bringIntoView(editableState.widget.controller.selection.extent);
          await t.pump(const Duration(milliseconds: 50));
          await t.pump(const Duration(milliseconds: 400));
          final editableRender = editableState.renderEditable;
          final caretLocal = editableRender.getLocalRectForCaret(editableState.widget.controller.selection.extent);
          final caret = caretLocal.shift(editableRender.localToGlobal(Offset.zero));
          final scroll = find.ancestor(of: activeField, matching: find.byType(SingleChildScrollView)).first;
          final visible = t.getRect(scroll).intersect(Rect.fromLTWH(0, 0, width, height - keyboard));
          expect(editableState.widget.focusNode.hasFocus, isTrue);
          expect(caret.top, greaterThanOrEqualTo(visible.top - 1), reason: 'focused text caret must remain readable above keyboard');
          expect(caret.bottom, lessThanOrEqualTo(visible.bottom + 1), reason: 'focused text caret must not hide behind actions or keyboard');
          expect(caret.height, greaterThan(20), reason: 'large text scale remains active');
          expect(t.takeException(), isNull);
          await capture('form');
          final send = nbInDialog(newPost ? 'Onaya gönder' : 'Gönder');
          await t.ensureVisible(send);
          await t.pump();
          expect(t.takeException(), isNull);
          expect(send.hitTestable(), findsOneWidget);
          await capture('submit');
          await t.tap(send);
          await nbSettle(t);
          expect(find.byType(AlertDialog), findsNothing);
          expect(newPost ? rig.fake.createCalls : rig.fake.reportCalls, hasLength(1));
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
