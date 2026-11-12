import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { saveTerminationReadings, terminationInput } from '../src/modules/residency_termination_checks.js';
import { redactForReadOnlyRole } from '../src/modules/people_common.js';

const now = new Date('2026-11-12T10:00:00Z');
const input = (patch = {}) => terminationInput({ debtDisposition: 'KEEP_ON_DEBTOR', finalMeterReadings: [], ...patch }, now);

describe('ayrılma giriş ve sayaç sözleşmesi', () => {
  it('kurul önizlemesinde yeni camelCase kullanıcı kimlikleri de gizlenir', () => {
    const value = { person: { userCode: 15, fullName: 'Sakin' }, remainingMembers: [{ userCode: 20 }], defaultSuccessorUserCode: 20 };
    assert.deepEqual(redactForReadOnlyRole(value), { person: { fullName: 'Sakin' }, remainingMembers: [{}] });
    assert.equal(value.person.userCode, 15);
  });
  it('TR tarihi normalleştirir, virgüllü endeksi kayıpsız çözer', () => {
    const result = input({ moveOutDate: '10.11.2026', finalMeterReadings: [{ meterId: 7, readingValue: '123,456', readingDate: '10.11.2026' }] });
    assert.equal(result.date, '2026-11-10');
    assert.equal(result.readings[0].date, result.date);
    assert.equal(result.readings[0].parsed.milli, 123456n);
  });
  it('olmayan/gelecek tarih, negatif veya aşırı hassas endeks ve mükerrer sayaç reddedilir', () => {
    for (const patch of [
      { moveOutDate: '2026-02-30' }, { moveOutDate: '2026-11-13' }, { debtDisposition: 'auto' },
      { finalMeterReadings: [{ meterId: 7, readingValue: -1 }] },
      { finalMeterReadings: [{ meterId: 7, readingValue: '1.2345' }] },
      { finalMeterReadings: [{ meterId: 7, readingValue: 1, readingDate: '2026-11-13' }] },
      { finalMeterReadings: [{ meterId: 7, readingValue: 1 }, { meterId: 7, readingValue: 2 }] },
    ]) assert.throws(() => input(patch), { code: 'INVALID_BODY' });
  });
  it('aynı sayaç+tarih+değer tekrarı yeni okuma yazmaz', async () => {
    const calls = [];
    const client = { query: async (sql, params) => {
      calls.push({ sql, params });
      if (sql.startsWith('SELECT id, is_active')) return { rows: [{ id: 7, is_active: true }] };
      if (sql.startsWith('SELECT id, value')) return { rows: [{ id: 9, value: '1.000' }] };
      throw new Error('unexpected write');
    } };
    await saveTerminationReadings(client, { siteCode: 1, apartmentId: 2,
      readings: input({ finalMeterReadings: [{ meterId: 7, readingValue: 1 }] }).readings, actor: { user_code: 3 } });
    assert.deepEqual(calls[0].params, [7, 1, 2]);
    assert.equal(calls.some((q) => q.sql.startsWith('INSERT')), false);
  });
});
