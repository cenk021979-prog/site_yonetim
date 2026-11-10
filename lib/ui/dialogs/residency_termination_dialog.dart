import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/termination_preview_model.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/dialogs/large_dialog_parts.dart';
import 'package:site_kapi_kontrol/ui/helpers/date_input.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// 360° Daireden Ayrılma, İkamet Sonu, Otopark/Plaka, Rezervasyon ve Görev Devir Sihirbazı.
class ResidencyTerminationDialog extends StatefulWidget {
  const ResidencyTerminationDialog({
    super.key,
    required this.scope,
    required this.apartmentId,
    required this.residencyId,
    this.personId,
    this.personName = '',
    this.apartmentLabel = '',
    this.onCompleted,
  });

  final PeopleScope scope;
  final int apartmentId;
  final int residencyId;
  final int? personId;
  final String personName;
  final String apartmentLabel;
  final VoidCallback? onCompleted;

  static Future<bool?> show(
    BuildContext context, {
    required PeopleScope scope,
    required int apartmentId,
    required int residencyId,
    int? personId,
    String personName = '',
    String apartmentLabel = '',
    VoidCallback? onCompleted,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ResidencyTerminationDialog(
        scope: scope,
        apartmentId: apartmentId,
        residencyId: residencyId,
        personId: personId,
        personName: personName,
        apartmentLabel: apartmentLabel,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<ResidencyTerminationDialog> createState() => _ResidencyTerminationDialogState();
}

class _ResidencyTerminationDialogState extends State<ResidencyTerminationDialog> {
  bool _loading = true;
  String? _error;
  TerminationPreview? _preview;

  // Form State
  late final TextEditingController _dateCtrl = TextEditingController(
    text: formatDateField(DateTime.now()),
  );
  int? _selectedSuccessorUserCode;
  String _debtDisposition = 'KEEP_ON_DEBTOR'; // 'PAID' | 'TRANSFER_TO_OWNER' | 'KEEP_ON_DEBTOR'
  bool _terminateSiteRoles = true;
  final Map<int, TextEditingController> _meterCtrls = {};

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview());
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    for (final c in _meterCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.scope.authService.getTerminationPreview(
        widget.scope.siteCode,
        widget.apartmentId,
        widget.residencyId,
      );
      if (!mounted) return;
      final preview = TerminationPreview.fromJson(res);

      // Initialize meter controllers
      for (final m in preview.meters) {
        _meterCtrls[m.id] = TextEditingController();
      }

      setState(() {
        _preview = preview;
        _selectedSuccessorUserCode = preview.defaultSuccessorUserCode;
        if (preview.debt.liabilityTransfer?.canTransfer == true) {
          _debtDisposition = 'TRANSFER_TO_OWNER';
        } else if (preview.debt.hasDebt) {
          _debtDisposition = 'PAID';
        } else {
          _debtDisposition = 'KEEP_ON_DEBTOR';
        }
        _terminateSiteRoles = preview.siteRoles.hasRoles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(
          e,
          'Ayrılma bilgileri yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting || _preview == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final moveOut = parseDateField(_dateCtrl.text) ?? DateTime.now();

    // Prepare meter readings
    final finalReadings = <Map<String, dynamic>>[];
    for (final m in _preview!.meters) {
      final text = _meterCtrls[m.id]?.text.trim() ?? '';
      if (text.isNotEmpty) {
        final val = double.tryParse(text.replaceAll(',', '.'));
        if (val != null) {
          finalReadings.add({
            'meterId': m.id,
            'readingValue': val,
            'readingDate': _dateCtrl.text.trim(),
          });
        }
      }
    }

    try {
      await widget.scope.authService.executeResidencyTermination(
        widget.scope.siteCode,
        widget.apartmentId,
        widget.residencyId,
        moveOutDate: moveOut,
        successorUserCode: _selectedSuccessorUserCode,
        terminateSiteRoles: _terminateSiteRoles,
        debtDisposition: _debtDisposition,
        finalMeterReadings: finalReadings,
        reason: 'move_out',
      );

      if (!mounted) return;
      AppSnack.show(
        context,
        'Daireden ayrılma ve ilişik kesme işlemi başarıyla tamamlandı.',
        kind: AppSnackKind.success,
      );
      widget.onCompleted?.call();
      popIfCurrent(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = crmMessageOf(
          e,
          'Ayrılma işlemi kaydedilemedi. Lütfen tekrar deneyin.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Daireden Ayrılma & Taşınma';
    final subtitle = widget.apartmentLabel.isNotEmpty
        ? widget.apartmentLabel
        : (_preview?.apartmentFullLabel ?? '');

    Widget body;
    if (_loading) {
      body = const DialogRowsSkeleton(
        rows: 4,
        caption: 'Ayrılma ve ilişik kesme analizi yapılıyor...',
      );
    } else if (_error != null && _preview == null) {
      body = InlineNotice(message: _error!, onRetry: _loadPreview);
    } else {
      body = _buildWizardContent(context, _preview!);
    }

    return PopScope(
      canPop: !_submitting,
      child: AppDialog(
        title: title,
        subtitle: subtitle.isEmpty ? null : subtitle,
        icon: Icons.logout_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => popIfCurrent(context),
            child: const Text('Vazgeç'),
          ),
          if (!_loading && _preview != null)
            ElevatedButton.icon(
              style: filledToneStyle(context, tone: AppTone.warning),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(_submitting ? 'İşleniyor...' : 'Ayrılmayı Tamamla'),
            ),
        ],
        child: body,
      ),
    );
  }

  Widget _buildWizardContent(BuildContext context, TerminationPreview p) {
    final th = Theme.of(context).textTheme;
    final pal = context.palette;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineNotice(message: _error!, onRetry: () => setState(() => _error = null)),
            const SizedBox(height: AppSpace.md),
          ],

          // 1. KİŞİ VE TARİH KARTI
          DialogPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DialogSectionTitle(
                  icon: Icons.person_remove_rounded,
                  title: 'Ayrılan Sakin ve Tarih',
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.fullName.isNotEmpty ? p.fullName : 'Sakin',
                            style: th.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: AppSpace.xs,
                            runSpacing: 4,
                            children: [
                              StatusChip(
                                label: p.relation == 'tenant'
                                    ? 'Kiracı'
                                    : (p.relation == 'owner' ? 'Kat Maliki' : 'Sakin'),
                                tone: AppTone.primary,
                              ),
                              if (p.isAdmin)
                                const StatusChip(
                                  label: 'Daire Yöneticisi (Admin)',
                                  tone: AppTone.warning,
                                  icon: Icons.admin_panel_settings_rounded,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _dateCtrl,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [DateInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Ayrılış / Taşınma Tarihi',
                    hintText: 'GG.AA.YYYY',
                    prefixIcon: Icon(Icons.event_rounded),
                  ),
                  validator: validateDateField,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),

          // 2. DAİRE ADMİNİ HALEF SEÇİMİ (Eğer admin ayrılıyorsa)
          if (p.isAdmin) ...[
            DialogPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DialogSectionTitle(
                    icon: Icons.manage_accounts_rounded,
                    title: 'Daire Yöneticiliği Devri',
                    tone: AppTone.warning,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Ayrılan kişi bu dairenin yöneticisi (admini) konumundadır. Dairenin yönetimsiz kalmaması için yeni bir daire yöneticisi belirlenmelidir.',
                    style: th.bodySmall?.copyWith(color: pal.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  if (p.remainingMembers.isNotEmpty) ...[
                    Text('Dairede Kalan Sakinler:', style: th.labelMedium),
                    const SizedBox(height: AppSpace.xs),
                    for (final m in p.remainingMembers)
                      ListTile(
                        leading: Radio<int?>(
                          value: m.userCode,
                          groupValue: _selectedSuccessorUserCode,
                          onChanged: _submitting
                              ? null
                              : (val) => setState(() => _selectedSuccessorUserCode = val),
                        ),
                        title: Text(m.fullName, style: th.bodyMedium),
                        subtitle: Text(
                          m.userCode != null
                              ? 'Hesaplı sakin (Önerilen Halef)'
                              : 'Hesapsız sakin',
                          style: th.bodySmall?.copyWith(color: pal.textSecondary),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onTap: _submitting || m.userCode == null
                            ? null
                            : () => setState(() => _selectedSuccessorUserCode = m.userCode),
                      ),
                  ] else ...[
                    const InlineNotice(
                      tone: AppTone.info,
                      icon: Icons.home_work_rounded,
                      message:
                          'Dairede başka sakin kalmıyor (daire boşaltılıyor). Daire yönetimi otomatik olarak Kat Malikine veya Site Yönetimine devredilecektir.',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],

          // 3. OTOPARK VE PLAKALAR KARTI
          DialogPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.directions_car_rounded, size: 20, color: primaryColor),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'Otopark & Plaka Yetkileri',
                        style: th.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    StatusChip(
                      label: '${p.activeVehicles.length} Araç',
                      tone: p.activeVehicles.isNotEmpty ? AppTone.warning : AppTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                if (p.activeVehicles.isNotEmpty) ...[
                  Text(
                    'Aşağıdaki araçların Plaka Tanıma Sistemi (PTS) beyaz listesindeki geçiş yetkileri iptal edilecek ve daire otopark kotası serbest bırakılacaktır:',
                    style: th.bodySmall?.copyWith(color: pal.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    children: [
                      for (final v in p.activeVehicles)
                        Chip(
                          avatar: const Icon(Icons.pin_rounded, size: 16),
                          label: Text(
                            v.plateDisplay ?? v.plate,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ] else ...[
                  Text(
                    'Kişiye veya daireye kayıtlı aktif araç plakası bulunmuyor. Otopark kotası etkilenmeyecektir.',
                    style: th.bodySmall?.copyWith(color: pal.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),

          // 4. TESİS REZERVASYONLARI VE MİSAFİR LİNKLERİ
          if (p.upcomingReservations.isNotEmpty || p.activeGuestPasses.isNotEmpty) ...[
            DialogPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DialogSectionTitle(
                    icon: Icons.event_busy_rounded,
                    title: 'Rezervasyon ve Geçici Geçiş İptalleri',
                    tone: AppTone.warning,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  if (p.upcomingReservations.isNotEmpty) ...[
                    Text(
                      'İptal edilecek ${p.upcomingReservations.length} adet ileri tarihli tesis rezervasyonu bulunuyor (saatler boşa çıkarılacaktır):',
                      style: th.bodySmall?.copyWith(color: pal.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    for (final r in p.upcomingReservations)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.schedule_rounded, size: 14, color: pal.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${r.areaName ?? "Tesis"} (${r.startsAt.replaceAll("T", " ").substring(0, 16)})',
                                style: th.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpace.sm),
                  ],
                  if (p.activeGuestPasses.isNotEmpty) ...[
                    Text(
                      '${p.activeGuestPasses.length} adet aktif geçici misafir / kurye geçiş linki anında iptal edilecektir.',
                      style: th.bodySmall?.copyWith(color: pal.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],

          // 5. FİNANSAL MUTABAKAT VE BORÇ ÇÖZÜMÜ
          DialogPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded, size: 20, color: primaryColor),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'Finansal Bakiye & Borç Durumu',
                        style: th.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    StatusChip(
                      label: p.debt.hasDebt ? p.debt.balanceFormatted : 'Borcu Yoktur',
                      tone: p.debt.hasDebt ? AppTone.danger : AppTone.success,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                if (p.debt.hasDebt) ...[
                  Text(
                    'Dairenin / ayrılan sakinin vadesi geçmiş ${p.debt.balanceFormatted} borcu bulunmaktadır. Bu borç için nasıl bir işlem yapılacak?',
                    style: th.bodySmall?.copyWith(color: pal.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  if (p.debt.liabilityTransfer?.canTransfer == true)
                    ListTile(
                      leading: Radio<String>(
                        value: 'TRANSFER_TO_OWNER',
                        groupValue: _debtDisposition,
                        onChanged: _submitting ? null : (v) => setState(() => _debtDisposition = v!),
                      ),
                      title: const Text('Kiracı Borcunu Kat Malikine Devret'),
                      subtitle: const Text(
                        'KMK m.20 gereği ev sahibi depozitodan mahsup eder; borç ev sahibinin hesabına aktarılır.',
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onTap: _submitting ? null : () => setState(() => _debtDisposition = 'TRANSFER_TO_OWNER'),
                    ),
                  ListTile(
                    leading: Radio<String>(
                      value: 'PAID',
                      groupValue: _debtDisposition,
                      onChanged: _submitting ? null : (v) => setState(() => _debtDisposition = v!),
                    ),
                    title: const Text('Borç Tahsil Edildi / Ödendi'),
                    subtitle: const Text('Ayrılma öncesi nakit/havale tahsilatı veya makbuz kesildi.'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: _submitting ? null : () => setState(() => _debtDisposition = 'PAID'),
                  ),
                  ListTile(
                    leading: Radio<String>(
                      value: 'KEEP_ON_DEBTOR',
                      groupValue: _debtDisposition,
                      onChanged: _submitting ? null : (v) => setState(() => _debtDisposition = v!),
                    ),
                    title: const Text('Borç Ayrılan Kişinin Üzerinde Kalsın'),
                    subtitle: const Text('Hukuki / icra takibi şahsi olarak devam edecektir.'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: _submitting ? null : () => setState(() => _debtDisposition = 'KEEP_ON_DEBTOR'),
                  ),
                ] else ...[
                  Text(
                    'Bu daireye ait ödenmemiş açık borç kaydı bulunmamaktadır. Temiz ayrılma kaydı oluşturulacaktır.',
                    style: th.bodySmall?.copyWith(color: pal.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),

          // 6. SAYAÇ SON OKUMA KARTI (Varsa)
          if (p.meters.isNotEmpty) ...[
            DialogPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DialogSectionTitle(
                    icon: Icons.speed_rounded,
                    title: 'Sayaç Son Okuma (Ara Hesap)',
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Daireye bağlı aktif sayaçlar aşağıdadır. Ayrılış anındaki son endeksleri girerek ara hesap kaydedebilirsiniz:',
                    style: th.bodySmall?.copyWith(color: pal.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  for (final m in p.meters) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.kindLabel, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                                Text(
                                  'Seri: ${m.serialNo}${m.lastReadingValue != null ? " (Son: ${m.lastReadingValue})" : ""}',
                                  style: th.bodySmall?.copyWith(color: pal.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _meterCtrls[m.id],
                              enabled: !_submitting,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Son Endeks',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],

          // 7. SİTE YÖNETİM GÖREVLERİ (Varsa)
          if (p.siteRoles.hasRoles) ...[
            DialogPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DialogSectionTitle(
                    icon: Icons.shield_rounded,
                    title: 'Site Yönetim Görevi',
                    tone: AppTone.warning,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Bu kişinin site yönetiminde aktif bir görevi bulunmaktadır:',
                    style: th.bodySmall?.copyWith(color: pal.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  for (final d in p.siteRoles.duties)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.badge_rounded, size: 16, color: primaryColor),
                          const SizedBox(width: 6),
                          Text(d.label, style: th.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  if (p.siteRoles.isSiteManager)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.star_rounded, size: 16, color: Colors.orange),
                          SizedBox(width: 6),
                          Text('Site Yöneticisi', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpace.sm),
                  CheckboxListTile(
                    value: _terminateSiteRoles,
                    onChanged: _submitting
                        ? null
                        : (val) => setState(() => _terminateSiteRoles = val == true),
                    title: const Text('Site yönetim görevini de sonlandır'),
                    subtitle: const Text(
                      'İşaretlenirse kişinin sitedeki yöneticilik, denetçilik veya kurul üyeliği görevi de sonlandırılır.',
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],

          // GÜVENLİK VE BİLGİLENDİRME NOTU
          const InlineNotice(
            tone: AppTone.info,
            icon: Icons.security_rounded,
            message:
                'Bu işlem onaylandığında kapı geçiş şifreleri ve BLE/MQTT tokenları anında sıfırlanır. Kişinin hesabı silinmez; adli kütüğe taşınma kaydı düşülür.',
          ),
        ],
      ),
    );
  }
}
