// Opt-in: ONLY a disposable kapi_test/rehearsal DB, never the production DB.
import { describe, it, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
const run = process.env.PARKING_PG_TEST === '1';
if (run && !/^kapi_(test|rehearsal)_\d{8}_\d{6}$/.test(process.env.DB_NAME ?? '')) throw new Error('Parking PG tests require a disposable guarded DB');

describe('otopark: gerçek PostgreSQL atomik giriş ve yaşam döngüsü', { skip: !run }, () => {
  let pool; let request; let release; let overview; let approval; let recordEvent; let clearInside; let ids = {};
  let seq = 0;
  const q = (sql, args = []) => pool.query(sql, args);
  const body = (plate = '34ABC123', patch = {}) => ({ request_id: `parking_test_${++seq}`, camera_id: ids.cameraIn, plate, direction: 'giris', confidence: .95, recognition_ready: true, ...patch });
  const publishOk = async () => ({ request_id: 'test-publish-only' });
  const admit = (value, publish = publishOk) => request({ siteCode: ids.site, body: value, publish });
  before(async () => {
    ({ pool } = await import('../src/db.js'));
    ({ requestParkingAdmission: request, releaseParkingRecord: release, parkingOverview: overview } = await import('../src/modules/parking_access_service.js'));
    ({ registeredPlateApproval: approval } = await import('../src/modules/parking_access_common.js'));
    ({ recordEdgeEvent: recordEvent } = await import('../src/modules/plate_edge_service.js'));
    ({ clearInside } = await import('../src/modules/plate_gates_service.js'));
    ids.user = Number((await q(`INSERT INTO users(full_name,email,role,is_active,email_verified,approval_status,password_hash)
      VALUES('Otopark test','parking-test@example.invalid','super_user',TRUE,TRUE,'approved','test-hash') RETURNING user_code`)).rows[0].user_code);
    ids.auth = { id: ids.user, user_code: ids.user, role: 'super_user', full_name: 'Otopark test' };
    ids.site = Number((await q(`INSERT INTO sites(name,approval_status) VALUES('Parking isolated fixture','approved') RETURNING site_code`)).rows[0].site_code);
    ids.other = Number((await q(`INSERT INTO sites(name,approval_status) VALUES('Parking other fixture','approved') RETURNING site_code`)).rows[0].site_code);
    await q(`INSERT INTO site_modules(site_code,module_code,enabled) VALUES($1,'plate_recognition',TRUE)`, [ids.site]);
    ids.block = Number((await q(`INSERT INTO site_blocks(site_code,block_name,sort_order) VALUES($1,'A',1) RETURNING id`, [ids.site])).rows[0].id);
    ids.apartment = Number((await q(`INSERT INTO apartments(site_code,block_id,unit_label,sort_order,parking_slots) VALUES($1,$2,'1',1,1) RETURNING id`, [ids.site, ids.block])).rows[0].id);
    ids.apartment2 = Number((await q(`INSERT INTO apartments(site_code,block_id,unit_label,sort_order,parking_slots) VALUES($1,$2,'2',2,1) RETURNING id`, [ids.site, ids.block])).rows[0].id);
    for (const [plate, apartment] of [['34ABC123', ids.apartment], ['06XY123', ids.apartment], ['35XY123', ids.apartment2]]) await q(`INSERT INTO vehicles(site_code,apartment_id,plate) VALUES($1,$2,$3)`, [ids.site, apartment, plate]);
    ids.device = Number((await q(`INSERT INTO devices(device_uid,site_code,gate_name) VALUES('PARKING-ISOLATED',$1,'Test') RETURNING id`, [ids.site])).rows[0].id);
    ids.door = Number((await q(`INSERT INTO site_doors(site_code,door_name,door_index,assigned_device_id) VALUES($1,'Test',1,$2) RETURNING id`, [ids.site, ids.device])).rows[0].id);
    ids.gate = Number((await q(`INSERT INTO plate_gates(site_code,name,direction_mode,device_uid,door_id,consecutive_vehicle_delay_seconds,entry_rear_suppress_seconds,exit_rear_suppress_seconds)
      VALUES($1,'Test','cift','PARKING-ISOLATED',$2,1,5,5) RETURNING id`, [ids.site, ids.door])).rows[0].id);
    await q(`INSERT INTO plate_gate_settings(site_code,door_id,auto_open,min_confidence) VALUES($1,$2,TRUE,.85)`, [ids.site,ids.door]);
    for (const direction of ['giris','cikis']) {
      const id = Number((await q(`INSERT INTO camera_devices(site_code,brand,name,host,token_hash) VALUES($1,'onvif',$2,'10.0.0.9','test') RETURNING id`, [ids.site, direction])).rows[0].id);
      await q(`INSERT INTO plate_gate_cameras(site_code,gate_id,camera_id,direction) VALUES($1,$2,$3,$4)`, [ids.site, ids.gate, id, direction]);
      ids[direction === 'giris' ? 'cameraIn' : 'cameraOut'] = id;
    }
    await q(`INSERT INTO parking_apartment_approvals(apartment_id,approved) VALUES($1,TRUE),($2,TRUE) ON CONFLICT DO NOTHING`, [ids.apartment, ids.apartment2]);
    await q(`INSERT INTO parking_policies(site_code,enabled,capacity) VALUES($1,TRUE,10)`, [ids.site]);
  });
  beforeEach(async () => {
    await q('DELETE FROM parking_admissions WHERE site_code=$1', [ids.site]);
    await q('DELETE FROM plate_presence WHERE site_code=$1', [ids.site]);
    await q('UPDATE parking_policies SET enabled=TRUE,capacity=10 WHERE site_code=$1', [ids.site]);
    await q('UPDATE parking_apartment_approvals SET approved=TRUE WHERE apartment_id=ANY($1::BIGINT[])', [[ids.apartment, ids.apartment2]]);
  });
  after(async () => { if (pool) await pool.end(); });

  it('aynı dairenin iki farklı plakasından eşzamanlı yalnız biri komut alır', async () => {
    let published = 0;
    const publisher = async () => { ++published; await new Promise((r) => setTimeout(r, 30)); return {}; };
    const results = await Promise.all([admit(body(), publisher), admit(body('06XY123'), publisher)]);
    assert.equal(results.filter((r) => r.command_accepted).length, 1); assert.equal(published, 1);
    const denied = results.find((r) => !r.allowed);
    assert.equal(denied.reason, 'apartment_full'); assert.equal(denied.blocking_plates.length, 1);
  });
  it('farklı daireler toplam son kapasiteyi paylaşamaz', async () => {
    await q('UPDATE parking_policies SET capacity=1 WHERE site_code=$1', [ids.site]);
    let published = 0;
    const results = await Promise.all([admit(body(), async () => { ++published; }), admit(body('35XY123'), async () => { ++published; })]);
    assert.equal(results.filter((r) => r.command_accepted).length, 1); assert.equal(published, 1);
    assert.equal(results.find((r) => !r.allowed).reason, 'site_full');
  });
  it('aynı request tekrarında MQTT yalnız bir kez, farklı payload409', async () => {
    let published = 0; const value = body();
    await admit(value, async () => { ++published; });
    const second = await admit(value, async () => { ++published; });
    assert.equal(second.duplicate, true); assert.equal(published, 1);
    await assert.rejects(() => admit({ ...value, plate: '06XY123' }), (e) => e.code === 'ADMISSION_REQUEST_REUSED');
  });
  it('MQTT gönderimden önce offline ise kontenjan serbest kalır', async () => {
    const result = await admit(body(), async () => { throw Object.assign(new Error('offline'), { code: 'DEVICE_OFFLINE' }); });
    assert.equal(result.status, 'failed'); assert.equal((await admit(body('06XY123'))).command_accepted, true);
  });
  it('gönderim sonucu belirsizse kapasite tutulur, görevli düzeltince boşalır', async () => {
    const result = await admit(body(), async () => { throw new Error('transport result unknown'); });
    assert.equal(result.status, 'uncertain'); assert.equal((await admit(body('06XY123'))).reason, 'apartment_full');
    await assert.rejects(() => release({ siteCode: ids.site, id: result.admission_id, authUser: ids.auth }), (e) => e.code === 'PARKING_COMMAND_IN_FLIGHT');
    await q(`UPDATE parking_admissions SET created_at=NOW()-INTERVAL '31 seconds' WHERE id=$1`, [result.admission_id]);
    await release({ siteCode: ids.site, id: result.admission_id, authUser: ids.auth });
    assert.equal((await admit(body('06XY123'))).command_accepted, true);
  });
  it('pending komut yarışında elle düzeltme yer açamaz', async () => {
    let finish; let entered;
    const ready = new Promise((r) => { entered = r; });
    const response = admit(body(), async () => { entered(); await new Promise((r) => { finish = r; }); });
    await ready;
    const pending = (await q('SELECT id FROM parking_admissions WHERE site_code=$1 AND status=$2', [ids.site, 'pending'])).rows[0];
    await assert.rejects(() => release({ siteCode: ids.site, id: pending.id, authUser: ids.auth }), (e) => e.code === 'PARKING_COMMAND_IN_FLIGHT');
    finish(); assert.equal((await response).command_accepted, true);
  });
  it('legacy presence kapasiteyi tutar ve aynı panelden elle düzeltilebilir', async () => {
    const id = Number((await q(`INSERT INTO plate_presence(site_code,plate,apartment_id,kind,inside,since_at) VALUES($1,'34ABC123',$2,'resident',TRUE,NOW()) RETURNING id`, [ids.site, ids.apartment])).rows[0].id);
    assert.equal((await admit(body('06XY123'))).reason, 'apartment_full');
    const state = await overview(ids.site); assert.equal(state.reservations.find((r) => r.id === id && r.origin === 'presence').status, 'legacy');
    await release({ siteCode: ids.site, id, origin: 'presence', authUser: ids.auth });
    assert.equal((await admit(body('06XY123'))).command_accepted, true);
  });
  it('çıkış sonrası dairenin diğer aracı giriş hakkı kazanır', async () => {
    await admit(body());
    await q(`UPDATE parking_admissions SET created_at=NOW()-INTERVAL '10 seconds' WHERE site_code=$1`, [ids.site]);
    const exit = await admit(body('34ABC123', { camera_id: ids.cameraOut, direction: 'cikis' }));
    assert.equal(exit.command_accepted, true);
    assert.equal((await admit(body('06XY123'))).command_accepted, true);
  });
  it('daire onayı kapasite kapalıyken de gerekir; onay tüm plakaları kapsar', async () => {
    await q('UPDATE parking_policies SET enabled=FALSE WHERE site_code=$1', [ids.site]);
    await q('UPDATE parking_apartment_approvals SET approved=FALSE WHERE apartment_id=$1', [ids.apartment]);
    assert.equal((await admit(body())).authorized, false); assert.equal((await admit(body('06XY123'))).authorized, false);
    await q('UPDATE parking_apartment_approvals SET approved=TRUE WHERE apartment_id=$1', [ids.apartment]);
    assert.equal((await admit(body())).authorized, true); assert.equal((await admit(body('06XY123'))).authorized, true);
  });
  it('denetim kapanıp normal çıkış kaydı geldikten sonra açılınca hayalet kontenjan kalmaz', async () => {
    await admit(body());
    await q(`UPDATE parking_policies SET enabled=FALSE WHERE site_code=$1`, [ids.site]);
    await q(`UPDATE parking_admissions SET created_at=NOW()-INTERVAL '10 seconds' WHERE site_code=$1`, [ids.site]);
    await recordEvent({ siteCode: ids.site, id: null }, { schema_version: 3, event_id: `off_exit_${++seq}`, camera_id: ids.cameraOut,
      plate: '34ABC123', direction: 'cikis', decision: 'acildi', gate_command: 'accepted', seen_at: new Date().toISOString() }, { admissionId: -1 });
    await q(`UPDATE parking_policies SET enabled=TRUE WHERE site_code=$1`, [ids.site]);
    assert.equal((await admit(body('06XY123'))).command_accepted, true);
  });
  it('reddedilen onay/kontenjan kararı olay ve karar geçmişine de yazılır', async () => {
    await q(`UPDATE parking_apartment_approvals SET approved=FALSE WHERE apartment_id=$1`, [ids.apartment]);
    const countBefore = Number((await q(`SELECT COUNT(*) FROM plate_events WHERE site_code=$1`, [ids.site])).rows[0].count);
    await admit(body());
    assert.equal(Number((await q(`SELECT COUNT(*) FROM plate_events WHERE site_code=$1`, [ids.site])).rows[0].count), countBefore+1);
    const last = (await q('SELECT decision,reason FROM plate_decisions WHERE site_code=$1 ORDER BY id DESC LIMIT 1', [ids.site])).rows[0];
    assert.equal(last.decision, 'DENIED'); assert.equal(last.reason, 'parking_apartment_not_approved');
  });
  it('eski içeriden düşür endpointi de rezervasyonu atomik bırakır', async () => {
    await admit(body());
    const presence = (await q(`SELECT id FROM plate_presence WHERE site_code=$1 AND plate='34ABC123'`, [ids.site])).rows[0];
    await clearInside({ siteCode: ids.site, rawId: presence.id, authUser: ids.auth });
    await q(`UPDATE parking_admissions SET created_at=NOW()-INTERVAL '10 seconds' WHERE site_code=$1`, [ids.site]);
    assert.equal((await admit(body('06XY123'))).command_accepted, true);
  });
  it('başka sitenin kameraları ve eşleşmeyen kapılar reddedilir', async () => {
    await q(`INSERT INTO parking_policies(site_code,enabled,capacity) VALUES($1,TRUE,1)`, [ids.other]);
    await assert.rejects(() => request({ siteCode: ids.other, body: body(), publish: publishOk }), (e) => e.code === 'PARKING_GATE_NOT_READY');
  });
  it('otomatik açma kapalı, model hazır değil veya düşük güven: MQTT hiç çağrılmaz', async () => {
    let published = 0; const publisher = async () => { ++published; };
    assert.equal((await admit(body('34ABC123', { confidence: .5 }), publisher)).reason, 'low_confidence');
    assert.equal((await admit(body('34ABC123', { recognition_ready: false }), publisher)).reason, 'recognition_not_ready');
    await q('UPDATE plate_gate_settings SET auto_open=FALSE WHERE site_code=$1', [ids.site]);
    assert.equal((await admit(body(), publisher)).reason, 'auto_open_disabled');
    await q('UPDATE plate_gate_settings SET auto_open=TRUE WHERE site_code=$1', [ids.site]);
    assert.equal(published, 0);
  });
  it('apartment_id boş eski kişi aracı currentresidencyden daire onayını bulur', async () => {
    const person = Number((await q(`INSERT INTO site_people(site_code,full_name) VALUES($1,'Legacy fixture') RETURNING id`, [ids.site])).rows[0].id);
    await q(`INSERT INTO apartment_residencies(site_code,apartment_id,person_id,relation) VALUES($1,$2,$3,'resident')`, [ids.site, ids.apartment, person]);
    await q(`INSERT INTO vehicles(site_code,person_id,plate) VALUES($1,$2,'07XY123')`, [ids.site, person]);
    assert.equal(await approval(pool, ids.site, '07XY123'), true);
    await q('UPDATE parking_apartment_approvals SET approved=FALSE WHERE apartment_id=$1', [ids.apartment]);
    assert.equal(await approval(pool, ids.site, '07XY123'), false);
  });
  it('eski bağsız araç istisnası daireye bağlanınca onayı bypass edemez; yabancı kişinin plakası reddedilir', async () => {
    const person = Number((await q(`INSERT INTO site_people(site_code,full_name) VALUES($1,'Former company') RETURNING id`, [ids.site])).rows[0].id);
    const car = Number((await q(`INSERT INTO vehicles(site_code,person_id,plate) VALUES($1,$2,'16XY123') RETURNING id`, [ids.site,person])).rows[0].id);
    await q(`INSERT INTO parking_legacy_vehicle_exemptions(vehicle_id) VALUES($1)`, [car]);
    assert.equal(await approval(pool,ids.site,'16XY123'),true);
    await q(`INSERT INTO apartment_residencies(site_code,apartment_id,person_id,relation) VALUES($1,$2,$3,'resident')`, [ids.site,ids.apartment,person]);
    await q(`UPDATE parking_apartment_approvals SET approved=FALSE WHERE apartment_id=$1`, [ids.apartment]);
    assert.equal(await approval(pool,ids.site,'16XY123'),false);
    const foreign = Number((await q(`INSERT INTO site_people(site_code,full_name) VALUES($1,'Foreign person') RETURNING id`, [ids.other])).rows[0].id);
    await q(`INSERT INTO vehicles(site_code,person_id,apartment_id,plate) VALUES($1,$2,$3,'17XY123')`, [ids.site,foreign,ids.apartment2]);
    assert.equal(await approval(pool,ids.site,'17XY123'),false);
  });
  it('ruhsat aynı transactionda plaka/sahip/daire değişince silinir; not değişince korunur', async () => {
    const car = Number((await q(`SELECT id FROM vehicles WHERE site_code=$1 AND plate='34ABC123'`, [ids.site])).rows[0].id);
    const addPhoto = () => q(`INSERT INTO vehicle_registration_photos(vehicle_id,mime_type,image_bytes) VALUES($1,'image/png',$2)`, [car,Buffer.from([137,80,78,71,13,10,26,10])]);
    const count = async () => Number((await q('SELECT COUNT(*) FROM vehicle_registration_photos WHERE vehicle_id=$1',[car])).rows[0].count);
    await addPhoto(); await q(`UPDATE vehicles SET note='yalnız not' WHERE id=$1`,[car]); assert.equal(await count(),1);
    await q(`UPDATE vehicles SET plate='34ABC124' WHERE id=$1`,[car]); assert.equal(await count(),0);
    await addPhoto(); await q(`UPDATE vehicles SET apartment_id=$2 WHERE id=$1`,[car,ids.apartment2]); assert.equal(await count(),0);
    const person = Number((await q(`SELECT id FROM site_people WHERE site_code=$1 LIMIT 1`,[ids.site])).rows[0].id);
    await addPhoto(); await q('UPDATE vehicles SET person_id=$2 WHERE id=$1',[car,person]); assert.equal(await count(),0);
  });
  it('ikinci ensure ve migration yeni eklenen araçlı daireyi kendiliğinden onaylamaz', async () => {
    const apartment = Number((await q(`INSERT INTO apartments(site_code,block_id,unit_label,sort_order) VALUES($1,$2,'99',99) RETURNING id`, [ids.site,ids.block])).rows[0].id);
    await q(`INSERT INTO vehicles(site_code,apartment_id,plate) VALUES($1,$2,'61AB123')`, [ids.site,apartment]);
    const { ensureParkingAccessSchema } = await import('../src/modules/parking_access_schema.js');
    const { readFileSync } = await import('node:fs');
    await ensureParkingAccessSchema(pool); await ensureParkingAccessSchema(pool);
    await q(readFileSync(new URL('../migrations/130_parking_access.sql', import.meta.url),'utf8'));
    assert.equal(await approval(pool,ids.site,'61AB123'),false);
  });
});
