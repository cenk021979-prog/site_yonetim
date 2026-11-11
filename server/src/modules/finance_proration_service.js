// Günlük aidat DB adaptörü. Çağıran işlem people_sync -> finance_post -> apartment kilit sırasını alır.
// Ödeme/kasa hareketi yazılmaz. Değişiklik yalnız özgün borcu tersleyip yeni borç payları ekler.
import { actorFromAuthUser } from './audit_service.js';
import { PlatformError } from './errors.js';
import { resolveOpenPeriod } from './finance_4b_guard.js';
import { periodOfDate, today } from './finance_common.js';
import { toBigInt } from './finance_money.js';
import { effectiveFund } from './finance_funds.js';
import { dailyAidatShares, prorationDescription } from './finance_proration.js';
import { recordFinanceAudit } from './finance_tx.js';

export async function loadTenantIntervals(db, siteCode, apartmentIds, period = null) {
  if (!apartmentIds.length) return new Map();
  const found = await db.query(`
    SELECT r.id, r.apartment_id,
      to_char(COALESCE(r.move_in_date, (r.created_at AT TIME ZONE 'Europe/Istanbul')::DATE), 'YYYY-MM-DD') AS move_in,
      CASE WHEN r.is_current THEN NULL ELSE to_char(r.move_out_date, 'YYYY-MM-DD') END AS move_out
    FROM apartment_residencies r INNER JOIN site_people sp ON sp.id = r.person_id
    WHERE r.site_code = $1 AND r.apartment_id = ANY($2::BIGINT[]) AND r.relation = 'tenant'
      AND ((r.is_current = TRUE AND sp.is_active = TRUE) OR (r.is_current = FALSE AND r.move_out_date IS NOT NULL))
      AND ($3::DATE IS NULL OR (
        COALESCE(r.move_in_date, (r.created_at AT TIME ZONE 'Europe/Istanbul')::DATE) < ($3::DATE + INTERVAL '1 month')
        AND (r.is_current OR r.move_out_date >= $3::DATE)))
    ORDER BY r.apartment_id, r.id`, [siteCode, apartmentIds, period]);
  const result = new Map();
  for (const row of found.rows ?? []) {
    const id = Number(row.apartment_id);
    if (!result.has(id)) result.set(id, []);
    result.get(id).push({ id: Number(row.id), moveIn: row.move_in, moveOut: row.move_out ?? null });
  }
  return result;
}

export async function addDailyAidatShares(db, siteCode, plan, period) {
  const intervals = await loadTenantIntervals(db, siteCode, plan.lines.map((line) => line.apartmentId), period);
  return { ...plan, lines: plan.lines.map((line) => {
    const proration = dailyAidatShares({ period, amountMinor: line.amount, residencies: intervals.get(line.apartmentId) ?? [] });
    return { ...line, accountParty: proration.shares.length === 1 ? proration.shares[0].account_party : null, proration };
  }) };
}

/** Yeni KİŞİ önceki kiracının ortak hesap bakiyesini devralamaz. Aynı kişinin düzeltmesi/yeniden girişi engellenmez. */
export async function assertTenantAccountReady(client, { siteCode, apartmentId, personId }) {
  const found = await client.query(`
    SELECT COALESCE(SUM(l.amount_minor), 0)::TEXT AS balance_minor
    FROM ledger_entries l
    WHERE l.site_code = $1 AND l.apartment_id = $2
      AND COALESCE(l.account_party, CASE WHEN l.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END) = 'tenant'
      AND (SELECT old.person_id FROM apartment_residencies old
        WHERE old.site_code = $1 AND old.apartment_id = $2 AND old.relation = 'tenant' AND old.is_current = FALSE
        ORDER BY COALESCE(old.move_out_date, old.created_at::DATE) DESC, old.id DESC LIMIT 1) IS DISTINCT FROM $3::BIGINT`, [siteCode, apartmentId, personId]);
  const balance = toBigInt(found.rows?.[0]?.balance_minor ?? '0');
  if (balance !== 0n) {
    throw new PlatformError(409, 'TENANT_ACCOUNT_UNSETTLED', balance > 0n
      ? 'Önceki kiracının borcu bu hesapta duruyor. Yeni kiracıyı eklemeden önce Finans ekranında borcu tahsil edin veya malike devir işlemini tamamlayın.'
      : 'Önceki kiracının bu hesapta alacağı var. Yeni kiracıyı eklemeden önce Finans ekranında alacak iadesini tamamlayın.');
  }
}

const accountOf = (row) => row.account_party ?? (row.payer_party === 'tenant' ? 'tenant' : 'owner');
const jsonOf = (value) => typeof value === 'string' ? JSON.parse(value) : value;
const sameShares = (left, right) => ['owner', 'tenant'].every((party) => {
  const amount = (details) => (details?.shares ?? []).filter((s) => s.account_party === party).reduce((sum, s) => sum + toBigInt(s.amount_minor), 0n);
  return amount(left) === amount(right);
});

