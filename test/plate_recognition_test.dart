import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/plate_audit_label.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/views/plate_recognition_view.dart';

class _FakeAuth extends Fake implements AuthService {
  @override
  AuthApi get api => AuthApi(baseUrl: 'http://localhost');
}

class _FakeService extends Fake implements PlateRecognitionService {
  _FakeService({this.notificationsAvailable = false});
  final bool notificationsAvailable;
  @override
  Future<PlateGatesOverview> gatesOverview(int site) async =>
      PlateGatesOverview.fromJson(<String, dynamic>{
        'settings': <String, dynamic>{
          'guest_rule': 'tum_bos',
          'heartbeat_warn_seconds': 180,
          'heartbeat_crit_seconds': 600,
        },
        'guest_rules': <dynamic>[],
        'direction_modes': <dynamic>[],
        'gates': <dynamic>[],
        'unassigned_cameras': <dynamic>[],
        'devices': <dynamic>[],
        'edge_clients': <dynamic>[],
        'inside_total': 0,
      });

  @override
  Future<PlateInside> inside(int site) async =>
      PlateInside.fromJson(<String, dynamic>{
        'total': 0,
        'items': <dynamic>[],
        'apartments': <dynamic>[],
      });
  @override
  Future<List<PlateDecisionRow>> events(int site, {String? decision}) async =>
      <PlateDecisionRow>[
        PlateDecisionRow.fromJson(<String, dynamic>{
          'id': 1,
          'plate': '34 ABC 123',
          'decision': 'ALLOWED',
          'reason': 'vehicle',
          'reason_label': 'Kayıtlı araç',
          'confidence': 0.93,
          'auto_action': 'would_open',
          'seen_at': '2026-10-22T10:00:00.000Z',
          'device_name': 'Giriş kamerası',
        }),
        PlateDecisionRow.fromJson(<String, dynamic>{
          'id': 2,
          'plate': '06 ZZ 99',
          'decision': 'DENIED',
          'reason_label': 'Kara listede',
          'auto_action': 'none',
        }),
        PlateDecisionRow.fromJson(<String, dynamic>{
          'id': 3,
          'plate': '35 K 1234',
          'decision': 'UNKNOWN',
          'reason_label': 'Kayıtlı değil',
          'auto_action': 'none',
        }),
      ];

  @override
  Future<PlateResidentOverview> residentOverview(int site) async =>
      PlateResidentOverview.fromJson(<String, dynamic>{
        'movement_notify_available': notificationsAvailable,
        'apartments': <dynamic>[
          <String, dynamic>{'id': 7, 'label': 'A Blok - 3'},
        ],
        'permits': <dynamic>[
          <String, dynamic>{
            'id': 9,
            'apartment_id': 7,
            'apartment_label': 'A Blok - 3',
            'plate': '34ABC123',
            'valid_until': '2099-01-01T00:00:00Z',
            'status': 'active',
          },
        ],
        'daily_limit': 5,
        'daily_remaining': 4,
        'max_days': 30,
      });
}

