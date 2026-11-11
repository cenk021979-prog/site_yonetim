// 132: explicit equipment block scope. NULL retains the existing site-wide scope.
// Free-form location text is never converted into a physical block assignment.
export const EQUIPMENT_BLOCK_STEPS = Object.freeze([
  { name: 'block_id', sql: 'ALTER TABLE equipment_items ADD COLUMN IF NOT EXISTS block_id BIGINT;' },
  { name: 'equipment_items_block_id_fkey', sql: `DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'equipment_items_block_id_fkey' AND conrelid = 'equipment_items'::regclass) THEN
    ALTER TABLE equipment_items ADD CONSTRAINT equipment_items_block_id_fkey FOREIGN KEY (block_id) REFERENCES site_blocks(id) ON DELETE SET NULL;
  END IF;
END $$;` },
  { name: 'idx_equipment_items_block', sql: 'CREATE INDEX IF NOT EXISTS idx_equipment_items_block ON equipment_items (site_code, block_id) WHERE is_active = TRUE;' },
]);

export const equipmentBlockMigrationSql = () => `${EQUIPMENT_BLOCK_STEPS.map((s) => s.sql).join('\n\n')}\n`;

export async function ensureEquipmentBlockSchema(client) {
  const found = await client.query(`SELECT
    EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.equipment_items') AND attname = 'block_id' AND NOT attisdropped) AS column_ready,
    EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'equipment_items_block_id_fkey' AND conrelid = to_regclass('public.equipment_items')) AS fk_ready,
    to_regclass('public.idx_equipment_items_block') IS NOT NULL AS index_ready`);
  const row = found.rows?.[0] ?? {};
  const present = [row.column_ready, row.fk_ready, row.index_ready];
  if (present.every((value) => value === true)) return;
  await client.query("SET lock_timeout = '3s'");
  try {
    for (const [i, step] of EQUIPMENT_BLOCK_STEPS.entries()) if (present[i] !== true) await client.query(step.sql);
  } finally { await client.query('RESET lock_timeout'); }
}
