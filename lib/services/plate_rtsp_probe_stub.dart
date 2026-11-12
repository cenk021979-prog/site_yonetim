bool get isNativeRtspSupported => false;
Future<void> trySetNativeProperty(
  Object native,
  String key,
  String value,
) async {}

Future<bool> canReachRtspPort(
  String host,
  int port, {
  Duration timeout = const Duration(milliseconds: 850),
}) async => false;
