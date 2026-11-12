import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/interface_mode.dart';
import 'package:site_kapi_kontrol/services/interface_mode_service.dart';

class InterfaceModeScope extends InheritedNotifier<InterfaceModeService> {
  const InterfaceModeScope({super.key, required InterfaceModeService service, required super.child}) : super(notifier: service);
  static InterfaceModeService? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<InterfaceModeScope>()?.notifier;
}

class InterfaceModeSwitch extends StatelessWidget {
  const InterfaceModeSwitch({super.key});
  @override
  Widget build(BuildContext context) {
    final service = InterfaceModeScope.maybeOf(context);
    if (service == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Görünüm', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (mode, label) in [(InterfaceMode.classic, 'Klasik'), (InterfaceMode.simple, 'Sade')])
            ChoiceChip(
              key: ValueKey(mode == InterfaceMode.simple ? 'interface_mode_simple' : 'interface_mode_classic'),
              label: Text(label),
              selected: service.mode == mode,
              onSelected: (_) => service.setMode(mode),
            ),
        ]),
        const SizedBox(height: 8),
        const Text('Bu hesap için bu cihazda saklanır. Kolay görünüm yazı ve karşıtlık ayarı ayrıca kullanılabilir.'),
        if (service.persistenceFailed) const Text('Görünüm bu oturumda değişti; tercih cihaza kaydedilemedi.'),
      ]),
    );
  }
}
