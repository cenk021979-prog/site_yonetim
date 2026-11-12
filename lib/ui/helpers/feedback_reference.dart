import 'package:site_kapi_kontrol/models/feedback_models.dart';

/// Uygulama içi bağlam adresidir; herkese açık web/deep-link sözü vermez.
String feedbackScreenAddress(String screenRoute, {int? siteCode}) => Uri(
  path: '/${screenRoute.replaceFirst(RegExp(r'^/+'), '')}',
  queryParameters: siteCode == null ? null : <String, String>{'site': '$siteCode'},
).toString();

String feedbackRecordAddress(FeedbackRecord record) => Uri(
  path: '/feedback/${record.id}',
  queryParameters: <String, String>{'screen': record.screenRoute, if (record.siteCode != null) 'site': '${record.siteCode}'},
).toString();

/// Paylaşım kullanıcı tarafından yapılır; ekler ve gönderenin adı kopyalanmaz.
String feedbackReviewNote(FeedbackRecord record) => <String>[
  'Geri bildirim #${record.id}',
  'Not adresi: ${feedbackRecordAddress(record)}',
  'Sayfa adresi: ${feedbackScreenAddress(record.screenRoute, siteCode: record.siteCode)}',
  'Ekran: ${record.screenName}',
  if (record.appVersion != null) 'Sürüm: ${record.appVersion}',
  if (record.platform != null) 'Platform: ${record.platform}',
  '',
  'Kullanıcının notu:',
  record.message,
  if (record.attachments.isNotEmpty) ...['', 'Ek sayısı: ${record.attachments.length}. Ekler bu metne aktarılmadı.'],
].join('\n');
