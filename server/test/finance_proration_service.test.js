import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { pool } from '../src/db.js';
import { addDailyAidatShares, assertTenantAccountReady, reconcileApartmentAidat } from '../src/modules/finance_proration_service.js';
import { writeRun } from '../src/modules/finance_service.js';
import { dailyAidatShares } from '../src/modules/finance_proration.js';

const norm = (sql) => sql.replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const root = (extra = {}) => ({ id: '1', run_id: '10', definition_id: '2', definition_name: 'Aidat', kind: 'charge', amount_minor: '300000',
  root_period: '2026-11-01', original_due_date: '2026-11-01', payer_party: 'tenant', account_party: 'tenant', fund: 'operating',
  def_charge_party: 'occupant', def_kind: 'recurring', reversed: false, ...extra });

function fake(rows = [root()], intervals = [{ id: 20, apartment_id: 5, move_in: '2026-01-01', move_out: '2026-11-18' }]) {
  const calls = [];
  return { calls, async query(sql, params = []) {
    const q = norm(sql); calls.push({ sql: q, params });
    if (q.includes('FROM ledger_entries l INNER JOIN fee_runs fr')) return ok(rows);
    if (q.includes('FROM apartment_residencies r INNER JOIN site_people sp')) return ok(intervals);
    if (q.includes('FROM finance_period_closures')) return ok([{ period: '2026-11-01' }]);
    if (/^(INSERT INTO ledger_entries|SAVEPOINT|INSERT INTO audit_log|RELEASE SAVEPOINT)/.test(q)) return ok();
    throw new Error(`Beklenmeyen SQL: ${q}`);
  } };
}

describe('Günlük aidat kayıt adaptörü', () => {
  it('önizleme daire toplamını korur, ek paylar verir', async () => {
    const db = fake();
    const result = await addDailyAidatShares(db, 1000000001, { total: 300000n, lines: [{ apartmentId: 5, amount: 300000n }] }, '2026-11-01');
    assert.equal(result.total, 300000n);
    assert.equal(result.lines.length, 1);
    assert.equal(result.lines[0].accountParty, null);
    assert.deepEqual(result.lines[0].proration.shares.map((s) => s.amount_minor), ['120000', '180000']);
    assert.deepEqual(db.calls[0].params, [1000000001, [5], '2026-11-01']);
  });
  it('yazılmış aidat: bir ters kayıt ve iki yeni borç; kapalı ay açık döneme; ödeme yazmaz', async () => {
    const db = fake();
    assert.deepEqual(await reconcileApartmentAidat(db, { siteCode: 1000000001, apartmentId: 5, fromDate: '2026-11-18', now: new Date('2026-11-20T10:00:00Z') }), { adjusted: 1, skipped: 0 });
    const writes = db.calls.filter((c) => c.sql.startsWith('INSERT INTO ledger_entries'));
    assert.equal(writes.length, 3);
    assert.match(writes[0].sql, /'reversal'/);
    assert.equal(writes[0].params[2], '-300000');
    assert.equal(writes[0].params[3], '2026-12-01');
    assert.equal(writes[0].params[10], 'tenant');
    assert.deepEqual(writes.slice(1).map((c) => [c.params[2], c.params[10]]), [['120000', 'owner'], ['180000', 'tenant']]);
    assert.ok(writes.every((c) => !c.sql.includes("'payment'")));
  });
  it('aynı payla tekrar çalıştırma yeni satır üretmez', async () => {
    const db = fake([root({ id: 1, amount_minor: '120000', account_party: 'owner' }), root({ id: 2, amount_minor: '180000' })]);
    assert.deepEqual(await reconcileApartmentAidat(db, { siteCode: 1, apartmentId: 5, fromDate: '2026-11-18' }), { adjusted: 0, skipped: 0 });
    assert.equal(db.calls.filter((c) => c.sql.startsWith('INSERT')).length, 0);
  });
  it('elle terslenmiş/devredilmiş borç dirilmez; Fon da hesaplanmaz', async () => {
    const db = fake([root({ reversed: true }), root({ id: 2, fund: 'capital', amount_minor: '500000' })]);
    assert.deepEqual(await reconcileApartmentAidat(db, { siteCode: 1, apartmentId: 5, fromDate: '2026-11-18' }), { adjusted: 0, skipped: 1 });
    assert.equal(db.calls.filter((c) => c.sql.startsWith('INSERT INTO ledger_entries')).length, 0);
  });
  it('yeni kişi eski pozitif borcu veya negatif avansı devralamaz; sıfır bakiye serbest', async () => {
    for (const balance of ['1200', '-1200', '0']) {
      const db = { query: async (sql, params) => { assert.match(sql, /old\.person_id/); assert.deepEqual(params, [1, 5, 99]); return ok([{ balance_minor: balance }]); } };
      const promise = assertTenantAccountReady(db, { siteCode: 1, apartmentId: 5, personId: 99 });
      if (balance === '0') await promise;
      else await assert.rejects(promise, { code: 'TENANT_ACCOUNT_UNSETTLED' });
    }
  });
  it('kısmi devirden sonra 19 girişinde sessiz0aidat yok; yalnız gerçekten değişen paylaşım engellenir', async () => {
    const snapshot = dailyAidatShares({ period: '2026-11-01', amountMinor: 300000n, residencies: [{ id: 20, moveIn: '2026-01-01', moveOut: '2026-11-18' }] });
    const rows = [root({ id: 1, amount_minor: '180000', reversed: true, proration: snapshot }), root({ id: 2, amount_minor: '120000', account_party: 'owner', proration: snapshot })];
    const args = { siteCode: 1, apartmentId: 5, fromDate: '2026-11-19', requireComplete: true };
    const changed = fake(rows, [{ id: 20, apartment_id: 5, move_in: '2026-01-01', move_out: '2026-11-18' }, { id: 21, apartment_id: 5, move_in: '2026-11-19', move_out: null }]);
    await assert.rejects(reconcileApartmentAidat(changed, args), { code: 'PRORATION_REVIEW_REQUIRED', statusCode: 409 });
    assert.equal(changed.calls.some((c) => c.sql.startsWith('INSERT INTO ledger_entries')), false);
    const unchanged = fake(rows);
    assert.deepEqual(await reconcileApartmentAidat(unchanged, args), { adjusted: 0, skipped: 1 });
    const fullyCancelled = fake(rows.map((r) => ({ ...r, reversed: true })));
    assert.deepEqual(await reconcileApartmentAidat(fullyCancelled, args), { adjusted: 0, skipped: 1 });
  });
});

