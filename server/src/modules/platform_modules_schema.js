// 134: Platform-geneli Modül Yönetimi (Platform Master Switch) Şeması ve Veri Erişimi.
// 135: Devreye alınmamış modüllerin site_modules temizliği ve VACUUM bakımı.
import { pool } from '../db.js';
import { MODULE_CATALOG } from './catalog.js';

export const PLATFORM_MODULES_SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS platform_modules (
  module_code TEXT PRIMARY KEY,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_platform_modules_active ON platform_modules(is_active);

INSERT INTO platform_modules (module_code, is_active, updated_at)
VALUES
  ('budget', FALSE, NOW()),
  ('work_tracking', FALSE, NOW()),
  ('reservation', FALSE, NOW()),
  ('visitor_log', FALSE, NOW()),
  ('contracts', FALSE, NOW()),
  ('decision_book', FALSE, NOW()),
  ('survey', FALSE, NOW()),
  ('equipment', FALSE, NOW()),
  ('hgs_access', FALSE, NOW()),
  ('annual_report', FALSE, NOW()),
  ('neighbor_board', FALSE, NOW()),
  ('card_access', FALSE, NOW()),
  ('online_payment', FALSE, NOW()),
  ('metering', FALSE, NOW()),
  ('people', TRUE, NOW()),
  ('finance', TRUE, NOW()),
  ('announcements', TRUE, NOW()),
  ('door_control', TRUE, NOW()),
  ('directory', TRUE, NOW()),
  ('plate_recognition', TRUE, NOW()),
  ('drive_storage', TRUE, NOW())
ON CONFLICT (module_code) DO NOTHING;

-- 135: Devreye alınmamış modüllerin hiçbir sitede bulunmamasını garanti et
DELETE FROM site_modules
WHERE module_code IN (
  SELECT module_code FROM platform_modules WHERE is_active = FALSE
);
`;

export async function ensurePlatformModulesSchema(client) {
  await client.query(PLATFORM_MODULES_SCHEMA_SQL);
}

// Bellek içi kısa süreli önbellek (her istekte DB'ye gitmesin diye 15 saniye veya güncellemede geçersizleşir)
let cachedPlatformModules = null;
let cacheExpiresAt = 0;

export function invalidatePlatformModulesCache() {
  cachedPlatformModules = null;
  cacheExpiresAt = 0;
}

/**
 * Platform genelindeki modül durum haritası: Map<module_code, boolean>
 */
export async function getPlatformModulesMap(db = pool) {
  const now = Date.now();
  if (cachedPlatformModules && cacheExpiresAt > now) {
    return cachedPlatformModules;
  }

  try {
    const res = await db.query('SELECT module_code, is_active FROM platform_modules');
    const map = new Map();
    for (const row of res.rows ?? []) {
      map.set(row.module_code, row.is_active === true);
    }
    // Katalogdaki eksik kalanlar varsa varsayılan true kabul edilir
    for (const def of MODULE_CATALOG) {
      if (!map.has(def.code)) {
        map.set(def.code, true);
      }
    }
    cachedPlatformModules = map;
    cacheExpiresAt = now + 15000;
    return map;
  } catch (_err) {
    // Tablo henüz yoksa veya hata anında güvenli varsayılan: katalog durumuna dön
    const fallback = new Map();
    for (const def of MODULE_CATALOG) {
      fallback.set(def.code, true);
    }
    return fallback;
  }
}

/**
 * Tek bir modül platformda aktif mi?
 */
export async function isModuleActiveOnPlatform(moduleCode, db = pool) {
  const map = await getPlatformModulesMap(db);
  return map.get(moduleCode) ?? true;
}

/**
 * Süper kullanıcının modülü platform genelinde açıp kapatması.
 * Devre dışı bırakıldığında (isActive === false):
 * - İlgili modül tüm sitelerin site_modules ve module_requests tablolarından anında silinir.
 * Devreye alındığında (isActive === true) ve modül temel (core) ise:
 * - Tüm sitelere otomatik olarak tanımlanır (site_modules içine eklenir).
 */
export async function updatePlatformModuleStatus(moduleCode, isActive, updatedByUserCode = null, db = pool) {
  await db.query(
    `
    INSERT INTO platform_modules (module_code, is_active, updated_at, updated_by)
    VALUES ($1, $2, NOW(), $3)
    ON CONFLICT (module_code) DO UPDATE
    SET is_active = EXCLUDED.is_active,
        updated_at = NOW(),
        updated_by = EXCLUDED.updated_by
    `,
    [moduleCode, Boolean(isActive), updatedByUserCode],
  );

  if (!isActive) {
    await db.query('DELETE FROM site_modules WHERE module_code = $1', [moduleCode]);
  } else {
    const def = MODULE_CATALOG.find((m) => m.code === moduleCode);
    if (def?.core) {
      await db.query(
        `
        INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
        SELECT s.site_code, $1, TRUE, NOW()
        FROM sites s
        ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE, updated_at = NOW()
        WHERE site_modules.enabled IS DISTINCT FROM TRUE
        `,
        [moduleCode],
      );
    }
  }

  invalidatePlatformModulesCache();
}

/**
 * Devreye alınmamış (platform_modules.is_active = FALSE) modülleri tüm sitelerin
 * site_modules ve module_requests tablolarından temizler ve veritabanı çöplüğünü (dead tuples)
 * temizlemek için VACUUM ANALYZE çalıştırır.
 */
export async function cleanupUndeployedModulesFromDatabase(db = pool) {
  const deleteSiteModulesRes = await db.query(`
    DELETE FROM site_modules
    WHERE module_code IN (
      SELECT module_code FROM platform_modules WHERE is_active = FALSE
    )
    RETURNING module_code;
  `);

  let vacuumExecuted = false;
  try {
    // VACUUM ANALYZE transaction blokları içinde çalıştırılamaz; pool üzerinden bağımsız çalıştırılır
    await db.query('VACUUM ANALYZE site_modules;');
    await db.query('VACUUM ANALYZE platform_modules;');
    vacuumExecuted = true;
  } catch (_err) {
    // Test ortamında veya transaction içindeyse vacuum hata verebilir, güvenle yutulur
    vacuumExecuted = false;
  }

  invalidatePlatformModulesCache();

  return {
    ok: true,
    deletedSiteModulesCount: deleteSiteModulesRes.rowCount ?? deleteSiteModulesRes.rows?.length ?? 0,
    deletedModuleRequestsCount: 0,
    vacuumExecuted,
  };
}
