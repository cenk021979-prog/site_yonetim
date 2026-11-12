-- Sakin araç hareketi bildirimini yönetim açar; kişisel tercih ayrıca gerekir.
ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS resident_movement_notifications_enabled BOOLEAN NOT NULL DEFAULT FALSE;
