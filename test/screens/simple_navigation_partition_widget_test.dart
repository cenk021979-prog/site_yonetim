import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/site_application_tracker.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/ui/design/view_mode_toggle.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/helpers/simple_navigation.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/manager_call_tile.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_application_status_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import 'emergency_view_test.dart' show alarmReviewTheme, loadAlarmReviewFont;

const _debt = MyFinance(
  items: [
    MyFinanceApartment(
      siteCode: 11,
      apartmentId: 101,
      siteName: 'SANAL Gül',
      label: 'A / 1',
      balanceMinor: 12345,
    ),
  ],
);
const _pending = SiteApplication(
  id: 41,
  status: SiteApplicationStatus.pending,
  siteName: 'SANAL başvuru',
);

// Contract examples of an already-authorized input, not a second permission
// implementation. Expected ownership is independent of the product helper.
const _residentOwners = <SirketMenuItem, SimpleTopic>{
  SirketMenuItem.dairem: SimpleTopic.home,
  SirketMenuItem.kapilar: SimpleTopic.home,
  SirketMenuItem.acilDurum: SimpleTopic.home,
  SirketMenuItem.katilimVeKurulum: SimpleTopic.home,
  SirketMenuItem.borcum: SimpleTopic.payments,
  SirketMenuItem.taleplerim: SimpleTopic.site,
  SirketMenuItem.duyurular: SimpleTopic.site,
  SirketMenuItem.belgeler: SimpleTopic.site,
  SirketMenuItem.rehber: SimpleTopic.site,
  SirketMenuItem.komsuPanosu: SimpleTopic.site,
  SirketMenuItem.profilim: SimpleTopic.site,
};
const _adminOwners = <SirketMenuItem, SimpleTopic>{
  SirketMenuItem.finans: SimpleTopic.finance,
  SirketMenuItem.sayaclar: SimpleTopic.finance,
  SirketMenuItem.isletmeProjesi: SimpleTopic.finance,
  SirketMenuItem.kisiler: SimpleTopic.apartments,
  SirketMenuItem.daireKullanicilariYonetimi: SimpleTopic.apartments,
  SirketMenuItem.kapilar: SimpleTopic.management,
  SirketMenuItem.profilim: SimpleTopic.management,
  SirketMenuItem.moduller: SimpleTopic.management,
  SirketMenuItem.kayitliCihazlar: SimpleTopic.management,
  SirketMenuItem.duyurular: SimpleTopic.management,
  SirketMenuItem.talepler: SimpleTopic.management,
  SirketMenuItem.ekipmanBakim: SimpleTopic.management,
};

class _Calls {
  final opened = <SirketMenuItem>[];
  final payments = <int>[];
  final opaque = <String, int>{};
  int guest = 0, help = 0, all = 0;
  Widget marker(String id) => TextButton(
    key: ValueKey(id),
    onPressed: () => opaque.update(id, (n) => n + 1, ifAbsent: () => 1),
    child: Text(id),
  );
}

Set<SirketMenuItem> _renderedRoutes(WidgetTester t) => {
  for (final item in SirketMenuItem.values)
    if (find.byKey(ValueKey('simple_route_${item.name}')).evaluate().isNotEmpty)
      item,
};

Future<void> _tap(WidgetTester t, String id) async {
  final target = find.byKey(ValueKey(id));
  await t.ensureVisible(target);
  await t.pump();
  expect(target.hitTestable(), findsOneWidget);
  await t.tap(target);
  await t.pump();
}

