import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/views/super_user_dashboard_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import 'modules_fixtures.dart';

class _FakeDashboardAuth extends ModulesFakeAuth {
  _FakeDashboardAuth() : super();

  @override
  Future<Map<String, dynamic>> getSuperUserDashboardSummary() async => <String, dynamic>{
    'ok': true,
    'attention': <String, dynamic>{
      'pending_site_applications': 3,
      'pending_module_requests': 2,
      'unresolved_client_errors': 4,
      'unique_client_errors': 1,
      'total_feedbacks': 5,
    },
    'platform': <String, dynamic>{
      'total_sites': 15,
      'active_sites': 12,
      'passive_sites': 3,
      'total_apartments': 320,
      'occupied_apartments': 280,
      'empty_apartments': 40,
      'total_users': 450,
      'site_managers': 20,
      'apartment_users': 420,
      'super_users': 3,
      'individuals': 7,
    },
    'iot': <String, dynamic>{
      'total_doors': 25,
      'active_doors': 22,
      'total_devices': 20,
      'online_devices': 18,
      'offline_devices': 2,
      'esp32_c3_count': 14,
      'esp32_wroom_count': 6,
      'today_door_passes': 156,
    },
    'system': <String, dynamic>{
      'database': 'connected',
      'mqtt': <String, dynamic>{
        'configured': true,
        'connected': true,
        'has_error': false,
      },
      'uptime_seconds': 180000,
      'server_time': '2026-11-16T21:00:00Z',
      'version': '1.0.0',
    },
  };
}

void main() {
  group('SuperUserDashboardView', () {
    testWidgets('Tüm bölümler ve metrikler ekranda eksiksiz çizilir', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final auth = _FakeDashboardAuth();
      SirketMenuItem? navigatedItem;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SuperUserDashboardView(
                authService: auth,
                onNavigate: (item) => navigatedItem = item,
              ),
            ),
          ),
        ),
      );

      // Yükleme tamamlanana kadar bekle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Başlık kontrolü
      expect(find.text('Sistem ve Platform Genel Bakışı'), findsOneWidget);

      // 2. Bekleyen işler (Attention)
      expect(find.text('3 Site Kurulum Başvurusu'), findsOneWidget);
      expect(find.text('2 Ek Modül Talebi'), findsOneWidget);
      expect(find.text('4 İstemci Hatası'), findsOneWidget);

      // 3. Platform Hacmi
      expect(find.text('Sitelerimiz'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('Daireler'), findsOneWidget);
      expect(find.text('320'), findsOneWidget);
      expect(find.text('Kullanıcı Hesapları'), findsOneWidget);
      expect(find.text('450'), findsOneWidget);

      // 4. Donanım & IoT
      expect(find.text('Canlı Cihaz Durumu'), findsOneWidget);
      expect(find.text('18'), findsOneWidget); // online devices
      expect(find.text('Donanım Mimarisi'), findsOneWidget);
      expect(find.text('14 ESP32-C3'), findsOneWidget);
      expect(find.text('6 ESP32-WROOM'), findsOneWidget);
      expect(find.text('Kapı ve Geçiş Trafiği'), findsOneWidget);
      expect(find.text('156'), findsOneWidget); // today passes

      // 5. Altyapı ve Sunucu Nabzı
      expect(find.text('PostgreSQL Veritabanı'), findsOneWidget);
      expect(find.text('MQTT Broker Haberleşmesi'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);

      // 6. Kısayol tıklama testi
      await tester.tap(find.text('3 Site Kurulum Başvurusu'));
      await tester.pump();
      expect(navigatedItem, SirketMenuItem.siteBasvurulari);

      final newDeviceBtn = find.text('Yeni Cihaz Kaydet');
      await tester.ensureVisible(newDeviceBtn);
      await tester.pump();
      await tester.tap(newDeviceBtn);
      await tester.pump();
      expect(navigatedItem, SirketMenuItem.kayitliCihazlar);
    });

    testWidgets('Taşma testi: 320x640 ve 360x640 ekranlarda açık ve koyu temada sıfır taşma', (tester) async {
      final auth = _FakeDashboardAuth();
      final testSizes = [
        const Size(320, 640),
        const Size(360, 640),
        const Size(412, 915),
      ];

      for (final size in testSizes) {
        for (final isDark in [false, true]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            MaterialApp(
              theme: isDark ? AppTheme.dark() : AppTheme.light(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SuperUserDashboardView(
                    authService: auth,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // Ekranda render hatası veya taşma olmadığını doğrula
          expect(tester.takeException(), isNull, reason: 'Size: $size, dark: $isDark taşma olmamalıdır');
        }
      }

      tester.view.reset();
    });
  });
}
