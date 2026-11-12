import { pool } from '../db.js';
import { publishDoorPulse } from '../mqtt_bridge.js';
import { recordAudit, actorFromAuthUser } from './audit_service.js';
import { PlatformError } from './errors.js';
import { requireTrPlate } from './plate_recognition_common.js';
import { recordEdgeEvent } from './plate_edge_service.js';
import { loadParkingPolicy, parkingLock, parkingAdmissionDecision, parkingAutomationBlock, PARKING_REASON_LABELS, parseParkingPolicy, parkingError, registeredPlateApproval } from './parking_access_common.js';

const HELD_SQL = `SELECT plate, apartment_id FROM plate_presence WHERE site_code = $1 AND inside
  UNION SELECT plate, apartment_id FROM parking_admissions WHERE site_code = $1 AND direction = 'giris' AND status IN ('pending','accepted','uncertain')`;

async function transaction(run) {
  const db = await pool.connect();
  try { await db.query('BEGIN'); const result = await run(db); await db.query('COMMIT'); return result; }
  catch (error) { await db.query('ROLLBACK').catch(() => {}); throw error; }
  finally { db.release(); }
}

function admissionView(row, { duplicate = false } = {}) {
  const allowed = ['pending', 'accepted', 'uncertain'].includes(row.status);
  return {
    enabled: true, admission_id: Number(row.id), duplicate, allowed,
    command_accepted: row.status === 'accepted', status: row.status, reason: row.reason,
    message: PARKING_REASON_LABELS[row.reason] ?? row.reason, direction: row.direction,
    blocking_plates: row.blocking_plates ?? [],
  };
}

export async function parkingOverview(siteCode) {
  const [policy, apartments, held, legacyPresence] = await Promise.all([
    loadParkingPolicy(pool, siteCode),
    pool.query(`SELECT a.id, b.block_name, a.unit_label, a.parking_slots, COALESCE(p.approved,FALSE) AS approved,
      COALESCE((SELECT jsonb_agg(v.plate ORDER BY v.plate) FROM vehicles v WHERE v.site_code = a.site_code AND v.is_active AND (v.apartment_id = a.id OR (v.apartment_id IS NULL AND EXISTS(SELECT 1 FROM apartment_residencies r WHERE r.apartment_id=a.id AND r.person_id=v.person_id AND r.is_current)))), '[]') AS plates,
      COALESCE((SELECT jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate)) FROM vehicles v JOIN vehicle_registration_photos photo ON photo.vehicle_id=v.id WHERE v.site_code=a.site_code AND v.apartment_id=a.id AND v.is_active),'[]') AS photo_vehicles
      FROM apartments a LEFT JOIN site_blocks b ON b.id = a.block_id
      LEFT JOIN parking_apartment_approvals p ON p.apartment_id = a.id
      WHERE a.site_code = $1 AND a.is_active ORDER BY b.sort_order, a.sort_order, a.id`, [siteCode]),
    pool.query(`SELECT id, plate, apartment_id, status, direction, created_at FROM parking_admissions
      WHERE site_code = $1 AND direction = 'giris' AND status IN ('pending','accepted','uncertain') ORDER BY id DESC LIMIT 500`, [siteCode]),
    pool.query(`SELECT p.id,p.plate,p.apartment_id,p.since_at AS created_at FROM plate_presence p WHERE p.site_code=$1 AND p.inside
      AND NOT EXISTS(SELECT 1 FROM parking_admissions a WHERE a.site_code=p.site_code AND a.plate=p.plate AND a.direction='giris' AND a.status IN ('pending','accepted','uncertain')) ORDER BY p.id DESC LIMIT 500`, [siteCode]),
  ]);
  const heldPlates = (await pool.query(HELD_SQL, [siteCode])).rows;
  return {
    policy, total: new Set(heldPlates.map((p) => p.plate)).size,
    apartments: apartments.rows.map((a) => ({ ...a, id: Number(a.id), inside_plates: [...new Set(heldPlates.filter((p) => Number(p.apartment_id) === Number(a.id)).map((p) => p.plate))] })),
    reservations: [...held.rows.map((r) => ({ ...r, origin: 'admission', id: Number(r.id), apartment_id: r.apartment_id === null ? null : Number(r.apartment_id),
      status: r.status === 'pending' && Date.now() - new Date(r.created_at).getTime() > 30000 ? 'uncertain' : r.status })),
    ...legacyPresence.rows.map((r) => ({ ...r, origin: 'presence', id: Number(r.id), status: 'legacy', direction: 'giris' }))],
    notice: 'İçeride bilgisi geçiş/komut kaydına göredir; fiziksel geçiş sensörü teyidi yoktur. Belirsiz kayıtları görevli kontrol ederek düzeltir.',
  };
}

