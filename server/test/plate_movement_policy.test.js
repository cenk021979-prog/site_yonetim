import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pool } from '../src/db.js';
import { ensurePlateMovementPolicySchema, PLATE_MOVEMENT_POLICY_SQL } from '../src/modules/plate_movement_policy_schema.js';
import { DEFAULT_SITE_SETTINGS, parseSettingsInput, mergeSettings } from '../src/modules/plate_gates_common.js';
import { residentCreate, residentRevoke, residentOverview } from '../src/modules/plate_recognition_permits.js';
import { setMovementPref, notifyResidentMovement } from '../src/modules/plate_notify.js';

const actor = { user_code: 20004, role: 'apartment_owner' };
const originalQuery = pool.query;
afterEach(() => { pool.query = originalQuery; });

function fakePolicyDb({ allowed = false, optin = false } = {}) {
  const log = [];
  return { log, async query(raw, params = []) {
    const sql = String(raw); log.push({ sql, params });
    if (/SELECT ma.id, ma.since/.test(sql)) return { rows: [{ id: 7, block_name: 'A', unit_label: '1', since: new Date(0) }] };
    if (/SELECT enabled FROM site_modules/.test(sql)) return { rows: [{ enabled: true }] };
    if (/FROM plate_site_settings/.test(sql)) return { rows: [{ resident_movement_notifications_enabled: allowed }] };
    if (/SELECT movement_enabled FROM plate_notify_prefs/.test(sql)) return { rows: [{ movement_enabled: optin }] };
    if (/INSERT INTO plate_notify_prefs/.test(sql)) return { rows: [] };
    if (/FROM site_people/.test(sql)) return { rows: [{ user_code: 20004 }] };
    if (/FROM plate_notify_prefs np/.test(sql)) return { rows: optin ? [{ user_code: 20004 }] : [] };
    if (/FROM plate_guest_permits/.test(sql)) return { rows: [] };
    if (/UPDATE plate_guest_permits/.test(sql)) return { rows: [{ id: 9, plate: '34ABC123', apartment_id: 7 }] };
    if (/INSERT INTO audit_log/.test(sql)) return { rows: [] };
    throw new Error('Unexpected policy query: '+sql.slice(0, 80));
  } };
}

describe('resident plate policy', () => {
  it('migration is additive false default, ensure skips existing schema', async () => {
    const migration = readFileSync(new URL('../migrations/133_plate_movement_policy.sql', import.meta.url), 'utf8').replace(/--[^\n]*/g, '').trim();
    assert.equal(migration, PLATE_MOVEMENT_POLICY_SQL+';');
    const calls = [];
    const db = { query: async sql => { calls.push(sql); return { rows: [{ parent_exists: true, column_exists: calls.length > 1 }] }; } };
    await ensurePlateMovementPolicySchema(db);
    assert.equal(calls[1], PLATE_MOVEMENT_POLICY_SQL);
    calls.length = 0;
    await ensurePlateMovementPolicySchema({ query: async sql => { calls.push(sql); return { rows: [{ parent_exists: true, column_exists: true }] }; } });
    assert.equal(calls.length, 1);
  });
  it('legacy settings patch preserves opt-in permission; values must be boolean', () => {
    assert.equal(DEFAULT_SITE_SETTINGS.resident_movement_notifications_enabled, false);
    const oldPatch = parseSettingsInput({ guest_rule: 'en_az_bir_bos' });
    assert.equal(mergeSettings({ resident_movement_notifications_enabled: true }, oldPatch).resident_movement_notifications_enabled, true);
    assert.deepEqual(parseSettingsInput({ resident_movement_notifications_enabled: false }), { resident_movement_notifications_enabled: false });
    for (const value of ['true', 1, null]) assert.throws(() => parseSettingsInput({ resident_movement_notifications_enabled: value }));
  });
  it('resident guest creation is rejected before SQL; old revoke stays scoped', async () => {
    const db = fakePolicyDb(); pool.query = db.query;
    await assert.rejects(residentCreate(actor, { site_code: 1, apartment_id: 999 }), e => e.statusCode === 403 && e.code === 'RESIDENT_GUEST_PERMIT_DISABLED');
    assert.equal(db.log.length, 0);
    await residentRevoke(actor, 1, 9);
    const write = db.log.find(x => /UPDATE plate_guest_permits/.test(x.sql));
    assert.deepEqual(write.params[3], [7]);
  });
  it('manager permission gates opt-in, while opt-out remains available', async () => {
    const closed = fakePolicyDb(); pool.query = closed.query;
    await assert.rejects(setMovementPref(actor, { site_code: 1, movement_enabled: true }), e => e.statusCode === 403 && e.code === 'MOVEMENT_NOTIFICATIONS_DISABLED');
    assert.equal(closed.log.some(x => /INSERT INTO plate_notify_prefs/.test(x.sql)), false);
    await setMovementPref(actor, { site_code: 1, movement_enabled: false });
    assert.equal(closed.log.find(x => /INSERT INTO plate_notify_prefs/.test(x.sql)).params[2], false);
    const open = fakePolicyDb({ allowed: true }); pool.query = open.query;
    await setMovementPref(actor, { site_code: 1, movement_enabled: true });
    assert.deepEqual(open.log.find(x => /INSERT INTO plate_notify_prefs/.test(x.sql)).params, [1, 20004, true]);
  });
  it('overview exposes site availability separately from saved personal preference', async () => {
    const db = fakePolicyDb({ allowed: false, optin: true }); pool.query = db.query;
    const data = await residentOverview(actor, 1);
    assert.equal(data.movement_notify_available, false);
    assert.equal(data.movement_notify, true);
  });
  it('site closure blocks even old opt-ins; open site still requires personal opt-in', async () => {
    const input = { siteCode: 1, vehicle: { person_id: 5 }, direction: 'giris', seenAt: new Date() };
    assert.deepEqual(await notifyResidentMovement(input, fakePolicyDb({ optin: true })), { skipped: 'site_disabled' });
    assert.deepEqual(await notifyResidentMovement(input, fakePolicyDb({ allowed: true })), { skipped: 'no_opt_in' });
  });
});
