// 131 adds a new explicit audience; it does not change any document row.
export const DOCUMENT_AUDIENCE_ALL_SQL = `DO $$
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
END $$;`;

export async function ensureDocumentAudienceSchema(client) {
  const found = await client.query(`SELECT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('public.documents')
      AND conname = 'chk_documents_audience' AND pg_get_constraintdef(oid) LIKE '%''all''%'
  ) AS ready`);
  if (found.rows[0]?.ready === true) return;
  await client.query(DOCUMENT_AUDIENCE_ALL_SQL);
}
