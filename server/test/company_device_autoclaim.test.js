import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { autoClaimCompanyDevice } from '../src/routes/company_routes.js';
import { pool } from '../src/db.js';
import { claimDevice } from '../src/services/membership_service.js';

afterEach(() => {
  delete pool.query;
  delete pool.connect;
});

describe('autoClaimCompanyDevice: Şirket aracı cihazını otomatik envantere sahiplendirme', () => {
  it('cihaz zaten sahiplenilmişse üzerine yazmaz (already_claimed)', async () => {
    const fakeDb = {
      async query(sql) {
        if (/FROM devices/.test(sql)) {
          return { rows: [{ id: 10, owner_user_id: 1311, assigned_user_code: 52702, site_code: null }] };
        }
        throw new Error('Beklenmeyen sorgu');
      },
    };

    const res = await autoClaimCompanyDevice(fakeDb, 'B86D72A172E0');
    assert.deepEqual(res, { already_claimed: true, owner_user_id: 1311, assigned_user_code: 52702 });
  });

  it('cihaz sahipsizse varsayılan super_user hesabına bağlar', async () => {
    const queries = [];
    const fakeDb = {
      async query(sql, params) {
        queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
        if (/FROM devices/.test(sql)) {
          return { rows: [{ id: 10, owner_user_id: null, assigned_user_code: null, site_code: null }] };
        }
        if (/role = 'super_user'/.test(sql)) {
          return { rows: [{ id: 1311, user_code: 52702 }] };
        }
        if (/UPDATE devices SET owner_user_id/.test(sql)) {
          return { rowCount: 1, rows: [] };
        }
        return { rows: [] };
      },
    };

    const res = await autoClaimCompanyDevice(fakeDb, 'B86D72A172E0');
    assert.deepEqual(res, { claimed: true, owner_user_id: 1311, assigned_user_code: 52702 });
    const updateCall = queries.find((q) => q.sql.includes('UPDATE devices SET owner_user_id'));
    assert.ok(updateCall);
    assert.equal(updateCall.params[0], 1311);
    assert.equal(updateCall.params[1], 52702);
    assert.equal(updateCall.params[2], 'B86D72A172E0');
  });

  it('preferredUserCode belirtilmişse ilgili kullanıcıya bağlar', async () => {
    const queries = [];
    const fakeDb = {
      async query(sql, params) {
        queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
        if (/FROM devices/.test(sql)) {
          return { rows: [{ id: 10, owner_user_id: null, assigned_user_code: null, site_code: null }] };
        }
        if (/FROM users WHERE user_code = \$1/.test(sql)) {
          return { rows: [{ id: 1439, user_code: 81793 }] };
        }
        if (/UPDATE devices SET owner_user_id/.test(sql)) {
          return { rowCount: 1, rows: [] };
        }
        return { rows: [] };
      },
    };

    const res = await autoClaimCompanyDevice(fakeDb, 'B86D72A172E0', 81793);
    assert.deepEqual(res, { claimed: true, owner_user_id: 1439, assigned_user_code: 81793 });
    const updateCall = queries.find((q) => q.sql.includes('UPDATE devices SET owner_user_id'));
    assert.ok(updateCall);
    assert.equal(updateCall.params[0], 1439);
    assert.equal(updateCall.params[1], 81793);
  });
});

