import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

describe('document audiences: real PostgreSQL site and legacy isolation', {
  skip: process.env.DOCUMENT_AUDIENCE_PG_TEST !== '1' ? 'DOCUMENT_AUDIENCE_PG_TEST=1 gerekir' : false,
}, () => {
  let db, resident, visibility, manager;
  before(async () => {
    assert.match(process.env.DB_NAME ?? '', /^kapi_(test|rehearsal)_\d{8}_\d{6}$/,
      'Only an explicitly isolated rehearsal database may be used');
    const pg = (await import('pg')).default;
    db = new pg.Client({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 5432),
      database: process.env.DB_NAME, user: process.env.DB_USER, password: process.env.DB_PASSWORD });
    await db.connect();
    assert.equal((await db.query('SELECT current_database() AS name')).rows[0].name, process.env.DB_NAME);
    await db.query(`SET statement_timeout = '10s';
      CREATE TEMP TABLE users(user_code integer, is_active boolean);
      CREATE TEMP TABLE sites(site_code bigint, name text, approval_status text);
      CREATE TEMP TABLE site_people(id bigint, site_code bigint, user_code integer, is_active boolean);
      CREATE TEMP TABLE apartments(id bigint, site_code bigint, block_id bigint, is_active boolean);
      CREATE TEMP TABLE apartment_residencies(person_id bigint, apartment_id bigint, is_current boolean);
      CREATE TEMP TABLE apartment_memberships(user_code integer, apartment_id bigint, is_active boolean);
      CREATE TEMP TABLE site_manager_sites(site_code bigint, manager_user_code integer);
      CREATE TEMP TABLE site_memberships(site_code bigint, user_code integer, role text, is_active boolean);
      CREATE TEMP TABLE site_modules(site_code bigint, module_code text, enabled boolean);
      CREATE TEMP TABLE documents(id bigint, site_code bigint, title text, category text, description text,
        updated_at timestamptz, status text, audience text, target_type text,
        target_block_ids bigint[], target_apartment_ids bigint[], current_version_no integer);
      CREATE TEMP TABLE document_versions(id bigint, document_id bigint, version_no integer, status text,
        storage_key text, display_name text, mime_type text, size_bytes bigint, completed_at timestamptz,
        server_copy boolean, drive_file_id bigint);
      CREATE TEMP TABLE drive_files(id bigint, site_code bigint, status text);
      CREATE TEMP TABLE announcements(id bigint, site_code bigint, status text);
      CREATE TEMP TABLE announcement_recipients(announcement_id bigint, person_id bigint);
      CREATE TEMP TABLE announcement_attachments(announcement_id bigint, document_id bigint, position integer);`);
    // Every source query below sees connection-local fixtures, never public user/document rows.
    await db.query('SET search_path = pg_temp, public');
    resident = await import('../src/modules/document_resident.js');
    visibility = await import('../src/modules/document_visibility.js');
    manager = await import('../src/modules/document_service.js');
  });
  after(async () => { await db?.end(); });

  beforeEach(async () => {
    await db.query(`TRUNCATE pg_temp.users, pg_temp.sites, pg_temp.site_people, pg_temp.apartments,
      pg_temp.apartment_residencies, pg_temp.apartment_memberships, pg_temp.site_manager_sites,
      pg_temp.site_memberships, pg_temp.site_modules, pg_temp.documents, pg_temp.document_versions,
      pg_temp.drive_files, pg_temp.announcements, pg_temp.announcement_recipients, pg_temp.announcement_attachments;
      INSERT INTO pg_temp.users VALUES
        (101,TRUE),(102,TRUE),(103,TRUE),(104,TRUE),(105,TRUE),(106,TRUE),
        (107,TRUE),(108,FALSE),(109,TRUE),(110,TRUE),(111,TRUE),(112,TRUE),(113,TRUE),(114,TRUE),(201,TRUE);
      INSERT INTO pg_temp.sites VALUES (10,'Own site','approved'),(20,'Foreign site','approved'),(30,'Pending site','pending');
      INSERT INTO pg_temp.site_memberships VALUES
        (10,101,'STAFF',TRUE),(10,103,'BOARD_MEMBER',TRUE),(10,105,'SITE_OWNER',TRUE),
        (10,106,'SITE_ADMIN',TRUE),(10,107,'STAFF',FALSE),(10,108,'STAFF',TRUE),
        (10,110,'RESIDENT',TRUE),(20,201,'STAFF',TRUE),(30,101,'STAFF',TRUE);
      INSERT INTO pg_temp.site_manager_sites VALUES (10,102);
      INSERT INTO pg_temp.apartments VALUES (1001,10,501,TRUE),(1002,10,502,TRUE),(1003,10,501,FALSE);
      INSERT INTO pg_temp.site_people VALUES
        (104,10,104,TRUE),(109,10,109,TRUE),(111,10,111,TRUE),
        (112,10,112,TRUE),(113,10,113,FALSE),(114,10,114,TRUE);
      INSERT INTO pg_temp.apartment_residencies VALUES
        (104,1001,TRUE),(111,1002,TRUE),(112,1001,FALSE),(113,1001,TRUE),(114,1003,TRUE);
      INSERT INTO pg_temp.documents VALUES
        (1,10,'Whole site','notice',NULL,NOW(),'active','all','site','{}','{}',2),
        (2,10,'Legacy residents','notice',NULL,NOW(),'active','residents','site','{}','{}',2),
        (3,10,'Block A','notice',NULL,NOW(),'active','residents','blocks','{501}','{}',2),
        (4,10,'Apartment A','notice',NULL,NOW(),'active','residents','apartments','{}','{1001}',2),
        (5,10,'Management','notice',NULL,NOW(),'active','board','site','{}','{}',2),
        (6,10,'Legacy private','notice',NULL,NOW(),'active','managers','site','{}','{}',2),
        (7,10,'Block B','notice',NULL,NOW(),'active','residents','blocks','{502}','{}',2),
        (8,20,'Foreign public','notice',NULL,NOW(),'active','all','site','{}','{}',2),
        (9,30,'Pending public','notice',NULL,NOW(),'active','all','site','{}','{}',2);
      INSERT INTO pg_temp.document_versions
        SELECT d.id*10+v.n,d.id,v.n,'ready',d.site_code||'/fixture-'||d.id||'-'||v.n,
          'document-'||d.id||'.pdf','application/pdf',123,NOW(),TRUE,NULL
        FROM pg_temp.documents d CROSS JOIN (VALUES(1),(2)) AS v(n);
      INSERT INTO pg_temp.announcements VALUES (90,10,'published');
      INSERT INTO pg_temp.announcement_recipients VALUES (90,104);
      INSERT INTO pg_temp.announcement_attachments VALUES (90,1,0),(90,7,1);`);
  });

  const auth = (id) => ({ id, user_code: id, userCode: id });
  const notFound = (promise) => assert.rejects(promise, (error) => error.statusCode === 404 && error.code === 'DOCUMENT_NOT_FOUND');
  async function visibleIds(userCode) {
    const result = await db.query(`WITH ${resident.myApartmentsCte('$1')}
      SELECT d.id FROM documents d WHERE d.site_code=$2 AND
        ${visibility.publicDocumentAccessSql('d', '$1', resident.documentVisibleToUserSql('d', '$1'))}
      ORDER BY d.id`, [userCode, 10]);
    return result.rows.map((row) => Number(row.id));
  }

  it('new all includes active same-site staff, manager, board, owner, admin and actual resident', async () => {
    for (const userCode of [101,102,103,104,105,106]) {
      assert.ok((await visibleIds(userCode)).includes(1), `all must include eligible user ${userCode}`);
      const detail = await resident.getMyDocument(auth(userCode), 1, db);
      assert.equal(detail.id, 1);
      const file = await resident.resolveResidentDownload(auth(userCode), 1, db);
      assert.deepEqual([file.documentId,file.siteCode,file.versionNo], [1,10,2]);
    }
  });

  it('foreign, inactive membership/account, person-only, role-only and former/inactive apartment are denied', async () => {
    for (const userCode of [201,107,108,109,110,112,113,114]) {
      assert.ok(!(await visibleIds(userCode)).includes(1), `all must exclude user ${userCode}`);
      await notFound(resident.getMyDocument(auth(userCode), 1, db));
      await notFound(resident.resolveResidentDownload(auth(userCode), 1, db));
    }
    await notFound(resident.getMyDocument(auth(101), 9, db)); // member, but site is not approved
    await notFound(resident.resolveResidentDownload(auth(101), 8, db)); // another site's document
  });

  it('legacy residents target rules and legacy managers privacy never broaden to staff', async () => {
    assert.deepEqual(await visibleIds(101), [1]);
    assert.deepEqual(await visibleIds(104), [1,2,3,4]);
    assert.deepEqual(await visibleIds(111), [1,2,7]);
    assert.deepEqual(await visibleIds(103), [1,2,3,4,7]); // board has the original target bypass
    for (const documentId of [2,3,4,5,6,7]) await notFound(resident.resolveResidentDownload(auth(101), documentId, db));
    await notFound(resident.resolveResidentDownload(auth(104), 7, db));
    await notFound(resident.resolveResidentDownload(auth(111), 4, db));
    const listed = await resident.listMyDocuments(auth(101), {}, db);
    assert.deepEqual(listed.items.map((row) => row.id), [1]);
  });

  it('membership revocation, account deactivation, site approval and module visibility are evaluated fresh', async () => {
    await resident.resolveResidentDownload(auth(101), 1, db);
    await db.query("UPDATE pg_temp.site_memberships SET is_active=FALSE WHERE user_code=101 AND site_code=10");
    assert.deepEqual((await resident.listMyDocuments(auth(101), {}, db)).items, []);
    await notFound(resident.getMyDocument(auth(101), 1, db));
    await notFound(resident.resolveResidentDownload(auth(101), 1, db));
    await db.query("UPDATE pg_temp.site_memberships SET is_active=TRUE WHERE user_code=101 AND site_code=10");
    await db.query('UPDATE pg_temp.users SET is_active=FALSE WHERE user_code=101');
    await notFound(resident.resolveResidentDownload(auth(101), 1, db));
    await db.query('UPDATE pg_temp.users SET is_active=TRUE WHERE user_code=101');
    await db.query("UPDATE pg_temp.sites SET approval_status='pending' WHERE site_code=10");
    await notFound(resident.resolveResidentDownload(auth(101), 1, db));
    await db.query("UPDATE pg_temp.sites SET approval_status='approved' WHERE site_code=10");
    await db.query("INSERT INTO pg_temp.site_modules VALUES(10,'drive_storage',FALSE)");
    await notFound(resident.resolveResidentDownload(auth(101), 1, db));
  });

  it('all to board/private narrowing immediately closes list, detail and current-version resolver', async () => {
    await resident.resolveResidentDownload(auth(101), 1, db);
    for (const audience of ['board','managers']) {
      await db.query('UPDATE pg_temp.documents SET audience=$1 WHERE id=1', [audience]);
      assert.deepEqual((await resident.listMyDocuments(auth(101), {}, db)).items, []);
      await notFound(resident.getMyDocument(auth(101), 1, db));
      await notFound(resident.resolveResidentDownload(auth(101), 1, db));
    }
    await db.query("UPDATE pg_temp.documents SET audience='all' WHERE id=1");
    assert.equal((await resident.resolveResidentDownload(auth(101), 1, db)).versionNo, 2);
  });

  it('management reads keep old private/version rules while public routes expose only current ready content', async () => {
    const privateFile = await manager.resolveManagerDownload({ siteCode:10,rawId:6,versionNo:1,kind:'manager' }, db);
    assert.equal(privateFile.versionNo, 1);
    await notFound(manager.resolveManagerDownload({ siteCode:10,rawId:6,versionNo:null,kind:'board' }, db));
    await notFound(manager.resolveManagerDownload({ siteCode:10,rawId:1,versionNo:1,kind:'board' }, db));
    assert.equal((await manager.resolveManagerDownload({ siteCode:10,rawId:1,versionNo:null,kind:'board' }, db)).versionNo, 2);
    await db.query("UPDATE pg_temp.documents SET status='deleted' WHERE id=1");
    await notFound(resident.resolveResidentDownload(auth(101), 1, db));
    await notFound(manager.resolveManagerDownload({ siteCode:10,rawId:1,versionNo:null,kind:'board' }, db));
    assert.equal((await manager.resolveManagerDownload({ siteCode:10,rawId:1,versionNo:null,kind:'manager' }, db)).documentId, 1);
  });

  it('Drive-backed all returns the same authorized current version without exposing a Drive URL', async () => {
    await db.query("INSERT INTO pg_temp.drive_files VALUES(700,10,'stored')");
    await db.query('UPDATE pg_temp.document_versions SET server_copy=FALSE,drive_file_id=700 WHERE document_id=1 AND version_no=2');
    const file = await resident.resolveResidentDownload(auth(101), 1, db);
    assert.deepEqual([file.serverCopy,file.driveFileId,file.driveStatus], [false,700,'stored']);
    assert.equal(Object.keys(file).some((key) => /url|link/i.test(key)), false);
    await db.query('UPDATE pg_temp.site_memberships SET is_active=FALSE WHERE user_code=101 AND site_code=10');
    await notFound(resident.resolveResidentDownload(auth(101), 1, db));
  });

  it('announcement attachments retain recipient/site checks and close on audience narrowing', async () => {
    const file = await resident.resolveAnnouncementAttachmentDownload(auth(104), 90, 1, db);
    assert.equal(file.documentId, 1);
    // A public document does not grant access to another recipient's announcement.
    await notFound(resident.resolveAnnouncementAttachmentDownload(auth(101), 90, 1, db));
    // Legacy A12: a received announcement attachment can outlive document target narrowing within the same site.
    assert.equal((await resident.resolveAnnouncementAttachmentDownload(auth(104), 90, 7, db)).documentId, 7);
    await db.query("UPDATE pg_temp.documents SET audience='board' WHERE id=1");
    await notFound(resident.resolveAnnouncementAttachmentDownload(auth(104), 90, 1, db));
    await db.query('UPDATE pg_temp.apartment_residencies SET is_current=FALSE WHERE person_id=104');
    await notFound(resident.resolveAnnouncementAttachmentDownload(auth(104), 90, 7, db));
  });
});
