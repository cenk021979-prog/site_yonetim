import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Genel kullanım bilgisini ekranı doldurmadan sunar. Fare/klavye için
/// Tooltip; dokunmatik ekran ve ekran okuyucu için aynı metne açılan düğme.
/// Kritik uyarı veya mevcut hata/durum metinleri bunun içine taşınmamalıdır.
class ContextHelp extends StatelessWidget {
  const ContextHelp({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    constraints: BoxConstraints(
      maxWidth: math.max(
        1,
        math.min(360, MediaQuery.sizeOf(context).width - 32),
      ),
    ),
    excludeFromSemantics: true,
    child: Semantics(
      container: true,
      label: '$title hakkında bilgi',
      button: true,
      child: IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.info_outline_rounded, size: 20),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            scrollable: true,
            content: SelectableText(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Kapat'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
