import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/feedback_models.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';

/// Geliştirme süresince ana modül sayfalarında görünen, kaldırılabilir giriş.
class TemporaryFeedbackStrip extends StatelessWidget {
  const TemporaryFeedbackStrip({
    super.key,
    required this.screen,
    required this.onFeedback,
  });

  final FeedbackScreenContext screen;
  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey<String>('temporary_feedback_open'),
    tooltip: '${screen.screenName}: geri bildirim',
    visualDensity: VisualDensity.standard,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    onPressed: onFeedback,
    icon: const Icon(Icons.rate_review_outlined, size: 20),
  );
}

class FeedbackCopyButton extends StatelessWidget {
  const FeedbackCopyButton({
    super.key,
    required this.value,
    required this.label,
    this.copiedMessage =
        'İnceleme notu kopyalandı. Bu sohbete yapıştırabilirsiniz.',
  });

  final String value;
  final String label;
  final String copiedMessage;

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) AppSnack.show(context, copiedMessage);
    } catch (_) {
      if (context.mounted) {
        AppSnack.show(
          context,
          'Kopyalanamadı. Tekrar deneyin.',
          kind: AppSnackKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => _copy(context),
    icon: const Icon(Icons.copy_rounded, size: 18),
    label: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
  );
}
