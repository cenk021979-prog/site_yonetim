import { PlatformError } from './errors.js';

export const PARKING_DEFAULT_POLICY = Object.freeze({ enabled: false, capacity: null, registration_photo_enabled: false });
export const HELD_STATUSES = Object.freeze(['pending', 'accepted', 'uncertain']);
export const parkingError = (message, field) => new PlatformError(400, 'INVALID_PARKING_INPUT', message, { field });

export function parseParkingPolicy(body) {
  if (typeof body.enabled !== 'boolean' || typeof body.registration_photo_enabled !== 'boolean') {
    throw parkingError('Denetim ve ruhsat fotoğrafı tercihlerini seçin.', 'enabled');
  }
  const capacity = body.capacity === null || body.capacity === '' || body.capacity === undefined ? null : Number(body.capacity);
  if (capacity !== null && (!Number.isSafeInteger(capacity) || capacity < 1 || capacity > 100000)) throw parkingError('Otopark kapasitesi 1–100000 arasında olmalı.', 'capacity');
  if (body.enabled && capacity === null) throw parkingError('Denetimi açmadan önce toplam araç kapasitesini girin.', 'capacity');
  return { enabled: body.enabled, capacity, registration_photo_enabled: body.registration_photo_enabled };
}

export function parkingAdmissionDecision({ direction, blacklisted, registered, approved, parkingSlots, apartmentInside = [], siteInside = [], capacity, plate }) {
  if (blacklisted) return { allowed: false, reason: 'blacklist', blocking_plates: [] };
  if (!registered) return { allowed: false, reason: 'not_registered', blocking_plates: [] };
  // Exit never consumes a slot; revoked apartment approval must not trap a registered vehicle inside.
  if (direction === 'cikis') return { allowed: true, reason: 'exit', blocking_plates: [] };
  if (!approved) return { allowed: false, reason: 'apartment_not_approved', blocking_plates: [] };
  if (!Number.isInteger(parkingSlots) || parkingSlots < 1) return { allowed: false, reason: 'no_parking', blocking_plates: [] };
  const own = [...new Set(apartmentInside)].filter((p) => p !== plate);
  if (apartmentInside.includes(plate)) return { allowed: false, reason: 'already_inside', blocking_plates: [plate] };
  if (own.length >= parkingSlots) return { allowed: false, reason: 'apartment_full', blocking_plates: own };
  if (new Set(siteInside).size >= capacity) return { allowed: false, reason: 'site_full', blocking_plates: [] };
  return { allowed: true, reason: 'space_reserved', blocking_plates: [] };
}

export function parkingAutomationBlock({ autoOpen, confidence, minConfidence = .85, recognitionReady }) {
  if (autoOpen !== true) return 'auto_open_disabled';
  if (recognitionReady !== true) return 'recognition_not_ready';
  if (typeof confidence !== 'number' || !Number.isFinite(confidence) || confidence < minConfidence || confidence > 1) return 'low_confidence';
  return null;
}

export function parseRegistrationPhoto(body) {
  const mime = body?.mime_type;
  const encoded = body?.image_base64;
  if (!['image/png', 'image/jpeg'].includes(mime) || typeof encoded !== 'string' || encoded.length > 699052 || !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) {
    throw parkingError('En fazla 512 KB PNG veya JPEG ruhsat fotoğrafı seçin.', 'image_base64');
  }
  const bytes = Buffer.from(encoded, 'base64');
  const png = bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const jpg = bytes.length >= 4 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 && bytes[bytes.length - 2] === 255 && bytes[bytes.length - 1] === 217;
  if (bytes.length > 524288 || bytes.length < 8 || (mime === 'image/png' ? !png : !jpg)) throw parkingError('Fotoğraf biçimi okunamadı. PNG veya JPEG seçin.', 'image_base64');
  return { mime, bytes };
}

export async function loadParkingPolicy(db, siteCode) {
  const row = (await db.query('SELECT enabled, capacity, registration_photo_enabled FROM parking_policies WHERE site_code = $1', [siteCode])).rows[0];
  return { ...PARKING_DEFAULT_POLICY, ...row };
}

export async function parkingLock(db, siteCode) {
  await db.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`parking_admission:${siteCode}`]);
}

/** Apartment approval always applies to registered resident plates, independently of capacity enforcement. */
export async function registeredPlateApproval(db, siteCode, plate) {
  const row = (await db.query(`SELECT ((COALESCE(pa.approved,FALSE) OR (a.id IS NULL AND EXISTS(SELECT 1 FROM parking_legacy_vehicle_exemptions ex WHERE ex.vehicle_id=v.id)))
    AND (v.person_id IS NULL OR EXISTS(SELECT 1 FROM site_people vp WHERE vp.id=v.person_id AND vp.site_code=v.site_code AND vp.is_active))) AS approved FROM vehicles v
    LEFT JOIN LATERAL (SELECT r.apartment_id FROM apartment_residencies r WHERE r.person_id=v.person_id AND r.is_current ORDER BY r.id LIMIT 1) r ON TRUE
    LEFT JOIN apartments a ON a.id=COALESCE(v.apartment_id,r.apartment_id) AND a.site_code=v.site_code AND a.is_active
    LEFT JOIN parking_apartment_approvals pa ON pa.apartment_id=a.id
    WHERE v.site_code=$1 AND v.plate=$2 AND v.is_active LIMIT 1`, [siteCode, plate])).rows[0];
  return row ? row.approved === true : null; // null = not a resident vehicle; existing guest flow is separate.
}

export const PARKING_REASON_LABELS = Object.freeze({
  blacklist: 'Plaka kara listede.', not_registered: 'Kayıtlı araç veya geçerli misafir izni yok.',
  apartment_not_approved: 'Dairenin araç girişine yönetim onayı bekleniyor.',
  no_parking: 'Dairenin eşzamanlı araç giriş hakkı yok.', already_inside: 'Bu plaka geçiş kaydına göre zaten içeride.',
  apartment_full: 'Dairenin araç hakkı dolu.', site_full: 'Sitenin otopark kapasitesi dolu.',
  space_reserved: 'Araç için kontenjan ayrıldı.', exit: 'Araç çıkışı için izin verildi.',
  command_failed: 'Kapıya komut gönderilemedi; kontenjan serbest bırakıldı.',
  command_uncertain: 'Kapı komutunun sonucu belirsiz; görevli kontrolü gerekiyor.',
  command_accepted: 'Kapı komutu kabul edildi. Geçiş kaydına göre izlenir; fiziksel geçiş sensörü teyidi yok.',
  consecutive_vehicle_wait: 'Önceki aracın geçişi için kapı bekleme süresi devam ediyor.',
  rear_plate_suppressed: 'Aracın karşı yöndeki mükerrer arka plaka okuması engellendi.',
  auto_open_disabled: 'Bu kapıda otomatik plaka açma kapalı. Kapı ve eşik ayarlarını kontrol edin.',
  recognition_not_ready: 'Plaka tanıma modeli hazır değil; otomatik komut gönderilmedi.',
  low_confidence: 'Okuma güveni kapının eşiğinin altında; komut gönderilmedi.',
});