Future<void> _pump(
  WidgetTester tester,
  PlateSite site, {
  bool notificationsAvailable = false,
  VoidCallback? onOpenVehicles,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        // Ana sayfa gövdesi gibi: kaydırılan, sınırsız yükseklikli üst öğe.
        body: SingleChildScrollView(
          child: PlateRecognitionView(
            authService: _FakeAuth(),
            sites: <PlateSite>[site],
            service: _FakeService(
              notificationsAvailable: notificationsAvailable,
            ),
            onOpenVehicles: onOpenVehicles,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('TR plaka kuralı (sunucuyla aynı)', () {
    test('boşluk / tire / küçük harf / Türkçe harf temizlenir', () {
      expect(normalizeTrPlate('34 abc 123'), '34ABC123');
      expect(normalizeTrPlate('34-ABC-123'), '34ABC123');
      expect(normalizeTrPlate(' 06 a 1234 '), '06A1234');
      expect(canonicalTrPlate('34 şç 123'), '34SC123');
    });

    test('il kodu 01-81 dışı ve bozuk biçim geçersiz', () {
      for (final bad in <String>[
        '00ABC123',
        '82ABC123',
        '99ABC123',
        '34ABCD123',
        '34A1',
        'ABC123',
        '3ABC123',
        '',
        '34 123 ABC',
      ]) {
        expect(normalizeTrPlate(bad), isNull, reason: bad);
      }
    });

    test('biçimleme', () {
      expect(formatTrPlate('34ABC123'), '34 ABC 123');
      expect(formatTrPlate('XX'), 'XX');
    });
  });

  group('modeller ve gövde', () {
    test('karar satırı: otomatik açma kaydı "açılırdı" bayrağı', () {
      final row = PlateDecisionRow.fromJson(<String, dynamic>{
        'id': 1,
        'plate': '34 ABC 123',
        'decision': 'ALLOWED',
        'auto_action': 'would_open',
      });
      expect(row.wouldOpen, isTrue);
      expect(
        PlateDecisionRow.fromJson(<String, dynamic>{
          'id': 2,
          'plate': 'x',
          'decision': 'UNKNOWN',
        }).wouldOpen,
        isFalse,
      );
    });

    test('ayarlar: kapı açma desteklenmiyor bayrağı', () {
      final s = PlateSettings.fromJson(<String, dynamic>{
        'doors': <dynamic>[
          <String, dynamic>{
            'door_id': 5,
            'door_name': 'Ana kapı',
            'device_id': 3,
            'auto_open': true,
            'min_confidence': 0.9,
            'cooldown_seconds': 60,
          },
        ],
        'cameras': <dynamic>[
          <String, dynamic>{'id': 3, 'name': 'Giriş', 'is_active': true},
        ],
        'auto_open_supported': false,
      });
      expect(s.autoOpenSupported, isFalse);
      expect(s.doors.single.autoOpen, isTrue);
      expect(s.doors.single.minConfidence, 0.9);
      expect(s.cameras.single.name, 'Giriş');
    });

    test('izin gövdesi: özel süre yalnız custom ile gider, boş not gitmez', () {
      expect(
        const PermitDraft(
          apartmentId: 7,
          plate: '34ABC123',
          duration: 'day',
          days: 5,
        ).toBody(),
        <String, Object?>{
          'apartment_id': 7,
          'plate': '34ABC123',
          'duration': 'day',
        },
      );
      expect(
        const PermitDraft(
          apartmentId: 7,
          plate: '34ABC123',
          duration: 'custom',
          days: 5,
          note: ' Ali ',
        ).toBody(),
        <String, Object?>{
          'apartment_id': 7,
          'plate': '34ABC123',
          'duration': 'custom',
          'days': 5,
          'note': 'Ali',
        },
      );
    });

    test('site erişimi: yalnız yönetici yazar', () {
      expect(
        const PlateSite(
          code: 1,
          name: 'a',
          access: PlateAccess.manager,
        ).canWrite,
        isTrue,
      );
      expect(
        const PlateSite(
          code: 1,
          name: 'a',
          access: PlateAccess.viewer,
        ).canWrite,
        isFalse,
      );
      expect(
        const PlateSite(
          code: 1,
          name: 'a',
          access: PlateAccess.resident,
        ).canWrite,
        isFalse,
      );
      expect(
        const PlateSite(code: 1, name: ' ', access: PlateAccess.viewer).label,
        'İsimsiz site',
      );
    });

    test('denetim eylemi başlıkları', () {
      expect(plateActionLabel('plate.permit_created'), isNotNull);
      expect(plateActionLabel('plate.auto_open'), contains('otomatik'));
      expect(plateActionLabel('yok.bilinmeyen'), isNull);
    });
  });

  group('ekran (kaydırılan gövdede sınırsız yükseklik hatası yok)', () {
    testWidgets(
      'yönetici: olay satırları karar metniyle, yazma düğmesi ve not',
      (tester) async {
        await _pump(
          tester,
          const PlateSite(
            code: 1,
            name: 'Gül Sitesi',
            access: PlateAccess.manager,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Plaka Tanıma'), findsOneWidget);
        expect(find.text('Geçiş noktaları'), findsWidgets);
        expect(find.text('Olaylar'), findsOneWidget);
        await tester.tap(find.text('Olaylar'));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is LicensePlateBadge &&
                LicensePlateBadge.format(widget.plate) == '34 ABC 123',
          ),
          findsOneWidget,
        );
        expect(find.text('İzinli'), findsOneWidget);
        expect(find.text('Engelli'), findsOneWidget);
        expect(find.text('Bilinmiyor'), findsOneWidget);
        expect(
          find.textContaining('Araçlar ekranından yönetilir'),
          findsOneWidget,
        );
        expect(find.textContaining('kapı komutu göndermez'), findsOneWidget);
        for (final tab in <String>['Olaylar', 'Canlı akış', 'Ayarlar']) {
          expect(find.text(tab), findsOneWidget, reason: tab);
        }
        expect(find.text('Geçiş noktaları'), findsWidgets);
      },
    );

    testWidgets(
      'sakin: kendi araç yolu, kapalı bildirim ve katlı eski izinler',
      (tester) async {
        await _pump(
          tester,
          const PlateSite(
            code: 1,
            name: 'Gül Sitesi',
            access: PlateAccess.resident,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Araçlarım ve bildirimler'), findsOneWidget);
        expect(find.text('Misafir plakası ekle'), findsNothing);
        expect(
          find.byKey(const ValueKey('resident_movement_notifications')),
          findsNothing,
        );
        await tester.tap(find.text('Önceki geçici izinler'));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is LicensePlateBadge &&
                LicensePlateBadge.format(widget.plate) == '34 ABC 123',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('4 / 5'), findsNothing);
        // Sakin sekme / kara liste / ayar görmez.
        expect(find.text('Kara liste'), findsNothing);
        expect(find.text('Ayarlar'), findsNothing);
      },
    );

    testWidgets(
      'yönetim açarsa kişisel tercih görünür ve Araçlarıma git çalışır',
      (tester) async {
        var opened = 0;
        await _pump(
          tester,
          const PlateSite(
            code: 1,
            name: 'Gül Sitesi',
            access: PlateAccess.resident,
          ),
          notificationsAvailable: true,
          onOpenVehicles: () => opened++,
        );
        expect(
          find.byKey(const ValueKey('resident_movement_notifications')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('resident_movement_notifications')),
              )
              .value,
          isFalse,
        );
        await tester.tap(
          find.byKey(const ValueKey('resident_open_own_vehicles')),
        );
        expect(opened, 1);
        expect(find.text('Misafir plakası ekle'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'sakin plaka 320px ve büyük yazıda içerik erişilebilir, taşma yok',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(
          tester,
          const PlateSite(
            code: 1,
            name: 'Uzun isimli site',
            access: PlateAccess.resident,
          ),
          notificationsAvailable: true,
          textScale: 2,
          onOpenVehicles: () {},
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('resident_movement_notifications')),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
