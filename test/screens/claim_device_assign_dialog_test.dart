import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/claim_device_assign_dialog.dart';

import 'dialog_layout_harness.dart';

SiteRecord _site(int id, String name) => SiteRecord.fromJson({
      'id': id,
      'name': name,
      'block_count': 2,
      'apartment_count': 20,
      'door_count': 2,
      'approval_status': 'approved',
    });

DoorRecord _door({
  required int id,
  required String name,
  String? uid,
}) =>
    DoorRecord.fromJson({
      'id': id,
      'site_code': 1,
      'site_name': 'Güneş Sitesi',
      'door_name': name,
      'door_index': id,
      'is_active': true,
      'access_scope': 'SITE',
      'assigned_device_id': uid == null ? null : 100 + id,
      'assigned_device_uid': uid,
      'assigned_device_hardware_target': uid != null ? 'esp32-c3' : null,
      'created_at': '2026-01-01T00:00:00Z',
    });

class _AssignMockAuth extends AuthService {
  _AssignMockAuth({
    this.sites = const [],
    this.doors = const [],
  }) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final List<SiteRecord> sites;
  final List<DoorRecord> doors;
  String? assignError;

  int? assignedDoorId;
  String? assignedDeviceUid;

  @override
  Future<SitePage> listSites({
    int page = 1,
    int pageSize = 50,
    String? approvalStatus,
  }) async {
    return SitePage(
        sites: sites, page: page, pageSize: pageSize, total: sites.length);
  }

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({
    required int siteCode,
  }) async {
    final s = sites.firstWhere((item) => item.id == siteCode,
        orElse: () => _site(siteCode, 'Site $siteCode'));
    return (
      SiteStructureRecord(
        site: s,
        blocks: const [],
        apartments: const [],
        doors: doors,
      ),
      null,
    );
  }

  @override
  Future<(DoorRecord?, String?)> assignDoorDevice({
    required int doorId,
    required String deviceUid,
  }) async {
    assignedDoorId = doorId;
    assignedDeviceUid = deviceUid;
    if (assignError != null) return (null, assignError);
    final d = doors.firstWhere((x) => x.id == doorId,
        orElse: () => _door(id: doorId, name: 'Kapı $doorId'));
    return (d, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClaimDeviceAssignDialog Tests', () {
    testWidgets(
        'Kapıları listeler, bir kapı seçilip "Kapıya Ata" tıklandığında başarıyla döner',
        (t) async {
      final s = _site(1, 'Güneş Sitesi');
      final d1 = _door(id: 1, name: 'Ana Giriş', uid: null);
      final d2 = _door(id: 2, name: 'Otopark', uid: 'GD-C3-OLD123');

      final auth = _AssignMockAuth(sites: [s], doors: [d1, d2]);

      ClaimDeviceAssignResult? result;
      await openDialogAt(
        t,
        (context) async {
          result = await ClaimDeviceAssignDialog.show(
            context,
            authService: auth,
            deviceUid: 'GD-C3-NEW999',
            sites: [s],
          );
        },
        width: 390,
        height: 844,
        scale: 1.0,
        dark: false,
      );

      await t.pumpAndSettle();

      expect(find.text('Cihaz Başarıyla Eklendi'), findsOneWidget);
      expect(find.textContaining('GD-C3-NEW999'), findsWidgets);
      expect(find.textContaining('Ana Giriş'), findsOneWidget);

      final assignBtn =
          find.byKey(const ValueKey<String>('claim_device_assign_btn'));
      expect(assignBtn, findsOneWidget);

      await t.tap(assignBtn);
      await t.pumpAndSettle();

      expect(auth.assignedDoorId, 1);
      expect(auth.assignedDeviceUid, 'GD-C3-NEW999');
      expect(result?.outcome, ClaimDeviceAssignOutcome.assigned);
    });

    testWidgets('"Yeni Kapı Oluştur" tıklandığında createDoor sonucu ile kapanır',
        (t) async {
      final s = _site(1, 'Güneş Sitesi');
      final auth = _AssignMockAuth(sites: [s], doors: []);

      ClaimDeviceAssignResult? result;
      await openDialogAt(
        t,
        (context) async {
          result = await ClaimDeviceAssignDialog.show(
            context,
            authService: auth,
            deviceUid: 'GD-C3-NEW999',
            sites: [s],
          );
        },
        width: 390,
        height: 844,
        scale: 1.0,
        dark: false,
      );

      await t.pumpAndSettle();

      final createBtn =
          find.byKey(const ValueKey<String>('claim_device_create_door_btn'));
      expect(createBtn, findsOneWidget);

      await t.tap(createBtn);
      await t.pumpAndSettle();

      expect(result?.outcome, ClaimDeviceAssignOutcome.createDoor);
    });

    testWidgets(
        '"Daha Sonra" tıklandığında dismissed sonucu döner (sadece cihaz ekle bırak)',
        (t) async {
      final s = _site(1, 'Güneş Sitesi');
      final auth = _AssignMockAuth(sites: [s], doors: []);

      ClaimDeviceAssignResult? result;
      await openDialogAt(
        t,
        (context) async {
          result = await ClaimDeviceAssignDialog.show(
            context,
            authService: auth,
            deviceUid: 'GD-C3-NEW999',
            sites: [s],
          );
        },
        width: 390,
        height: 844,
        scale: 1.0,
        dark: false,
      );

      await t.pumpAndSettle();

      final laterBtn =
          find.byKey(const ValueKey<String>('claim_device_later_btn'));
      expect(laterBtn, findsOneWidget);

      await t.tap(laterBtn);
      await t.pumpAndSettle();

      expect(result?.outcome, ClaimDeviceAssignOutcome.dismissed);
    });

    testWidgets(
        'Site kapısı olmadığında kullanıcıya bilgi mesajı verilir ve taşma oluşmaz',
        (t) async {
      final s = _site(1, 'Boş Kapısız Site');
      final auth = _AssignMockAuth(sites: [s], doors: []);

      await openDialogAt(
        t,
        (context) => ClaimDeviceAssignDialog.show(
          context,
          authService: auth,
          deviceUid: 'GD-C3-TEST',
          sites: [s],
        ),
        width: 320,
        height: 640,
        scale: 1.0,
        dark: false,
      );

      await t.pumpAndSettle();

      expect(
          find.textContaining('Bu sitede henüz tanımlı bir kapı bulunmuyor'),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('claim_device_assign_btn')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('claim_device_create_door_btn')),
          findsOneWidget);
    });
  });
}
