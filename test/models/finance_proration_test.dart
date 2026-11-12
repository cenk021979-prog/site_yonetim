import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance.dart';

void main() {
  test('Günlük aidat payları sunucudan kuruş ve gün olarak okunur', () {
    final line = FeePreviewLine.fromJson({
      'apartment_id': 1,
      'amount_minor': 300000,
      'account_party': null,
      'proration': {
        'total_days': 30,
        'shares': [
          {'account_party': 'owner', 'days': 12, 'amount_minor': 120000},
          {'account_party': 'tenant', 'days': 18, 'amount_minor': 180000},
        ],
      },
    });
    expect(line.prorationDays, 30);
    expect(line.prorationShares.map((s) => s.days), [12, 18]);
    expect(line.prorationShares.map((s) => s.amountMinor), [120000, 180000]);
    expect(line.accountParty, isNull);
  });
  test('Eski sunucu günlük paylaşım alanı olmadan okunur', () {
    final line = FeePreviewLine.fromJson({
      'apartment_id': 1,
      'amount_minor': 300000,
      'account_party': 'tenant',
    });
    expect(line.prorationShares, isEmpty);
    expect(line.prorationDays, isNull);
    expect(line.accountParty, AccountParty.tenant);
  });
}
