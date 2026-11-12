// Aylık Aidat: gerçek takvim günleri, giriş ve çıkış dahil; para yalnız BigInt kuruş.
import { createHash } from 'node:crypto';
import { distributeLargestRemainder } from './finance_distribution.js';
import { toBigInt } from './finance_money.js';

export function monthDays(period) {
  if (!/^\d{4}-(0[1-9]|1[0-2])-01$/.test(period)) throw new RangeError('Geçersiz aidat dönemi');
  return new Date(Date.UTC(Number(period.slice(0, 4)), Number(period.slice(5, 7)), 0)).getUTCDate();
}

/** Çakışan ikametler aynı takvim gününü iki kez borçlandıramaz. Gün, önce başlayan ikamete bağlanır; kimlik yalnız iz içindir. */
export function dailyAidatShares({ period, amountMinor, residencies = [] }) {
  const total = toBigInt(amountMinor);
  if (total < 0n) throw new RangeError('Aidat negatif olamaz');
  const totalDays = monthDays(period);
  const ordered = [...residencies].sort((a, b) => a.moveIn.localeCompare(b.moveIn) || a.id - b.id);
  const residencyDays = new Map();
  let tenantDays = 0;
  let overlapDays = 0;
  for (let day = 1; day <= totalDays; day += 1) {
    const date = `${period.slice(0, 7)}-${String(day).padStart(2, '0')}`;
    const matches = ordered.filter((r) => r.moveIn <= date && (r.moveOut === null || r.moveOut >= date));
    if (matches.length > 1) overlapDays += 1;
    if (matches.length) {
      tenantDays += 1;
      const id = matches[0].id;
      residencyDays.set(id, (residencyDays.get(id) ?? 0) + 1);
    }
  }
  const ownerDays = totalDays - tenantDays;
  // Eşit kalanda malik (id=0) önce kalan kuruşu alır; kural deterministiktir.
  const amounts = distributeLargestRemainder(total, [{ id: 0, weight: BigInt(ownerDays) }, { id: 1, weight: BigInt(tenantDays) }]);
  const shares = [
    { account_party: 'owner', days: ownerDays, amount_minor: String(amounts.get(0)) },
    { account_party: 'tenant', days: tenantDays, amount_minor: String(amounts.get(1)) },
  ].filter((s) => s.days > 0);
  const schedule = ordered.map((r) => [r.id, r.moveIn, r.moveOut]);
  const hash = createHash('sha256').update(JSON.stringify([1, period, String(total), schedule])).digest('hex');
  return {
    version: 1, period, total_days: totalDays, monthly_amount_minor: String(total), schedule_hash: hash,
    overlap_days: overlapDays, shares,
    residency_days: [...residencyDays].sort((a, b) => a[0] - b[0]).map(([residency_id, days]) => ({ residency_id, days })),
  };
}

export function prorationDescription(details, accountParty) {
  const share = details.shares.find((s) => s.account_party === accountParty);
  return `Günlük aidat paylaşımı: ${share.days}/${details.total_days} gün (${accountParty === 'tenant' ? 'kiracı' : 'malik'})`;
}

/** Önizleme tek daire satırını korur; defter en çok iki hesaba yazılır. Sıfır kuruş satır yazılmaz. */
export function chargeLinesOf(plan) {
  return plan.lines.flatMap((line) => line.proration
    ? line.proration.shares.filter((share) => toBigInt(share.amount_minor) > 0n).map((share) => ({
      ...line, amount: toBigInt(share.amount_minor), accountParty: share.account_party,
      description: prorationDescription(line.proration, share.account_party),
    }))
    : [line]);
}
