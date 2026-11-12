// 133: bildirim izni kapı/araç yetkisini değiştirmez. Eski kişisel tercihler saklanır.
export const PLATE_MOVEMENT_POLICY_SQL = 'ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS resident_movement_notifications_enabled BOOLEAN NOT NULL DEFAULT FALSE';

export async function ensurePlateMovementPolicySchema(client) {
  const { rows } = await client.query(`SELECT
    to_regclass('public.plate_site_settings') IS NOT NULL AS parent_exists,
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
      AND table_name='plate_site_settings' AND column_name='resident_movement_notifications_enabled') AS column_exists`);
  if (rows[0]?.parent_exists && !rows[0]?.column_exists) await client.query(PLATE_MOVEMENT_POLICY_SQL);
}