Future<void> _render(
  WidgetTester t, {
  required ShowcaseAudience audience,
  required SimpleTopic topic,
  required ViewModeService viewMode,
  required _Calls calls,
  required SiteApplicationTracker applications,
  bool financeFailure = false,
}) async {
  final admin = audience == ShowcaseAudience.admin;
  final owners = admin ? _adminOwners : _residentOwners;
  await t.pumpWidget(
    MaterialApp(
      theme: alarmReviewTheme(false),
      home: ViewModeScope(
        service: viewMode,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ModuleShowcaseView(
                key: const ValueKey('partition_subject'),
                session: UserSession(
                  id: 7,
                  fullName: 'SANAL kullanıcı',
                  email: 'qa@example.invalid',
                  loginName: null,
                  role: admin ? UserRole.siteManager : UserRole.apartmentOwner,
                  isActive: true,
                  token: 'fixture-only',
                ),
                audience: audience,
                menuItems: [SirketMenuItem.dashboard, ...owners.keys],
                onOpen: calls.opened.add,
                simple: true,
                simpleTopic: topic,
                // A nonfeatured allowed item still needs exactly one permanent owner.
                featuredItems: const {SirketMenuItem.kapilar},
                badgeCounts: const {SirketMenuItem.duyurular: 3},
                fetchMyFinance: admin
                    ? null
                    : () async {
                        if (financeFailure) {
                          throw StateError('controlled finance unavailable');
                        }
                        return _debt;
                      },
                onPay: (item) => calls.payments.add(item.apartmentId),
                residentSiteName: 'SANAL Gül',
                applications: applications,
                onReapply: (_) async {},
                applicantRole: true,
                aboveHero: calls.marker('qa_unread_announcement'),
                belowHero: calls.marker('qa_invitation'),
                attentionBar: calls.marker('qa_classic_attention'),
                simpleTodayOverview: const Text(
                  'Salt okunur güncel durum',
                  key: ValueKey('qa_today_overview'),
                ),
                simpleFinanceAttention: calls.marker('qa_finance_attention'),
                simpleManagementAttention: calls.marker('qa_management_setup'),
                managerPhoneMissing: admin,
                onCreateGuestPass: () => calls.guest++,
                onOpenHelp: () => calls.help++,
                onOpenAllActions: () => calls.all++,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 350));
}

SiteApplicationTracker _tracker() => SiteApplicationTracker(
  fetch: () async => const MySiteApplications(items: [_pending]),
  cancel: (_) async => _pending,
);

void main() {
  setUpAll(loadAlarmReviewFont);
  for (final audience in [ShowcaseAudience.resident, ShowcaseAudience.admin]) {
    for (final mode in [ListViewMode.list, ListViewMode.tiles]) {
      testWidgets(
        'actual showcase has one owner for routes and supplied actions ${audience.name} ${mode.name}',
        (t) async {
          SharedPreferences.setMockInitialValues({});
          final service = ViewModeService();
          await service.setMode(ViewScreen.simpleModules, mode);
          final applications = _tracker();
          final calls = _Calls();
          final seen = <SirketMenuItem, int>{};
          final owners = audience == ShowcaseAudience.admin
              ? _adminOwners
              : _residentOwners;
          final admin = audience == ShowcaseAudience.admin;
          final topics = admin
              ? [
                  SimpleTopic.today,
                  SimpleTopic.finance,
                  SimpleTopic.apartments,
                  SimpleTopic.management,
                ]
              : [
                  SimpleTopic.today,
                  SimpleTopic.home,
                  SimpleTopic.payments,
                  SimpleTopic.site,
                ];
          final counts = <String, int>{};
          t.view.physicalSize = const Size(1100, 1400);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          try {
            for (final topic in topics) {
              await _render(
                t,
                audience: audience,
                topic: topic,
                viewMode: service,
                calls: calls,
                applications: applications,
              );
              final actual = _renderedRoutes(t);
              expect(
                actual,
                owners.entries
                    .where((entry) => entry.value == topic)
                    .map((entry) => entry.key)
                    .toSet(),
              );
              for (final item in actual) {
                seen.update(item, (n) => n + 1, ifAbsent: () => 1);
                final before = calls.opened.length;
                await _tap(t, 'simple_route_${item.name}');
                expect(calls.opened.length, before + 1);
                expect(
                  calls.opened.last,
                  item,
                  reason: 'list/tile reaches the same actual onOpen dispatcher',
                );
              }
              for (final (id, owner) in <(String, SimpleTopic)>[
                ('qa_today_overview', SimpleTopic.today),
                if (!admin) ('qa_unread_announcement', SimpleTopic.site),
                if (!admin) ('qa_invitation', SimpleTopic.home),
                if (admin) ('qa_finance_attention', SimpleTopic.finance),
                if (admin) ('qa_management_setup', SimpleTopic.management),
              ]) {
                final marker = find.byKey(ValueKey(id));
                expect(
                  marker,
                  topic == owner ? findsOneWidget : findsNothing,
                  reason:
                      '$id must be rendered by the actual owning topic only',
                );
                if (marker.evaluate().isNotEmpty) {
                  counts.update(id, (n) => n + 1, ifAbsent: () => 1);
                  if (id != 'qa_today_overview') await _tap(t, id);
                }
              }
              expect(
                find.byKey(const ValueKey('qa_classic_attention')),
                findsNothing,
              );
              if (admin) {
                expect(
                  find.byKey(const ValueKey('qa_unread_announcement')),
                  findsNothing,
                );
                expect(
                  find.byKey(const ValueKey('qa_invitation')),
                  findsNothing,
                );
                expect(
                  find.byType(ManagerPhoneHint),
                  findsNothing,
                );
              }
              expect(
                find.byType(SiteApplicationStatusCard),
                topic == (admin ? SimpleTopic.management : SimpleTopic.home)
                    ? findsOneWidget
                    : findsNothing,
              );
              expect(
                find.byKey(const ValueKey('panel_hero_borc')),
                !admin && topic == SimpleTopic.payments
                    ? findsOneWidget
                    : findsNothing,
              );
              expect(
                find.byKey(const ValueKey('panel_hero_ode')),
                !admin && topic == SimpleTopic.payments
                    ? findsOneWidget
                    : findsNothing,
              );
              expect(
                find.byKey(const ValueKey('panel_hero_borcuma_git')),
                !admin && topic == SimpleTopic.payments
                    ? findsOneWidget
                    : findsNothing,
              );
              if (!admin && topic == SimpleTopic.payments) {
                await _tap(t, 'panel_hero_ode');
                expect(calls.payments, [101]);
                await _tap(t, 'panel_hero_borcuma_git');
                expect(calls.opened.last, SirketMenuItem.borcum);
              }
              for (final (id, owner) in [
                ('simple_action_guest_pass', SimpleTopic.home),
                (
                  'simple_action_help',
                  admin ? SimpleTopic.management : SimpleTopic.site,
                ),
                (
                  'simple_action_all',
                  admin ? SimpleTopic.management : SimpleTopic.site,
                ),
              ]) {
                expect(
                  find.byKey(ValueKey(id)),
                  topic == owner ? findsOneWidget : findsNothing,
                );
                if (topic == owner) await _tap(t, id);
              }
              if (topic == SimpleTopic.today) {
                expect(actual, isEmpty);
                expect(
                  find.byType(TextButton),
                  findsNothing,
                  reason: 'Today contains no supplied opaque action callbacks',
                );
                expect(
                  find.byKey(const ValueKey('gorunum_anahtari_simpleModules')),
                  findsNothing,
                );
              }
              expect(t.takeException(), isNull);
            }
            expect(seen.keys.toSet(), owners.keys.toSet());
            expect(seen.values.every((n) => n == 1), isTrue);
            expect(counts.values.every((n) => n == 1), isTrue);
            expect(calls.guest, admin ? 0 : 1);
            expect(calls.help, 1);
            expect(calls.all, 1);
            expect(calls.opaque['qa_unread_announcement'], admin ? isNull : 1);
            expect(calls.opaque['qa_invitation'], admin ? isNull : 1);
            expect(calls.opaque['qa_finance_attention'], admin ? 1 : isNull);
            expect(calls.opaque['qa_management_setup'], admin ? 1 : isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            applications.dispose();
            service.dispose();
            await t.pump();
          }
        },
      );
    }
  }

  testWidgets(
    'finance error is not zero debt and its Borcum action exists in Payments only',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final service = ViewModeService();
      final applications = _tracker();
      final calls = _Calls();
      try {
        for (final topic in [
          SimpleTopic.today,
          SimpleTopic.home,
          SimpleTopic.payments,
          SimpleTopic.site,
        ]) {
          await _render(
            t,
            audience: ShowcaseAudience.resident,
            topic: topic,
            viewMode: service,
            calls: calls,
            applications: applications,
            financeFailure: true,
          );
          expect(
            find.text('Borç bilginiz şu an alınamadı.'),
            topic == SimpleTopic.payments ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('panel_hero_borcuma_git')),
            topic == SimpleTopic.payments ? findsOneWidget : findsNothing,
          );
          expect(find.byKey(const ValueKey('panel_hero_ode')), findsNothing);
          expect(find.byKey(const ValueKey('panel_hero_borc')), findsNothing);
          if (topic == SimpleTopic.payments) {
            await _tap(t, 'panel_hero_borcuma_git');
            expect(calls.opened, [SirketMenuItem.borcum]);
          }
          expect(t.takeException(), isNull);
        }
        expect(calls.payments, isEmpty);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        applications.dispose();
        service.dispose();
        await t.pump();
      }
    },
  );
}
