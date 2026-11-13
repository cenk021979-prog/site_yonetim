import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

/// Eylem adına göre çip tonu: açma/atama -> success, kapatma -> warning, kaldırma -> neutral,
/// bilinmeyen -> info (kayıt yine görünür).
AppTone auditToneOf(String action) {
  switch (action) {
    case 'module.enabled':
    case 'staff_role.assigned':
    case 'module_request.approved':
    case 'person.created':
    case 'residency.added':
    case 'vehicle.added':
    case 'announcement.created':
    case 'announcement.published':
    case 'site_application.approved':
    case 'finance.definition.created':
    case 'finance.run.posted':
    case 'finance.charge.posted':
    case 'finance.payment.recorded':
    case 'finance.receipt.issued':
    case 'finance.latefee.posted':
    case 'finance.account.created':
    case 'finance.transfer.created':
    case 'finance.expense.created':
    case 'finance.expense.document_attached':
    case 'finance.category.created':
    case 'finance.supplier.created':
    case 'finance.reminder.sent':
    case 'document.created':
    case 'document.version_added':
    case 'document.restored':
    case 'document.attached':
    case 'user.created':
    case 'user.activated':
    case 'user.subscription_approved':
    case 'site_manager.added':
    case 'site_manager.invited':
    case 'site.created':
    case 'site.approved':
    case 'join_request.approved':
    case 'door_permission.granted':
    case 'door_permission.bulk_granted':
      return AppTone.success;
    case 'module.disabled':
    case 'person.deactivated':
    case 'apartment.deleted':
    case 'apartment.pin_reset':
    case 'announcement.withdrawn':
    case 'finance.definition.deactivated':
    case 'finance.entry.reversed':
    case 'finance.period.closed':
    case 'finance.receipt.cancelled':
    case 'finance.latefee.voided':
    case 'finance.transfer.voided':
    case 'finance.expense.voided':
    case 'finance.legal_gate.updated':
    case 'document.deleted':
    case 'document.version_deleted':
    case 'document.detached':
    case 'user.deactivated':
    case 'user.role_changed':
    case 'user.password_set':
    case 'site.deletion_requested':
    case 'site.deletion_code_locked':
    case 'door_permission.denied':
    case 'door_permission.bulk_denied':
    case 'device.ownership_released':
      return AppTone.warning;
    case 'staff_role.removed':
    case 'module_request.cancelled':
    case 'residency.ended':
    case 'vehicle.removed':
    case 'announcement.deleted':
    case 'site_application.cancelled':
    case 'finance.expense.document_removed':
    case 'finance.reminder.cancelled':
    case 'finance.reminder.exclusion_removed':
    case 'site_manager.invitation_revoked':
    case 'site_manager.removed':
    case 'site.deletion_cancelled':
    case 'door_permission.removed':
    case 'door_permission.bulk_removed':
      return AppTone.neutral;
    case 'module_request.created':
    case 'announcement.updated':
    case 'announcement.scheduled':
    case 'site_application.created':
    case 'platform_settings.updated':
    case 'finance.definition.updated':
    case 'finance.entry.corrected':
    case 'finance.period.reopened':
    case 'finance.settings.updated':
    case 'finance.receipt.printed':
    case 'finance.account.updated':
    case 'finance.account.adjusted':
    case 'finance.reconciliation.recorded':
    case 'finance.payments.assigned':
    case 'finance.expense.corrected':
    case 'finance.category.updated':
    case 'finance.supplier.updated':
    case 'finance.report.debtor_list':
    case 'finance.reminder.exclusion_added':
    case 'document.updated':
      return AppTone.info;
    case 'module_request.rejected':
    case 'site_application.rejected':
    case 'document.purged':
    case 'user.deleted':
    case 'user.subscription_rejected':
    case 'site.deleted':
    case 'site.rejected':
    case 'join_request.rejected':
      return AppTone.danger;
    default:
      return AppTone.info;
  }
}

/// İşlemi yapanın okunur rol adı (sunucudaki `actor_role` değerinden).
String auditActorRoleLabel(String? role) {
  switch (role) {
    case 'super_user':
      return 'Süper Kullanıcı';
    case 'site_manager':
      return 'Site Yöneticisi';
    case 'apartment_owner':
      return 'Daire Sakini';
    case 'individual':
      return 'Bireysel Kullanıcı';
    case 'system':
      return 'Sistem';
    default:
      return role ?? '';
  }
}

