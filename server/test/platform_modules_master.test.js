import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { MODULE_CATALOG } from '../src/modules/catalog.js';
import {
  getPlatformModulesMap,
  isModuleActiveOnPlatform,
  updatePlatformModuleStatus,
  cleanupUndeployedModulesFromDatabase,
} from '../src/modules/platform_modules_schema.js';

describe('platform_modules_master (Katman 1)', () => {
  it('varsayılan harita: DB hatasında bile tüm katalog döner', async () => {
    const fakeDb = {
      query: async () => {
        throw new Error('tablo yok');
      },
    };
    const map = await getPlatformModulesMap(fakeDb);
    assert.equal(map instanceof Map, true);
    for (const def of MODULE_CATALOG) {
      assert.equal(map.has(def.code), true);
    }
  });

  it('isModuleActiveOnPlatform bilinmeyen modülde varsayılan true döner', async () => {
    const fakeDb = {
      query: async () => ({ rows: [] }),
    };
    const active = await isModuleActiveOnPlatform('unknown_module', fakeDb);
    assert.equal(active, true);
  });

  it('updatePlatformModuleStatus doğru SQL ve parametrelerle çağrılır ve pasif yapılınca site_modules siler', async () => {
    const queries = [];
    const fakeDb = {
      query: async (sql, params) => {
        queries.push({ sql, params });
        return { rows: [] };
      },
    };
    await updatePlatformModuleStatus('survey', false, 81793, fakeDb);
    assert.ok(queries[0].sql.includes('INSERT INTO platform_modules'));
    assert.equal(queries[0].params[0], 'survey');
    assert.equal(queries[0].params[1], false);
    assert.equal(queries[0].params[2], 81793);

    // Pasife alındığında site_modules ve module_requests silinmelidir
    const siteModulesDelete = queries.find((q) => q.sql.includes('DELETE FROM site_modules'));
    assert.ok(siteModulesDelete);
    assert.equal(siteModulesDelete.params[0], 'survey');

    const requestsDelete = queries.find((q) => q.sql.includes('DELETE FROM module_requests'));
    assert.ok(requestsDelete);
    assert.equal(requestsDelete.params[0], 'survey');
  });

  it('cleanupUndeployedModulesFromDatabase devreye alınmamış modülleri temizler ve vacuum çalıştırır', async () => {
    const queries = [];
    const fakeDb = {
      query: async (sql, params) => {
        queries.push({ sql, params });
        if (sql.includes('DELETE FROM site_modules')) {
          return { rows: [{ module_code: 'survey' }], rowCount: 1 };
        }
        if (sql.includes('DELETE FROM module_requests')) {
          return { rows: [{ id: 101 }], rowCount: 1 };
        }
        return { rows: [] };
      },
    };
    const res = await cleanupUndeployedModulesFromDatabase(fakeDb);
    assert.equal(res.ok, true);
    assert.equal(res.deletedSiteModulesCount, 1);
    assert.equal(res.deletedModuleRequestsCount, 1);
    assert.equal(res.vacuumExecuted, true);

    assert.ok(queries.some((q) => q.sql.includes('DELETE FROM site_modules')));
    assert.ok(queries.some((q) => q.sql.includes('DELETE FROM module_requests')));
    assert.ok(queries.some((q) => q.sql.includes('VACUUM ANALYZE site_modules')));
    assert.ok(queries.some((q) => q.sql.includes('VACUUM ANALYZE module_requests')));
  });
});
