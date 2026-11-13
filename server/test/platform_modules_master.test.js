import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { MODULE_CATALOG } from '../src/modules/catalog.js';
import { getPlatformModulesMap, isModuleActiveOnPlatform, updatePlatformModuleStatus } from '../src/modules/platform_modules_schema.js';

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

  it('updatePlatformModuleStatus doğru SQL ve parametrelerle çağrılır', async () => {
    let executedSql = '';
    let executedParams = [];
    const fakeDb = {
      query: async (sql, params) => {
        executedSql = sql;
        executedParams = params;
        return { rows: [] };
      },
    };
    await updatePlatformModuleStatus('survey', false, 81793, fakeDb);
    assert.ok(executedSql.includes('INSERT INTO platform_modules'));
    assert.equal(executedParams[0], 'survey');
    assert.equal(executedParams[1], false);
    assert.equal(executedParams[2], 81793);
  });
});
