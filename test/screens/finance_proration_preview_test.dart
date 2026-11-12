import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_parts.dart';

void main() {
  for (final width in [320.0, 600.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Aidat payları $width dp / yazı $scale taşmaz', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1200),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FeePreviewLineTile(
                      line: FeePreviewLine(
                        apartmentId: 1,
                        label: 'Uzun isimli daire ve bölüm 12345',
                        blockName: 'Uzun isimli blok',
                        amountMinor: 300000,
                        prorationDays: 30,
                        prorationShares: const [
                          FeeProrationShare(
                            accountParty: AccountParty.owner,
                            days: 12,
                            amountMinor: 120000,
                          ),
                          FeeProrationShare(
                            accountParty: AccountParty.tenant,
                            days: 18,
                            amountMinor: 180000,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.textContaining('12/30 gün'), findsOneWidget);
        expect(find.textContaining('18/30 gün'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
