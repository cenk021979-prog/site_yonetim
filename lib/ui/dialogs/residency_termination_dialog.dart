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
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/helpers/termination_meter_input.dart';
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
  State<ResidencyTerminationDialog> createState() =>
      _ResidencyTerminationDialogState();
}

class _ResidencyTerminationDialogState
    extends State<ResidencyTerminationDialog> {
  bool _loading = true;
  String? _error;
  TerminationPreview? _preview;

  // Form State
  late final TextEditingController _dateCtrl = TextEditingController(
    text: formatDateField(DateTime.now()),
  );
  int? _selectedSuccessorUserCode;
  String _debtDisposition =
      'KEEP_ON_DEBTOR'; // 'PAID' | 'TRANSFER_TO_OWNER' | 'KEEP_ON_DEBTOR'
  bool _terminateSiteRoles = true;
  final Map<int, TextEditingController> _meterCtrls = {};

  bool _submitting = false;
  String? _completedWarning;

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
      for (final controller in _meterCtrls.values) {
        controller.dispose();
      }
      _meterCtrls.clear();
      for (final m in preview.meters) {
        _meterCtrls[m.id] = TextEditingController();
      }

      setState(() {
        _preview = preview;
        _selectedSuccessorUserCode = preview.defaultSuccessorUserCode;
        _debtDisposition = 'KEEP_ON_DEBTOR';
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
    if (_submitting || _preview == null || _completedWarning != null) return;
    final moveOut = parseDateField(_dateCtrl.text);
    if (moveOut == null) {
      setState(
        () => _error =
            validateDateField(_dateCtrl.text) ??
            'Ayrılış tarihini GG.AA.YYYY biçiminde girin.',
      );
      return;
    }
    late final List<Map<String, dynamic>> finalReadings;
    try {
      finalReadings = terminationMeterReadings(
        meters: _preview!.meters,
        values: {
          for (final entry in _meterCtrls.entries) entry.key: entry.value.text,
        },
        readingDate: moveOut,
      );
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await widget.scope.authService.executeResidencyTermination(
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
      if (result['debtTransferFailed'] == true) {
        setState(() {
          _submitting = false;
          _completedWarning =
              'Daireden ayrılma kaydedildi, ancak borç devri tamamlanamadı. '
              'Borç mevcut hesabında kaldı. Aidat ve Finans → Borç devri bölümünden durumu kontrol edin.';
        });
        widget.onCompleted?.call();
        return;
      }
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
    if (_completedWarning != null) {
      body = InlineNotice(message: _completedWarning!, tone: AppTone.warning);
    } else if (_loading) {
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
      canPop: !_submitting && _completedWarning == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_submitting && _completedWarning != null) {
          popIfCurrent(context, true);
        }
      },
      child: AppDialog(
        title: title,
        subtitle: subtitle.isEmpty ? null : subtitle,
        icon: Icons.logout_rounded,
        tone: AppTone.warning,
        actions: [
          TextButton(
            onPressed: _submitting
                ? null
                : () => popIfCurrent(
                    context,
                    _completedWarning != null ? true : null,
                  ),
            child: Text(_completedWarning != null ? 'Kapat' : 'Vazgeç'),
          ),
          if (!_loading && _preview != null && _completedWarning == null)
            ElevatedButton.icon(
              style: filledToneStyle(context, tone: AppTone.warning),
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
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

    return RadioGroup<int?>(
      groupValue: _selectedSuccessorUserCode,
      onChanged: (value) {
        if (!_submitting && value != null) {
          setState(() => _selectedSuccessorUserCode = value);
        }
      },
      child: RadioGroup<String>(
        groupValue: _debtDisposition,
        onChanged: (value) {
          if (!_submitting && value != null) {
            setState(() => _debtDisposition = value);
          }
        },
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                InlineNotice(
                  message: _error!,
                  onRetry: () => setState(() => _error = null),
                ),
                const SizedBox(height: AppSpace.md),
              ],

              // 1. KİŞİ VE TARİH KARTI
              _TerminationPanel(
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
                                style: th.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
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
                                        : (p.relation == 'owner'
                                              ? 'Kat Maliki'
                                              : 'Sakin'),
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
                _TerminationPanel(
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
                            leading: m.userCode == null
                                ? const Icon(Icons.person_outline_rounded)
                                : Radio<int?>(
                                    value: m.userCode,
                                    enabled: !_submitting,
                                  ),
                            title: Text(m.fullName, style: th.bodyMedium),
                            subtitle: Text(
                              m.userCode != null
                                  ? 'Hesaplı sakin (Önerilen Halef)'
                                  : 'Hesapsız sakin',
                              style: th.bodySmall?.copyWith(
                                color: pal.textSecondary,
                              ),
                            ),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onTap: _submitting || m.userCode == null
                                ? null
                                : () => setState(
                                    () =>
                                        _selectedSuccessorUserCode = m.userCode,
                                  ),
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
              _TerminationPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.directions_car_rounded,
                          size: 20,
                          color: primaryColor,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            'Otopark & Plaka Yetkileri',
                            style: th.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        StatusChip(
                          label: '${p.activeVehicles.length} Araç',
                          tone: p.activeVehicles.isNotEmpty
                              ? AppTone.warning
                              : AppTone.neutral,
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
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
              if (p.upcomingReservations.isNotEmpty ||
                  p.activeGuestPasses.isNotEmpty) ...[
                _TerminationPanel(
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
                          style: th.bodySmall?.copyWith(
                            color: pal.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final r in p.upcomingReservations)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 14,
                                  color: pal.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${r.areaName ?? "Tesis"} (${_reservationTime(r.startsAt)})',
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
                          style: th.bodySmall?.copyWith(
                            color: pal.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
              ],

              // 5. FİNANSAL MUTABAKAT VE BORÇ ÇÖZÜMÜ
              _TerminationPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 20,
                          color: primaryColor,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            'Finansal Bakiye & Borç Durumu',
                            style: th.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    StatusChip(
                      label: p.debt.hasDebt
                          ? p.debt.balanceFormatted
                          : 'Borcu Yoktur',
                      tone: p.debt.hasDebt ? AppTone.danger : AppTone.success,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    if (p.debt.hasDebt) ...[
                      Text(
                        'Ayrılan sakinin ${p.debt.balanceFormatted} açık borcu bulunmaktadır. Bu borç için nasıl bir işlem yapılacak?',
                        style: th.bodySmall?.copyWith(color: pal.textSecondary),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      if (p.debt.liabilityTransfer?.canTransfer == true)
                        ListTile(
                          leading: Radio<String>(
                            value: 'TRANSFER_TO_OWNER',
                            enabled: !_submitting,
                          ),
                          title: const Text(
                            'Kiracı Borcunu Kat Malikine Devret',
                          ),
                          subtitle: const Text(
                            'Uygun borçlar malikin hesabına devredilir. Bu işlem tahsilat oluşturmaz.',
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onTap: _submitting
                              ? null
                              : () => setState(
                                  () => _debtDisposition = 'TRANSFER_TO_OWNER',
                                ),
                        ),
                      ListTile(
                        leading: Radio<String>(
                          value: 'PAID',
                          enabled: !_submitting,
                        ),
                        title: const Text('Borç Tahsil Edildi / Ödendi'),
                        subtitle: const Text(
                          'Tahsilatı önce Aidat ve Finans ekranında kaydedin. Bu seçim tahsilat oluşturmaz; açık borç varsa işlem tamamlanmaz.',
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onTap: _submitting
                            ? null
                            : () => setState(() => _debtDisposition = 'PAID'),
                      ),
                      ListTile(
                        leading: Radio<String>(
                          value: 'KEEP_ON_DEBTOR',
                          enabled: !_submitting,
                        ),
                        title: const Text(
                          'Borç Ayrılan Kişinin Üzerinde Kalsın',
                        ),
                        subtitle: const Text(
                          'Mevcut borç kaydı ve tutarı korunur; başka hesaba aktarılmaz.',
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onTap: _submitting
                            ? null
                            : () => setState(
                                () => _debtDisposition = 'KEEP_ON_DEBTOR',
                              ),
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
                _TerminationPanel(
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
                                    Text(
                                      m.kindLabel,
                                      style: th.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Seri: ${m.serialNo}${m.lastReadingValue != null ? " (Son: ${m.lastReadingValue})" : ""}',
                                      style: th.bodySmall?.copyWith(
                                        color: pal.textSecondary,
                                      ),
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
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
                _TerminationPanel(
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
                              Icon(
                                Icons.badge_rounded,
                                size: 16,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  d.label,
                                  style: th.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (p.siteRoles.isSiteManager)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: Colors.orange,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Site Yöneticisi',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppSpace.sm),
                      CheckboxListTile(
                        value: _terminateSiteRoles,
                        onChanged: _submitting
                            ? null
                            : (val) => setState(
                                () => _terminateSiteRoles = val == true,
                              ),
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
                    'Ayrılan kişinin bu daireden gelen erişimleri sonlandırılır. Hesabı silinmez; ayrılış işlemi sistemin işlem geçmişine kaydedilir.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _reservationTime(String value) {
    final text = value.replaceAll('T', ' ');
    return text.length > 16 ? text.substring(0, 16) : text;
  }
}

class _TerminationPanel extends StatelessWidget {
  const _TerminationPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DialogPanel(
    child: Material(type: MaterialType.transparency, child: child),
  );
}
