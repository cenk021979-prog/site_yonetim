-- 135: Devreye alinmamis (platform_modules.is_active = FALSE) modullerin site_modules temizligi
-- AGENTS.md Kural 33: Devreye alinmamis moduller hicbir sitede tanimli olamaz, gorunemez veya talep edilemez.

DELETE FROM site_modules
WHERE module_code IN (
  SELECT module_code FROM platform_modules WHERE is_active = FALSE
);
