import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pushCapabilities } from '../src/modules/push_capabilities.js';
import { registerPushDevice } from '../src/modules/push_devices.js';

const input = { install_id: 'notification-device-123456', platform: 'android', token: 'synthetic-fcm-registration-token-123456' };
function database(eligible) {
  const queries = [];
  const query = async (sql, params = []) => {
    queries.push({ sql, params });
    if (sql.includes(' AS eligible')) return { rows: [{ eligible }] };
    if (sql.includes('FROM users')) return { rows: [{ user_code: 7 }] };
    if (sql.includes('INSERT INTO push_devices')) return { rows: [{ id: 8 }] };
    return { rows: [], rowCount: 0 };
  };
  return { queries, query, connect: async () => ({ query, release() {} }) };
}

test('individual device registration needs actual alarm eligibility; malformed truthy values fail closed', async () => {
  for (const eligible of [false, null, 'true']) {
    const db = database(eligible);
    const actor = { user_code: 7, role: 'individual' };
    const capabilities = await pushCapabilities(actor, db);
    assert.equal(capabilities.can_register, false);
    await assert.rejects(registerPushDevice(actor, input, db), (error) => error.code === 'PUSH_REGISTRATION_FORBIDDEN');
    assert.equal(db.queries.some(({ sql }) => sql.includes('INSERT INTO push_devices')), false);
    assert.ok(db.queries.filter(({ sql }) => sql.includes(' AS eligible')).every(({ params }) => params[0] === 7));
  }
});

test('an eligible individual registers only their device without granting a site or announcement role', async () => {
  const db = database(true);
  const actor = { user_code: 7, role: 'individual' };
  assert.equal((await pushCapabilities(actor, db)).emergency_only, true);
  assert.equal((await registerPushDevice(actor, input, db)).device_id, 8);
  assert.equal(db.queries.some(({ sql }) => /INSERT INTO (site_memberships|apartment_memberships)/.test(sql)), false);
  assert.equal(actor.role, 'individual');
});

test('legacy recipient roles remain compatible; super, unknown and trial cannot register', async () => {
  for (const role of ['site_manager', 'apartment_owner']) assert.equal((await pushCapabilities({ role }, database(false))).can_register, true);
  for (const actor of [{ role: 'super_user' }, { role: 'unknown' }, { role: 'individual', trial: { siteCode: 100 } }, { role: 'apartment_owner', trial: { siteCode: 100 } }]) {
    const db = database(true);
    assert.equal((await pushCapabilities(actor, db)).can_register, false);
    assert.equal(db.queries.length, 0);
  }
});