export async function saveParkingPolicy({ siteCode, authUser, body }) {
  const policy = parseParkingPolicy(body);
  if (policy.enabled && body.confirm_updated_clients !== true) throw parkingError('Tüm izleme istemcilerini güncel sürüme alın; eski/çevrimdışı yerel istemciler kontenjanı aşabilir. Güncelleme kontrolünü onaylayın.', 'confirm_updated_clients');
  await transaction(async (db) => {
    await parkingLock(db, siteCode);
    await db.query(`INSERT INTO parking_policies(site_code, enabled, capacity, registration_photo_enabled, updated_by)
      VALUES($1,$2,$3,$4,$5) ON CONFLICT(site_code) DO UPDATE SET enabled=EXCLUDED.enabled, capacity=EXCLUDED.capacity,
      registration_photo_enabled=EXCLUDED.registration_photo_enabled,updated_by=EXCLUDED.updated_by,updated_at=NOW()`,
    [siteCode, policy.enabled, policy.capacity, policy.registration_photo_enabled, actorFromAuthUser(authUser).userCode]);
    await recordAudit(db, { actor: authUser, siteCode, action: 'plate.parking_policy_changed', targetType: 'site', targetId: String(siteCode), details: policy }, { inTransaction: true });
  });
  return parkingOverview(siteCode);
}

export async function saveApartmentParking({ siteCode, apartmentId, body, authUser }) {
  const id = Number(apartmentId); const slots = Number(body.parking_slots);
  if (!Number.isSafeInteger(id) || id < 1 || !Number.isInteger(slots) || slots < 0 || slots > 50 || typeof body.approved !== 'boolean') throw parkingError('Daire, onay ve 0–50 arası araç hakkı seçin.', 'parking_slots');
  await transaction(async (db) => {
    await parkingLock(db, siteCode);
    const apt = (await db.query(`SELECT id FROM apartments WHERE id=$1 AND site_code=$2 AND is_active FOR UPDATE`, [id, siteCode])).rows[0];
    if (!apt) throw new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
    await db.query(`UPDATE apartments SET parking_slots=$2 WHERE id=$1`, [id, slots]);
    await db.query(`INSERT INTO parking_apartment_approvals(apartment_id,approved,updated_by) VALUES($1,$2,$3)
      ON CONFLICT(apartment_id) DO UPDATE SET approved=EXCLUDED.approved,updated_by=EXCLUDED.updated_by,updated_at=NOW()`, [id, body.approved, actorFromAuthUser(authUser).userCode]);
    await recordAudit(db, { actor: authUser, siteCode, action: 'plate.apartment_parking_changed', targetType: 'apartment', targetId: String(id), details: { approved: body.approved, parking_slots: slots } }, { inTransaction: true });
  });
  return parkingOverview(siteCode);
}

