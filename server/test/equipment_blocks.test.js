import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { assertEquipmentBlock } from '../src/modules/equipment_blocks.js';
import { EQUIPMENT_BLOCK_STEPS, ensureEquipmentBlockSchema, equipmentBlockMigrationSql } from '../src/modules/equipment_block_schema.js';
import { createEquipment, getEquipmentMeta, updateEquipment } from '../src/modules/equipment_service.js';
import { elevatorScopeSql } from '../src/modules/emergency_elevator_scope.js';
import { findUnsafeStatements } from '../scripts/migrate.js';

test('132 adds explicit block scope only; migration and bootstrap are identical and idempotent', async () => {
  const migration = readFileSync(new URL('../migrations/132_equipment_blocks.sql', import.meta.url), 'utf8');
  assert.ok(migration.endsWith(equipmentBlockMigrationSql()));
  assert.deepEqual(findUnsafeStatements(migration), []);
  assert.doesNotMatch(migration, /\b(DROP|TRUNCATE|UPDATE|INSERT INTO|DELETE FROM)\b/i);
  const sent = [];
  await ensureEquipmentBlockSchema({ query: async (sql) => { sent.push(sql); return { rows: [{ column_ready: true, fk_ready: true, index_ready: true }] }; } });
  assert.equal(sent.length, 1, 'normal startup never reacquires equipment DDL locks');
  const missing = [];
  await ensureEquipmentBlockSchema({ query: async (sql) => { missing.push(sql); return { rows: [{ column_ready: false, fk_ready: false, index_ready: false }] }; } });
  assert.deepEqual(missing.slice(2, -1), EQUIPMENT_BLOCK_STEPS.map((step) => step.sql));
  assert.equal(missing.at(-1), 'RESET lock_timeout');
});

test('block metadata keeps the old defaults and returns only the selected site blocks', async () => {
  const result = await getEquipmentMeta(100, { query: async (sql, params) => {
    assert.match(sql, /FROM site_blocks WHERE site_code = \$1/);
    assert.deepEqual(params, [100]);
    return { rows: [{ id: '40', block_name: 'A Blok' }] };
  } });
  assert.equal(result.kinds[0].code, 'asansor');
  assert.deepEqual(result.blocks, [{ id: 40, name: 'A Blok' }]);
});

test('a foreign/missing block is rejected before any equipment write; NULL is site-wide', async () => {
  const calls = [];
  const noBlock = { query: async (sql, params) => { calls.push({ sql, params }); return { rows: [] }; } };
  await assertEquipmentBlock(noBlock, 100, null);
  assert.equal(calls.length, 0);
  await assert.rejects(createEquipment({ siteCode: 100, access: {}, body: { name: 'Lift', kind: 'asansor', block_id: 41 } }, noBlock), { code: 'INVALID_FIELD', statusCode: 400 });
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].params, [41, 100]);
  assert.ok(calls.every((call) => !/INSERT|UPDATE/.test(call.sql)));
  for (const blockId of [-1, 0, 'x', 1.5, true, {}]) {
    await assert.rejects(createEquipment({ siteCode: 100, access: {}, body: { name: 'Lift', kind: 'asansor', block_id: blockId } }, noBlock), { code: 'INVALID_FIELD' });
  }
});

test('block update validates before writing; omitted scope stays unchanged and explicit NULL clears it', async () => {
  const calls = [];
  const row = { id: 30, kind: 'asansor', name: 'Lift', location: null, block_id: 40, block_name: 'A Blok', vendor_id: null };
  const db = { query: async (sql, params = []) => {
    calls.push({ sql, params });
    if (sql.includes('FROM equipment_items i')) return { rows: [{ ...row }] };
    if (sql.startsWith('SELECT id FROM site_blocks')) return { rows: [] };
    if (sql.startsWith('UPDATE equipment_items')) { if (sql.includes('block_id =')) { row.block_id = params[2]; row.block_name = null; } return { rows: [] }; }
    if (sql.includes('INSERT INTO audit_log')) return { rows: [] };
    throw new Error('Unexpected test query');
  } };
  await assert.rejects(updateEquipment({ siteCode: 100, rawId: 30, body: { block_id: 41 } }, db), { code: 'INVALID_FIELD' });
  assert.equal(calls.filter((call) => call.sql.startsWith('UPDATE')).length, 0);
  await updateEquipment({ siteCode: 100, rawId: 30, body: { name: 'Renamed' } }, db);
  assert.equal(row.block_id, 40);
  assert.ok(!calls.find((call) => call.sql.startsWith('UPDATE')).sql.includes('block_id ='));
  const result = await updateEquipment({ siteCode: 100, rawId: 30, body: { block_id: null } }, db);
  assert.equal(result.equipment.block_id, null);
  assert.equal(result.equipment.block_name, null);
});

test('elevator discovery/dispatch scope requires an actual apartment in the explicit block', () => {
  const sql = elevatorScopeSql('eq', '$1', '$2');
  assert.match(sql, /eq\.block_id IS NULL/);
  assert.match(sql, /eblock\.site_code = \$1/);
  assert.match(sql, /rap\.block_id = eq\.block_id/);
  assert.match(sql, /apartment_memberships/);
  assert.match(sql, /apartment_residencies/);
  assert.doesNotMatch(sql, /door_access|site_memberships/);
});
