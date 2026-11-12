-- Yangın: site/blok sakin alıcıları ve alarmı başlatan kişi.
ALTER TABLE emergency_alarms ADD COLUMN IF NOT EXISTS created_by_name TEXT;

ALTER TABLE emergency_alarm_recipients DROP CONSTRAINT IF EXISTS emergency_alarm_recipients_role_check;
ALTER TABLE emergency_alarm_recipients ADD CONSTRAINT emergency_alarm_recipients_role_check
  CHECK (role IN ('security', 'elevator_service', 'manager', 'resident'));
