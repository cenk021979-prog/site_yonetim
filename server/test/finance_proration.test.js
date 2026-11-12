import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { dailyAidatShares, monthDays, chargeLinesOf } from '../src/modules/finance_proration.js';
import { planHash } from '../src/modules/finance_distribution.js';

const tenant = (moveIn, moveOut = null, id = 1) => ({ id, moveIn, moveOut });
const split = (period, amountMinor, residencies) => dailyAidatShares({ period, amountMinor, residencies });
const amounts = (result) => Object.fromEntries(result.shares.map((s) => [s.account_party, Number(s.amount_minor)]));

describe('Aylık aidat gerçek gün paylaşımı', () => {
  it('3000 TL / 30 gün; 18 çıkış günü dahil: kiracı1800, malik1200 TL', () => {
    const result = split('2026-11-01', 300000n, [tenant('2026-01-01', '2026-11-18')]);
    assert.deepEqual(amounts(result), { owner: 120000, tenant: 180000 });
    assert.deepEqual(result.shares.map((s) => s.days), [12, 18]);
  });
  for (const [period, days] of [['2026-02-01', 28], ['2028-02-01', 29], ['2026-11-01', 30], ['2026-12-01', 31]]) {
    it(`${period}: ${days} takvim günü, ay sonu dahil tam aidat`, () => {
      assert.equal(monthDays(period), days);
      const result = split(period, 300001n, [tenant(`${period.slice(0, 7)}-01`, `${period.slice(0, 7)}-${days}`)]);
      assert.deepEqual(amounts(result), { tenant: 300001 });
    });
  }
  it('ay ortası giriş: giriş öncesi malik, giriş günü ve sonrası kiracı', () => {
    const result = split('2026-11-01', 300000n, [tenant('2026-11-18')]);
    assert.deepEqual(amounts(result), { owner: 170000, tenant: 130000 });
  });
  it('tek günlük ikamet iki uç dahil yalnız bir gün borçlanır', () => {
    assert.deepEqual(amounts(split('2026-11-01', 300000n, [tenant('2026-11-18', '2026-11-18')])), { owner: 290000, tenant: 10000 });
  });
  it('kiracı yoksa/başka aydaysa bütün günler malikindir', () => {
    assert.deepEqual(amounts(split('2026-11-01', 300000n, [])), { owner: 300000 });
    assert.deepEqual(amounts(split('2026-11-01', 300000n, [tenant('2026-12-01'), tenant('2026-01-01', '2026-10-31', 2)])), { owner: 300000 });
  });
  it('aynı ay iki kiracı ve boş aralık: günler tek sayılır, ikamet izi ayrıdır', () => {
    const result = split('2026-11-01', 300000n, [tenant('2026-01-01', '2026-11-10', 5), tenant('2026-11-21', null, 7)]);
    assert.deepEqual(amounts(result), { owner: 100000, tenant: 200000 });
    assert.deepEqual(result.residency_days, [{ residency_id: 5, days: 10 }, { residency_id: 7, days: 10 }]);
  });
  it('çakışan kayıt aynı günü mükerrer borçlandıramaz', () => {
    const result = split('2026-11-01', 300000n, [tenant('2026-01-01', '2026-11-18', 5), tenant('2026-11-18', null, 7)]);
    assert.deepEqual(amounts(result), { tenant: 300000 });
    assert.equal(result.overlap_days, 1);
    assert.deepEqual(result.residency_days, [{ residency_id: 5, days: 18 }, { residency_id: 7, days: 12 }]);
  });
  it('kuruş toplamı her tutar ve çıkış gününde kesindir; sıralama sonucu değiştirmez', () => {
    for (const days of [28, 29, 30, 31]) {
      const period = ({ 28: '2026-02-01', 29: '2028-02-01', 30: '2026-11-01', 31: '2026-12-01' })[days];
      for (let day = 1; day <= days; day += 1) for (const total of [1n, 2n, 99n, 100n, 300001n, 1000000000000n]) {
        const result = split(period, total, [tenant('2025-01-01', `${period.slice(0, 7)}-${String(day).padStart(2, '0')}`)]);
        assert.equal(result.shares.reduce((sum, s) => sum + BigInt(s.amount_minor), 0n), total);
        assert.equal(result.shares.reduce((sum, s) => sum + s.days, 0), days);
      }
    }
  });
  it('aynı toplam ve dairede taşınma tarihi değişirse preview hash değişir', () => {
    const line = { apartmentId: 1, amount: 300000n, payerParty: 'tenant', accountParty: null };
    const hash = (day) => planHash({ lines: [{ ...line, proration: split('2026-11-01', 300000n, [tenant('2025-01-01', day)]) }], missing: [] });
    assert.notEqual(hash('2026-11-18'), hash('2026-11-19'));
  });
  it('bir daire önizleme satırından iki pozitif hesap satırı; Fon/tek seferlik satır olduğu gibi kalır', () => {
    const base = { apartmentId: 1, amount: 300000n, accountParty: 'tenant' };
    const lines = chargeLinesOf({ lines: [{ ...base, proration: split('2026-11-01', 300000n, [tenant('2025-01-01', '2026-11-18')]) }, { ...base, apartmentId: 2, accountParty: 'owner' }] });
    assert.deepEqual(lines.map((l) => [l.apartmentId, l.accountParty, l.amount]), [[1, 'owner', 120000n], [1, 'tenant', 180000n], [2, 'owner', 300000n]]);
    assert.equal(chargeLinesOf({ lines: [{ ...base, proration: split('2026-11-01', 1n, [tenant('2025-01-01', '2026-11-18')]) }] }).length, 1);
  });
});
