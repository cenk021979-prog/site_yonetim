import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/feedback_models.dart';
import 'package:site_kapi_kontrol/services/feedback_api.dart';
import 'package:site_kapi_kontrol/ui/views/feedback_inbox_view.dart';
import 'simple_appearance_home_test.dart'
    show loadSimpleReviewFonts, simpleReviewTheme;
import 'work_fixtures.dart';

class _OwnApi extends FeedbackApi {
  _OwnApi() : super(baseUrl: 'http://localhost');
  @override
  Future<FeedbackPage> listMine({
    required String token,
    int? cursor,
    int limit = 30,
  }) async => FeedbackPage(
    items: [
      for (var i = 0; i < 7; i++)
        FeedbackRecord(
          id: i + 1,
          siteCode: 11,
          userName: 'Örnek sakin',
          role: 'resident',
          siteName: 'Örnek Site',
          screenName: [
            'Dairem',
            'Panel',
            'Anketler',
            'Plaka Tanıma',
            'Sayaçlar',
            'Ödemeler',
            'Site',
          ][i],
          screenRoute: 'menu/example',
          message:
              'Bu ekrandaki işlemleri daha kolay bulabilmek istiyorum. Açıklamanın tamamını ayrıntıda okuyabilmeliyim.',
          createdAt: DateTime(2026, 11, 10, 9, i),
          appVersion: null,
          platform: null,
          attachments: const [],
        ),
    ],
    nextCursor: null,
  );
}

void main() {
  setUpAll(loadSimpleReviewFonts);
  for (final (width, height, scale) in [
    (1100.0, 850.0, 1.0),
    (390.0, 844.0, 1.0),
    (320.0, 640.0, 2.0),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('own feedback real-font visual $width/$scale dark=$dark', (
        t,
      ) async {
        t.view.physicalSize = Size(width, height);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        const key = ValueKey('mine_capture');
        await t.pumpWidget(
          MaterialApp(
            theme: simpleReviewTheme(dark),
            builder: (context, child) => RepaintBoundary(
              key: key,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: FeedbackInboxPage(
              service: FeedbackService(
                authService: WorkFakeAuth(),
                api: _OwnApi(),
              ),
              mine: true,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(ExpansionTile), findsNWidgets(7));
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          const directory = String.fromEnvironment('SIMPLE_REVIEW_DIR', defaultValue: 'work/sade-redesign-2026-11-10');
          await Directory(directory).create(recursive: true);
          final bitmap = await t
              .renderObject<RenderRepaintBoundary>(find.byKey(key))
              .toImage();
          final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$directory/my-feedback-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          bitmap.dispose();
        });
      });
    }
  }
}
