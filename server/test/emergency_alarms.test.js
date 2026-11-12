import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pool } from '../src/db.js';
import { pushCapabilities } from '../src/modules/push_capabilities.js';
import { parseAlarmInput } from '../src/modules/emergency_alarm_common.js';
import { EMERGENCY_ALARM_STEPS, emergencyAlarmMigrationSql, ensureEmergencyAlarmSchema } from '../src/modules/emergency_alarm_schema.js';
import { emergencyAlarmRouter, emergencyAlarmReadLimiter, emergencyAlarmWriteLimiter } from '../src/modules/emergency_alarm_routes.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { createEmergencyAlarm, emergencyAlarmHooks, listAlarmElevators, listAlarmLocations, listEmergencyAlarms, listEmergencyAlarmHistory, markEmergencyAlarm, RECEIVER_FLAGS_SQL } from '../src/modules/emergency_alarm_service.js';
import { getAlarmResponders, saveAlarmResponders, selectAlarmRecipients, MANAGER_RECIPIENTS_SQL, SOUND_RECIPIENTS_SQL } from '../src/modules/emergency_alarm_recipients.js';
import { alarmAccountEligibleSql, listAlarmSites, recipientAccessSql } from '../src/modules/emergency_alarm_access.js';
import { findUnsafeStatements } from '../scripts/migrate.js';
import { notifyAlarmManagers, notifyAlarmRecipients } from '../src/modules/emergency_alarm_push.js';
import { pushDeviceHooks } from '../src/modules/push_devices.js';
import { EMERGENCY_FIRE_MIGRATION_SQL, ensureEmergencyFireSchema } from '../src/modules/emergency_fire_schema.js';

const fire = { site_code: 100, kind: 'fire', location_id: 'site', idempotency_key: 'fire-test-001' };
const elevator = { site_code: 100, kind: 'elevator', equipment_id: 30, idempotency_key: 'lift-test-001' };
const user = (id) => ({ user_code: id, role: 'individual', full_name: `User ${id}` });

test('all recipient channels share login eligibility and super-user exclusion without changing first-password rules', () => {
  const eligible = alarmAccountEligibleSql('sample');
  assert.match(eligible, /sample\.is_active IS TRUE/);
  assert.match(eligible, /sample\.deleted_at IS NULL/);
  assert.match(eligible, /sample\.email_verified IS TRUE/);
  assert.match(eligible, /COALESCE\(sample\.approval_status, ''\) NOT IN \('pending', 'rejected'\)/);
  assert.match(eligible, /sample\.role IS DISTINCT FROM 'super_user'/);
  assert.doesNotMatch(eligible, /must_change_password/);
  for (const sql of [MANAGER_RECIPIENTS_SQL, SOUND_RECIPIENTS_SQL]) assert.ok(sql.includes(alarmAccountEligibleSql()));
  assert.ok(recipientAccessSql().includes(alarmAccountEligibleSql('au')));
  assert.equal(RECEIVER_FLAGS_SQL.split(alarmAccountEligibleSql('au')).length - 1, 2, 'both feed flags check current account eligibility');
});

test('alarm body: explicit registered location and valid elevator, bounded transport idempotency', () => {
  assert.equal(parseAlarmInput(fire).locationId, 'site');
  assert.equal(parseAlarmInput({ ...fire, location_id: 'block:40' }).locationId, 'block:40');
  assert.equal(parseAlarmInput(elevator).equipmentId, 30);
  for (const bad of [null, {}, { ...fire, kind: '112' }, { ...fire, location_id: null }, { ...fire, location_id: 'free-form' }, { ...fire, equipment_id: 30 }, { ...elevator, equipment_id: -1 }, { ...fire, idempotency_key: 'short' }, { ...fire, idempotency_key: 'x'.repeat(81) }, { ...fire, site_code: '1;DROP' }]) {
    assert.throws(() => parseAlarmInput(bad), (e) => e.statusCode === 400);
  }
});

test('trial inbox is quiet and trial mutations are rejected without querying recipients', async () => {
  const trialUser = { ...user(1), trial: { siteCode: 100 } };
  const noDb = { query: async () => { throw new Error('must not query'); }, connect: async () => { throw new Error('must not connect'); } };
  assert.deepEqual(await listEmergencyAlarms(trialUser, noDb), { alarms: [], can_receive: false, can_sound: false, has_more: false });
  await assert.rejects(createEmergencyAlarm({ authUser: trialUser, body: elevator }, noDb), (e) => e.code === 'TRIAL_ACTION_DENIED');
  await assert.rejects(markEmergencyAlarm({ authUser: trialUser, rawId: 1, action: 'ack' }, noDb), (e) => e.code === 'TRIAL_ACTION_DENIED');
  const sites = await listAlarmSites(trialUser, { query: async () => ({ rows: [{ site_code: 100 }, { site_code: 200 }] }) });
  assert.deepEqual(sites.sites.map((s) => [s.site_code, s.can_create]), [[100, false]]);
});

