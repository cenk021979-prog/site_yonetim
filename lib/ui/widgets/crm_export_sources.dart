import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart';

/// One file for all four CRM sections. List search/filter state is
/// intentionally not forwarded: a person filter cannot silently omit apartments.
List<ExportSource> buildCombinedCrmSources(BulkService service, int siteCode) {
  final session = service.authService.session;
  bool current() {
    final now = service.authService.session;
    return session != null &&
        now != null &&
        session.id == now.id &&
        session.token == now.token &&
        session.role == now.role;
  }

  Future<ExportEnvelope> guarded(Future<ExportEnvelope> Function() load) async {
    if (!current()) {
      throw ApiException('Oturum değişti. Dışa aktarmayı yeniden açın.');
    }
    final result = await load();
    if (!current()) {
      throw ApiException('Oturum değişti. Dışa aktarmayı yeniden açın.');
    }
    return result;
  }

  ExportSource table(
    String kind,
    String title,
    IconData icon, {
    bool notes = false,
  }) => ExportSource(
    label: title,
    sheetName: title,
    icon: icon,
    isCurrent: current,
    notesLabel: notes ? 'Notları da ekle' : null,
    fetch: (format) => guarded(
      () => service.exportData(
        siteCode,
        kind: kind,
        filters: const BulkExportFilters(status: 'all'),
        format: format,
      ),
    ),
    fetchWithNotes: notes
        ? (format, includeNotes) => guarded(
            () => service.exportData(
              siteCode,
              kind: kind,
              filters: const BulkExportFilters(status: 'all'),
              format: format,
              includeNotes: includeNotes,
            ),
          )
        : null,
  );
  return [
    table('people', 'Kişiler', Icons.groups_2_rounded, notes: true),
    table('apartments', 'Daireler', Icons.apartment_rounded),
    table('vehicles', 'Araçlar', Icons.directions_car_rounded, notes: true),
    ExportSource(
      label: 'Kadro',
      sheetName: 'Kadro',
      isCurrent: current,
      fetch: (_) => guarded(
        () async =>
            teamExportEnvelope(await service.authService.getTeam(siteCode)),
      ),
    ),
  ];
}

/// Only the roster already visible to the requesting account. No invitation,
/// login/PIN, payroll, private personnel or contact-directory notes are exported.
ExportEnvelope teamExportEnvelope(TeamData team) => ExportEnvelope(
  kind: 'team',
  filenameBase: 'kadro',
  columns: const [
    ExportColumn(key: 'ad_soyad', label: 'Ad Soyad'),
    ExportColumn(key: 'gorev', label: 'Görev'),
    ExportColumn(key: 'telefon', label: 'İletişim Telefonu'),
  ],
  rows: [
    for (final name in team.managers) [name, 'Site Yöneticisi', null],
    for (final duty in team.duties)
      [duty.fullName, duty.label, duty.publicPhone],
    for (final role in team.legacyRoles)
      [
        role.fullName,
        switch (role.role.toUpperCase()) {
          'BOARD_MEMBER' => 'Kurul Üyesi',
          'STAFF' => 'Görevli',
          _ => 'Ek Görev',
        },
        null,
      ],
  ],
);
