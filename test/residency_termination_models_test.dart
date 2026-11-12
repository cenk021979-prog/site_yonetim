import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/termination_preview_model.dart';

void main() {
  group('TerminationPreview Model Tests', () {
    test('parses full json payload correctly', () {
      final json = <String, dynamic>{
        'residency': {
          'id': 101,
          'relation': 'tenant',
          'moveInDate': '2026-01-01',
          'isMinor': false,
        },
        'person': {
          'id': 301,
          'userCode': 4001,
          'fullName': 'Mehmet Demir',
          'phone': '+905551234567',
          'email': 'mehmet@example.com',
          'isAdmin': true,
        },
        'apartment': {
          'id': 45,
          'apartmentNo': '10',
          'blockName': 'B Blok',
        },
        'remainingMembers': [
          {
            'residencyId': 102,
            'personId': 302,
            'userCode': 4002,
            'fullName': 'Fatma Demir',
            'phone': '+905559876543',
            'relation': 'family_member',
            'membershipRole': 'RESIDENT',
          }
        ],
        'defaultSuccessorUserCode': 4002,
        'activeVehicles': [
          {
            'id': 7,
            'plate': '34XYZ99',
            'plate_display': '34 XYZ 99',
            'note': 'SUV',
          }
        ],
        'upcomingReservations': [
          {
            'id': 12,
            'area_id': 3,
            'starts_at': '2026-11-20T14:00:00Z',
            'ends_at': '2026-11-20T15:00:00Z',
            'slot_count': 1,
            'status': 'onaylandi',
            'area_name': 'Havuz',
          }
        ],
        'activeGuestPasses': [
          {
            'id': 9,
            'title': 'Misafir',
            'token': 'tok-pass-1',
            'pass_type': 'single_use',
            'expires_at': '2026-11-12T12:00:00Z',
          }
        ],
        'debt': {
          'balanceMinor': '250000',
          'balanceFormatted': '2.500,00 TL',
          'hasDebt': true,
          'liabilityTransfer': {
            'hasOwner': true,
            'canTransfer': true,
            'itemCount': 1,
            'totalMinor': '250000',
            'previewHash': 'hash123',
            'ownerBalanceMinor': '0',
          },
        },
        'siteRoles': {
          'isSiteManager': true,
          'duties': [
            {
              'id': 4,
              'duty': 'auditor',
              'title': 'Denetçi',
            }
          ],
          'hasRoles': true,
        },
        'meters': [
          {
            'id': 2,
            'kind': 'heat',
            'serialNo': 'ISI-4545',
            'lastReadingValue': 89.2,
            'lastReadingDate': '2026-10-31',
          }
        ],
      };

      final preview = TerminationPreview.fromJson(json);

      expect(preview.residencyId, 101);
      expect(preview.relation, 'tenant');
      expect(preview.fullName, 'Mehmet Demir');
      expect(preview.isAdmin, true);
      expect(preview.apartmentFullLabel, 'B Blok - No: 10');
      expect(preview.remainingMembers.length, 1);
      expect(preview.remainingMembers.first.fullName, 'Fatma Demir');
      expect(preview.defaultSuccessorUserCode, 4002);
      expect(preview.activeVehicles.length, 1);
      expect(preview.activeVehicles.first.plate, '34XYZ99');
      expect(preview.upcomingReservations.length, 1);
      expect(preview.upcomingReservations.first.areaName, 'Havuz');
      expect(preview.activeGuestPasses.length, 1);
      expect(preview.debt.hasDebt, true);
      expect(preview.debt.balanceFormatted, '2.500,00 TL');
      expect(preview.debt.liabilityTransfer?.canTransfer, true);
      expect(preview.siteRoles.hasRoles, true);
      expect(preview.siteRoles.isSiteManager, true);
      expect(preview.siteRoles.duties.first.label, 'Denetçi');
      expect(preview.meters.length, 1);
      expect(preview.meters.first.kindLabel, 'Isı / Kalorimetre');
      expect(preview.meters.first.serialNo, 'ISI-4545');
    });

    test('handles empty or minimal json gracefully', () {
      final preview = TerminationPreview.fromJson({});

      expect(preview.residencyId, 0);
      expect(preview.fullName, '');
      expect(preview.isAdmin, false);
      expect(preview.apartmentFullLabel, 'No: ');
      expect(preview.remainingMembers, isEmpty);
      expect(preview.activeVehicles, isEmpty);
      expect(preview.upcomingReservations, isEmpty);
      expect(preview.activeGuestPasses, isEmpty);
      expect(preview.debt.hasDebt, false);
      expect(preview.siteRoles.hasRoles, false);
      expect(preview.meters, isEmpty);
    });
  });
}