test('128 migration matches source and is additive; normal startup acquires no table locks', async () => {
  const migration = readFileSync(new URL('../migrations/128_emergency_alarms.sql', import.meta.url), 'utf8');
  assert.ok(migration.endsWith(emergencyAlarmMigrationSql()));
  assert.deepEqual(findUnsafeStatements(migration), []);
  assert.doesNotMatch(migration, /\b(DROP|TRUNCATE|UPDATE|DELETE FROM)\b/i);
  const queries = [];
  await ensureEmergencyAlarmSchema({ query: async (sql) => {
    queries.push(sql);
    return { rows: [{ actor_name: true, resident_role: true, tables: EMERGENCY_ALARM_STEPS.filter((s) => s.kind === 'table').map((s) => s.name), fks: EMERGENCY_ALARM_STEPS.filter((s) => s.kind === 'fk').map((s) => s.name), indexes: EMERGENCY_ALARM_STEPS.filter((s) => s.kind === 'index').map((s) => s.name) }] };
  } });
  assert.equal(queries.length, 2);
  assert.ok(queries.every((sql) => /^SELECT/.test(sql)), 'normal startup has no DDL');
});

test('every new alarm route authenticates and rate-limits; no unauthenticated dispatch path', () => {
  const routes = emergencyAlarmRouter.stack.filter((s) => s.route).map((s) => s.route);
  assert.equal(routes.length, 12);
  for (const route of routes) {
    assert.equal(route.stack[0].handle, authRequired, route.path);
    assert.equal(route.stack[1].handle, route.methods.get ? emergencyAlarmReadLimiter : emergencyAlarmWriteLimiter, route.path);
  }
});

test('129 retains old recipient timestamps and expands only the role check, startup is idempotent', async () => {
  const migration = readFileSync(new URL('../migrations/129_emergency_fire_broadcast.sql', import.meta.url), 'utf8');
  assert.ok(migration.endsWith(EMERGENCY_FIRE_MIGRATION_SQL));
  assert.deepEqual(findUnsafeStatements(migration), []);
  assert.doesNotMatch(migration, /DROP\s+(TABLE|COLUMN)|\bTRUNCATE\b|\bUPDATE\b|DELETE FROM/i);
  const queries = [];
  await ensureEmergencyFireSchema({ query: async (sql) => { queries.push(sql); return { rows: [{ actor_name: true, resident_role: true }] }; } });
  assert.equal(queries.length, 1);
  assert.match(queries[0], /^SELECT/);
});

test('fire push respects rechecked recipients and uses audible channel only for resident/security recipients', async () => {
  const before = { available: pushDeviceHooks.available, client: pushDeviceHooks.client };
  const messages = [];
  pushDeviceHooks.available = () => true;
  pushDeviceHooks.client = () => ({ send: async (message) => { messages.push(message); return { kind: 'ok' }; } });
  try {
    const result = await notifyAlarmRecipients({ id: 10, site_code: 100, kind: 'fire' }, { query: async (sql) => {
      assert.ok(sql.includes(recipientAccessSql()));
      assert.match(sql, /r\.acknowledged_at IS NULL/);
      return { rows: [{ fcm_token: 'test-resident', role: 'resident' }, { fcm_token: 'test-manager', role: 'manager' }] };
    } });
    assert.deepEqual(result, { available: true, accepted: 2 });
    assert.equal(messages[0].android.notification.channel_id, 'emergency_alarm');
    assert.equal(messages[0].android.notification.sound, 'emergency_alarm');
    assert.equal(messages[0].data.sound_enabled, 'true');
    assert.equal(messages[0].apns.payload.aps.sound, 'default');
    assert.equal(messages[1].android.notification.channel_id, 'emergency_info');
    assert.equal(messages[1].data.sound_enabled, 'false');
    assert.equal(messages[1].apns.payload.aps.sound, undefined);
  } finally { Object.assign(pushDeviceHooks, before); }
});

