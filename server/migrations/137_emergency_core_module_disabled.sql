-- Acil Durum ve SOS temel moduldur; hazirliklar tamamlanana kadar platform ana salterinde pasiftir.
INSERT INTO platform_modules (module_code, is_active, updated_at)
VALUES ('emergency', FALSE, NOW())
ON CONFLICT (module_code) DO NOTHING;

DELETE FROM site_modules
WHERE module_code = 'emergency'
  AND EXISTS (SELECT 1 FROM platform_modules WHERE module_code = 'emergency' AND is_active = FALSE);

INSERT INTO site_modules (site_code, module_code, enabled, updated_at)
SELECT s.site_code, 'emergency', TRUE, NOW()
FROM sites s
INNER JOIN platform_modules pm ON pm.module_code = 'emergency' AND pm.is_active = TRUE
ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE, updated_at = NOW()
WHERE site_modules.enabled IS DISTINCT FROM TRUE;
