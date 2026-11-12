import { before, after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { PERSON_LOCATION_JOIN, PERSON_LOCATION_ORDER, naturalOrderSql } from '../src/modules/people_order.js';

describe('people order: natural location before server pagination', {
  skip: process.env.PEOPLE_ORDER_PG_TEST !== '1' ? 'PEOPLE_ORDER_PG_TEST=1 gerekir' : false,
}, () => {
  let db;
  before(async () => {
    assert.match(process.env.DB_NAME ?? '', /^kapi_(test|rehearsal)_\d{8}_\d{6}$/);
    const pg = (await import('pg')).default;
    db = new pg.Client({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 5432),
      database: process.env.DB_NAME, user: process.env.DB_USER, password: process.env.DB_PASSWORD });
    await db.connect();
    await db.query(`CREATE TEMP TABLE site_people(id bigint, site_code bigint, full_name text, user_code bigint);
      CREATE TEMP TABLE users(user_code bigint, full_name text);
      CREATE TEMP TABLE site_blocks(id bigint, site_code bigint, block_name text);
      CREATE TEMP TABLE apartments(id bigint, site_code bigint, block_id bigint, unit_label text);
      CREATE TEMP TABLE apartment_residencies(id bigserial, person_id bigint, apartment_id bigint, is_current boolean, move_out_date date)`);
  });
  after(async () => { await db?.end(); });
  const reset = () => db.query('TRUNCATE pg_temp.site_people,pg_temp.users,pg_temp.site_blocks,pg_temp.apartments,pg_temp.apartment_residencies RESTART IDENTITY');
  const page = async (limit = 99, offset = 0) => (await db.query(`
    SELECT sp.id FROM pg_temp.site_people sp LEFT JOIN pg_temp.users u ON u.user_code=sp.user_code
    ${PERSON_LOCATION_JOIN} WHERE sp.site_code=$1 ORDER BY ${PERSON_LOCATION_ORDER} LIMIT $2 OFFSET $3`, [1, limit, offset])).rows.map(r => Number(r.id));

  it('A1,A2,A10,B1,B2 across all pages; names cannot reorder numeric apartments', async () => {
    await reset();
    await db.query(`INSERT INTO pg_temp.site_blocks VALUES(1,1,'A Blok'),(2,1,'B Blok');
      INSERT INTO pg_temp.apartments VALUES(1,1,1,'Daire 1'),(2,1,1,'Daire 2'),(10,1,1,'Daire 10'),(11,1,2,'Daire 1'),(12,1,2,'Daire 2');
      INSERT INTO pg_temp.site_people VALUES(1,1,'SALİH 1',NULL),(2,1,'SALİH 2',NULL),(10,1,'SALİH 10',NULL),(11,1,'SALİH 11',NULL),(12,1,'SALİH 12',NULL),(99,1,'AAA unassigned',NULL);
      INSERT INTO pg_temp.apartment_residencies(person_id,apartment_id,is_current) VALUES(1,1,TRUE),(2,2,TRUE),(10,10,TRUE),(11,11,TRUE),(12,12,TRUE)`);
    assert.deepEqual(await page(), [1,2,10,11,12,99]);
    assert.deepEqual([...(await page(2,0)),...(await page(2,2)),...(await page(2,4))], [1,2,10,11,12,99]);
  });
  it('multi-apartment person occurs once; current location wins; latest former location retained; foreign site excluded', async () => {
    await reset();
    await db.query(`INSERT INTO pg_temp.site_blocks VALUES(1,1,'A'),(2,1,'B'),(3,2,'Foreign');
      INSERT INTO pg_temp.apartments VALUES(1,1,1,'1'),(2,1,1,'2'),(10,1,2,'10'),(30,2,3,'1');
      INSERT INTO pg_temp.site_people VALUES(1,1,'Z current',NULL),(2,1,'A former',NULL),(3,1,'Foreign link',NULL),(4,2,'Foreign person',NULL);
      INSERT INTO pg_temp.apartment_residencies(person_id,apartment_id,is_current,move_out_date) VALUES
        (1,1,FALSE,'2026-10-01'),(1,10,TRUE,NULL),(1,2,TRUE,NULL),
        (2,1,FALSE,'2026-09-01'),(2,10,FALSE,'2026-10-01'),(3,30,TRUE,NULL),(4,1,TRUE,NULL)`);
    assert.deepEqual(await page(), [1,2,3]);
    const locations = (await db.query(`SELECT sp.id,person_location.unit_label FROM pg_temp.site_people sp
      LEFT JOIN pg_temp.users u ON u.user_code=sp.user_code ${PERSON_LOCATION_JOIN} WHERE sp.site_code=1 ORDER BY ${PERSON_LOCATION_ORDER}`)).rows;
    assert.deepEqual(locations.map(r => r.unit_label), ['2','10',null]);
  });
  it('mixed suffixes, leading zeros and very large numeric labels use text-safe natural keys', async () => {
    const result = await db.query(`SELECT label FROM unnest(ARRAY['10A','2B','002A','2A','999999999999999999999999999999999']) AS label
      ORDER BY ${naturalOrderSql('label')},label`);
    assert.deepEqual(result.rows.map(r => r.label), ['002A','2A','2B','10A','999999999999999999999999999999999']);
  });
});
