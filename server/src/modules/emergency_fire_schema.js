// 129 extends persisted alarms without rewriting historical events or recipient timestamps.
export const EMERGENCY_FIRE_MIGRATION_SQL = `ALTER TABLE emergency_alarms ADD COLUMN IF NOT EXISTS created_by_name TEXT;

ALTER TABLE emergency_alarm_recipients DROP CONSTRAINT IF EXISTS emergency_alarm_recipients_role_check;
ALTER TABLE emergency_alarm_recipients ADD CONSTRAINT emergency_alarm_recipients_role_check
  CHECK (role IN ('security', 'elevator_service', 'manager', 'resident'));
`;

export async function ensureEmergencyFireSchema(client) {
  const state = (await client.query(`SELECT
    EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'emergency_alarms'::regclass AND attname = 'created_by_name' AND NOT attisdropped) AS actor_name,
    EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'emergency_alarm_recipients'::regclass
      AND conname = 'emergency_alarm_recipients_role_check' AND pg_get_constraintdef(oid) LIKE '%resident%') AS resident_role`)).rows?.[0];
  if (state?.actor_name && state?.resident_role) return;
  await client.query("SET lock_timeout = '5s'");
  try { await client.query(EMERGENCY_FIRE_MIGRATION_SQL); }
  finally { await client.query('RESET lock_timeout'); }
}