test('manager mobile notifications use silent channel and passive APNs, with honest provider outcome', async () => {
  const before = { available: pushDeviceHooks.available, client: pushDeviceHooks.client };
  const messages = [];
  pushDeviceHooks.available = () => true;
  pushDeviceHooks.client = () => ({ send: async (message) => { messages.push(message); return { kind: 'ok' }; } });
  const db = { query: async (sql, params) => {
    assert.match(sql, /r\.role = 'manager'/);
    assert.match(sql, /site_manager_sites/);
    assert.ok(sql.includes(alarmAccountEligibleSql()), 'silent push rechecks the same account predicate');
    assert.deepEqual(params, [10, 100]);
    return { rows: [{ fcm_token: 'synthetic-device-token' }] };
  } };
  try {
    assert.deepEqual(await notifyAlarmManagers({ id: 10, site_code: 100, kind: 'fire' }, db), { available: true, accepted: 1 });
    assert.equal(messages[0].android.notification.channel_id, 'emergency_info');
    assert.equal(messages[0].data.sound_enabled, 'false');
    assert.equal(messages[0].apns.payload.aps.sound, undefined);
    assert.equal(messages[0].apns.payload.aps['interruption-level'], 'passive');
    assert.ok(Number(messages[0].apns.headers['apns-expiration']) > Date.now() / 1000);
    pushDeviceHooks.client = () => ({ send: async () => { throw new Error('provider unavailable'); } });
    assert.deepEqual(await notifyAlarmManagers({ id: 10, site_code: 100, kind: 'fire' }, db), { available: true, accepted: 0 });
    pushDeviceHooks.available = () => false;
    assert.deepEqual(await notifyAlarmManagers({ id: 10, site_code: 100, kind: 'fire' }, db), { available: false, accepted: 0 });
  } finally { Object.assign(pushDeviceHooks, before); }
});

