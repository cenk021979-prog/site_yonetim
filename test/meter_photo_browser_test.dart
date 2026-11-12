import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/meter_photo_store_stub.dart'
    if (dart.library.js_interop) 'package:site_kapi_kontrol/services/meter_photo_store_web.dart' as browser;

void main() {
  test('gerçek IndexedDB commit sonrası veri başka işlemde okunur; kapsamlı liste/silme yalıtılmıştır', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final a = 'u991_s$stamp/1.jpg';
    final b = 'u992_s$stamp/1.jpg';
    try {
      await browser.putMeterPhoto(a, Uint8List.fromList([1, 2, 3]));
      await browser.putMeterPhoto(b, Uint8List.fromList([4, 5]));
      expect(await browser.getMeterPhoto(a), [1, 2, 3]);
      expect(await browser.meterPhotoKeys('u991_s$stamp/'), [a]);
      await browser.deleteMeterPhoto(a);
      expect(await browser.getMeterPhoto(a), isNull);
      expect(await browser.getMeterPhoto(b), [4, 5]);
    } finally {
      await browser.deleteMeterPhoto(a);
      await browser.deleteMeterPhoto(b);
    }
  }, skip: !kIsWeb ? 'Gerçek IndexedDB için --platform chrome ile çalışır.' : false);
}
