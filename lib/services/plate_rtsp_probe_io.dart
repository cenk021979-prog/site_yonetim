import 'dart:io';
import 'package:media_kit/media_kit.dart';

Future<void> trySetNativeProperty(
  Object native,
  String key,
  String value,
) async {
  if (native is! NativePlayer) return;
  try {
    await native.setProperty(key, value);
  } catch (_) {}
}

bool get isNativeRtspSupported {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  return Platform.isWindows ||
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux;
}

Future<bool> canReachRtspPort(
  String host,
  int port, {
  Duration timeout = const Duration(milliseconds: 850),
}) async {
  final cleanHost = host.trim();
  if (cleanHost.isEmpty || port <= 0 || port > 65535) return false;
  Socket? socket;
  try {
    socket = await Socket.connect(cleanHost, port, timeout: timeout);
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      socket?.destroy();
    } catch (_) {}
  }
}