describe('claimDevice: Şirket stokundaki (super_user) atanmamış cihazın devralınması', () => {
  it('şirket stokundaki (super_user, site_code=null, kapı yok) cihazı site yöneticisi devralabilir', async () => {
    const queries = [];
    const client = {
      async query(sql, params) {
        const text = sql.replace(/\s+/g, ' ').trim();
        queries.push({ text, params });
        if (text === 'BEGIN' || text === 'COMMIT') return { rows: [] };
        // Kullanıcı sorgusu
        if (/FROM users WHERE user_code = \$1/.test(text)) {
          return { rowCount: 1, rows: [{ id: 99, user_code: 12345, full_name: 'Ahmet Yonetici', email: 'ahmet@site.com', email_verified: true, role: 'site_manager' }] };
        }
        // İzin sorgusu (SQL_MANAGED_SITE_WITH_DOOR_CONTROL)
        if (/FROM sites s/.test(text)) {
          return { rowCount: 1, rows: [{ site_code: 101 }] };
        }
        // Cihaz sorgusu
        if (/FROM \( SELECT id, device_uid/.test(text)) {
          return {
            rowCount: 1,
            rows: [{
              id: 38,
              device_uid: 'B86D72A172E0',
              hardware_type: 'esp32_wroom',
              gate_name: null,
              site_code: null,
              owner_user_id: 1311, // super_user sahibi
              assigned_user_code: 52702,
              claimed_at: new Date().toISOString(),
              is_defective: false,
              defective_reason: null,
            }],
          };
        }
        // Sahip kontrolü (owner_user_id rolü)
        if (/SELECT role FROM users WHERE id = \$1/.test(text)) {
          return { rowCount: 1, rows: [{ role: 'super_user' }] };
        }
        // Kapı kontrolü
        if (/SELECT id FROM site_doors WHERE assigned_device_id = \$1/.test(text)) {
          return { rowCount: 0, rows: [] };
        }
        // Atomik güncelleme
        if (/UPDATE devices SET owner_user_id/.test(text)) {
          return {
            rowCount: 1,
            rows: [{
              id: 38,
              device_uid: 'B86D72A172E0',
              hardware_type: 'esp32_wroom',
              gate_name: null,
              site_code: null,
              owner_user_id: 99,
              claimed_at: new Date().toISOString(),
              is_defective: false,
            }],
          };
        }
        return { rowCount: 1, rows: [] };
      },
      release() {},
    };

    pool.connect = async () => client;

    const res = await claimDevice({ userCode: 12345, deviceInput: 'B86D72A172E0' });
    assert.equal(res.ok, true);
    assert.equal(res.device.owner_user_id, 99);
  });

  it('başka bir normal müşteriye ait cihaz devralınamaz (409)', async () => {
    const client = {
      async query(sql) {
        const text = sql.replace(/\s+/g, ' ').trim();
        if (text === 'BEGIN' || text === 'ROLLBACK') return { rows: [] };
        if (/FROM users WHERE user_code = \$1/.test(text)) {
          return { rowCount: 1, rows: [{ id: 99, user_code: 12345, full_name: 'Ahmet', email: 'ahmet@site.com', email_verified: true, role: 'site_manager' }] };
        }
        if (/FROM sites s/.test(text)) {
          return { rowCount: 1, rows: [{ site_code: 101 }] };
        }
        if (/FROM \( SELECT id, device_uid/.test(text)) {
          return {
            rowCount: 1,
            rows: [{
              id: 38,
              device_uid: 'B86D72A172E0',
              hardware_type: 'esp32_wroom',
              gate_name: null,
              site_code: null,
              owner_user_id: 55, // baska bir musteri
              assigned_user_code: 98765,
              claimed_at: new Date().toISOString(),
              is_defective: false,
              defective_reason: null,
            }],
          };
        }
        if (/SELECT role FROM users WHERE id = \$1/.test(text)) {
          return { rowCount: 1, rows: [{ role: 'site_manager' }] }; // super degil
        }
        return { rowCount: 0, rows: [] };
      },
      release() {},
    };

    pool.connect = async () => client;

    await assert.rejects(
      async () => {
        await claimDevice({ userCode: 12345, deviceInput: 'B86D72A172E0' });
      },
      (err) => {
        assert.equal(err.statusCode, 409);
        assert.match(err.message, /başka bir kullanıcı hesabı tarafından sahiplenilmiş/);
        return true;
      },
    );
  });
});
