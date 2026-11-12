import 'package:flutter/material.dart';

/// Kişiler varsayılan listesi için iki sık kullanılan görünüm; daha seyrek
/// işlemler menüde kalır. Sayısal bölüm kimlikleri eski girişlerle uyumludur.
class PeopleSectionNavigation extends StatelessWidget {
  const PeopleSectionNavigation({
    super.key,
    required this.selected,
    required this.unitPlural,
    required this.onSelected,
    this.onSafetyRequests,
  });

  final int selected;
  final String unitPlural;
  final ValueChanged<int> onSelected;
  final VoidCallback? onSafetyRequests;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (selected != 0) _section(context, 0, 'Kişiler', 'Kişi listesine dön'),
      _section(context, 1, unitPlural, '$unitPlural listesini aç'),
      _section(context, 3, 'Kadro', 'Yönetici, kurul ve görevlileri görüntüle'),
      PopupMenuButton<int>(
        key: const ValueKey('people_more_actions'),
        tooltip: 'Diğer işlemler',
        onSelected: (value) {
          if (value == 2) {
            onSelected(2);
          } else {
            onSafetyRequests?.call();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem<int>(
            key: ValueKey('people_tab_2'),
            value: 2,
            child: Text('Araçlar'),
          ),
          if (onSafetyRequests != null)
            const PopupMenuItem<int>(
              key: ValueKey('people_safety_requests'),
              value: 4,
              child: Text('Güvenlik talepleri'),
            ),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Text('İşlemler'),
        ),
      ),
    ],
  );

  Widget _section(BuildContext context, int index, String title, String help) =>
      Semantics(
        selected: selected == index,
        child: Tooltip(
          message: help,
          child: TextButton(
            key: ValueKey('people_tab_$index'),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: selected == index
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : null,
              backgroundColor: selected == index
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
            ),
            onPressed: () => onSelected(selected == index ? 0 : index),
            child: Text(title, textAlign: TextAlign.center),
          ),
        ),
      );
}
