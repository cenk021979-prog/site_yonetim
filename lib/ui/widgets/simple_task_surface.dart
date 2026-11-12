import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';

/// A task keeps one destination; layout changes only how the permitted set is displayed.
class SimpleTaskEntry {
  const SimpleTaskEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.group,
    required this.icon,
    required this.onTap,
    this.badge = 0,
    this.badgeNoun = 'bekleyen',
  });
  final String id, title, description, group, badgeNoun;
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
}

class SimpleTaskSurface extends StatelessWidget {
  const SimpleTaskSurface({
    super.key,
    required this.entries,
    required this.mode,
  });
  final List<SimpleTaskEntry> entries;
  final ListViewMode mode;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 10.0;
      final scale = (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(
        1.0,
        2.0,
      );
      final minimum = (mode == ListViewMode.tiles ? 230 : 320) * scale;
      final columns = ((constraints.maxWidth + gap) / (minimum + gap))
          .floor()
          .clamp(1, mode == ListViewMode.tiles ? 5 : 3);
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final entry in entries)
            SizedBox(
              width: width,
              child: _Task(entry: entry, tile: mode == ListViewMode.tiles),
            ),
        ],
      );
    },
  );
}

class _Task extends StatelessWidget {
  const _Task({required this.entry, required this.tile});
  final SimpleTaskEntry entry;
  final bool tile;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final enlarged = MediaQuery.textScalerOf(context).scale(16) > 24;
    final icon = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(entry.icon, size: 22, color: colors.primary),
    );
    final title = Text(
      entry.title,
      style: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
    );
    final group = Text(
      entry.group,
      maxLines: enlarged ? null : 1,
      overflow: enlarged ? null : TextOverflow.ellipsis,
      style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant),
    );
    final description = Text(
      entry.description,
      maxLines: enlarged ? null : 2,
      overflow: enlarged ? null : TextOverflow.ellipsis,
      style: text.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
        height: 1.35,
      ),
    );
    final badge = entry.badge > 0
        ? Text(
            '${entry.badge} ${entry.badgeNoun}',
            style: text.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          )
        : null;
    return Material(
      key: ValueKey(entry.id),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: '${entry.title}: ${entry.description}',
        child: InkWell(
          onTap: entry.onTap,
          child: Padding(
            padding: EdgeInsets.all(tile ? 14 : 12),
            child: tile
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                group,
                                const SizedBox(height: 3),
                                title,
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      description,
                      if (badge != null) ...[const SizedBox(height: 6), badge],
                    ],
                  )
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            group,
                            const SizedBox(height: 2),
                            title,
                            const SizedBox(height: 3),
                            description,
                            if (badge != null) ...[
                              const SizedBox(height: 4),
                              badge,
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
