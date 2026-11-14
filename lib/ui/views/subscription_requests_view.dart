import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/subscription_request.dart';
import 'package:site_kapi_kontrol/models/subscription_request_page.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/subscription_request_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/workspace_split_shell.dart';

class SubscriptionRequestsView extends StatelessWidget {
  const SubscriptionRequestsView({
    super.key,
    required this.pageData,
    required this.requests,
    required this.busyRequests,
    required this.isLoading,
    required this.onRefresh,
    required this.onLoadPage,
    required this.onApprove,
    required this.onReject,
  });

  final SubscriptionRequestPage? pageData;
  final List<SubscriptionRequest> requests;
  final Set<int> busyRequests;
  final bool isLoading;
  final VoidCallback onRefresh;
  final ValueChanged<int> onLoadPage;
  final ValueChanged<int> onApprove;
  final ValueChanged<int> onReject;

  @override
  Widget build(BuildContext context) {
    final page = pageData;
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    return WorkspaceSplitShell(
      leftFlex: 4,
      rightFlex: 8,
      header: const PageHeaderCard(title: 'Yeni Abonelik Talepleri'),
      left: WorkspacePaneCard(
        icon: Icons.mark_email_unread_outlined,
        title: 'Talep Özeti',
        subtitle: 'Doğrulanmış yeni abonelik başvuruları.',
        tone: AppTone.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              page == null
                  ? 'Abonelik talepleri yükleniyor.'
                  : 'Toplam ${page.total} abonelik talebi.',
              style: th.bodyMedium?.copyWith(color: p.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Talepleri sağdaki listeden inceleyip onaylayabilir veya reddedebilirsiniz.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
      right: WorkspacePaneCard(
        icon: Icons.fact_check_outlined,
        title: 'Talep Listesi',
        subtitle: 'Onay bekleyen abonelik kayıtları.',
        tone: AppTone.primary,
        onRefresh: isLoading ? null : onRefresh,
        refreshIcon: Icons.refresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: page == null
                  ? 'Bekleyen Talepler'
                  : 'Bekleyen Talepler (${page.total})',
            ),
            const SizedBox(height: AppSpace.md),
            if (isLoading && page == null)
              const ListSkeleton()
            else if (requests.isEmpty)
              const EmptyCard(
                icon: Icons.mark_email_read_outlined,
                title: 'Doğrulanmış yeni abonelik talebi yok.',
              )
            else ...[
              for (var i = 0; i < requests.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: StaggeredEntry(
                    index: i,
                    child: SubscriptionRequestCard(
                      request: requests[i],
                      busy: busyRequests.contains(requests[i].id),
                      formattedCreatedAt: formatDateTime(requests[i].createdAt),
                      onApprove: () => onApprove(requests[i].id),
                      onReject: () => onReject(requests[i].id),
                    ),
                  ),
                ),
              PaginationBar(
                label:
                    'Sayfa ${page?.page ?? 1} / ${page?.totalPages ?? 1} | Toplam ${page?.total ?? 0}',
                onPrevious: (page?.page ?? 1) > 1
                    ? () => onLoadPage((page?.page ?? 1) - 1)
                    : null,
                onNext: (page?.page ?? 1) < (page?.totalPages ?? 1)
                    ? () => onLoadPage((page?.page ?? 1) + 1)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
