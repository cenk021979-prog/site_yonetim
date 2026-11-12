import { it } from 'node:test';
import assert from 'node:assert/strict';
import { statisticsGateId, statisticsAnchor, plateStatistics } from '../src/modules/plate_statistics_service.js';

it('istatistik kapısı katı tamsayıdır; SQL parametreleri ve kişisel veri içermeyen yanıt', async () => {
  assert.equal(statisticsGateId(undefined), null);
  assert.equal(statisticsGateId('10'), 10);
  for (const value of ['1.2', '0', '-1', '10 OR TRUE', [], {}, '999999999999999999']) {
    assert.throws(() => statisticsGateId(value), e => e.statusCode === 400);
  }
  const now = new Date('2026-11-08T12:00:00Z');
  const db = { query: async (sql, params) => {
    assert.deepEqual(params, [1001, 10, now]);
    assert.match(sql, /Europe\/Istanbul/);
    assert.doesNotMatch(sql, /LIMIT|INSERT|UPDATE|DELETE/i);
    return { rows: [{ period: 'day', starts_at: '2026-11-07T21:00:00Z', ends_at: '2026-11-08T21:00:00Z', entries: '130', exits: '2', unknown: '1' }] };
  } };
  const result = await plateStatistics(1001, { gate_id: '10' }, { db, now });
  assert.equal(result.periods.day.entries, 130);
  assert.equal(result.gate_id, 10);
  assert.equal(result.timezone, 'Europe/Istanbul');
  assert.equal(result.periods.day.ends_at, '2026-11-08T21:00:00.000Z');
});

it('rapor tarihi gerçek bir takvim tarihi olmalı; aşırı/taşan/yinelenen girdi reddedilir', async () => {
  for (const value of ['2026-02-29', '2026-13-01', '2026-04-31', '2026-01-00', '2026-01-32',
    '2026-1-1', '2026-11-08T00:00Z', '0000-01-01', '10000-01-01', ['2026-01-01'], {}, '2026-01-01 OR 1=1']) {
    assert.throws(() => statisticsAnchor(value), e => e.statusCode === 400);
  }
  assert.equal(statisticsAnchor('2028-02-29').toISOString(), '2028-02-29T09:00:00.000Z');
  const now = new Date('2026-11-08T12:00Z');
  const result = await plateStatistics(1, { anchor: '2025-12-31' }, { now, db: { query: async (_sql, params) => {
    assert.equal(params[2].toISOString(), '2025-12-31T09:00:00.000Z'); return { rows: [] };
  } } });
  assert.equal(result.server_time, now.toISOString(), 'anchor sunucu saatini değiştirmez');
});
