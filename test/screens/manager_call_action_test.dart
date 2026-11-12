import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/manager_contact.dart';
import 'package:site_kapi_kontrol/ui/widgets/manager_call_action.dart';

void main() {
  testWidgets(
    'header opens selected site manager only and never calls the viewer',
    (t) async {
      final dialed = <Uri>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ManagerCallAction(
                  siteCode: 11,
                  fetch: () async => const [
                    ManagerContact(
                      siteCode: 11,
                      siteName: 'Mine',
                      phone: '05320000001',
                      isSelf: true,
                    ),
                    ManagerContact(
                      siteCode: 11,
                      siteName: 'Mine',
                      phone: '05320000002',
                    ),
                    ManagerContact(
                      siteCode: 22,
                      siteName: 'Other',
                      phone: '05320000003',
                    ),
                  ],
                  launcher: (uri) async {
                    dialed.add(uri);
                    return true;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('header_call_manager')));
      await t.pumpAndSettle();
      expect(dialed.map((u) => u.toString()), ['tel:05320000002']);
    },
  );
  testWidgets('late contact response after site switch is discarded', (
    t,
  ) async {
    final request = Completer<List<ManagerContact>>();
    final dialed = <Uri>[];
    Future<void> show(int code) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ManagerCallAction(
                siteCode: code,
                fetch: () => request.future,
                launcher: (uri) async {
                  dialed.add(uri);
                  return true;
                },
              ),
            ],
          ),
        ),
      ),
    );
    await show(11);
    await t.tap(find.byKey(const ValueKey('header_call_manager')));
    await t.pump();
    await show(22);
    request.complete(const [
      ManagerContact(siteCode: 11, siteName: 'Old', phone: '05320000001'),
    ]);
    await t.pumpAndSettle();
    expect(dialed, isEmpty);
    expect(t.takeException(), isNull);
  });
}
