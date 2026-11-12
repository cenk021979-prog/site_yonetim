import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/parking_access.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/widgets/parking_access_panel.dart';
import 'package:site_kapi_kontrol/ui/widgets/vehicle_registration_photo_actions.dart';

import 'design/harness.dart';
import 'screens/work_fixtures.dart' show kWkPng;

class _Auth extends Fake implements AuthService {
  UserSession? current = const UserSession(
    id: 7,
    fullName: 'Test',
    email: 'test@example.invalid',
    loginName: null,
    role: UserRole.siteManager,
    isActive: true,
    token: 'scope-a',
  );
  @override
  UserSession? get session => current;
}

class _Photos extends Fake implements ApartmentManagementService {
  @override
  final _Auth authService = _Auth();
  final reads = <(int, int)>[];
  final removals = <(int, int)>[];
  Completer<Uint8List>? gate;
  @override
  Future<Uint8List> registrationPhoto(int apartment, int vehicle) {
    reads.add((apartment, vehicle));
    return gate?.future ?? Future.value(kWkPng);
  }

  @override
  Future<void> removeRegistrationPhoto(int apartment, int vehicle) async =>
      removals.add((apartment, vehicle));
}

ParkingOverview _overview(int site) => ParkingOverview(
  enabled: true,
  capacity: 5,
  photoEnabled: true,
  total: 1,
  notice: 'Geçiş kaydına göre; fiziksel geçiş sensörü teyidi yoktur.',
  apartments: [
    {
      'id': site * 10,
      'block_name': 'Çok Uzun Adlı Kuzey Bahçesi Rezidans Bloku',
      'unit_label': 'Çok Uzun Daire Adı 1205',
      'parking_slots': 1,
      'approved': true,
      'plates': ['34ABC123', '06XYZ456', '35AB789'],
      'inside_plates': ['34ABC123'],
      'photo_vehicles': [
        {'id': site * 10 + 1, 'plate': '34ABC123'},
      ],
    },
  ],
  reservations: [
    {
      'id': 2,
      'plate': '34ABC123',
      'status': 'uncertain',
      'origin': 'admission',
    },
  ],
);

class _Parking extends Fake implements PlateRecognitionService {
  @override
  final _Auth authService = _Auth();
  Completer<String>? photoGate;
  final photoReads = <(int, int)>[];
  final changes = <(int, int)>[];
  final Map<int, Completer<ParkingOverview>> loads = {};
  @override
  Future<ParkingOverview> parking(int site) =>
      loads[site]?.future ?? Future.value(_overview(site));
  @override
  Future<String> parkingPhoto(int apartment, int vehicle) {
    photoReads.add((apartment, vehicle));
    return photoGate?.future ?? Future.value(base64Encode(kWkPng));
  }

  @override
  Future<ParkingOverview> saveApartmentParking(
    int site,
    int apartment, {
    required bool approved,
    required int slots,
  }) async {
    changes.add((site, apartment));
    return _overview(site);
  }
}

