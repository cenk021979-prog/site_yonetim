import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parkingAdmissionDecision, parseParkingPolicy, parseRegistrationPhoto } from '../src/modules/parking_access_common.js';
import { PARKING_ACCESS_DDL } from '../src/modules/parking_access_schema.js';

const input = { direction: 'giris', blacklisted: false, registered: true, approved: true, parkingSlots: 1, apartmentInside: [], siteInside: [], capacity: 10, plate: '34ABC123' };
const decide = (patch) => parkingAdmissionDecision({ ...input, ...patch });
describe('otopark giriş kuralları', () => {
  it('3 kayıtlı araç ve tek hakta içerideki plaka ikinci aracın önünü kapatır', () => {
    const result = decide({ apartmentInside: ['06XY123'], siteInside: ['06XY123'] });
    assert.equal(result.allowed, false); assert.equal(result.reason, 'apartment_full'); assert.deepEqual(result.blocking_plates, ['06XY123']);
  });
  it('daire hakkı 2 ise bir araç varken diğerine izin verir', () => assert.equal(decide({ parkingSlots: 2, apartmentInside: ['06XY123'] }).allowed, true));
  it('aynı plakanın iki girişi kontenjanı çifte tüketmez, tekrar açılmaz', () => assert.equal(decide({ apartmentInside: ['34ABC123'] }).reason, 'already_inside'));
  it('site toplam kapasitesi dairenin boş hakkından bağımsızdır', () => assert.equal(decide({ siteInside: ['06XY123'], capacity: 1 }).reason, 'site_full'));
  it('aynı plaka presence+reservation içinde bir kez sayılır', () => assert.equal(decide({ siteInside: ['06XY123', '06XY123'], capacity: 2 }).allowed, true));
  it('onaysız daire ve sıfır araç hakkı reddedilir', () => {
    assert.equal(decide({ approved: false }).reason, 'apartment_not_approved'); assert.equal(decide({ parkingSlots: 0 }).reason, 'no_parking');
  });
  it('çıkış kontenjan tüketmez ve daire onayı kaldırılmış araç çıkabilir', () => assert.equal(decide({ direction: 'cikis', approved: false, parkingSlots: 0, capacity: 0 }).allowed, true));
  it('kara liste ve tanımsız araç izin alamaz', () => {
    assert.equal(decide({ blacklisted: true }).reason, 'blacklist'); assert.equal(decide({ registered: false }).reason, 'not_registered');
  });
});
describe('otopark politikası ve özel ruhsat', () => {
  it('kapasite boş ve kontrol kapalı eski siteyi bozmayan varsayılandır', () => assert.deepEqual(parseParkingPolicy({ enabled: false, capacity: null, registration_photo_enabled: false }), { enabled: false, capacity: null, registration_photo_enabled: false }));
  it('kontrol açılmadan pozitif toplam kapasite zorunludur', () => {
    for (const capacity of [null, 0, -1, 1.1, 100001, 'yanlış']) assert.throws(() => parseParkingPolicy({ enabled: true, capacity, registration_photo_enabled: false }));
  });
  it('ruhsat isteğe bağlı, PNG/JPEG ve512KB sınırına tabidir', () => {
    assert.throws(() => parseRegistrationPhoto({ mime_type: 'text/html', image_base64: Buffer.from('<script>').toString('base64') }));
    assert.throws(() => parseRegistrationPhoto({ mime_type: 'image/png', image_base64: Buffer.alloc(524289).toString('base64') }));
    assert.throws(() => parseRegistrationPhoto({ mime_type: 'image/png', image_base64: Buffer.from('not_an_image').toString('base64') }));
    const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==', 'base64');
    assert.equal(parseRegistrationPhoto({ mime_type: 'image/png', image_base64: png.toString('base64') }).bytes.length, png.length);
  });
  it('migration ve açılış tanımı aynı SQL; geçmiş onay seed yalnız bir kez', () => {
    assert.equal(readFileSync(new URL('../migrations/130_parking_access.sql', import.meta.url), 'utf8').replace(/\r\n/g,'\n'), PARKING_ACCESS_DDL.map((s) => s.trim()+';').join('\n\n')+'\n');
    assert.ok(PARKING_ACCESS_DDL.some((s) => s.includes('130_existing_vehicle_approvals') && s.includes('ON CONFLICT DO NOTHING RETURNING')));
  });
});