/** Etkilenen ay ve ileri borçlandırılmış aylar; geçmişin tamamına otomatik geri doldurma YOK. */
export async function reconcileApartmentAidat(client, { siteCode, apartmentId, fromDate, actor = null, now = new Date(), requireComplete = false }) {
  const found = await client.query(`
    SELECT l.*, l.amount_minor::TEXT AS amount_minor,
      to_char(fr.period, 'YYYY-MM-DD') AS root_period, to_char(l.due_date, 'YYYY-MM-DD') AS original_due_date,
      fd.charge_party AS def_charge_party, fd.kind AS def_kind,
      EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id) AS reversed
    FROM ledger_entries l INNER JOIN fee_runs fr ON fr.id = l.run_id
    INNER JOIN fee_definitions fd ON fd.id = fr.definition_id
    WHERE l.site_code = $1 AND l.apartment_id = $2 AND l.kind = 'charge' AND fd.kind = 'recurring'
      AND fr.period >= $3::DATE
      AND (l.fund = 'operating' OR (l.fund IS NULL AND COALESCE(fd.charge_party, 'occupant') = 'occupant'))
    ORDER BY l.run_id, l.id`, [siteCode, apartmentId, periodOfDate(fromDate ?? today(now))]);
  const groups = new Map();
  for (const row of found.rows ?? []) {
    if (effectiveFund(row) !== 'operating') continue;
    if (!groups.has(String(row.run_id))) groups.set(String(row.run_id), []);
    groups.get(String(row.run_id)).push({ ...row, proration: jsonOf(row.proration) });
  }
  if (!groups.size) return { adjusted: 0, skipped: 0 };
  const intervals = await loadTenantIntervals(client, siteCode, [apartmentId]);
  const actorCode = actorFromAuthUser(actor).userCode;
  let openPeriod;
  let adjusted = 0;
  let skipped = 0;
  for (const rows of groups.values()) {
    const live = rows.filter((row) => !row.reversed);
    const metadata = rows.reduce((latest, row) => row.proration && (!latest || (row.proration.generation ?? 0) > (latest.generation ?? 0)) ? row.proration : latest, null);
    const total = metadata ? toBigInt(metadata.monthly_amount_minor) : rows.reduce((sum, row) => sum + toBigInt(row.amount_minor), 0n);
    const root = rows[0];
    const details = dailyAidatShares({ period: root.root_period, amountMinor: total, residencies: intervals.get(apartmentId) ?? [] });
    // Tam iptal dirilmez. Kısmi devir/iptalde yalnız yeni girişin gerçekten değiştireceği paylar varsa açık inceleme gerekir.
    if (!live.length || live.reduce((sum, row) => sum + toBigInt(row.amount_minor), 0n) !== total) {
      if (live.length && requireComplete && (!metadata || !sameShares(metadata, details))) {
        throw new PlatformError(409, 'PRORATION_REVIEW_REQUIRED', `${root.root_period.slice(0, 7)} ayının aidatı daha önce kısmen iptal edilmiş veya malike devredilmiş. Yeni kiracı/giriş tarihi paylaşımı otomatik tamamlanamaz. Finans ekranında ilgili borç devri ve düzeltme kayıtlarını inceleyip hesapları düzenledikten sonra tekrar deneyin.`);
      }
      skipped += 1;
      continue;
    }
    const expected = new Map(details.shares.map((s) => [s.account_party, toBigInt(s.amount_minor)]));
    const actual = new Map();
    for (const row of live) actual.set(accountOf(row), (actual.get(accountOf(row)) ?? 0n) + toBigInt(row.amount_minor));
    if (['owner', 'tenant'].every((party) => (actual.get(party) ?? 0n) === (expected.get(party) ?? 0n))) continue;
    openPeriod ??= await resolveOpenPeriod(client, siteCode, now);
    const date = today(now);
    const generation = 1 + rows.reduce((max, row) => Math.max(max, row.proration?.generation ?? 0), 0);
    const snapshot = { ...details, generation };
    for (const row of live) {
      await client.query(`
        INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date,
          definition_id, definition_name, run_id, payer_party, account_party, fund, reverses_entry_id, reversal_reason,
          created_by, source_kind, source_id, proration)
        VALUES ($1, $2, 'reversal', $3::BIGINT, $4::DATE, $5::DATE, $6::DATE, $7, $8, $9, $10, $11, $12, $13,
          'Günlük aidat paylaşımı yeniden hesaplandı', $14, $15, $16, $17::JSONB)`,
      [siteCode, apartmentId, String(-toBigInt(row.amount_minor)), openPeriod, date, row.original_due_date,
        row.definition_id, row.definition_name, row.run_id, row.payer_party, accountOf(row), row.fund,
        row.id, actorCode, row.source_kind ?? null, row.source_id ?? null, JSON.stringify(snapshot)]);
    }
    for (const share of details.shares.filter((s) => toBigInt(s.amount_minor) > 0n)) {
      await client.query(`
        INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date,
          definition_id, definition_name, run_id, payer_party, account_party, fund, created_by, description, proration)
        VALUES ($1, $2, 'charge', $3::BIGINT, $4::DATE, $5::DATE, $6::DATE, $7, $8, $9, $10, $11, 'operating', $12, $13, $14::JSONB)`,
      [siteCode, apartmentId, share.amount_minor, openPeriod, date, root.original_due_date, root.definition_id,
        root.definition_name, root.run_id, root.payer_party, share.account_party, actorCode,
        prorationDescription(details, share.account_party), JSON.stringify(snapshot)]);
    }
    adjusted += 1;
  }
  if (adjusted || skipped) await recordFinanceAudit(client, actor, 'finance.aidat_proration.reconciled', siteCode, apartmentId, { adjusted_count: adjusted, skipped_cancelled_count: skipped });
  return { adjusted, skipped };
}
