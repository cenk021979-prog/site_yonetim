// 128: yalnız yeni tablolar. Eski 107 acil rehberini ve donanımı değiştirmez.
import { ensureEmergencyFireSchema } from './emergency_fire_schema.js';
const fk = (table, column, parent, target, deletion = 'CASCADE') => {
  const name = `${table}_${column}_fkey`;
  return { name, sql: `DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass) THEN
    ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${target}) ON DELETE ${deletion};
  END IF;
END $$;` };
};
const tables = {
  emergency_responders: `CREATE TABLE IF NOT EXISTS emergency_responders (
  id BIGSERIAL PRIMARY KEY, site_code BIGINT NOT NULL, user_code INTEGER NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('security', 'elevator_service')), vendor_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_emergency_responders_user UNIQUE (site_code, user_code),
  CONSTRAINT chk_emergency_responders_vendor CHECK ((role = 'security' AND vendor_id IS NULL) OR (role = 'elevator_service' AND vendor_id IS NOT NULL))
);`,
  emergency_alarms: `CREATE TABLE IF NOT EXISTS emergency_alarms (
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
);`,
  emergency_alarm_recipients: `CREATE TABLE IF NOT EXISTS emergency_alarm_recipients (
  alarm_id BIGINT NOT NULL, user_code INTEGER NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('security', 'elevator_service', 'manager')),
  received_at TIMESTAMPTZ, played_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ,
  PRIMARY KEY (alarm_id, user_code)
);`,
};
const fks = [
  fk('emergency_responders', 'site_code', 'sites', 'site_code'),
  fk('emergency_responders', 'user_code', 'users', 'user_code'),
  fk('emergency_responders', 'vendor_id', 'contract_vendors', 'id'),
  fk('emergency_alarms', 'site_code', 'sites', 'site_code'),
  fk('emergency_alarms', 'created_by', 'users', 'user_code', 'SET NULL'),
  fk('emergency_alarms', 'equipment_id', 'equipment_items', 'id', 'SET NULL'),
  fk('emergency_alarms', 'vendor_id', 'contract_vendors', 'id', 'SET NULL'),
  fk('emergency_alarm_recipients', 'alarm_id', 'emergency_alarms', 'id'),
  fk('emergency_alarm_recipients', 'user_code', 'users', 'user_code'),
];
const indexes = [
  { name: 'idx_emergency_alarm_site_open', sql: "CREATE INDEX IF NOT EXISTS idx_emergency_alarm_site_open ON emergency_alarms (site_code, id DESC) WHERE status <> 'resolved';" },
  { name: 'idx_emergency_alarm_actor_time', sql: 'CREATE INDEX IF NOT EXISTS idx_emergency_alarm_actor_time ON emergency_alarms (created_by, created_at DESC);' },
  { name: 'idx_emergency_recipient_pending', sql: 'CREATE INDEX IF NOT EXISTS idx_emergency_recipient_pending ON emergency_alarm_recipients (user_code, alarm_id DESC) WHERE acknowledged_at IS NULL;' },
];
export const EMERGENCY_ALARM_STEPS = Object.freeze([
  ...Object.entries(tables).map(([name, sql]) => ({ name, sql, kind: 'table' })),
  ...fks.map((s) => ({ ...s, kind: 'fk' })), ...indexes.map((s) => ({ ...s, kind: 'index' })),
]);
export const emergencyAlarmMigrationSql = () => `${EMERGENCY_ALARM_STEPS.map((s) => s.sql).join('\n\n')}\n`;
export async function ensureEmergencyAlarmSchema(client) {
  const found = await client.query(`SELECT
    ARRAY(SELECT tablename::TEXT FROM pg_tables WHERE schemaname = 'public' AND tablename = ANY($1::TEXT[])) AS tables,
    ARRAY(SELECT conname::TEXT FROM pg_constraint WHERE connamespace = 'public'::regnamespace AND conname = ANY($2::TEXT[])) AS fks,
    ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($3::TEXT[])) AS indexes`,
  [Object.keys(tables), fks.map((s) => s.name), indexes.map((s) => s.name)]);
  const row = found.rows?.[0] ?? {};
  const present = new Set([...(row.tables ?? []), ...(row.fks ?? []), ...(row.indexes ?? [])]);
  const missing = EMERGENCY_ALARM_STEPS.filter((s) => !present.has(s.name));
  if (!missing.length) {
    await ensureEmergencyFireSchema(client);
    return;
  }
  await client.query("SET lock_timeout = '5s'");
  try { for (const step of missing) await client.query(step.sql); }
  finally { await client.query('RESET lock_timeout'); }
  await ensureEmergencyFireSchema(client);
}