export async function releaseParkingRecord({ siteCode, id, authUser, origin = 'admission' }) {
  const recordId = Number(id);
  if (!Number.isSafeInteger(recordId) || recordId < 1) throw parkingError('Kayıt geçersiz.', 'id');
  await transaction(async (db) => {
    await parkingLock(db, siteCode);
    const r = (await db.query(origin === 'presence' ? 'SELECT plate FROM plate_presence WHERE site_code=$1 AND id=$2 FOR UPDATE'
      : 'SELECT plate,status,created_at FROM parking_admissions WHERE site_code=$1 AND id=$2 FOR UPDATE', [siteCode, recordId])).rows[0];
    if (!r) throw new PlatformError(404, 'PARKING_RECORD_NOT_FOUND', 'Kayıt bulunamadı.');
    const inFlight = (await db.query(`SELECT 1 FROM parking_admissions WHERE site_code=$1 AND plate=$2 AND status IN ('pending','uncertain') AND created_at>NOW()-INTERVAL '30 seconds' LIMIT 1`, [siteCode, r.plate])).rows[0];
    if (inFlight) throw new PlatformError(409, 'PARKING_COMMAND_IN_FLIGHT', 'Kapı komutu işleniyor. En az 30 saniye bekleyip fiziksel durumu kontrol edin.');
    await db.query(`UPDATE parking_admissions SET status='released',updated_at=NOW() WHERE site_code=$1 AND plate=$2 AND direction='giris' AND status IN ('pending','accepted','uncertain')`, [siteCode, r.plate]);
    await db.query(`UPDATE plate_presence SET inside=FALSE,updated_at=NOW() WHERE site_code=$1 AND plate=$2`, [siteCode, r.plate]);
    await recordAudit(db, { actor: authUser, siteCode, action: 'plate.parking_record_released', targetType: origin === 'presence' ? 'plate_presence' : 'parking_admission', targetId: String(recordId), details: { source: 'manual_verification' } }, { inTransaction: true });
  });
  return parkingOverview(siteCode);
}

