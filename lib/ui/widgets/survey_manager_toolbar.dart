import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Arama, durum ve yeni kayıt aynı iş alanındadır. Dar ekranda doğal olarak
/// alt satıra iner; kontroller ve dokunma hedefleri küçültülmez.
class SurveyManagerToolbar extends StatelessWidget {
  const SurveyManagerToolbar({super.key, required this.statuses, required this.status, required this.onQuery, required this.onStatus, this.onCreate});
  final List<(String, String)> statuses;
  final String status;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onStatus;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final search = TextField(
      key: const ValueKey<String>('svm_search'),
      onChanged: onQuery,
      decoration: const InputDecoration(labelText: 'Anket ara', isDense: true, prefixIcon: Icon(Icons.search_rounded)),
    );
    final filters = Semantics(label: 'Anket durumu', child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
      for (final entry in statuses) ChoiceChip(
        key: ValueKey<String>('svm_status_${entry.$1}'), label: Text(entry.$2),
        selected: status == entry.$1, onSelected: (_) => onStatus(entry.$1),
      ),
    ]));
    final create = onCreate == null ? null : PrimaryActionButton(
      key: const ValueKey<String>('svm_new'), label: 'Yeni Anket', icon: Icons.add_rounded,
      expand: false, onPressed: onCreate,
    );
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (constraints.maxWidth >= 850 * scale.clamp(1, 2)) {
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: search),
        const SizedBox(width: AppSpace.lg),
        Flexible(child: filters),
        if (create != null) ...[const SizedBox(width: AppSpace.lg), create],
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      search, const SizedBox(height: AppSpace.sm), filters,
      if (create != null) ...[
        const SizedBox(height: AppSpace.sm),
        Align(alignment: Alignment.centerLeft, child: create),
      ],
    ]);
  });
}
