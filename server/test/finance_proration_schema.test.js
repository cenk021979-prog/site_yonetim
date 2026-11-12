import { it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FINANCE_PRORATION_SQL, ensureFinanceProrationSchema } from '../src/modules/finance_proration_schema.js';

it('127 migration ve açılış aynı eklemeli şemadır, eski borca geri doldurma yapmaz', () => {
  const migration = readFileSync(new URL('../migrations/127_finance_daily_proration.sql', import.meta.url), 'utf8');
  assert.ok(migration.includes(FINANCE_PRORATION_SQL));
  assert.doesNotMatch(migration, /UPDATE|DELETE|TRUNCATE/);
});
it('kolon zaten varsa yalnız katalog okuması yapılır; yoksa idempotent ADD COLUMN', async () => {
  for (const present of [true, false]) {
    const calls = [];
    const client = { async query(sql) { calls.push(sql); return { rows: [{ present }] }; } };
    assert.deepEqual(await ensureFinanceProrationSchema(client), present ? [] : ['ledger_entries:proration']);
    assert.equal(calls.length, present ? 1 : 2);
    if (!present) assert.equal(calls[1], FINANCE_PRORATION_SQL);
  }
});
