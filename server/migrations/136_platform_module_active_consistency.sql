-- 136: Devreye alınmamış modüller site düzeyinde tanımlı kalamaz.
-- Açılış ve yeni site doldurmaları platform_modules.is_active filtresiyle çalışır;
-- bu adım önceki sürümlerin bıraktığı satırları idempotent biçimde temizler.
DELETE FROM site_modules sm
USING platform_modules pm
WHERE pm.module_code = sm.module_code
  AND pm.is_active = FALSE;
