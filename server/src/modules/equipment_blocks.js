import { PlatformError } from './errors.js';

export async function listEquipmentBlocks(db, siteCode) {
  const found = await db.query('SELECT id, block_name FROM site_blocks WHERE site_code = $1 ORDER BY sort_order, block_name, id', [siteCode]);
  return found.rows.map((row) => ({ id: Number(row.id), name: row.block_name }));
}

export async function assertEquipmentBlock(db, siteCode, blockId) {
  if (blockId == null) return;
  const found = await db.query('SELECT id FROM site_blocks WHERE id = $1 AND site_code = $2', [blockId, siteCode]);
  if (!found.rows?.length) throw new PlatformError(400, 'INVALID_FIELD', 'Blok bu sitede bulunamadı.', { field: 'block_id' });
}
