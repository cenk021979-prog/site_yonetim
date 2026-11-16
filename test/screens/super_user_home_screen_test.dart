import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/super_user_dashboard_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import 'modules_fixtures.dart';

class _SuperUserAuth extends ModulesFakeAuth {
  _SuperUserAuth() : super();

  @override
  UserSession? get session => const UserSession(
    id: 1,
    fullName: 'Süper Yönetici',
    email: 'super@example.com',
    loginName: 'super.admin',
    role: UserRole.superUser,
    isActive: true,
    token: 'super_token',
  );

  @override
  Future<MyModulesResult> getMyModules() async => const MyModulesResult(scope: 'all');

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async {
    final site = sites.firstWhere((s) => s.id == siteCode, orElse: () => sites.first);
    return (
      SiteStructureRecord(
        site: site,
        blocks: const <SiteBlockRecord>[],
        apartments: const <ApartmentRecord>[],
        doors: const <DoorRecord>[],
      ),
      null,
    );
  }

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);

  @override
  Future<MySiteApplications> getMySiteApplications() async => const MySiteApplications();

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<Map<String, dynamic>> getSuperUserDashboardSummary() async => <String, dynamic>{
    'ok': true,
    'attention': <String, dynamic>{
      'pending_site_applications': 2,
      'pending_module_requests': 1,
      'unresolved_client_errors': 0,
      'unique_client_errors': 0,
      'total_feedbacks': 3,
    },
    'platform': <String, dynamic>{
      'total_sites': 12,
      'active_sites': 10,
      'passive_sites': 2,
      'total_apartments': 240,
      'occupied_apartments': 200,
      'empty_apartments': 40,
      'total_users': 310,
      'site_managers': 14,
      'apartment_users': 290,
      'super_users': 2,
      'individuals': 4,
    },
    'iot': <String, dynamic>{
      'total_doors': 18,
      'active_doors': 16,
      'total_devices': 14,
      'online_devices': 12,
      'offline_devices': 2,
      'esp32_c3_count': 10,
      'esp32_wroom_count': 4,
      'today_door_passes': 84,
    },
    'system': <String, dynamic>{
      'database': 'connected',
      'mqtt': <String, dynamic>{
        'configured': true,
        'connected': true,
        'has_error': false,
      },
      'uptime_seconds': 7200,
      'server_time': '2026-11-16T20:00:00Z',
      'version': '1.0.0',
    },
  };
}

void main() {
  testWidgets('Süper kullanıcı: sakin modu / ikili mod anahtarı, daireye katıl ve yeni site başvurusu tamamen kaldırılmıştır', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = _SuperUserAuth();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: HomePage(authService: auth),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Panel ekranında Süper Kullanıcı Dashboard (Cockpit) görünmelidir
    expect(find.byType(SuperUserDashboardView), findsOneWidget);
    expect(find.text('Sistem ve Platform Genel Bakışı'), findsOneWidget);

    // 1. AppBar üzerinde 'Sakin Moduna Geç', 'Yönetici Paneli', veya ikili mod hap butonu olmamalıdır
    expect(find.text('Sakin Moduna Geç'), findsNothing);
    expect(find.text('Sakin Görünümü'), findsNothing);
    expect(find.text('Yönetici Görünümü'), findsNothing);
    expect(find.byKey(const ValueKey<String>('appbar_mode_toggle')), findsNothing);

    // 2. YanMenu'de süper kullanıcı için görünür öğeler arasında 'katilimVeKurulum' ve 'yeniSite' olmamalıdır
    final visibleItems = YanMenu.visibleItems(role: UserRole.superUser);
    expect(visibleItems.contains(SirketMenuItem.katilimVeKurulum), isFalse);
    expect(visibleItems.contains(SirketMenuItem.yeniSite), isFalse);
    expect(visibleItems.length, 14);
    expect(visibleItems.contains(SirketMenuItem.kullaniciYonetimi), isTrue);
    expect(visibleItems.contains(SirketMenuItem.modulGelistirme), isTrue);
    expect(visibleItems.contains(SirketMenuItem.kayitliCihazlar), isTrue);
    expect(visibleItems.contains(SirketMenuItem.superUserYonetimi), isFalse);
    expect(visibleItems.contains(SirketMenuItem.siteYoneticileriYonetimi), isFalse);
    expect(visibleItems.contains(SirketMenuItem.devreyeAlinanModuller), isFalse);
    expect(visibleItems.contains(SirketMenuItem.pasifModuller), isFalse);
    expect(visibleItems.contains(SirketMenuItem.cihazEkle), isFalse);
    expect(visibleItems.contains(SirketMenuItem.daireKullanicilariYonetimi), isFalse);

    // 3. Sol çekmeceyi aç ve kontrol et
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    // Çekmecede mod geçiş switch'i olmamalıdır
    expect(find.text('Sakin Moduna Geç'), findsNothing);
    expect(find.text('Yönetici Paneline Geç'), findsNothing);

    // Çekmecede daireye katılma veya yeni site başvurusu olmamalıdır
    expect(find.text('Daireye Katıl'), findsNothing);
    expect(find.text('Yeni Site Oluştur'), findsNothing);

    // Çekmecede süper kullanıcı yönetim öğeleri bulunmalıdır
    final drawer = find.byType(Drawer);
    expect(find.descendant(of: drawer, matching: find.text('Panel')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Site Yönetimi')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Kullanıcı Yönetimi')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Siteye Göre Kişilerin Yönetimi')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Tüm Kullanıcı Yönetimi')), findsOneWidget);
    expect(find.descendant(of: drawer, matching: find.text('Daire Sakinleri')), findsNothing);
    expect(find.descendant(of: drawer, matching: find.text('Yardım ve Destek')), findsNothing);
    expect(find.descendant(of: drawer, matching: find.text('Geri bildirim')), findsNothing);

    // 4. Sağ ayarlar panelini (endDrawer) aç ve kontrol et
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openEndDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    // Süper kullanıcı için "Geri bildirim gönder" ve "Gönderdiğim geri bildirimler" ayarlar panelinde de olmamalıdır
    expect(find.text('Geri bildirim gönder'), findsNothing);
    expect(find.text('Gönderdiğim geri bildirimler'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
