-- New explicit whole-site audience, including active staff. No existing sharing changes.
DO $$
BEGIN
  IF to_regclass('public.documents') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.documents')
      AND conname = 'chk_documents_audience' AND pg_get_constraintdef(oid) LIKE '%''all''%'
  ) THEN
    PERFORM set_config('lock_timeout', '2s', TRUE);
    ALTER TABLE documents DROP CONSTRAINT IF EXISTS chk_documents_audience;
    ALTER TABLE documents ADD CONSTRAINT chk_documents_audience
      CHECK (audience IN ('residents', 'board', 'managers', 'all')) NOT VALID;
    ALTER TABLE documents VALIDATE CONSTRAINT chk_documents_audience;
  END IF;
END $$;
