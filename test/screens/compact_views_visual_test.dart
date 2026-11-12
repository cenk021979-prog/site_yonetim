import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_management.dart';
import 'package:site_kapi_kontrol/models/apartment_vehicles.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/views/my_apartment_view.dart';
import 'package:site_kapi_kontrol/ui/views/survey_manager_view.dart';

import 'people_fixtures.dart';
import 'simple_appearance_home_test.dart' show loadSimpleReviewFonts, simpleReviewTheme;
import 'survey_fixtures.dart';

class _ApartmentReviewService extends ApartmentManagementService {
  _ApartmentReviewService() : super(authService: PeopleFakeAuth());
  @override
  Future<MyApartmentsData> mine() async => const MyApartmentsData(apartments: [
    MyApartment(apartmentId: 5, siteCode: 11, siteName: 'Örnek Konutları', label: 'A Blok · Daire 1', myRole: 'owner', isAdmin: true, isOwner: true,
      adminName: 'Deniz Yılmaz', adminSide: 'owner', owner: AptPerson(personId: 1, name: 'Deniz Yılmaz', hasAccount: true),
      can: AptCan(manageFamily: true, addTenant: true, searchPeople: true),
      family: [AptFamilyMember(residencyId: 21, name: 'Ekin Yılmaz', relation: 'family_member', hasAccount: true, canRemove: true)],
    ),
  ]);
  @override
  Future<ApartmentVehicles> vehicles(int apartmentId) async => const ApartmentVehicles(canManage: true, apartmentApproved: false, items: [
    VehicleRecord(id: 1, plate: '34ABC123', plateDisplay: '34 ABC 123', personName: 'Deniz Yılmaz', note: 'Beyaz otomobil'),
  ]);
}

void main() {
  setUpAll(loadSimpleReviewFonts);
  for (final (width, height, scale) in <(double, double, double)>[(1366, 768, 1), (390, 844, 1), (320, 640, 2)]) {
    for (final dark in [false, true]) {
      testWidgets('Dairem gerçek görünüm ${width.toInt()} ${dark ? 'dark' : 'light'}', (t) async {
        final service = _ApartmentReviewService();
        await _render(t, width: width, height: height, scale: scale, dark: dark, name: 'apartment',
          view: MyApartmentView(authService: service.authService, service: service));
        final rect = t.getRect(find.text('Araçlarım'));
        if (width > 1000) {
          expect(rect.top, lessThan(250));
          expect(rect.left, greaterThan(width / 2 - 10));
        }
      });
    }
  }
  for (final (width, height, scale) in <(double, double, double)>[(1366, 768, 1), (320, 640, 2)]) {
    testWidgets('Anket üst kapsam gerçek görünüm ${width.toInt()}', (t) async {
      final auth = SurveyFakeAuth();
      await _render(t, width: width, height: height, scale: scale, dark: false, name: 'survey-scoped',
        view: SurveyManagerView(authService: auth, service: seededSurvey(auth), sites: const [SurveySite(code: 11, name: 'Gül Sitesi'), SurveySite(code: 12, name: 'Mavi Park')], scopedSiteCode: 11));
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      if (width > 1000) {
        for (final id in [1, 2, 3]) {
          expect(t.getRect(svKey('svm_card_$id')).bottom, lessThanOrEqualTo(height), reason: 'Üç anket geniş ekranda kaydırmadan tam görünmeli');
        }
        expect(t.getRect(svKey('svm_card_3')).top, lessThan(220));
      }
    });
  }
}

Future<void> _render(WidgetTester t, {required double width, required double height, required double scale, required bool dark, required String name, required Widget view}) async {
  const key = ValueKey('compact_view_review');
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: simpleReviewTheme(dark),
    builder: (context, child) => RepaintBoundary(key: key, child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!)),
    home: Scaffold(appBar: AppBar(title: Text(name == 'apartment' ? 'Dairem' : 'Anket ve Oylama · Gül Sitesi')), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: view)),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 650));
  await t.pump(const Duration(milliseconds: 650));
  expect(t.takeException(), isNull);
  await t.runAsync(() async {
    const directory = String.fromEnvironment('SIMPLE_REVIEW_DIR', defaultValue: 'work/sade-redesign-2026-11-10');
    await Directory(directory).create(recursive: true);
    final image = await t.renderObject<RenderRepaintBoundary>(find.byKey(key)).toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name-${width.toInt()}-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