typedef _Target = ({int apartment, int vehicle, bool canUpload});
typedef _Site = ({int site, bool canWrite});

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets(
    'ruhsat GET beklerken daire/araç değişirse eski görsel yeni kaydın üstünde açılmaz',
    (t) async {
      final service = _Photos()..gate = Completer<Uint8List>();
      final target = ValueNotifier<_Target>((
        apartment: 10,
        vehicle: 11,
        canUpload: true,
      ));
      addTearDown(target.dispose);
      await pumpAt(
        t,
        ValueListenableBuilder<_Target>(
          valueListenable: target,
          builder: (_, value, _) => VehicleRegistrationPhotoActions(
            service: service,
            apartmentId: value.apartment,
            vehicleId: value.vehicle,
            hasPhoto: true,
            canUpload: value.canUpload,
            onChanged: () async {},
          ),
        ),
        width: 500,
        height: 900,
        scale: 1,
      );
      await t.tap(find.text('Ruhsatı görüntüle'));
      await t.pump();
      target.value = (apartment: 20, vehicle: 21, canUpload: true);
      await t.pump();
      service.gate!.complete(kWkPng);
      await _settle(t);
      expect(find.byType(Dialog), findsNothing);
      expect(service.reads, [(10, 11)]);
      service.gate = null;
      await t.tap(find.text('Ruhsatı görüntüle'));
      await _settle(t);
      expect(service.reads, [(10, 11), (20, 21)]);
      expect(find.byType(Dialog), findsOneWidget);
      await t.tap(find.text('Kapat'));
      await _settle(t);
      expect(t.takeException(), isNull);
    },
  );

  for (final changed in ['apartment', 'vehicle', 'permission', 'session']) {
    testWidgets(
      'ruhsat kaldır onayı beklerken $changed değişirse eski onay yeni kaydı silmez',
      (t) async {
        final service = _Photos();
        final target = ValueNotifier<_Target>((
          apartment: 10,
          vehicle: 11,
          canUpload: true,
        ));
        addTearDown(target.dispose);
        var notified = 0;
        await pumpAt(
          t,
          ValueListenableBuilder<_Target>(
            valueListenable: target,
            builder: (_, value, _) => VehicleRegistrationPhotoActions(
              service: service,
              apartmentId: value.apartment,
              vehicleId: value.vehicle,
              hasPhoto: true,
              canUpload: value.canUpload,
              onChanged: () async {
                notified++;
              },
            ),
          ),
          width: 500,
          height: 900,
          scale: 1,
        );
        await t.tap(find.text('Fotoğrafı kaldır'));
        await _settle(t);
        if (changed == 'session') {
          service.authService.current = service.authService.current!.copyWith(
            token: 'scope-b',
          );
        }
        target.value = (
          apartment: changed == 'apartment' ? 20 : 10,
          vehicle: changed == 'vehicle' ? 21 : 11,
          canUpload: changed != 'permission',
        );
        await t.pump();
        await t.tap(find.text('Kaldır'));
        await _settle(t);
        expect(service.removals, isEmpty);
        expect(notified, 0);
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final change in ['site', 'permission', 'session']) {
    testWidgets(
      'yönetici ruhsat GET yanıtı beklerken $change değişirse eski görüntü açılmaz',
      (t) async {
        final service = _Parking()..photoGate = Completer<String>();
        final target = ValueNotifier<_Site>((site: 1, canWrite: true));
        addTearDown(target.dispose);
        await pumpAt(
          t,
          SizedBox(
            width: double.infinity,
            child: ValueListenableBuilder<_Site>(
              valueListenable: target,
              builder: (_, value, _) => ParkingAccessPanel(
                service: service,
                siteCode: value.site,
                canWrite: value.canWrite,
              ),
            ),
          ),
          width: 600,
          height: 1800,
          scale: 1,
        );
        await _settle(t);
        await t.ensureVisible(find.text('Ruhsat: 34ABC123'));
        await t.tap(find.text('Ruhsat: 34ABC123'));
        await t.pump();
        if (change == 'session') {
          service.authService.current = service.authService.current!.copyWith(
            token: 'scope-b',
          );
        }
        target.value = (
          site: change == 'site' ? 2 : 1,
          canWrite: change != 'permission',
        );
        await t.pump();
        service.photoGate!.complete(base64Encode(kWkPng));
        await _settle(t);
        expect(find.byType(Dialog), findsNothing);
        expect(service.photoReads, [(10, 11)]);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('eski site overview yanıtı yeni sitenin kapasitesini ezmez', (
    t,
  ) async {
    final service = _Parking()..loads[1] = Completer<ParkingOverview>();
    final target = ValueNotifier<int>(1);
    addTearDown(target.dispose);
    await pumpAt(
      t,
      SizedBox(
        width: double.infinity,
        child: ValueListenableBuilder<int>(
          valueListenable: target,
          builder: (_, value, _) => ParkingAccessPanel(
            service: service,
            siteCode: value,
            canWrite: true,
          ),
        ),
      ),
      width: 600,
      height: 1200,
      scale: 1,
    );
    target.value = 2;
    await _settle(t);
    service.loads[1]!.complete(const ParkingOverview(capacity: 99));
    await _settle(t);
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('parking_capacity')))
          .controller!
          .text,
      '5',
    );
    expect(t.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      '320 dp, yüzde200 yazı, ${dark ? 'koyu' : 'açık'}: otopark/ruhsat ve daire diyalogu taşmaz',
      (t) async {
        final service = _Parking();
        final photos = _Photos();
        await pumpAt(
          t,
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ParkingAccessPanel(
                  service: service,
                  siteCode: 1,
                  canWrite: true,
                ),
                VehicleRegistrationPhotoActions(
                  service: photos,
                  apartmentId: 10,
                  vehicleId: 11,
                  hasPhoto: true,
                  onChanged: () async {},
                ),
              ],
            ),
          ),
          width: 320,
          height: 640,
          scale: 2,
          dark: dark,
        );
        await _settle(t);
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('Daire onayı / araç hakkı'));
        await t.pump();
        await t.tap(find.text('Daire onayı / araç hakkı'));
        await _settle(t);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Vazgeç'));
        await t.pump(const Duration(milliseconds: 500));
        expect(
          t.takeException(),
          isNull,
        ); // Controller çıkış animasyonunda erken dispose edilmemeli.
        await t.ensureVisible(find.text('Fiziksel kontrol sonrası düzelt'));
        await t.pump();
        await t.tap(find.text('Fiziksel kontrol sonrası düzelt'));
        await _settle(t);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Vazgeç'));
        await _settle(t);
        await t.ensureVisible(find.text('Fotoğrafı kaldır'));
        await t.pump();
        await t.tap(find.text('Fotoğrafı kaldır'));
        await _settle(t);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Vazgeç'));
        await _settle(t);
        await t.ensureVisible(find.text('Ruhsatı görüntüle'));
        await t.pump();
        await t.tap(find.text('Ruhsatı görüntüle'));
        await _settle(t);
        expect(t.takeException(), isNull);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await t.tap(find.text('Kapat'));
        await _settle(t);
        expect(t.takeException(), isNull);
      },
    );
  }
}