/** Reserve before dispatch. Serializes ALL entrances to a site, including different apartments/PCs. */
export async function requestParkingAdmission({ siteCode, edgeClientId = null, body, publish = publishDoorPulse }) {
  const plate = requireTrPlate(body.plate);
  const requestId = String(body.request_id ?? '');
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(requestId)) throw parkingError('İstek kimliği geçersiz.', 'request_id');
  const cameraId = Number(body.camera_id);
  if (!Number.isSafeInteger(cameraId) || cameraId < 1) throw parkingError('Kamera seçin.', 'camera_id');
  const prepared = await transaction(async (db) => {
    await parkingLock(db, siteCode);
    const policy = await loadParkingPolicy(db, siteCode);
    if (!policy.enabled) {
      const approved = await registeredPlateApproval(db, siteCode, plate);
      const permit = approved === null && (await db.query(`SELECT 1 FROM plate_guest_permits p JOIN apartments a ON a.id=p.apartment_id AND a.site_code=p.site_code AND a.is_active
        WHERE p.site_code=$1 AND p.plate=$2 AND p.revoked_at IS NULL AND p.valid_from<=NOW() AND p.valid_until>NOW() LIMIT 1`, [siteCode,plate])).rows.length > 0;
      return { legacy: true, authorized: approved === true || permit || (approved === false && body.direction === 'cikis'), reason: approved === false ? 'apartment_not_approved' : 'not_registered' };
    }
    const previous = (await db.query('SELECT * FROM parking_admissions WHERE site_code=$1 AND request_id=$2', [siteCode, requestId])).rows[0];
    if (previous) {
      if (previous.plate !== plate || Number(previous.camera_id) !== cameraId || Number(previous.edge_client_id ?? 0) !== Number(edgeClientId ?? 0)
        || (['giris','cikis'].includes(body.direction) && previous.direction !== body.direction)) throw new PlatformError(409, 'ADMISSION_REQUEST_REUSED', 'İstek kimliği başka bir işlemde kullanılmış.');
      return { row: previous, duplicate: true };
    }
    const camera = (await db.query(`SELECT c.id, gc.gate_id, gc.direction, g.direction_mode, g.door_id,
      COALESCE(g.device_uid,d.device_uid) AS device_uid, g.consecutive_vehicle_delay_seconds,g.entry_rear_suppress_seconds,g.exit_rear_suppress_seconds,
      COALESCE(gs.auto_open,FALSE) AS auto_open,COALESCE(gs.min_confidence,.85)::FLOAT AS min_confidence
      FROM camera_devices c JOIN plate_gate_cameras gc ON gc.camera_id=c.id
      JOIN plate_gates g ON g.id=gc.gate_id AND g.site_code=c.site_code AND g.is_active
      LEFT JOIN site_doors sd ON sd.id=g.door_id AND sd.site_code=g.site_code
      LEFT JOIN devices d ON d.id=sd.assigned_device_id
      LEFT JOIN plate_gate_settings gs ON gs.site_code=g.site_code AND gs.door_id=g.door_id
      WHERE c.id=$1 AND c.site_code=$2 AND c.is_active`, [cameraId, siteCode])).rows[0];
    if (!camera || !camera.device_uid || !camera.door_id) throw new PlatformError(409, 'PARKING_GATE_NOT_READY', 'Kamera için etkin SmartKeyPass kapısı ve cihaz bağlantısı gerekli.');
    const direction = camera.direction === 'auto' ? body.direction : camera.direction;
    if (!['giris', 'cikis'].includes(direction)) throw parkingError('Giriş/çıkış yönü belirli bir kamera kullanın.', 'direction');
    const vehicle = (await db.query(`SELECT v.id, a.id AS apartment_id, COALESCE(a.parking_slots,1) AS parking_slots,
      (COALESCE(pa.approved,FALSE) OR (a.id IS NULL AND EXISTS(SELECT 1 FROM parking_legacy_vehicle_exemptions ex WHERE ex.vehicle_id=v.id))) AS approved
      FROM vehicles v LEFT JOIN LATERAL (SELECT r.apartment_id FROM apartment_residencies r WHERE r.person_id=v.person_id AND r.is_current ORDER BY r.id LIMIT 1) r ON TRUE
      LEFT JOIN apartments a ON a.id=COALESCE(v.apartment_id,r.apartment_id) AND a.site_code=v.site_code AND a.is_active
      LEFT JOIN site_people sp ON sp.id=v.person_id LEFT JOIN parking_apartment_approvals pa ON pa.apartment_id=a.id
      WHERE v.site_code=$1 AND v.plate=$2 AND v.is_active AND (v.person_id IS NULL OR (sp.is_active AND sp.site_code=v.site_code)) LIMIT 1`, [siteCode, plate])).rows[0];
    const permit = vehicle ? null : (await db.query(`SELECT p.apartment_id,a.parking_slots,COALESCE(pa.approved,FALSE) AS approved
      FROM plate_guest_permits p JOIN apartments a ON a.id=p.apartment_id AND a.site_code=p.site_code AND a.is_active
      LEFT JOIN parking_apartment_approvals pa ON pa.apartment_id=a.id
      WHERE p.site_code=$1 AND p.plate=$2 AND p.revoked_at IS NULL AND p.valid_from<=NOW() AND p.valid_until>NOW() LIMIT 1`, [siteCode, plate])).rows[0];
    const registration = vehicle ?? permit;
    const blacklist = (await db.query('SELECT 1 FROM plate_blacklist WHERE site_code=$1 AND plate=$2 AND removed_at IS NULL', [siteCode, plate])).rows.length > 0;
    const held = (await db.query(HELD_SQL, [siteCode])).rows;
    let decision = parkingAdmissionDecision({ direction, blacklisted: blacklist, registered: !!registration, approved: registration?.approved === true,
      parkingSlots: registration?.parking_slots, apartmentInside: registration?.apartment_id == null ? held.filter((p) => p.plate === plate).map((p) => p.plate)
        : held.filter((p) => Number(p.apartment_id) === Number(registration.apartment_id)).map((p) => p.plate),
      siteInside: held.map((p) => p.plate), capacity: policy.capacity, plate });
    const recognitionReady = edgeClientId === null ? body.recognition_ready === true : (await db.query(
      'SELECT recognition_ready FROM plate_edge_clients WHERE id=$1 AND site_code=$2 AND is_active AND revoked_at IS NULL', [edgeClientId, siteCode])).rows[0]?.recognition_ready === true;
    const automationBlock = parkingAutomationBlock({ autoOpen: camera.auto_open, confidence: body.confidence, minConfidence: camera.min_confidence, recognitionReady });
    if (decision.allowed && automationBlock) decision = { allowed: false, reason: automationBlock, blocking_plates: [] };
    const recent = (await db.query(`SELECT plate,direction,created_at FROM parking_admissions WHERE site_code=$1 AND gate_id=$2
      AND status IN ('pending','accepted','uncertain') AND created_at>NOW()-INTERVAL '600 seconds' ORDER BY id DESC`, [siteCode, camera.gate_id])).rows;
    const now = Date.now();
    const rear = recent.some((r) => r.plate === plate && r.direction !== direction && now-new Date(r.created_at).getTime() < Number(r.direction === 'giris' ? camera.entry_rear_suppress_seconds ?? 60 : camera.exit_rear_suppress_seconds ?? 60)*1000);
    const wait = recent.some((r) => r.direction === direction && now-new Date(r.created_at).getTime() < Number(camera.consecutive_vehicle_delay_seconds ?? 10)*1000);
    if (decision.allowed && rear) decision = { allowed: false, reason: 'rear_plate_suppressed', blocking_plates: [] };
    else if (decision.allowed && wait) decision = { allowed: false, reason: 'consecutive_vehicle_wait', blocking_plates: [] };
    const row = (await db.query(`INSERT INTO parking_admissions(site_code,request_id,edge_client_id,plate,apartment_id,camera_id,gate_id,direction,status,reason,blocking_plates)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb) RETURNING *`,
    [siteCode, requestId, edgeClientId, plate, registration?.apartment_id ?? null, cameraId, camera.gate_id, direction, decision.allowed ? 'pending' : 'denied', decision.reason, JSON.stringify(decision.blocking_plates)])).rows[0];
    return { row, camera };
  });
  if (prepared.legacy) {
    if (!prepared.authorized) await recordParkingEvent({ siteCode, edgeClientId, cameraId, requestId, plate, body, reason: prepared.reason });
    return { enabled: false, authorized: prepared.authorized, message: prepared.authorized ? null : PARKING_REASON_LABELS[prepared.reason] };
  }
  if (prepared.duplicate) return admissionView(prepared.row, prepared);
  if (prepared.row.status !== 'pending') {
    await recordParkingEvent({ siteCode, edgeClientId, cameraId, requestId, plate, body, row: prepared.row });
    return admissionView(prepared.row);
  }
  let status; let reason;
  try {
    // MQTT PUBACK is transport acceptance, not physical gate/vehicle confirmation.
    await Promise.race([publish({ deviceUid: prepared.camera.device_uid, requestedBy: 'Plaka kontenjan denetimi', doorId: prepared.camera.door_id, siteCode }),
      new Promise((_, reject) => { const t = setTimeout(() => reject(Object.assign(new Error('timeout'), { code: 'PARKING_DISPATCH_TIMEOUT' })), 8000); t.unref?.(); })]);
    status = 'accepted'; reason = 'command_accepted';
  } catch (error) {
    const definitelyNotSent = ['DEVICE_OFFLINE', 'MQTT_BRIDGE_NOT_CONNECTED'].includes(error?.code);
    status = definitelyNotSent ? 'failed' : 'uncertain'; reason = definitelyNotSent ? 'command_failed' : 'command_uncertain';
  }
  const row = await transaction(async (db) => {
    await parkingLock(db, siteCode);
    const result = await db.query(`UPDATE parking_admissions SET status=$3,reason=$4,updated_at=NOW() WHERE site_code=$1 AND id=$2 AND status='pending' RETURNING *`, [siteCode, prepared.row.id, status, reason]);
    return result.rows[0] ?? (await db.query('SELECT * FROM parking_admissions WHERE site_code=$1 AND id=$2', [siteCode, prepared.row.id])).rows[0];
  });
  await recordParkingEvent({ siteCode, edgeClientId, cameraId, requestId, plate, body, row });
  return admissionView(row);
}

async function recordParkingEvent({ siteCode, edgeClientId, cameraId, requestId, plate, body, row, reason }) {
    try {
      await recordEdgeEvent({ id: edgeClientId, siteCode }, { schema_version: 3, event_id: `park_${row?.id ?? 'legacy'}_${requestId}`.slice(0, 64), camera_id: cameraId,
        plate, gate_id: row ? Number(row.gate_id) : undefined, decision: row?.status === 'accepted' ? 'acildi' : 'red',
        direction: row?.direction ?? body.direction, seen_at: new Date().toISOString(),
        reason: `parking_${reason ?? row.reason}`, confidence: body.confidence, gate_command: row?.status === 'accepted' ? 'accepted' : 'failed' }, { admissionId: row ? Number(row.id) : -1 });
    } catch (error) {
      // Reservation remains held if the event store is temporarily unavailable. Never resend the command.
      console.error('[parking] event_store_failed', { admission_id: row ? Number(row.id) : null, code: error?.code ?? 'unknown' }); // No plate/name/image.
    }
}
