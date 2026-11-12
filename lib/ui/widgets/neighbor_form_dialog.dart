import 'package:flutter/material.dart';

/// Keeps the heading, fields and actions reachable above a large keyboard.
/// The actions join the scroll area only when the keyboard leaves very little
/// height; otherwise Flutter keeps them visible below the scrollable fields.
class NeighborFormDialog extends StatelessWidget {
  const NeighborFormDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewInsets.vertical - media.padding.vertical;
    final textScale = media.textScaler.scale(16) / 16;
    final keyboardNeedsFullScroll = media.viewInsets.bottom > 0 && availableHeight < 240 * textScale;
    if (!keyboardNeedsFullScroll) {
      return AlertDialog(scrollable: true, title: Text(title), content: content, actions: actions);
    }
    return AlertDialog(
      semanticLabel: title,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(namesRoute: true, child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 16),
            OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, overflowSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}
