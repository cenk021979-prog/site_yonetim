import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/meter_field_models.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';
import 'package:site_kapi_kontrol/services/meter_field_queue.dart';
import 'package:site_kapi_kontrol/services/meter_ocr.dart';
import 'package:site_kapi_kontrol/services/meter_photo_picker.dart';

final class _File extends PlatformFile {
  _File(this.size, this.chunks);
  final int? size;
  final List<Uint8List> chunks;
  bool opened = false;
  bool cancelled = false;
  @override String get name => 'meter.png';
  @override Uri get uri => Uri.parse('memory:meter.png');
  @override Future<int?> length() async => size;
  @override Stream<Uint8List> readAsByteStream() async* {
    opened = true;
    try { yield* Stream.fromIterable(chunks); } finally { cancelled = true; }
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bilinen büyük fotoğraf açılmaz; bilinmeyen uzunluk sınırlandırılmış stream kullanır', () async {
    final big = _File(21 * 1024 * 1024, []);
    await expectLater(readMeterPhotoFile(big), throwsStateError);
    expect(big.opened, isFalse);
    final unknown = _File(null, [Uint8List.fromList([1, 2, 3])]);
    expect((await readMeterPhotoFile(unknown)).bytes, [1, 2, 3]);
    final dishonest = _File(1, [Uint8List(20 * 1024 * 1024), Uint8List(1)]);
    await expectLater(readMeterPhotoFile(dishonest), throwsStateError);
    expect(dishonest.cancelled, isTrue);
  });
  test('sayaç fotoğrafı taze piksellerden JPEG olur; GPS/EXIF silinir ve sunucu sınırında kalır', () {
    final source = img.Image(width: 12, height: 18);
    source.exif.gpsIfd.setGpsLocation(latitude: 41, longitude: 29);
    source.exif.imageIfd.make = 'Gizli cihaz';
    final encoded = shrinkMeterPhoto(Uint8List.fromList(img.encodeJpg(source)))!;
    expect(img.decodeJpg(encoded), isNotNull);
    expect(img.decodeJpgExif(encoded)?.gpsIfd.gpsLatitude, isNull);
    expect(img.decodeJpgExif(encoded)?.imageIfd.make, isNull);
    expect(encoded.length, lessThanOrEqualTo(600 * 1024));
  });
  test('bozuk ve boyut sınırı dışındaki görsel fotoğraf olarak kabul edilmez', () {
    expect(shrinkMeterPhoto(Uint8List.fromList([1, 2, 3])), isNull);
    expect(shrinkMeterPhoto(Uint8List(20 * 1024 * 1024 + 1)), isNull);
  });
  test('hesap/site kuyrukları ve kapsamı belirsiz v1 birbirine taşınmaz', () async {
    SharedPreferences.setMockInitialValues({});
    final legacy = LocalMeterFieldStore();
    final accountA = LocalMeterFieldStore(scope: 'u1_s7');
    final accountB = LocalMeterFieldStore(scope: 'u2_s7');
    final otherSite = LocalMeterFieldStore(scope: 'u1_s8');
    const m = FieldMeter(id: 1, kind: MeterKind.water, serialNo: 'S', apartmentLabel: 'A - 1');
    final old = await MeterFieldQueue(store: legacy).enqueue(siteCode: 7, meter: m, date: '2026-11-08', value: '1');
    final own = await MeterFieldQueue(store: accountA).enqueue(siteCode: 7, meter: m, date: '2026-11-08', value: '2');
    expect((await legacy.load()).single.id, old.id);
    expect((await accountA.load()).single.id, own.id);
    expect(await accountB.load(), isEmpty);
    expect(await otherSite.load(), isEmpty);
  });
}
