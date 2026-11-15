import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { resolveManagerPlateTarget } from '../src/modules/plate_edge_service.js';

describe('yönetici plaka olayı hedef kapısı', () => {
  it('kamera ve kapı verilmezse sorgu/alternatif kapı seçimi yapmaz', async () => {
    let calls = 0;
    const db = { query: async () => { calls += 1; return { rows: [] }; } };
    assert.equal(await resolveManagerPlateTarget(db, { siteCode: 7 }), null);
    assert.equal(calls, 0);
  });

  it('kamera ve kapı birlikte verilirse ikisinin aynı eşleşmede olmasını zorunlu tutar', async () => {
    const calls = [];
    const db = {
      query: async (sql, params) => {
        calls.push({ sql, params });
        return { rows: [{ door_id: 31, device_uid: 'SKP-31' }] };
      },
    };
    const row = await resolveManagerPlateTarget(db, { siteCode: 7, gateId: 9, cameraId: 12 });
    assert.equal(row.device_uid, 'SKP-31');
    assert.deepEqual(calls[0].params, [7, 9, 12]);
    assert.match(calls[0].sql, /g\.id = \$2 AND gc\.camera_id = \$3/);
    assert.match(calls[0].sql, /sd\.is_active = TRUE/);
    assert.match(calls[0].sql, /d\.site_code = g\.site_code/);
    assert.doesNotMatch(calls[0].sql, /ORDER BY sd\.id LIMIT 1/);
  });
});
