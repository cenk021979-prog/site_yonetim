// 127: eklemeli defterde günlük aidat paylaşımının değişmez anlık görüntüsü. Eski satırlara geri doldurma yok.
export const FINANCE_PRORATION_SQL = `ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS proration JSONB;`;

export async function ensureFinanceProrationSchema(client) {
  const found = await client.query(`SELECT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.ledger_entries') AND attname = 'proration' AND NOT attisdropped) AS present`);
  if (found.rows?.[0]?.present === true) return [];
  await client.query(FINANCE_PRORATION_SQL);
  return ['ledger_entries:proration'];
}
