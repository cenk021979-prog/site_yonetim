-- Site ici Asansor / Yangin alarmi. Ekleyici, idempotent.
CREATE TABLE IF NOT EXISTS emergency_responders (
  id BIGSERIAL PRIMARY KEY, site_code BIGINT NOT NULL, user_code INTEGER NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('security', 'elevator_service')), vendor_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_emergency_responders_user UNIQUE (site_code, user_code),
  CONSTRAINT chk_emergency_responders_vendor CHECK ((role = 'security' AND vendor_id IS NULL) OR (role = 'elevator_service' AND vendor_id IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS emergency_alarms (
  id BIGSERIAL PRIMARY KEY, site_code BIGINT NOT NULL, created_by INTEGER,
  kind TEXT NOT NULL CHECK (kind IN ('elevator', 'fire')), equipment_id BIGINT, vendor_id BIGINT,
  equipment_name TEXT, location TEXT, request_location TEXT, idempotency_key TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'acknowledged', 'resolved')),
  delivery JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), acknowledged_at TIMESTAMPTZ, resolved_at TIMESTAMPTZ,
  CONSTRAINT uq_emergency_alarm_request UNIQUE (created_by, idempotency_key),
  CONSTRAINT chk_emergency_alarm_key CHECK (idempotency_key ~ '^[A-Za-z0-9_-]{8,80}$'),
  CONSTRAINT chk_emergency_alarm_equipment CHECK ((kind = 'elevator' AND equipment_name IS NOT NULL) OR (kind = 'fire' AND equipment_id IS NULL)),
  CONSTRAINT chk_emergency_alarm_location CHECK (location IS NULL OR char_length(location) <= 120),
  CONSTRAINT chk_emergency_alarm_state CHECK ((status = 'resolved') = (resolved_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS emergency_alarm_recipients (
  alarm_id BIGINT NOT NULL, user_code INTEGER NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('security', 'elevator_service', 'manager')),
  received_at TIMESTAMPTZ, played_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ,
  PRIMARY KEY (alarm_id, user_code)
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'emergency_responders_site_code_fkey' AND conrelid = 'emergency_responders'::regclass) THEN
    ALTER TABLE emergency_responders ADD CONSTRAINT emergency_responders_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'emergency_responders_user_code_fkey' AND conrelid = 'emergency_responders'::regclass) THEN
    ALTER TABLE emergency_responders ADD CONSTRAINT emergency_responders_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'emergency_responders_vendor_id_fkey' AND conrelid = 'emergency_responders'::regclass) THEN
    ALTER TABLE emergency_responders ADD CONSTRAINT emergency_responders_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES contract_vendors(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'emergency_alarms_site_code_fkey' AND conrelid = 'emergency_alarms'::regclass) THEN
    ALTER TABLE emergency_alarms ADD CONSTRAINT emergency_alarms_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'emergency_alarms_created_by_fkey' AND conrelid = 'emergency_alarms'::regclass) THEN
    ALTER TABLE emergency_alarms ADD CONSTRAINT emergency_alarms_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'emergency_alarms_equipment_id_fkey' AND conrelid = 'emergency_alarms'::regclass) THEN
    ALTER TABLE emergency_alarms ADD CONSTRAINT emergency_alarms_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES equipment_items(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'emergency_alarms_vendor_id_fkey' AND conrelid = 'emergency_alarms'::regclass) THEN
    ALTER TABLE emergency_alarms ADD CONSTRAINT emergency_alarms_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES contract_vendors(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'emergency_alarm_recipients_alarm_id_fkey' AND conrelid = 'emergency_alarm_recipients'::regclass) THEN
    ALTER TABLE emergency_alarm_recipients ADD CONSTRAINT emergency_alarm_recipients_alarm_id_fkey FOREIGN KEY (alarm_id) REFERENCES emergency_alarms(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'emergency_alarm_recipients_user_code_fkey' AND conrelid = 'emergency_alarm_recipients'::regclass) THEN
    ALTER TABLE emergency_alarm_recipients ADD CONSTRAINT emergency_alarm_recipients_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_emergency_alarm_site_open ON emergency_alarms (site_code, id DESC) WHERE status <> 'resolved';

CREATE INDEX IF NOT EXISTS idx_emergency_alarm_actor_time ON emergency_alarms (created_by, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emergency_recipient_pending ON emergency_alarm_recipients (user_code, alarm_id DESC) WHERE acknowledged_at IS NULL;
