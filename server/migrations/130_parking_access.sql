CREATE TABLE IF NOT EXISTS parking_policies (
    site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    capacity INTEGER CHECK (capacity BETWEEN 1 AND 100000),
    registration_photo_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    updated_by INTEGER, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (NOT enabled OR capacity IS NOT NULL)
  );

CREATE TABLE IF NOT EXISTS parking_apartment_approvals (
    apartment_id BIGINT PRIMARY KEY REFERENCES apartments(id) ON DELETE CASCADE,
    approved BOOLEAN NOT NULL DEFAULT FALSE,
    updated_by INTEGER, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );

CREATE TABLE IF NOT EXISTS parking_schema_metadata (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW());

CREATE TABLE IF NOT EXISTS parking_legacy_vehicle_exemptions (
    vehicle_id BIGINT PRIMARY KEY REFERENCES vehicles(id) ON DELETE CASCADE,
    reason TEXT NOT NULL DEFAULT 'pre_130_unassigned_manager_vehicle', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );

WITH seeded AS (INSERT INTO parking_schema_metadata(name) VALUES('130_existing_vehicle_approvals') ON CONFLICT DO NOTHING RETURNING name)
   INSERT INTO parking_apartment_approvals(apartment_id,approved)
   SELECT DISTINCT COALESCE(v.apartment_id,r.apartment_id),TRUE FROM vehicles v
   LEFT JOIN apartment_residencies r ON r.person_id=v.person_id AND r.is_current
   JOIN apartments a ON a.id=COALESCE(v.apartment_id,r.apartment_id) AND a.site_code=v.site_code AND a.is_active
   WHERE v.is_active AND EXISTS(SELECT 1 FROM seeded) ON CONFLICT(apartment_id) DO NOTHING;

WITH seeded AS (INSERT INTO parking_schema_metadata(name) VALUES('130_existing_unassigned_vehicle_exemptions') ON CONFLICT DO NOTHING RETURNING name)
   INSERT INTO parking_legacy_vehicle_exemptions(vehicle_id)
   SELECT v.id FROM vehicles v WHERE v.is_active AND EXISTS(SELECT 1 FROM seeded)
   AND NOT EXISTS(SELECT 1 FROM apartments a WHERE a.id=v.apartment_id AND a.site_code=v.site_code AND a.is_active)
   AND NOT EXISTS(SELECT 1 FROM apartment_residencies r JOIN apartments a ON a.id=r.apartment_id AND a.site_code=v.site_code AND a.is_active WHERE r.person_id=v.person_id AND r.is_current)
   ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS parking_admissions (
    id BIGSERIAL PRIMARY KEY, site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
    request_id TEXT NOT NULL, edge_client_id BIGINT, plate TEXT NOT NULL, apartment_id BIGINT,
    camera_id BIGINT NOT NULL, gate_id BIGINT NOT NULL, direction TEXT NOT NULL CHECK (direction IN ('giris','cikis')),
    status TEXT NOT NULL CHECK (status IN ('pending','accepted','uncertain','failed','denied','released')),
    reason TEXT NOT NULL, blocking_plates JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (site_code, request_id)
  );

CREATE INDEX IF NOT EXISTS idx_parking_admissions_held ON parking_admissions(site_code, apartment_id, plate)
   WHERE direction = 'giris' AND status IN ('pending','accepted','uncertain');

CREATE TABLE IF NOT EXISTS vehicle_registration_photos (
    vehicle_id BIGINT PRIMARY KEY REFERENCES vehicles(id) ON DELETE CASCADE,
    mime_type TEXT NOT NULL CHECK (mime_type IN ('image/png','image/jpeg')),
    image_bytes BYTEA NOT NULL CHECK (octet_length(image_bytes) BETWEEN 8 AND 524288),
    uploaded_by INTEGER, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );

CREATE OR REPLACE FUNCTION clear_vehicle_registration_photo_on_identity_change() RETURNS TRIGGER AS $$
   BEGIN
     IF OLD.plate IS DISTINCT FROM NEW.plate OR OLD.person_id IS DISTINCT FROM NEW.person_id
       OR OLD.apartment_id IS DISTINCT FROM NEW.apartment_id OR OLD.site_code IS DISTINCT FROM NEW.site_code THEN
       DELETE FROM vehicle_registration_photos WHERE vehicle_id=OLD.id;
     END IF;
     RETURN NEW;
   END; $$ LANGUAGE plpgsql;

DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='vehicle_registration_photo_identity_changed' AND tgrelid='vehicles'::regclass) THEN
   CREATE TRIGGER vehicle_registration_photo_identity_changed BEFORE UPDATE OF plate,person_id,apartment_id,site_code ON vehicles
   FOR EACH ROW EXECUTE FUNCTION clear_vehicle_registration_photo_on_identity_change(); END IF; END $$;
