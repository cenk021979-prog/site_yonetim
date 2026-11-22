// Merkezi kimlik çözümleme ve hesap sahiplenme doğrulama şeması (138): migrations/138_identity_resolution.sql ile AYNI ifadeler.
// Yeni tablo, FK'siz; tablo varsa hiçbir DDL gönderilmez (kilit alınmaz). Bu dosya db.js'i İÇE AKTARMAZ.
export const IDENTITY_RESOLUTION_TABLES = Object.freeze(['identity_claim_challenges']);

export const IDENTITY_RESOLUTION_DDL = Object.freeze([
  `CREATE TABLE IF NOT EXISTS identity_claim_challenges (
    id BIGSERIAL PRIMARY KEY,
    token_hash TEXT NOT NULL UNIQUE,
    challenge_kind TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_sub TEXT,
    verified_email TEXT,
    verified_phone TEXT,
    full_name TEXT,
    candidate_user_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    consumed_user_code INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_identity_claim_kind CHECK (
      challenge_kind IN ('oauth_ambiguous', 'apple_relay_claim', 'sms_account_select')
    )
  )`,
  `CREATE INDEX IF NOT EXISTS idx_identity_claim_challenges_expires
    ON identity_claim_challenges (expires_at)`,
  `CREATE INDEX IF NOT EXISTS idx_identity_claim_challenges_sub
    ON identity_claim_challenges (provider, provider_sub)
    WHERE provider_sub IS NOT NULL`,
]);

export async function ensureIdentityResolutionSchema(client) {
  const found = await client.query(
    `SELECT COUNT(*)::int AS n FROM unnest($1::text[]) t(name) WHERE to_regclass('public.' || t.name) IS NOT NULL`,
    [IDENTITY_RESOLUTION_TABLES],
  );
  if (Number(found.rows?.[0]?.n) === IDENTITY_RESOLUTION_TABLES.length) return;
  for (const sql of IDENTITY_RESOLUTION_DDL) {
    await client.query(sql);
  }
}