/// Denetim kaydı satırı: Panel renkleriyle tasarlanmış, akordiyon şeklinde aşağı doğru açılan kart.
/// Tıklandığında genişleyerek kimin yaptığı, hangi site, hedef ve ayrıntıları gösterir.
class AuditLogCard extends StatefulWidget {
  const AuditLogCard({super.key, required this.entry});

  final AuditLogEntry entry;

  @override
  State<AuditLogCard> createState() => _AuditLogCardState();
}

class _AuditLogCardState extends State<AuditLogCard> {
  bool _expanded = false;

  IconData _iconForAction(String action) {
    if (action.contains('deleted') || action.contains('purged') || action.contains('rejected')) {
      return Icons.cancel_rounded;
    }
    if (action.contains('disabled') || action.contains('deactivated') || action.contains('warning')) {
      return Icons.pause_circle_filled_rounded;
    }
    if (action.contains('created') || action.contains('enabled') || action.contains('approved') || action.contains('added')) {
      return Icons.check_circle_rounded;
    }
    if (action.contains('updated') || action.contains('corrected')) {
      return Icons.edit_note_rounded;
    }
    return Icons.history_rounded;
  }

  Color _colorForTone(AppTone tone) {
    switch (tone) {
      case AppTone.primary:
        return AppColors.primary;
      case AppTone.success:
        return AppColors.success;
      case AppTone.warning:
        return AppColors.warning;
      case AppTone.danger:
        return AppColors.error;
      case AppTone.info:
        return AppColors.primary;
      case AppTone.violet:
        return Colors.purple.shade400;
      case AppTone.neutral:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final tone = auditToneOf(entry.action);
    final toneColor = _colorForTone(tone);
    final actionIcon = _iconForAction(entry.action);

    final target = entry.targetLabel;
    final actor = (entry.actorName ?? '').trim();
    final actorRole = auditActorRoleLabel(entry.actorRole);
    final who = actor.isEmpty
        ? (actorRole.isEmpty ? 'Sistem' : actorRole)
        : (actorRole.isEmpty || actorRole == actor ? actor : '$actor • $actorRole');
    final site = (entry.siteName ?? '').trim();

    final cardBg = isDark ? const Color(0xFF222834) : Colors.white;
    final expandedBg = isDark ? const Color(0xFF1A1F28) : const Color(0xFFF7F8FA);
    final borderColor = isDark
        ? toneColor.withValues(alpha: 0.35)
        : toneColor.withValues(alpha: 0.3);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tıklanabilir Üst Başlık (Özet Çubuğu)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Durum Rozet İkonu
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: toneColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(actionIcon, color: toneColor, size: 20),
                  ),
                  const SizedBox(width: 12),

                  // Orta Özet Bilgiler
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: toneColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                entry.actionLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: toneColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (target != null && target.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            target,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          site.isNotEmpty ? '$who • Site: $site' : who,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Sağ: Tarih & Dönen Akordiyon Oku
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatDateTime(entry.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textMuted,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Akordiyon Şeklinde Aşağı Doğru Açılan Detay Bölümü
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: expandedBg,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDetailRow(
                    icon: Icons.person_outline_rounded,
                    label: 'İşlemi Yapan',
                    value: entry.actorUserCode != null
                        ? '$who (Kullanıcı Kodu: #${entry.actorUserCode})'
                        : who,
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    icon: Icons.apartment_rounded,
                    label: 'Site',
                    value: site.isNotEmpty
                        ? (entry.siteCode != null ? '$site (Kod: ${entry.siteCode})' : site)
                        : (entry.siteCode != null ? 'Site Kodu: ${entry.siteCode}' : 'Genel / Site Yok'),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    icon: Icons.track_changes_rounded,
                    label: 'Hedef Nesne',
                    value: entry.targetLabel != null
                        ? '${entry.targetLabel} (${entry.targetType ?? '-'}${entry.targetId != null ? ' #${entry.targetId}' : ''})'
                        : (entry.targetType ?? '-'),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    icon: Icons.code_rounded,
                    label: 'Eylem / Sistem ID',
                    value: '${entry.action} • Kayıt ID: #${entry.id}',
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    icon: Icons.access_time_rounded,
                    label: 'Tam Zaman',
                    value: formatDateTime(entry.createdAt),
                  ),

                  // Ekstra ayrıntılar (varsa)
                  if (entry.details.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Text(
                      'İşlem Ayrıntıları:',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: entry.details.entries.map((e) {
                        final valStr = e.value is Map || e.value is List
                            ? e.value.toString()
                            : '${e.value}';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF282F3A) : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                          ),
                          child: Text(
                            '${e.key}: $valStr',
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

