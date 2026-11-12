import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { EQUIPMENT_BLOCK_STEPS } from '../src/modules/equipment_block_schema.js';
import { createEquipment, getEquipmentMeta, updateEquipment } from '../src/modules/equipment_service.js';

test('PostgreSQL: explicit equipment scope is additive, cross-site safe, editable and deletion-compatible', { skip: process.env.EQUIPMENT_BLOCK_PG_TEST !== '1' }, async () => {
  assert.match(process.env.DB_NAME ?? '', /^kapi_(test|rehearsal)_/, 'A dedicated disposable database is required');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`
      CREATE TEMP TABLE site_blocks (id BIGINT PRIMARY KEY, site_code BIGINT NOT NULL, block_name TEXT, sort_order INTEGER DEFAULT 0);
      CREATE TEMP TABLE equipment_items (
        id BIGSERIAL PRIMARY KEY, site_code BIGINT NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL, location TEXT,
        vendor_id BIGINT, serial_no TEXT, installed_on DATE, note TEXT, is_active BOOLEAN DEFAULT TRUE,
        created_by INTEGER, created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
      );
      CREATE TEMP TABLE audit_log (actor_user_code INTEGER, actor_name TEXT, actor_role TEXT, action TEXT, site_code BIGINT, target_type TEXT, target_id TEXT, details JSONB);
      INSERT INTO site_blocks(id,site_code,block_name) VALUES (40,100,'A Blok'),(42,100,'C Blok'),(41,200,'Other site');
      INSERT INTO equipment_items(site_code,kind,name,location) VALUES (100,'asansor','Legacy elevator','A Blok merdiven boşluğu');
    `);
    for (let pass = 0; pass < 2; pass++) for (const step of EQUIPMENT_BLOCK_STEPS) await client.query(step.sql);
    const legacy = (await client.query('SELECT block_id FROM equipment_items WHERE id=1')).rows[0];
    assert.equal(legacy.block_id, null, 'free text is never guessed into a physical block');
    const meta = await getEquipmentMeta(100, client);
    assert.deepEqual(meta.blocks.map((row) => row.id).sort(), [40,42]);
    const input = { siteCode: 100, actor: { user_code: 1, role: 'site_manager', full_name: 'Synthetic manager' }, access: { userCode: 1 } };
    await assert.rejects(createEquipment({ ...input, body: { kind: 'asansor', name: 'Foreign', block_id: 41 } }, client), { code: 'INVALID_FIELD' });
    assert.equal((await client.query('SELECT COUNT(*)::INTEGER AS n FROM equipment_items')).rows[0].n, 1);
    const created = (await createEquipment({ ...input, body: { kind: 'asansor', name: 'A elevator', block_id: 40 } }, client)).equipment;
    assert.equal(created.block_id, 40); assert.equal(created.block_name, 'A Blok');
    await assert.rejects(updateEquipment({ ...input, rawId: created.id, body: { block_id: 41 } }, client), { code: 'INVALID_FIELD' });
    assert.equal((await client.query('SELECT block_id FROM equipment_items WHERE id=$1', [created.id])).rows[0].block_id, '40');
    const renamed = (await updateEquipment({ ...input, rawId: created.id, body: { name: 'Renamed' } }, client)).equipment;
    assert.equal(renamed.block_id, 40, 'an old client update that omits block_id preserves scope');
    const common = (await updateEquipment({ ...input, rawId: created.id, body: { block_id: null } }, client)).equipment;
    assert.equal(common.block_id, null);
    await updateEquipment({ ...input, rawId: created.id, body: { block_id: 40 } }, client);
    await client.query('DELETE FROM site_blocks WHERE id=40');
    assert.equal((await client.query('SELECT block_id FROM equipment_items WHERE id=$1', [created.id])).rows[0].block_id, null, 'block removal keeps existing equipment and site deletion compatible');
    assert.equal((await client.query('SELECT COUNT(*)::INTEGER AS n FROM equipment_items')).rows[0].n, 2);
  } finally {
    await client.query('ROLLBACK');
    client.release(true);
    await pool.end();
  }
});