// Opt-in real SQL verification. All relations are TEMPORARY and shadow public tables on a dedicated connection.
// Does not mutate production records; every service transaction uses this connection; closing it drops all fixtures.
test('PostgreSQL: resident scope, vendor binding, manager silence, fire location, replay, delivery and ACK', { skip: process.env.EMERGENCY_PG_TEST !== '1' }, async (t) => {
  assert.match(process.env.DB_NAME ?? '', /^kapi_(test|rehearsal)_/, 'Real-SQL checks require an isolated test database');
  const connection = await pool.connect();
  const originalNotify = emergencyAlarmHooks.notify;
  emergencyAlarmHooks.notify = async () => {};
  const db = { query: (...args) => connection.query(...args), connect: async () => ({ query: (...args) => connection.query(...args), release() {} }) };
  try {
    await connection.query(`
      CREATE TEMP TABLE users (user_code INTEGER PRIMARY KEY, full_name TEXT, login_name TEXT, is_active BOOLEAN DEFAULT TRUE, deleted_at TIMESTAMPTZ,
        role TEXT DEFAULT 'individual', email_verified BOOLEAN DEFAULT TRUE, approval_status TEXT DEFAULT 'approved');
      CREATE TEMP TABLE sites (site_code BIGINT PRIMARY KEY, name TEXT, approval_status TEXT DEFAULT 'approved', address TEXT, city TEXT, district TEXT);
      CREATE TEMP TABLE site_manager_sites (site_code BIGINT, manager_user_code INTEGER);
      CREATE TEMP TABLE site_memberships (site_code BIGINT, user_code INTEGER, role TEXT, is_active BOOLEAN DEFAULT TRUE);
      CREATE TEMP TABLE site_blocks (id BIGINT PRIMARY KEY, site_code BIGINT, block_name TEXT);
      CREATE TEMP TABLE apartments (id BIGINT PRIMARY KEY, site_code BIGINT, block_id BIGINT, is_active BOOLEAN DEFAULT TRUE, resident_user_code INTEGER);
      CREATE TEMP TABLE apartment_memberships (apartment_id BIGINT, user_code INTEGER, is_active BOOLEAN DEFAULT TRUE);
      CREATE TEMP TABLE site_people (id BIGINT PRIMARY KEY, site_code BIGINT, user_code INTEGER, is_active BOOLEAN DEFAULT TRUE);
      CREATE TEMP TABLE apartment_residencies (person_id BIGINT, apartment_id BIGINT, is_current BOOLEAN DEFAULT TRUE);
      CREATE TEMP TABLE contract_vendors (id BIGINT PRIMARY KEY, site_code BIGINT, name TEXT, category TEXT, is_active BOOLEAN DEFAULT TRUE);
      CREATE TEMP TABLE site_contracts (vendor_id BIGINT, site_code BIGINT, category TEXT, status TEXT, start_date DATE, end_date DATE);
      CREATE TEMP TABLE equipment_items (id BIGINT PRIMARY KEY, site_code BIGINT, kind TEXT, name TEXT, location TEXT, block_id BIGINT, vendor_id BIGINT, is_active BOOLEAN DEFAULT TRUE);
      CREATE TEMP TABLE audit_log (actor_user_code INTEGER, actor_name TEXT, actor_role TEXT, action TEXT, site_code BIGINT, target_type TEXT, target_id TEXT, details JSONB);
      INSERT INTO users(user_code, full_name, login_name) SELECT n, 'User '||n, 'user'||n FROM generate_series(1,14) n;
      UPDATE users SET is_active = FALSE WHERE user_code = 8;
      UPDATE users SET approval_status = 'pending' WHERE user_code = 9;
      UPDATE users SET email_verified = FALSE WHERE user_code = 10;
      UPDATE users SET role = 'super_user' WHERE user_code = 11;
      UPDATE users SET approval_status = 'rejected' WHERE user_code = 12;
      UPDATE users SET email_verified = NULL WHERE user_code = 13;
      UPDATE users SET approval_status = NULL WHERE user_code = 14;
      INSERT INTO sites(site_code,name) VALUES (100,'Site A'),(200,'Site B');
      INSERT INTO site_manager_sites VALUES (100,4),(200,7);
      INSERT INTO site_memberships(site_code,user_code,role) VALUES (100,2,'STAFF'),(100,6,'STAFF'),(100,4,'SITE_ADMIN');
      INSERT INTO site_memberships(site_code,user_code,role) SELECT 100, n, 'STAFF' FROM generate_series(9,14) n;
      INSERT INTO apartments(id,site_code,block_id,resident_user_code) VALUES (1001,100,40,1);
      INSERT INTO apartment_memberships(apartment_id,user_code) VALUES (1001,1);
      INSERT INTO site_blocks VALUES (40,100,'A Blok'),(41,200,'B Blok');
      INSERT INTO contract_vendors(id,site_code,name,category) VALUES (20,100,'Lift A','asansor'),(21,200,'Lift B','asansor');
      INSERT INTO site_contracts VALUES (20,100,'asansor','aktif',CURRENT_DATE-1,NULL),(21,200,'asansor','aktif',CURRENT_DATE-1,NULL);
      INSERT INTO equipment_items(id,site_code,kind,name,location,vendor_id,is_active) VALUES
        (30,100,'asansor','Asansör A','A Blok',20,TRUE),(31,200,'asansor','Asansör B','B Blok',21,TRUE),
        (32,100,'asansor','Eski','A Blok',20,FALSE),(33,100,'kazan','Kazan','A Blok',NULL,TRUE);
    `);
    for (const step of EMERGENCY_ALARM_STEPS) await connection.query(step.kind === 'table' ? step.sql.replace('CREATE TABLE IF NOT EXISTS', 'CREATE TEMP TABLE') : step.sql);
    await connection.query(EMERGENCY_FIRE_MIGRATION_SQL);
    await t.test('only real residents can initiate, other-site elevators and fire blocks rejected', async () => {
      assert.deepEqual((await listAlarmSites(user(1), db)).sites.map((s) => s.site_code), [100]);
      assert.equal((await listAlarmSites(user(2), db)).sites.length, 0);
      assert.deepEqual((await listAlarmElevators({ authUser: user(1), siteCode: 100 }, db)).elevators.map((e) => e.id), [30]);
      assert.equal((await listAlarmLocations({ authUser: user(1), siteCode: 100 }, db)).locations[1].name, 'A Blok');
      for (const id of [31,32,33]) await assert.rejects(createEmergencyAlarm({ authUser: user(1), body: { ...elevator, equipment_id: id } }, db), (e) => e.code === 'ELEVATOR_NOT_AVAILABLE');
      await assert.rejects(createEmergencyAlarm({ authUser: user(2), body: elevator }, db), (e) => e.code === 'NOT_A_RESIDENT');
      await assert.rejects(createEmergencyAlarm({ authUser: user(1), body: { ...fire, location_id: 'block:41' } }, db), (e) => e.code === 'LOCATION_NOT_AVAILABLE');
      await assert.rejects(listAlarmElevators({ authUser: user(1), siteCode: 200 }, db), (e) => e.code === 'NOT_A_RESIDENT');
    });
    await t.test('block elevators follow real apartment associations, common elevators remain shared and POST cannot bypass the list', async () => {
      await db.query("INSERT INTO site_blocks VALUES (42,100,'C Blok')");
      await db.query("INSERT INTO equipment_items(id,site_code,kind,name,block_id,is_active) VALUES (34,100,'asansor','A Block lift',40,TRUE),(35,100,'asansor','C Block lift',42,TRUE),(36,100,'asansor','Shared lift',NULL,TRUE)");
      try {
        const visible = (await listAlarmElevators({ authUser: user(1), siteCode: 100 }, db)).elevators;
        assert.ok(visible.some((eq) => eq.id === 34 && eq.block_id === 40 && eq.block_name === 'A Blok'));
        assert.ok(visible.some((eq) => eq.id === 36));
        assert.ok(!visible.some((eq) => eq.id === 35));
        await assert.rejects(createEmergencyAlarm({ authUser: user(1), body: { ...elevator, equipment_id: 35, idempotency_key: 'scope-block-denied' } }, db), (error) => error.code === 'ELEVATOR_NOT_AVAILABLE');
        await db.query('UPDATE equipment_items SET is_active=FALSE WHERE id IN (30,34,36)');
        assert.equal((await listAlarmElevators({ authUser: user(1), siteCode: 100 }, db)).elevators.length, 0, 'a lift in another block cannot keep the button visible');
        await db.query('UPDATE equipment_items SET is_active=TRUE WHERE id IN (30,34,36)');
        await db.query('INSERT INTO apartments(id,site_code,block_id) VALUES (1002,100,42)');
        await db.query('INSERT INTO apartment_memberships(apartment_id,user_code) VALUES (1002,1)');
        assert.ok((await listAlarmElevators({ authUser: user(1), siteCode: 100 }, db)).elevators.some((eq) => eq.id === 35), 'multiple real apartment blocks are supported');
        await db.query('UPDATE apartment_memberships SET is_active=FALSE WHERE apartment_id=1002');
        assert.ok(!(await listAlarmElevators({ authUser: user(1), siteCode: 100 }, db)).elevators.some((eq) => eq.id === 35), 'revoked membership cannot keep an elevator in scope');
      } finally {
        await db.query('DELETE FROM apartment_memberships WHERE apartment_id=1002');
        await db.query('DELETE FROM apartments WHERE id=1002');
        await db.query('DELETE FROM equipment_items WHERE id IN (34,35,36)');
        await db.query('DELETE FROM site_blocks WHERE id=42');
      }
    });
    await t.test('assignment validates active accounts, local staff, valid contracts and notification-only manager', async () => {
      const save = (responders) => saveAlarmResponders({ siteCode: 100, actor: user(4), body: { responders } }, db);
      await assert.rejects(save([{ role: 'security', user_code: 3 }]), (e) => e.code === 'RESPONDER_NOT_STAFF');
      await assert.rejects(save([{ role: 'security', user_code: 4 }]), (e) => e.code === 'MANAGER_NOTIFICATION_ONLY');
      await assert.rejects(save([{ role: 'elevator_service', login_name: 'user3', vendor_id: 21 }]), (e) => e.code === 'SERVICE_CONTRACT_REQUIRED');
      await assert.rejects(save([{ role: 'elevator_service', login_name: 'user8', vendor_id: 20 }]), (e) => e.code === 'RESPONDER_ACCOUNT_INVALID');
      const assigned = await save([{ role: 'security', user_code: 2 },{ role: 'elevator_service', login_name: 'user3', vendor_id: 20 }]);
      assert.equal(assigned.responders.length, 2);
      assert.equal((await getAlarmResponders(100, db)).responders.every((r) => r.eligible), true);
      assert.equal((await db.query('SELECT * FROM site_memberships WHERE user_code = 3')).rowCount, 0, 'service gains no general site membership');
    });
    await t.test('individual push eligibility follows actual residents/responders and revokes on contract or account loss', async () => {
      const canRegister = async (code) => (await pushCapabilities({ user_code: code, role: 'individual' }, db)).can_register;
      for (const code of [1, 2, 3, 4]) assert.equal(await canRegister(code), true, `eligible account ${code}`);
      for (const code of [5, 6, 8, 9, 10, 11, 12, 13]) assert.equal(await canRegister(code), false, `not an eligible recipient ${code}`);
      await db.query("UPDATE site_contracts SET status='bitti' WHERE vendor_id=20");
      try { assert.equal(await canRegister(3), false); }
      finally { await db.query("UPDATE site_contracts SET status='aktif' WHERE vendor_id=20"); }
      await db.query('UPDATE users SET email_verified=FALSE WHERE user_code=3');
      try { assert.equal(await canRegister(3), false); }
      finally { await db.query('UPDATE users SET email_verified=TRUE WHERE user_code=3'); }
      assert.equal(await canRegister(3), true);
    });
    await t.test('pending, unverified, rejected, NULL verification and super users cannot be assigned; NULL legacy approval stays compatible', async () => {
      const save = (responders) => saveAlarmResponders({ siteCode: 100, actor: user(4), body: { responders } }, db);
      const before = (await getAlarmResponders(100, db)).responders.map((r) => r.user_code).sort();
      for (const userCode of [9,10,11,12,13]) {
        for (const role of ['security', 'elevator_service']) {
          await assert.rejects(save([{ role, user_code: userCode, ...(role === 'elevator_service' ? { vendor_id: 20 } : {}) }]), (e) => e.code === 'RESPONDER_ACCOUNT_INVALID');
          assert.deepEqual((await getAlarmResponders(100, db)).responders.map((r) => r.user_code).sort(), before, 'failed assignment is atomic');
        }
      }
      const candidates = (await getAlarmResponders(100, db)).security_candidates.map((r) => r.user_code);
      assert.ok([9,10,11,12,13].every((id) => !candidates.includes(id)));
      assert.ok(candidates.includes(14), 'NULL approval is not exact pending/rejected, as in authRequired');
      await save([{ role: 'security', user_code: 14 }]);
      assert.equal((await getAlarmResponders(100, db)).responders[0].eligible, true);
      await save([{ role: 'security', user_code: 2 }, { role: 'elevator_service', user_code: 3, vendor_id: 20 }]);
    });
    let id;
    await t.test('exact replay creates one alarm and recipient set; altered payload conflicts', async () => {
      const created = await createEmergencyAlarm({ authUser: user(1), body: elevator }, db);
      id = created.alarm.id;
      assert.deepEqual(created.delivery, { security_assigned: 1, service_assigned: 1, manager_notified: 1, warnings: [] });
      assert.equal(created.replayed, false);
      const replay = await createEmergencyAlarm({ authUser: user(1), body: elevator }, db);
      assert.equal(replay.alarm.id, id);
      assert.equal(replay.replayed, true);
      await assert.rejects(createEmergencyAlarm({ authUser: user(1), body: { ...fire, idempotency_key: elevator.idempotency_key } }, db), (e) => e.code === 'IDEMPOTENCY_CONFLICT');
      assert.equal((await db.query('SELECT * FROM emergency_alarms')).rowCount, 1);
      assert.equal((await db.query('SELECT * FROM emergency_alarm_recipients')).rowCount, 3);
    });
    await t.test('only assigned security/service sound; manager silent; no outsider or generic staff leak', async () => {
      assert.equal((await listEmergencyAlarms(user(2), db)).alarms[0].sound_enabled, true);
      assert.equal((await listEmergencyAlarms(user(3), db)).alarms[0].sound_enabled, true);
      assert.equal((await listEmergencyAlarms(user(4), db)).alarms[0].sound_enabled, false);
      for (const code of [1,5,6,7,8]) assert.equal((await listEmergencyAlarms(user(code), db)).alarms.length, 0);
      await assert.rejects(markEmergencyAlarm({ authUser: user(5), rawId: id, action: 'ack' }, db), (e) => e.code === 'ALARM_NOT_FOUND');
      await assert.rejects(markEmergencyAlarm({ authUser: user(4), rawId: id, action: 'played' }, db), (e) => e.code === 'ALARM_SOUND_FORBIDDEN');
    });
    await t.test('assigned accounts losing verification/approval or becoming super immediately lose feed flags, eligibility and ACK access', async () => {
      const states = [
        ['email_verified = FALSE', 'email_verified = TRUE'],
        ['email_verified = NULL', 'email_verified = TRUE'],
        ["approval_status = 'pending'", "approval_status = 'approved'"],
        ["approval_status = 'rejected'", "approval_status = 'approved'"],
        ["role = 'super_user'", "role = 'individual'"],
      ];
      for (const [change, restore] of states) {
        // SQL fragments are fixed test constants; no user input is interpolated.
        await db.query(`UPDATE users SET ${change} WHERE user_code = 3`);
        try {
          assert.deepEqual(await listEmergencyAlarms(user(3), db), { alarms: [], can_receive: false, can_sound: false, has_more: false });
          const responder = (await getAlarmResponders(100, db)).responders.find((r) => r.user_code === 3);
          assert.equal(responder.eligible, false);
          const selected = await selectAlarmRecipients(db, { siteCode: 100, kind: 'elevator', vendorId: 20 });
          assert.equal(selected.delivery.service_assigned, 0);
          assert.equal(selected.delivery.manager_notified, 1, 'manager notification scope stays intact');
          await assert.rejects(markEmergencyAlarm({ authUser: user(3), rawId: id, action: 'ack' }, db), (e) => e.code === 'ALARM_NOT_FOUND');
        } finally { await db.query(`UPDATE users SET ${restore} WHERE user_code = 3`); }
      }
      assert.equal((await listEmergencyAlarms(user(3), db)).can_sound, true, 'valid restored account receives again');
      // A manager is always notification-only, and also loses delivery when its login is not eligible.
      await db.query("UPDATE users SET approval_status = 'pending' WHERE user_code = 4");
      try {
        assert.deepEqual(await listEmergencyAlarms(user(4), db), { alarms: [], can_receive: false, can_sound: false, has_more: false });
        assert.equal((await selectAlarmRecipients(db, { siteCode: 100, kind: 'elevator', vendorId: 20 })).delivery.manager_notified, 0);
        await assert.rejects(markEmergencyAlarm({ authUser: user(4), rawId: id, action: 'ack' }, db), (e) => e.code === 'ALARM_NOT_FOUND');
      } finally { await db.query("UPDATE users SET approval_status = 'approved' WHERE user_code = 4"); }
    });
    await t.test('device received, playback report and human ACK stay distinct; manager ACK does not respond', async () => {
      await markEmergencyAlarm({ authUser: user(4), rawId: id, action: 'ack' }, db);
      assert.equal((await db.query('SELECT status FROM emergency_alarms WHERE id=$1',[id])).rows[0].status, 'open');
      await markEmergencyAlarm({ authUser: user(2), rawId: id, action: 'received' }, db);
      let recipient = (await db.query('SELECT * FROM emergency_alarm_recipients WHERE alarm_id=$1 AND user_code=2',[id])).rows[0];
      assert.ok(recipient.received_at); assert.equal(recipient.played_at, null); assert.equal(recipient.acknowledged_at, null);
      await markEmergencyAlarm({ authUser: user(2), rawId: id, action: 'played' }, db);
      recipient = (await db.query('SELECT * FROM emergency_alarm_recipients WHERE alarm_id=$1 AND user_code=2',[id])).rows[0];
      assert.ok(recipient.played_at); assert.equal(recipient.acknowledged_at, null);
      await markEmergencyAlarm({ authUser: user(2), rawId: id, action: 'ack' }, db);
      assert.equal((await listEmergencyAlarms(user(2), db)).alarms.length, 0);
      assert.equal((await listEmergencyAlarms(user(3), db)).alarms[0].status, 'acknowledged', 'other responder still needs own ACK');
    });
    await t.test('revoked contracts and newly granted manager role immediately revoke sound access', async () => {
      await db.query("UPDATE site_contracts SET status='feshedildi' WHERE vendor_id=20");
      assert.equal((await listEmergencyAlarms(user(3), db)).alarms.length, 0);
      await assert.rejects(markEmergencyAlarm({ authUser: user(3), rawId: id, action: 'ack' }, db), (e) => e.code === 'ALARM_NOT_FOUND');
      await db.query("UPDATE site_contracts SET status='aktif' WHERE vendor_id=20");
      await db.query('INSERT INTO site_manager_sites VALUES (100,3)');
      assert.equal((await listEmergencyAlarms(user(3), db)).alarms.length, 0);
      await db.query('DELETE FROM site_manager_sites WHERE manager_user_code=3');
    });
    await t.test('fire uses selected block, excludes elevator service, and resolving stops all alarms', async () => {
      const created = await createEmergencyAlarm({ authUser: user(1), body: { ...fire, location_id: 'block:40' } }, db);
      assert.equal(created.alarm.location, 'A Blok');
      assert.equal(created.delivery.service_assigned, 0);
      assert.equal((await listEmergencyAlarms(user(3), db)).alarms.some((a) => a.id === created.alarm.id), false);
      await markEmergencyAlarm({ authUser: user(4), rawId: created.alarm.id, action: 'resolve' }, db);
      assert.equal((await listEmergencyAlarms(user(2), db)).alarms.some((a) => a.id === created.alarm.id), false);
    });
    await t.test('fire block/site broadcast, initiator snapshot, personal ACK, immutable history and revoked membership scope', async () => {
      await db.query(`
        INSERT INTO users(user_code, full_name, login_name) SELECT n, 'User '||n, 'user'||n FROM generate_series(15,20) n;
        UPDATE users SET approval_status = 'pending' WHERE user_code = 20;
        INSERT INTO site_blocks VALUES (42,100,'C Blok');
        INSERT INTO apartments(id,site_code,block_id,resident_user_code) VALUES (1002,100,40,15),(1003,100,42,16),(2001,200,41,17);
        INSERT INTO apartment_memberships(apartment_id,user_code) VALUES (1002,15),(1002,18),(1002,4),(1002,2),(1002,20);
        INSERT INTO site_people(id,site_code,user_code) VALUES (190,100,19);
        INSERT INTO apartment_residencies(person_id,apartment_id) VALUES (190,1003);
      `);
      const block = await createEmergencyAlarm({ authUser: user(15), body: { ...fire, location_id: 'block:40', idempotency_key: 'block-broadcast-01' } }, db);
      assert.equal(block.alarm.created_by_name, 'User 15');
      assert.equal(block.alarm.scope, 'block');
      assert.equal(block.delivery.resident_assigned, 3, 'initiator, legacy apartment account, family member; security and manager deduplicated');
      for (const who of [1,15,18]) assert.ok((await listEmergencyAlarms(user(who), db)).alarms.some((a) => a.id === block.alarm.id && a.sound_enabled));
      for (const who of [3,16,17,19,20]) assert.ok(!(await listEmergencyAlarms(user(who), db)).alarms.some((a) => a.id === block.alarm.id));
      assert.equal((await db.query('SELECT role FROM emergency_alarm_recipients WHERE alarm_id=$1 AND user_code=4', [block.alarm.id])).rows[0].role, 'manager');
      assert.equal((await db.query('SELECT role FROM emergency_alarm_recipients WHERE alarm_id=$1 AND user_code=2', [block.alarm.id])).rows[0].role, 'security');
      await markEmergencyAlarm({ authUser: user(18), rawId: block.alarm.id, action: 'ack' }, db);
      assert.equal((await db.query('SELECT status FROM emergency_alarms WHERE id=$1', [block.alarm.id])).rows[0].status, 'open', 'resident ACK is not a responder intervention');
      await assert.rejects(markEmergencyAlarm({ authUser: user(18), rawId: block.alarm.id, action: 'resolve' }, db), (e) => e.code === 'ALARM_RESOLVE_FORBIDDEN');
      assert.ok((await listEmergencyAlarms(user(15), db)).alarms.some((a) => a.id === block.alarm.id), 'one resident cannot silence others');
      await db.query("UPDATE users SET full_name='Changed name' WHERE user_code=15");
      assert.equal((await listEmergencyAlarmHistory({ authUser: user(18) }, db)).alarms.find((a) => a.id === block.alarm.id).created_by_name, 'User 15', 'history remains after ACK and name change');
      const site = await createEmergencyAlarm({ authUser: user(15), body: { ...fire, idempotency_key: 'site-broadcast-01' } }, db);
      for (const who of [1,15,16,18,19]) assert.ok((await listEmergencyAlarms(user(who), db)).alarms.some((a) => a.id === site.alarm.id));
      assert.ok(!(await listEmergencyAlarms(user(17), db)).alarms.some((a) => a.id === site.alarm.id), 'different site never receives broadcast');
      assert.ok(!(await listEmergencyAlarmHistory({ authUser: user(17) }, db)).alarms.some((a) => a.site_code === 100));
      await db.query('UPDATE apartment_memberships SET is_active=FALSE WHERE user_code=18');
      assert.equal((await listEmergencyAlarms(user(18), db)).alarms.length, 0);
      assert.equal((await listEmergencyAlarmHistory({ authUser: user(18) }, db)).alarms.length, 0, 'saved recipient does not preserve access after leaving');
      await assert.rejects(markEmergencyAlarm({ authUser: user(18), rawId: site.alarm.id, action: 'ack' }, db), (e) => e.code === 'ALARM_NOT_FOUND');
      await markEmergencyAlarm({ authUser: user(4), rawId: site.alarm.id, action: 'resolve' }, db);
      assert.ok((await listEmergencyAlarmHistory({ authUser: user(4) }, db)).alarms.some((a) => a.id === site.alarm.id && a.status === 'resolved'));
      assert.ok((await listEmergencyAlarmHistory({ authUser: user(4), beforeId: site.alarm.id }, db)).alarms.every((a) => a.id < site.alarm.id));
    });
    await t.test('missing service account warns honestly and rapid repeated new requests are bounded', async () => {
      await db.query("DELETE FROM emergency_responders WHERE role='elevator_service'");
      const created = await createEmergencyAlarm({ authUser: user(1), body: { ...elevator, idempotency_key: 'lift-test-002' } }, db);
      assert.ok(created.delivery.warnings.includes('NO_ELIGIBLE_SERVICE_ACCOUNT'));
      for (let n = 3; n <= 5; n += 1) await createEmergencyAlarm({ authUser: user(1), body: { ...elevator, idempotency_key: `lift-test-00${n}` } }, db);
      await assert.rejects(createEmergencyAlarm({ authUser: user(1), body: { ...elevator, idempotency_key: 'lift-test-006' } }, db), (e) => e.code === 'ALARM_RATE_LIMIT');
    });
  } finally {
    emergencyAlarmHooks.notify = originalNotify;
    // Dedicated session termination also removes all TEMP relations, including after a failed test.
    connection.release(true);
    await pool.end();
  }
});
