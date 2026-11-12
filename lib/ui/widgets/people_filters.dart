import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/residency_relation.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Geniş ekranda tek satır; dar ekran ve büyük yazıda içerik sırasını koruyarak
/// sarar. Arama, ilişki ve durum aynı sunucu sorgusunun bağımsız parçalarıdır.
class PeopleFilters extends StatelessWidget {
  const PeopleFilters({
    super.key,
    required this.search,
    required this.relation,
    required this.status,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onRelationChanged,
    required this.onStatusChanged,
  });

  final TextEditingController search;
  final ResidencyRelation? relation;
  final String status;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchSubmitted;
  final VoidCallback onClearSearch;
  final ValueChanged<ResidencyRelation?> onRelationChanged;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: palette.text);
    final fields = <Widget>[
      TextField(
        key: const ValueKey('people_search'),
        controller: search,
        textInputAction: TextInputAction.search,
        onChanged: onSearchChanged,
        onSubmitted: (_) => onSearchSubmitted(),
        decoration: InputDecoration(
          labelText: 'Kişi ara',
          hintText: 'Ad, telefon, e-posta veya daire',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Aramayı temizle',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClearSearch,
                ),
        ),
      ),
      DropdownButtonFormField<String>(
        key: ValueKey('people_relation_${relation?.apiValue ?? ''}'),
        isExpanded: true,
        initialValue: relation?.apiValue ?? '',
        dropdownColor: palette.surface,
        style: style,
        decoration: const InputDecoration(labelText: 'İlişki'),
        items: [
          const DropdownMenuItem(
            value: '',
            child: Text('Tümü', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          for (final item in ResidencyRelation.values)
            DropdownMenuItem(
              value: item.apiValue,
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) {
            onRelationChanged(
              value.isEmpty ? null : ResidencyRelation.tryParse(value),
            );
          }
        },
      ),
      DropdownButtonFormField<String>(
        key: ValueKey('people_status_$status'),
        isExpanded: true,
        initialValue: status,
        dropdownColor: palette.surface,
        style: style,
        decoration: const InputDecoration(labelText: 'Durum'),
        items: const [
          DropdownMenuItem(
            value: 'active',
            child: Text(
              'Aktif kişiler',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DropdownMenuItem(
            value: 'inactive',
            child: Text(
              'Eski sakinler',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DropdownMenuItem(
            value: 'all',
            child: Text('Tümü', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            onStatusChanged(value);
          }
        },
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);
        final available = constraints.maxWidth / scale;
        const gap = AppSpace.md;
        if (available >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: fields[0]),
              const SizedBox(width: gap),
              Expanded(child: fields[1]),
              const SizedBox(width: gap),
              Expanded(child: fields[2]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fields[0],
            const SizedBox(height: gap),
            if (available >= 520)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields[1]),
                  const SizedBox(width: gap),
                  Expanded(child: fields[2]),
                ],
              )
            else ...[
              fields[1],
              const SizedBox(height: gap),
              fields[2],
            ],
          ],
        );
      },
    );
  }
}
