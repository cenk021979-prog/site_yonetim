-- 134: Platform-geneli Modul Yonetimi (Platform Master Switch)
-- Super user haricinde hicbir rolde gorunmeyecek pasif modullerin kaydi.
CREATE TABLE IF NOT EXISTS platform_modules (
  module_code TEXT PRIMARY KEY,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_platform_modules_active ON platform_modules(is_active);

-- Varsayılan durumlar: Belirtilen 13 modül PASİF (is_active = FALSE), diğerleri AKTİF
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
  ('plate_recognition', TRUE, NOW())
ON CONFLICT (module_code) DO NOTHING;
