import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';

describe('plaka istatistikleri: gerçek PostgreSQL takvimi ve kapsamı', {
  skip: process.env.PLATE_STATISTICS_PG_TEST !== '1' ? 'PLATE_STATISTICS_PG_TEST=1 gerekir' : false,
}, () => {
  let db, statistics;
  before(async () => {
    assert.match(process.env.DB_NAME ?? '', /^kapi_(test|rehearsal)_\d{8}_\d{6}$/,
      'Yalnız izole prova veritabanı kullanılabilir');
    const pg = (await import('pg')).default;
    db = new pg.Client({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 5432),
      database: process.env.DB_NAME, user: process.env.DB_USER, password: process.env.DB_PASSWORD });
    await db.connect();
    // These connection-local tables shadow public tables. No public fixture writes.
    await db.query(`CREATE TEMP TABLE plate_decisions(id bigserial, site_code bigint, event_id bigint, door_id bigint, decided_at timestamptz);
      CREATE TEMP TABLE plate_events(id bigserial, site_code bigint, seen_at timestamptz, gate_id bigint, direction text);
      CREATE TEMP TABLE plate_gates(id bigint, site_code bigint, door_id bigint)`);
    ({ plateStatistics: statistics } = await import('../src/modules/plate_statistics_service.js'));
  });
  after(async () => { await db?.end(); });
  const clear = () => db.query('TRUNCATE pg_temp.plate_decisions, pg_temp.plate_events, pg_temp.plate_gates RESTART IDENTITY');
  async function add(at, { site = 1, gate = 10, direction = 'giris', door = null } = {}) {
    const row = (await db.query('INSERT INTO pg_temp.plate_events(site_code,seen_at,gate_id,direction) VALUES($1,$2,$3,$4) RETURNING id', [site, at, gate, direction])).rows[0];
    await db.query('INSERT INTO pg_temp.plate_decisions(site_code,event_id,door_id,decided_at) VALUES($1,$2,$3,$4)', [site, row.id, door, at]);
  }
  const read = (now, query = {}, site = 1) => statistics(site, query, { db, now: new Date(now) });

  it('İstanbul gece yarısı yarı-açık gün aralığı; liste limiti yok ve olay çift sayılmaz', async () => {
    await clear();
    await add('2026-11-07T20:59:59.999Z');
    for (let n = 0; n < 137; n++) await add('2026-11-07T21:00:00.000Z');
    await add('2026-11-08T20:59:59.999Z', { direction: 'cikis' });
    await add('2026-11-08T21:00:00.000Z');
    const result = await read('2026-11-08T12:00:00Z');
    assert.deepEqual(result.periods.day, { starts_at: '2026-11-07T21:00:00.000Z', ends_at: '2026-11-08T21:00:00.000Z', entries: 137, exits: 1, unknown: 0 });
    const nextDay = await read('2026-11-08T21:00:00Z');
    assert.equal(nextDay.periods.day.entries, 1);
  });
  it('pazartesi başlayan hafta, ay ve yıl sınırları Türkiye takviminde hesaplanır', async () => {
    await clear();
    await add('2026-11-29T20:59:59Z'); // Sunday
    await add('2026-11-29T21:00:00Z'); // Monday
    const result = await read('2026-12-01T12:00:00Z');
    assert.equal(result.periods.week.starts_at, '2026-11-29T21:00:00.000Z');
    assert.equal(result.periods.week.entries, 1);
    assert.equal(result.periods.month.starts_at, '2026-11-30T21:00:00.000Z');
    assert.equal(result.periods.month.entries, 0);
    const year = await read('2026-12-31T21:00:00Z');
    assert.equal(year.periods.month.starts_at, '2026-12-31T21:00:00.000Z');
    await add('2025-12-30T21:00:00Z');
    const historic = await read('2026-12-01T12:00Z', { anchor: '2025-12-31' });
    assert.equal(historic.periods.month.starts_at, '2025-11-30T21:00:00.000Z');
    assert.equal(historic.periods.month.ends_at, '2025-12-31T21:00:00.000Z');
    assert.equal(historic.periods.month.entries, 1);
    const leap = await read('2026-12-01T12:00Z', { anchor: '2028-02-29' });
    assert.equal(leap.periods.month.starts_at, '2028-01-31T21:00:00.000Z');
    assert.equal(leap.periods.month.ends_at, '2028-02-29T21:00:00.000Z');
  });
  it('site/kapı ayrımı ve eski door_id bağı; yönsüz kayıt girişe eklenmez; boş gün0', async () => {
    await clear();
    await db.query('INSERT INTO pg_temp.plate_gates VALUES(10,1,90),(20,1,91),(30,2,90)');
    const at = '2026-11-08T12:00:00Z';
    await add(at); await add(at, { gate: 20 }); await add(at, { site: 2, gate: 10 });
    await add(at, { gate: null, door: 90, direction: 'cikis' });
    await add(at, { direction: null });
    const gate = (await read(at, { gate_id: '10' })).periods.day;
    assert.deepEqual([gate.entries, gate.exits, gate.unknown], [1, 1, 1]);
    const site = (await read(at)).periods.day;
    assert.deepEqual([site.entries, site.exits, site.unknown], [2, 1, 1]);
    const empty = (await read('2026-11-10T12:00:00Z')).periods.day;
    assert.deepEqual([empty.entries, empty.exits, empty.unknown], [0, 0, 0]);
  });
});
