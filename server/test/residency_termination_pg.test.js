// Opt-in: sadece tek kullanımlık şema provası; canlı DB adı kesinlikle kabul edilmez.
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

const run = process.env.TERMINATION_PG_TEST === '1';
if (run && !/^kapi_(test|rehearsal)_\d{8}_\d{6}$/.test(process.env.DB_NAME ?? '')) {
  throw new Error('Termination PG tests require a disposable guarded database');
}

describe('360 ayrılma: gerçek PostgreSQL şeması ve atomik sonuçlar', { skip: !run }, () => {
  let pool; let preview; let execute; let releaseReservations;
  const q = (sql, args = []) => pool.query(sql, args);
  const id = async (sql, args = []) => Number((await q(sql, args)).rows[0].id);
  before(async () => {
    ({ pool } = await import('../src/db.js'));
    ({ previewResidencyTermination: preview, executeResidencyTermination: execute } = await import('../src/modules/residency_termination_service.js'));
    ({ releaseUserReservations: releaseReservations } = await import('../src/modules/reservation_service.js'));
  });
  after(async () => { if (pool) await pool.end(); });

  async function fixture({ tenant = false, user = false } = {}) {
    const tag = randomUUID();
    const site = await id('INSERT INTO sites(name,approval_status) VALUES($1,\'approved\') RETURNING site_code AS id', [`Ayrılma test ${tag}`]);
    const otherSite = await id('INSERT INTO sites(name,approval_status) VALUES($1,\'approved\') RETURNING site_code AS id', [`Ayrılma diğer ${tag}`]);
    const block = await id('INSERT INTO site_blocks(site_code,block_name,sort_order) VALUES($1,\'A Blok\',1) RETURNING id', [site]);
    const otherBlock = await id('INSERT INTO site_blocks(site_code,block_name,sort_order) VALUES($1,\'B Blok\',1) RETURNING id', [otherSite]);
    const apt = await id('INSERT INTO apartments(site_code,block_id,unit_label,sort_order) VALUES($1,$2,\'12\',1) RETURNING id', [site, block]);
    const sameSiteApt = await id('INSERT INTO apartments(site_code,block_id,unit_label,sort_order) VALUES($1,$2,\'13\',2) RETURNING id', [site, block]);
    const otherApt = await id('INSERT INTO apartments(site_code,block_id,unit_label,sort_order) VALUES($1,$2,\'1\',1) RETURNING id', [otherSite, otherBlock]);
    const userCode = user ? await id(`INSERT INTO users(full_name,email,role,password_hash,is_active,email_verified,approval_status)
      VALUES('Ayrılma sentetik', $1,'apartment_owner','test-hash',TRUE,TRUE,'approved') RETURNING user_code AS id`, [`termination-${tag}@example.invalid`]) : null;
    const person = await id('INSERT INTO site_people(site_code,full_name,user_code) VALUES($1,\'Sentetik Sakin\',$2) RETURNING id', [site, userCode]);
    const residency = await id(`INSERT INTO apartment_residencies(site_code,apartment_id,person_id,relation,move_in_date)
      VALUES($1,$2,$3,$4,'2026-01-01') RETURNING id`, [site, apt, person, tenant ? 'tenant' : 'resident']);
    if (userCode) {
      await q(`INSERT INTO apartment_memberships(apartment_id,user_code,role,is_active) VALUES($1,$3,'FAMILY_MEMBER',TRUE),($2,$3,'FAMILY_MEMBER',TRUE)`, [apt, sameSiteApt, userCode]);
    }
    const meter = await id(`INSERT INTO meters(site_code,apartment_id,kind,serial_no) VALUES($1,$2,'water','TERM-METER') RETURNING id`, [site, apt]);
    const foreignMeter = await id(`INSERT INTO meters(site_code,apartment_id,kind,serial_no) VALUES($1,$2,'water','TERM-OTHER') RETURNING id`, [otherSite, otherApt]);
    await q(`INSERT INTO meter_readings(site_code,meter_id,reading_date,value) VALUES($1,$2,'2026-11-01',100)`, [site, meter]);
    return { site, otherSite, apt, sameSiteApt, otherApt, person, residency, meter, foreignMeter, userCode };
  }
  const args = (f, patch = {}) => ({ siteCode: f.site, apartmentId: f.apt, residencyId: f.residency,
    moveOutDate: '2026-11-10', actor: null, ...patch });
  const current = async (f) => (await q('SELECT is_current FROM apartment_residencies WHERE id=$1', [f.residency])).rows[0].is_current;

  it('önizleme gerçek daire/blok ve sayaç alanlarını okur; gün bir önceki güne kaymaz', async () => {
    const f = await fixture();
    const value = await preview(pool, args(f));
    assert.equal(value.apartment.apartmentNo, '12');
    assert.equal(value.apartment.blockName, 'A Blok');
    assert.equal(value.meters[0].lastReadingValue, 100);
    assert.equal(value.meters[0].lastReadingDate, '2026-11-01');
  });
  it('başka site/sayaç veya önceki endeksten küçük okuma tüm ayrılmayı geri alır', async () => {
    const f = await fixture();
    await assert.rejects(execute(pool, args(f, { siteCode: f.otherSite })), { code: 'APARTMENT_NOT_FOUND' });
    await assert.rejects(execute(pool, args(f, { finalMeterReadings: [{ meterId: f.foreignMeter, readingValue: 150 }] })), { code: 'METER_NOT_FOUND' });
    assert.equal(await current(f), true);
    await assert.rejects(execute(pool, args(f, { finalMeterReadings: [{ meterId: f.meter, readingValue: 99 }] })), { code: 'READING_OUT_OF_ORDER' });
    assert.equal(await current(f), true);
    assert.equal((await q('SELECT COUNT(*)::INT AS n FROM meter_readings WHERE meter_id=$1', [f.meter])).rows[0].n, 1);
  });
  it('aynı son okuma tekrar kullanılır; ayrılma kaydı ve okumalar tek işlemde tamamlanır', async () => {
    const f = await fixture();
    await q(`INSERT INTO meter_readings(site_code,meter_id,reading_date,value) VALUES($1,$2,'2026-11-10',150)`, [f.site, f.meter]);
    const result = await execute(pool, args(f, { finalMeterReadings: [{ meterId: f.meter, readingDate: '10.11.2026', readingValue: 150 }] }));
    assert.equal(result.ok, true);
    assert.equal(await current(f), false);
    assert.equal((await q('SELECT COUNT(*)::INT AS n FROM meter_readings WHERE meter_id=$1', [f.meter])).rows[0].n, 2);
  });
  it('daireden çıkış başka daire/site rezervasyonlarını ve araçlarını korur; hesap silme kapsamı değişmez', async () => {
    const f = await fixture({ user: true });
    const area = await id('INSERT INTO reservation_areas(site_code,name) VALUES($1,\'Test Alanı\') RETURNING id', [f.site]);
    const otherArea = await id('INSERT INTO reservation_areas(site_code,name) VALUES($1,\'Diğer Alan\') RETURNING id', [f.otherSite]);
    const reservations = [];
    const vehicle = await id(`INSERT INTO vehicles(site_code,person_id,apartment_id,plate) VALUES($1,$2,$3,'34TRM123') RETURNING id`, [f.site, f.person, f.sameSiteApt]);
    const door = await id(`INSERT INTO site_doors(site_code,door_name,door_index) VALUES($1,'Test Kapısı',1) RETURNING id`, [f.site]);
    const pass = await id(`INSERT INTO guest_passes(site_code,door_id,created_by_user_code,title,token,expires_at)
      VALUES($1,$2,$3,'Sentetik misafir',$4,NOW()+INTERVAL '1 day') RETURNING id`, [f.site, door, f.userCode, `termination-test-${randomUUID()}`]);
    for (const [site, apt, areaId] of [[f.site, f.apt, area], [f.site, f.sameSiteApt, area], [f.otherSite, f.otherApt, otherArea]]) {
      reservations.push(await id(`INSERT INTO reservations(site_code,apartment_id,area_id,user_code,starts_at,ends_at,slot_count)
        VALUES($1,$2,$3,$4,NOW()+INTERVAL '1 day',NOW()+INTERVAL '1 day 1 hour',1) RETURNING id`, [site, apt, areaId, f.userCode]));
    }
    const value = await preview(pool, args(f));
    assert.equal(Object.hasOwn(value.activeGuestPasses[0], 'token'), false);
    await execute(pool, args(f));
    assert.equal((await q('SELECT is_active FROM vehicles WHERE id=$1', [vehicle])).rows[0].is_active, true);
    assert.equal((await q('SELECT is_active FROM guest_passes WHERE id=$1', [pass])).rows[0].is_active, true);
    assert.deepEqual((await q('SELECT status FROM reservations WHERE id=ANY($1::BIGINT[]) ORDER BY id', [reservations])).rows.map((r) => r.status), ['iptal', 'beklemede', 'beklemede']);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      assert.equal((await releaseReservations(client, f.userCode)).reservations, 2);
      await client.query('ROLLBACK');
    } finally { client.release(); }
  });
  it('malik yoksa çıkış tamamlanır, devir başarısızlığı açık döner ve günlük paylar korunur', async () => {
    const f = await fixture({ tenant: true });
    const def = await id(`INSERT INTO fee_definitions(site_code,name,kind,distribution,amount_minor,due_day,start_period,target_type,charge_party)
      VALUES($1,'Test Aidat','recurring','fixed',300000,1,'2026-11-01','site','occupant') RETURNING id`, [f.site]);
    const feeRun = await id(`INSERT INTO fee_runs(site_code,definition_id,period,total_minor,apartment_count)
      VALUES($1,$2,'2026-11-01',300000,1) RETURNING id`, [f.site, def]);
    await q(`INSERT INTO ledger_entries(site_code,apartment_id,kind,amount_minor,period,entry_date,due_date,definition_id,run_id,payer_party,account_party,fund)
      VALUES($1,$2,'charge',300000,'2026-11-01','2026-11-01','2026-11-01',$3,$4,'tenant','tenant','operating')`, [f.site, f.apt, def, feeRun]);
    const result = await execute(pool, args(f, { debtDisposition: 'TRANSFER_TO_OWNER' }));
    assert.equal(result.ok, true);
    assert.equal(result.debtTransferFailed, true);
    assert.equal(typeof result.debtTransferError, 'string');
    assert.equal(await current(f), false);
    assert.deepEqual((await q('SELECT account_party,SUM(amount_minor)::TEXT AS balance FROM ledger_entries WHERE apartment_id=$1 GROUP BY account_party ORDER BY account_party', [f.apt])).rows,
      [{ account_party: 'owner', balance: '200000' }, { account_party: 'tenant', balance: '100000' }]);
  });
});
