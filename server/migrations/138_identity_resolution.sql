-- 138: Merkezi kimlik cozumleme ve hesap sahiplenme dogrulama meydan okumalari.
-- db.js (identity_resolution_schema.js) ile ayni DDL; ekleyici, idempotent, FK'siz.
CREATE TABLE IF NOT EXISTS identity_claim_challenges (
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
);

CREATE INDEX IF NOT EXISTS idx_identity_claim_challenges_expires
  ON identity_claim_challenges (expires_at);

CREATE INDEX IF NOT EXISTS idx_identity_claim_challenges_sub
  ON identity_claim_challenges (provider, provider_sub)
  WHERE provider_sub IS NOT NULL;
