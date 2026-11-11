-- Explicit equipment block scope; NULL retains site-wide compatibility.
ALTER TABLE equipment_items ADD COLUMN IF NOT EXISTS block_id BIGINT;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'equipment_items_block_id_fkey' AND conrelid = 'equipment_items'::regclass) THEN
    ALTER TABLE equipment_items ADD CONSTRAINT equipment_items_block_id_fkey FOREIGN KEY (block_id) REFERENCES site_blocks(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_equipment_items_block ON equipment_items (site_code, block_id) WHERE is_active = TRUE;