// YALNIZ ayrı test DB'si. Varsayılan çalıştırmada ağ bağlantısı kurulmaz. Sentetik fixture tamamen ROLLBACK edilir.
it('GERÇEK PG: ödenmiş ay, malik ödemesi, kapalı dönem, değişmezlik, tekrar ve yeni kiracı sınırı', { skip: process.env.FINANCE_PG_TEST !== '1' }, async () => {
  assert.match(process.env.DB_NAME ?? '', /^kapi_(test|rehearsal)_/, 'Canlı DB üzerinde bu test çalıştırılamaz');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const site = (await client.query('INSERT INTO sites (name) VALUES ($1) RETURNING site_code', [`Kıst aidat sentetik ${randomUUID()}`])).rows[0].site_code;
    const block = (await client.query("INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'Test', 1) RETURNING id", [site])).rows[0].id;
    const apt = (await client.query("INSERT INTO apartments (site_code, block_id, unit_label, sort_order, responsible_party) VALUES ($1, $2, '1', 1, 'tenant') RETURNING id", [site, block])).rows[0].id;
    const person = (await client.query("INSERT INTO site_people (site_code, full_name) VALUES ($1, 'Sentetik Kiracı') RETURNING id", [site])).rows[0].id;
    const residency = (await client.query("INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, move_in_date) VALUES ($1, $2, $3, 'tenant', '2026-01-01') RETURNING id", [site, apt, person])).rows[0].id;
    const def = (await client.query("INSERT INTO fee_definitions (site_code, name, kind, distribution, amount_minor, due_day, start_period, target_type, charge_party) VALUES ($1, 'Test Aidat', 'recurring', 'fixed', 300000, 1, '2026-11-01', 'site', 'occupant') RETURNING id", [site])).rows[0].id;
    const run = (await client.query("INSERT INTO fee_runs (site_code, definition_id, period, total_minor, apartment_count) VALUES ($1, $2, '2026-11-01', 300000, 1) RETURNING id", [site, def])).rows[0].id;
    const charge = (await client.query("INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_id, run_id, payer_party, account_party, fund) VALUES ($1, $2, 'charge', 300000, '2026-11-01', '2026-11-01', '2026-11-01', $3, $4, 'tenant', 'tenant', 'operating') RETURNING id", [site, apt, def, run])).rows[0].id;
    // Her iki hesabın ödemesi aynen kalmalıdır. Aidat yeni paylaşılınca kiracı fazla ödemesi alacak, malik borcu ödemesiyle kapanır.
    for (const [party, amount] of [['tenant', -300000], ['owner', -120000]]) await client.query("INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, method, payer_party, account_party, fund) VALUES ($1, $2, 'payment', $3, '2026-11-01', '2026-11-02', 'transfer', $4, $4, 'operating')", [site, apt, amount, party]);
    await client.query("UPDATE apartment_residencies SET is_current = FALSE, move_out_date = '2026-11-18' WHERE id = $1", [residency]);
    await client.query("INSERT INTO finance_period_closures (site_code, period) VALUES ($1, '2026-11-01')", [site]);
    const args = { siteCode: Number(site), apartmentId: Number(apt), fromDate: '2026-11-18', now: new Date('2026-11-20T10:00:00Z') };
    assert.deepEqual(await reconcileApartmentAidat(client, args), { adjusted: 1, skipped: 0 });
    assert.deepEqual(await reconcileApartmentAidat(client, args), { adjusted: 0, skipped: 0 });
    const totals = await client.query("SELECT account_party, SUM(amount_minor)::TEXT AS balance FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2 GROUP BY account_party ORDER BY account_party", [site, apt]);
    assert.deepEqual(totals.rows, [{ account_party: 'owner', balance: '0' }, { account_party: 'tenant', balance: '-120000' }]);
    const payments = await client.query("SELECT amount_minor::TEXT AS amount FROM ledger_entries WHERE site_code = $1 AND kind = 'payment' ORDER BY id", [site]);
    assert.deepEqual(payments.rows, [{ amount: '-300000' }, { amount: '-120000' }]);
    const original = (await client.query('SELECT amount_minor::TEXT AS amount, proration FROM ledger_entries WHERE id = $1', [charge])).rows[0];
    assert.deepEqual(original, { amount: '300000', proration: null });
    const corrections = await client.query("SELECT kind, amount_minor::TEXT AS amount, to_char(period, 'YYYY-MM-DD') AS period, account_party, fund FROM ledger_entries WHERE site_code = $1 AND id > $2 AND kind <> 'payment' ORDER BY id", [site, charge]);
    assert.deepEqual(corrections.rows, [
      { kind: 'reversal', amount: '-300000', period: '2026-12-01', account_party: 'tenant', fund: 'operating' },
      { kind: 'charge', amount: '120000', period: '2026-12-01', account_party: 'owner', fund: 'operating' },
      { kind: 'charge', amount: '180000', period: '2026-12-01', account_party: 'tenant', fund: 'operating' },
    ]);
    // DB'nin eklemelilik tetikleyicisi de yürürlüktedir.
    await client.query('SAVEPOINT immutable_check');
    await assert.rejects(client.query('UPDATE ledger_entries SET amount_minor = 1 WHERE id = $1', [charge]));
    await client.query('ROLLBACK TO SAVEPOINT immutable_check');
    await assert.rejects(assertTenantAccountReady(client, { siteCode: Number(site), apartmentId: Number(apt), personId: Number(person) + 1 }), { code: 'TENANT_ACCOUNT_UNSETTLED' });
    // Aynı kiracının dönüşü yanlışlıkla yeni kişi gibi engellenmez.
    await assertTenantAccountReady(client, { siteCode: Number(site), apartmentId: Number(apt), personId: Number(person) });
    // Legacy: kapanmış kiracı kaydı bulunamasa bile dolu hesap yeni kişiye bağlanamaz.
    const legacyApt = (await client.query("INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, '2', 2) RETURNING id", [site, block])).rows[0].id;
    await client.query("INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, account_party, fund) VALUES ($1, $2, 'charge', 999, '2026-11-01', '2026-11-01', 'tenant', 'tenant', 'operating')", [site, legacyApt]);
    await assert.rejects(assertTenantAccountReady(client, { siteCode: Number(site), apartmentId: Number(legacyApt), personId: Number(person) + 1 }), { code: 'TENANT_ACCOUNT_UNSETTLED' });
    // Üretimdeki asıl toplu INSERT yazıcısı: tek daireli plan iki hesaba yazılır; run toplam/sayısı değişmez.
    const nextPeriod = '2026-12-01';
    const dailyPlan = await addDailyAidatShares(client, Number(site), { total: 300000n, lines: [{ apartmentId: Number(legacyApt), amount: 300000n, payerParty: 'tenant' }], missing: [] }, '2026-11-01');
    // B dairesinin takvimi için sentetik, bilinen iki pay; toplam ve gerçek INSERT kontrol edilir.
    const detail = { version: 1, period: nextPeriod, total_days: 31, monthly_amount_minor: '300000', schedule_hash: 'a'.repeat(64),
      shares: [{ account_party: 'owner', days: 13, amount_minor: '125806' }, { account_party: 'tenant', days: 18, amount_minor: '174194' }] };
    dailyPlan.lines[0].proration = detail;
    const writtenRun = await writeRun(client, { siteCode: Number(site), definitionId: Number(def), definitionName: 'Test Aidat',
      plan: dailyPlan, timing: { period: nextPeriod, entryDate: nextPeriod, dueDate: nextPeriod },
      idempotencyKey: null, requestFingerprint: null, naturalKey: null, actorUserCode: null, fund: 'operating',
      decision: { decisionId: null, decisionReason: null, label: null } });
    assert.equal(writtenRun.total_minor, 300000);
    assert.equal(writtenRun.apartment_count, 1);
    const writtenShares = await client.query('SELECT account_party, amount_minor::TEXT AS amount, proration->>\'generation\' AS generation FROM ledger_entries WHERE run_id = $1 ORDER BY account_party', [writtenRun.id]);
    assert.deepEqual(writtenShares.rows, [{ account_party: 'owner', amount: '125806', generation: '0' }, { account_party: 'tenant', amount: '174194', generation: '0' }]);
    // Ödenmeyen eski kiracı payının malike devri: bu kök kısmen tüketilmiştir.
    const oldPayment = (await client.query("SELECT id FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2 AND kind = 'payment' AND account_party = 'tenant'", [site, apt])).rows[0].id;
    await client.query("INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, account_party, fund, reverses_entry_id, reversal_reason) VALUES ($1, $2, 'reversal', 300000, '2026-12-01', '2026-11-20', 'tenant', 'tenant', 'operating', $3, 'Sentetik ödeme düzeltmesi')", [site, apt, oldPayment]);
    const oldTenantCharge = (await client.query("SELECT id FROM ledger_entries l WHERE site_code = $1 AND apartment_id = $2 AND run_id = $3 AND kind = 'charge' AND account_party = 'tenant' AND NOT EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id)", [site, apt, run])).rows[0].id;
    await client.query("INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, account_party, fund, run_id, reverses_entry_id, reversal_reason, source_kind, source_id) VALUES ($1, $2, 'reversal', -180000, '2026-12-01', '2026-11-20', 'tenant', 'tenant', 'operating', $3, $4, 'Sentetik malike devir', 'liability_transfer', 999999)", [site, apt, run, oldTenantCharge]);
    await client.query("INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, account_party, fund, source_kind, source_id) VALUES ($1, $2, 'charge', 180000, '2026-12-01', '2026-11-20', '2026-11-01', 'tenant', 'owner', 'operating', 'liability_transfer', 999999)", [site, apt]);
    await assertTenantAccountReady(client, { siteCode: Number(site), apartmentId: Number(apt), personId: Number(person) + 1 });
    const beforeNewTenant = (await client.query('SELECT COUNT(*)::INTEGER AS count FROM ledger_entries WHERE site_code = $1', [site])).rows[0].count;
    await client.query('SAVEPOINT tenant_entry_atomic');
    const incoming = (await client.query("INSERT INTO site_people (site_code, full_name) VALUES ($1, 'Sentetik Yeni Kiracı') RETURNING id", [site])).rows[0].id;
    await client.query("INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, move_in_date) VALUES ($1, $2, $3, 'tenant', '2026-11-19')", [site, apt, incoming]);
    await assert.rejects(reconcileApartmentAidat(client, { ...args, requireComplete: true }), { code: 'PRORATION_REVIEW_REQUIRED' });
    await client.query('ROLLBACK TO SAVEPOINT tenant_entry_atomic');
    const rolledBack = await client.query('SELECT 1 FROM apartment_residencies WHERE person_id = $1', [incoming]);
    assert.equal(rolledBack.rowCount, 0, 'reddedilen giriş ve mali kayıt aynı transaction ile geri alınır');
    assert.equal((await client.query('SELECT COUNT(*)::INTEGER AS count FROM ledger_entries WHERE site_code = $1', [site])).rows[0].count, beforeNewTenant);
  } finally {
    await client.query('ROLLBACK');
    client.release();
    await pool.end();
  }
});
