import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/dialogs/residency_termination_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';

import 'people_fixtures.dart';

class _TerminationAuth extends PeopleFakeAuth {
  final calls = <Map<String, dynamic>>[];
  Map<String, dynamic> result = {'ok': true, 'debtTransferFailed': true};
  Map<String, dynamic> preview = {
    'residency': {'id': 3, 'relation': 'tenant', 'moveInDate': '2026-01-01'},
    'person': {'id': 4, 'userCode': 5, 'fullName': 'Deneme Sakini'},
    'apartment': {'id': 2, 'apartmentNo': '12', 'blockName': 'A Blok'},
    'debt': {
      'hasDebt': true,
      'balanceMinor': '180000',
      'balanceFormatted': '1.800,00 TL',
      'liabilityTransfer': {'canTransfer': true},
    },
    'meters': [
      {'id': 7, 'kind': 'water', 'serialNo': 'SU-7', 'lastReadingValue': 40},
    ],
  };

  @override
  Future<Map<String, dynamic>> getTerminationPreview(
    int siteCode,
    int apartmentId,
    int residencyId,
  ) async => preview;

  @override
  Future<Map<String, dynamic>> executeResidencyTermination(
    int siteCode,
    int apartmentId,
    int residencyId, {
    DateTime? moveOutDate,
    int? successorUserCode,
    bool terminateSiteRoles = false,
    String debtDisposition = 'KEEP_ON_DEBTOR',
    List<Map<String, dynamic>>? finalMeterReadings,
    String? reason,
  }) async {
    calls.add({
      'date': moveOutDate,
      'debt': debtDisposition,
      'meters': finalMeterReadings,
    });
    return result;
  }
}

Future<void> _pump(
  WidgetTester t,
  _TerminationAuth auth, {
  double width = 500,
  double scale = 1,
}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ResidencyTerminationDialog.show(
              context,
              scope: PeopleScope(
                authService: auth,
                siteCode: 1,
                canWrite: true,
              ),
              apartmentId: 2,
              residencyId: 3,
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Aç'));
  await t.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Future<void> _complete(WidgetTester t) async {
  await t.tap(find.text('Ayrılmayı Tamamla'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'borç otomatik devredilmez; kısmi devir hatası başarı mesajıyla gizlenmez',
    (t) async {
      final auth = _TerminationAuth();
      await _pump(t, auth);
      await _complete(t);
      expect(auth.calls.single['debt'], 'KEEP_ON_DEBTOR');
      expect(find.textContaining('borç devri tamamlanamadı'), findsOneWidget);
      expect(find.textContaining('başarıyla tamamlandı'), findsNothing);
      expect(find.text('Ayrılmayı Tamamla'), findsNothing);
      expect(find.text('Kapat'), findsOneWidget);
      await t.tap(find.text('Kapat'));
      await t.pumpAndSettle();
      expect(auth.calls, hasLength(1));
    },
  );

  testWidgets('geçersiz tarih bugüne çevrilmez ve sunucuya gönderilmez', (
    t,
  ) async {
    final auth = _TerminationAuth();
    await _pump(t, auth);
    await t.enterText(_field('Ayrılış / Taşınma Tarihi'), '31.02.2026');
    await _complete(t);
    expect(auth.calls, isEmpty);
    expect(find.textContaining('Geçersiz tarih'), findsOneWidget);
  });

  testWidgets(
    'hatalı son endeks sessizce atlanmaz; düzeltildiğinde ISO tarih gönderilir',
    (t) async {
      final auth = _TerminationAuth();
      await _pump(t, auth);
      await t.enterText(_field('Ayrılış / Taşınma Tarihi'), '12.11.2026');
      await t.ensureVisible(_field('Son Endeks'));
      await t.enterText(_field('Son Endeks'), 'yanlış');
      await _complete(t);
      expect(auth.calls, isEmpty);
      expect(
        find.textContaining('geçerli, sıfır veya daha büyük'),
        findsOneWidget,
      );
      await t.enterText(_field('Son Endeks'), '42,5');
      await _complete(t);
      expect(auth.calls.single['meters'], [
        {'meterId': 7, 'readingValue': 42.5, 'readingDate': '2026-11-12'},
      ]);
    },
  );

  testWidgets('360 ayrılma dar ekranda büyük yazı ve uzun bilgilerle taşmaz', (
    t,
  ) async {
    final auth = _TerminationAuth();
    auth.preview['person'] = {
      'id': 4,
      'isAdmin': true,
      'fullName': 'Uzun Adı Olan Deneme Sakini Çok Uzun Soyadı',
    };
    auth.preview['siteRoles'] = {
      'hasRoles': true,
      'isSiteManager': true,
      'duties': [
        {
          'id': 1,
          'duty': 'security',
          'title': 'Çok uzun güvenlik görevlisi unvanı',
        },
      ],
    };
    auth.preview['remainingMembers'] = [
      {'residencyId': 10, 'personId': 10, 'fullName': 'Hesapsız Birinci Sakin'},
      {'residencyId': 11, 'personId': 11, 'fullName': 'Hesapsız İkinci Sakin'},
    ];
    auth.preview['upcomingReservations'] = [
      {'id': 1, 'areaName': 'Tesis', 'startsAt': ''},
    ];
    await _pump(t, auth, width: 320, scale: 2);
    expect(t.takeException(), isNull);
    await t.ensureVisible(_field('Son Endeks'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
