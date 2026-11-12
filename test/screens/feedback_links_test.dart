import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/feedback_models.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/helpers/feedback_reference.dart';
import 'package:site_kapi_kontrol/ui/widgets/feedback_links.dart';

void main() {
  test('sayfa adresi site kapsamını taşır; genel bağlamda site uydurulmaz', () {
    expect(
      feedbackScreenAddress('menu/finance', siteCode: 11),
      '/menu/finance?site=11',
    );
    expect(feedbackScreenAddress('/menu/dashboard'), '/menu/dashboard');
    expect(
      Uri.parse(feedbackScreenAddress('menu/finance:sakin')).path,
      '/menu/finance:sakin',
    );
  });

  test(
    'inceleme notunda kayıt adresi vardır; gönderen adı ve ek içerikleri aktarılmaz',
    () {
      const record = FeedbackRecord(
        id: 42,
        siteCode: 11,
        siteName: 'Örnek Site',
        userName: 'Gönderen Adı',
        role: 'resident',
        screenName: 'Finans',
        screenRoute: 'menu/finance',
        message: 'Tutar alanının açıklamasını göremiyorum.',
        appVersion: '1.0.0+1',
        platform: 'windows',
        createdAt: null,
        attachments: <FeedbackAttachment>[],
      );
      final address = Uri.parse(feedbackRecordAddress(record));
      expect(address.path, '/feedback/42');
      expect(address.queryParameters['screen'], 'menu/finance');
      expect(address.queryParameters['site'], '11');
      final note = feedbackReviewNote(record);
      expect(note, contains('Geri bildirim #42'));
      expect(note, contains('/menu/finance?site=11'));
      expect(note, contains(record.message));
      expect(note, isNot(contains(record.userName)));
    },
  );

  for (final dark in <bool>[false, true]) {
    for (final scale in <double>[1, 2]) {
      testWidgets(
        '320 dp, yazı $scale, koyu $dark: bağlantılar taşmaz ve sayfayı kapatmaz',
        (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          var opened = 0;
          await t.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Column(
                      children: [
                        TemporaryFeedbackStrip(
                          screen: const FeedbackScreenContext(
                            screenName: 'Finans',
                            screenRoute: 'menu/finance',
                            siteCode: 11,
                          ),
                          onFeedback: () => opened++,
                        ),
                        const Text('Sayfa açık'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(t.takeException(), isNull);
          await t.tap(
            find.byKey(const ValueKey<String>('temporary_feedback_open')),
          );
          await t.pump();
          expect(opened, 1);
          expect(find.text('Sayfa açık'), findsOneWidget);
          expect(
            find.byKey(const ValueKey<String>('temporary_feedback_address')),
            findsNothing,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
