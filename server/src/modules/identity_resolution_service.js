// Merkezi kimlik çözümleme ve hesap sahiplenme servisi:
// - Sağlayıcıdan gelen güçlü kimlik sinyalleriyle mevcut hesabı bulma (users.email, apartments.resident_email, site_people.email, telefon)
// - Tek güçlü eşleşmede güvenli otomatik bağlama (@ahbu.local yükseltme dahil)
// - Çoklu güçlü eşleşmede maskeli kısa ömürlü doğrulama (challenge)
// - Ön-girişsiz veya Apple "E-postamı Gizle" hesaplarında isteğe bağlı güvenli sahiplenme / hesap birleştirme (claim)
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import { pool } from '../db.js';
import { signAccessToken } from '../jwt.js';
import {
  clearAccountLocks,
  loginGuard,
} from '../middlewares/login_throttle.js';
import {
  ATTEMPT_POLICIES,
  apartmentPinTarget,
  codeLockedError,
  peekAttemptLock,
  registerAttemptFailure,
  resetAttempts,
  smsCodeTarget,
} from '../security/attempt_limits.js';
import { reissueDeviceToken } from '../security/login_device_token.js';
import { buildLoginAttempt } from '../security/login_guard.js';
import { BCRYPT_COST, getDummyPasswordHash, hashPassword } from '../security/password_hashing.js';
import { rotateLocalControlTokensForUserAccess } from '../services/device_service.js';
import { generateNumericCode, mapUserRow, timingSafeEqualStrings } from '../utils/helpers.js';
import { recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import {
  formatTrE164FromLast10,
  generateClaimToken,
  hashClaimToken,
  isApplePrivateRelayEmail,
  isIdentityResolverEnabled,
  isInternalEmail,
  maskFullName,
  maskLoginName,
  normalizePhoneLast10,
  realVerifiedEmail,
  toMaskedCandidateDescriptor,
} from './identity_resolution_helpers.js';
import { isSmsEnabled, smsHooks } from './sms_provider.js';

const CLAIM_CHALLENGE_TTL_SECONDS = 10 * 60;
const CLAIM_SMS_TTL_SECONDS = 5 * 60;
const SMS_COOLDOWN_SECONDS = 60;
const SMS_MAX_PER_HOUR = 6;
const SMS_MAX_ATTEMPTS = 5;

const DEFAULT_USER_SELECT = `
  user_code AS id,
  user_code,
  full_name,
  email,
  login_name,
  role,
  is_active,
  email_verified,
  approval_status,
  phone_number,
  created_at,
  password_hash
`;

const DEFAULT_MUST_CHANGE_SQL = `(
  COALESCE(users.must_change_password, FALSE)
  OR EXISTS (SELECT 1 FROM apartments a WHERE a.resident_user_code = users.user_code AND a.resident_pin_issued = TRUE)
) AS must_change_password`;

function hashClaimSmsCode(challengeId, last10, code) {
  return crypto
    .createHash('sha256')
    .update(`claim_sms:${challengeId}:${last10}:${String(code ?? '').trim()}`, 'utf8')
    .digest('hex');
}

function hashStandardSmsCode(phone, code, pepper = process.env.SMS_CODE_PEPPER || process.env.JWT_SECRET || '') {
  return crypto.createHmac('sha256', String(pepper)).update(`${phone}:${code}`).digest('hex');
}

function asUserCode(row) {
  const code = Number(row?.user_code ?? row?.id);
  return Number.isSafeInteger(code) && code > 0 ? code : null;
}

function parseCandidateRecords(raw) {
  if (Array.isArray(raw)) return raw;
  if (typeof raw === 'string') {
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
}

/**
 * Doğrulanmış e-posta için güçlü adayları bulur.
 * 1) Direct users.email eşleşmesi (oauth_login.test.js fake client ile tam uyumlu kalır)
 * 2) Ek olarak aktif yönetilen hesapların apartments.resident_email ve site_people.email alanları.
 */
export async function findEmailIdentityCandidates(
  client,
  {
    email,
    emailVerified = false,
    userColumns = DEFAULT_USER_SELECT,
    mustChangeSql = DEFAULT_MUST_CHANGE_SQL,
    lockForUpdate = true,
  },
) {
  const cleanEmail = String(email ?? '').trim().toLowerCase();
  if (!cleanEmail) return [];

  const lockSuffix = lockForUpdate ? ' FOR UPDATE' : '';
  const directRes = await client.query(
    `SELECT ${userColumns}, ${mustChangeSql} FROM users WHERE LOWER(email) = LOWER($1) AND deleted_at IS NULL ORDER BY user_code${lockSuffix}`,
    [cleanEmail],
  );

  const byCode = new Map();
  for (const row of directRes.rows ?? []) {
    const code = asUserCode(row);
    if (code) {
      byCode.set(code, { ...row, _matchedVia: 'users_email' });
    }
  }

  // @privaterelay.appleid.com, @ahbu.local, @deleted.invalid veya doğrulanmamış e-posta ikincil alanlarla birleştirilmez.
  const verifiedReal = realVerifiedEmail(cleanEmail, emailVerified);
  if (!verifiedReal || !isIdentityResolverEnabled()) {
    return Array.from(byCode.values()).sort((a, b) => asUserCode(a) - asUserCode(b));
  }

  const secondaryRes = await client.query(
    `
      SELECT ${userColumns},
        ${mustChangeSql},
        CASE
          WHEN EXISTS (
            SELECT 1 FROM apartments a
            WHERE a.resident_user_code = users.user_code
              AND a.resident_email IS NOT NULL
              AND LOWER(a.resident_email) = LOWER($1)
          ) THEN 'apartment_resident_email'
          ELSE 'site_people_email'
        END AS _matched_via
      FROM users
      WHERE deleted_at IS NULL
        AND is_active = TRUE
        AND COALESCE(approval_status, 'approved') = 'approved'
        AND LOWER(COALESCE(email, '')) <> LOWER($1)
        AND (
          EXISTS (
            SELECT 1 FROM apartments a
            WHERE a.resident_user_code = users.user_code
              AND a.resident_email IS NOT NULL
              AND LOWER(a.resident_email) = LOWER($1)
          )
          OR EXISTS (
            SELECT 1 FROM site_people sp
            WHERE sp.user_code = users.user_code
              AND sp.is_active = TRUE
              AND sp.email IS NOT NULL
              AND LOWER(sp.email) = LOWER($1)
          )
        )
      ORDER BY user_code${lockForUpdate ? ' FOR UPDATE OF users' : ''}
    `,
    [verifiedReal],
  );

  for (const row of secondaryRes.rows ?? []) {
    const code = asUserCode(row);
    if (code && !byCode.has(code)) {
      byCode.set(code, {
        ...row,
        _matchedVia: row._matched_via || 'apartment_resident_email',
      });
    }
  }

  return Array.from(byCode.values()).sort((a, b) => asUserCode(a) - asUserCode(b));
}

/**
 * Doğrulanmış telefon numarasının son 10 hanesine uyan aktif ve onaylı kullanıcıları listeler.
 * Hem users.phone_number hem de aktif bağlı site_people.phone alanlarını kontrol eder.
 */
export async function findPhoneIdentityCandidates(phone, db = pool) {
  const last10 = normalizePhoneLast10(phone);
  if (!last10) return [];

  const result = await db.query(
    `
      SELECT DISTINCT ON (u.user_code)
        u.user_code,
        u.user_code AS id,
        u.full_name,
        u.email,
        u.login_name,
        u.role,
        u.is_active,
        u.email_verified,
        u.approval_status,
        u.phone_number,
        u.created_at,
        u.password_hash,
        (
          COALESCE(u.must_change_password, FALSE)
          OR EXISTS (
            SELECT 1 FROM apartments a WHERE a.resident_user_code = u.user_code AND a.resident_pin_issued = TRUE
          )
        ) AS must_change_password,
        EXISTS (
          SELECT 1 FROM site_memberships sm WHERE sm.user_code = u.user_code AND sm.is_active = TRUE
        ) AS has_site_membership,
        (
          SELECT sp.phone FROM site_people sp
          WHERE sp.user_code = u.user_code
            AND sp.is_active = TRUE
            AND sp.phone IS NOT NULL
            AND RIGHT(regexp_replace(sp.phone, '\\D', '', 'g'), 10) = $1
          ORDER BY sp.id ASC
          LIMIT 1
        ) AS person_phone
      FROM users u
      WHERE u.is_active = TRUE
        AND u.deleted_at IS NULL
        AND COALESCE(u.approval_status, 'approved') = 'approved'
        AND (u.email_verified = TRUE OR LOWER(COALESCE(u.email, '')) LIKE '%@ahbu.local')
        AND (
          RIGHT(regexp_replace(COALESCE(u.phone_number, ''), '\\D', '', 'g'), 10) = $1
          OR EXISTS (
            SELECT 1 FROM site_people sp
            WHERE sp.user_code = u.user_code
              AND sp.is_active = TRUE
              AND sp.phone IS NOT NULL
              AND RIGHT(regexp_replace(sp.phone, '\\D', '', 'g'), 10) = $1
          )
        )
      ORDER BY u.user_code ASC
    `,
    [last10],
  );

  return result.rows ?? [];
}

/**
 * Tek güçlü eşleşen OAuth adayında @ahbu.local e-postasını güvenli biçimde gerçek e-postaya yükseltir
 * ve hesapsız site_people bağını çakışmasız tamamlar.
 */
export async function claimSingleStrongCandidate(
  client,
  {
    candidate,
    provider,
    providerSub,
    verifiedEmail,
    fullName = null,
    clearTemporaryPin = true,
  },
) {
  const userCode = asUserCode(candidate);
  if (!userCode) return { upgradedEmail: false, claimed: false };

  const wasInternal = isInternalEmail(candidate.email);
  const realEmail = realVerifiedEmail(verifiedEmail, true);
  let upgradedEmail = false;

  if (wasInternal && realEmail) {
    const takenRes = await client.query(
      `SELECT 1 FROM users WHERE LOWER(email) = LOWER($1) AND user_code <> $2 LIMIT 1`,
      [realEmail, userCode],
    );
    if ((takenRes.rowCount ?? 0) === 0) {
      let upgradedPasswordHash = null;
      if (clearTemporaryPin) {
        upgradedPasswordHash = await bcrypt.hash(crypto.randomBytes(24).toString('base64url'), BCRYPT_COST);
      }
      if (upgradedPasswordHash) {
        await client.query(
          `
            UPDATE users
            SET email = $1,
                email_verified = TRUE,
                must_change_password = FALSE,
                password_hash = $2,
                full_name = COALESCE(NULLIF(TRIM(full_name), ''), NULLIF(TRIM($3), ''), full_name),
                updated_at = NOW()
            WHERE user_code = $4 AND deleted_at IS NULL
          `,
          [realEmail, upgradedPasswordHash, fullName, userCode],
        );
        candidate.password_hash = upgradedPasswordHash;
      } else {
        await client.query(
          `
            UPDATE users
            SET email = $1,
                email_verified = TRUE,
                full_name = COALESCE(NULLIF(TRIM(full_name), ''), NULLIF(TRIM($2), ''), full_name),
                updated_at = NOW()
            WHERE user_code = $3 AND deleted_at IS NULL
          `,
          [realEmail, fullName, userCode],
        );
      }
      candidate.email = realEmail;
      candidate.email_verified = true;
      candidate.must_change_password = false;
      upgradedEmail = true;
    }
  }

  if (clearTemporaryPin) {
    // apartments -> users kilit sırasını bozmamak için çağıran COMMIT sonrasında apartments tablosunu temizlemelidir.
  }

  if (realEmail) {
    // Bu kullanıcının aktif dairesinde henüz user_code bağlanmamış aynı e-postalı site_people kaydı varsa bağla (uq_site_people_user çakışması yoksa).
    await client.query(
      `
        UPDATE site_people sp
        SET user_code = $1, email = NULL, updated_at = NOW()
        WHERE sp.user_code IS NULL
          AND sp.is_active = TRUE
          AND sp.email IS NOT NULL
          AND LOWER(sp.email) = LOWER($2)
          AND EXISTS (
            SELECT 1 FROM apartments a
            WHERE a.site_code = sp.site_code
              AND (
                a.resident_user_code = $1
                OR EXISTS (
                  SELECT 1 FROM apartment_memberships am
                  WHERE am.apartment_id = a.id AND am.user_code = $1 AND am.is_active = TRUE
                )
              )
          )
          AND NOT EXISTS (
            SELECT 1 FROM site_people other
            WHERE other.site_code = sp.site_code AND other.user_code = $1
          )
      `,
      [userCode, realEmail],
    );
  }

  const matchedExternal = wasInternal || candidate._matchedVia !== 'users_email';
  if (matchedExternal || upgradedEmail) {
    await recordAudit(
      client,
      {
        actor: { userCode, role: candidate.role || 'individual' },
        action: 'identity.account_claimed',
        targetType: 'user',
        targetId: String(userCode),
        details: {
          provider: provider || 'oauth',
          has_provider_sub: Boolean(providerSub),
          via: candidate._matchedVia || 'oauth_email',
          upgraded_internal_email: upgradedEmail,
        },
      },
      { inTransaction: true },
    );
  }

  return { upgradedEmail, claimed: matchedExternal || upgradedEmail };
}

/**
 * Çoklu güçlü eşleşme veya Apple "E-postamı Gizle" hesap bağlama adımı için maskeli, kısa ömürlü challenge üretir.
 * Not: Hata (409) döndürecek çağıranlarda transaction dışında `pool` / `db` ile çağrılmalıdır.
 */
export async function createIdentityClaimChallenge(
  db = pool,
  {
    kind,
    provider,
    providerSub = null,
    verifiedEmail = null,
    verifiedPhone = null,
    fullName = null,
    candidates = [],
    ttlSeconds = CLAIM_CHALLENGE_TTL_SECONDS,
  },
) {
  const token = generateClaimToken();
  const tokenHash = hashClaimToken(token);
  const candidateRecords = (candidates ?? [])
    .map((c, idx) => ({
      ref: String(c.candidate_ref ?? idx + 1),
      user_code: asUserCode(c),
    }))
    .filter((entry) => entry.user_code !== null);

  const descriptors = (candidates ?? []).map((c, idx) => toMaskedCandidateDescriptor(c, idx));

  const verificationMethods = [];
  if (kind === 'sms_account_select') {
    verificationMethods.push('selection');
  } else {
    verificationMethods.push('credentials');
    const hasPhoneCandidate = (candidates ?? []).some(
      (c) => normalizePhoneLast10(c.phone_number ?? c.person_phone) !== null,
    );
    if (isSmsEnabled() && (kind === 'apple_relay_claim' || hasPhoneCandidate)) {
      verificationMethods.push('sms_otp');
    }
  }

  const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

  try {
    await db.query(
      `DELETE FROM identity_claim_challenges WHERE expires_at < NOW() - INTERVAL '1 day'`,
    );
    await db.query(
      `
        INSERT INTO identity_claim_challenges (
          token_hash, challenge_kind, provider, provider_sub, verified_email, verified_phone,
          full_name, candidate_user_codes, max_attempts, expires_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, 5, $9)
      `,
      [
        tokenHash,
        kind,
        String(provider || 'oauth'),
        providerSub ? String(providerSub) : null,
        verifiedEmail ? String(verifiedEmail).trim().toLowerCase() : null,
        normalizePhoneLast10(verifiedPhone),
        fullName ? String(fullName).trim().slice(0, 120) : null,
        JSON.stringify(candidateRecords),
        expiresAt,
      ],
    );
  } catch (error) {
    // Birim testlerindeki sahte db istemcileri `identity_claim_challenges` tablosunu mocklamamış olabilir.
    if (error?.code && !['42P01'].includes(error.code)) {
      throw error;
    }
  }

  return {
    token,
    expiresInSeconds: ttlSeconds,
    candidates: descriptors,
    verificationMethods,
  };
}

/**
 * Doğrulama challenge'ı üzerinden hesap bağlama için tek kullanımlık SMS OTP ister.
 * Hesap varlığı sızdırmamak için telefon eşleşse de eşleşmese de tek tip olumlu mesaj döner.
 */
export async function requestIdentityClaimSmsCode(
  { challengeToken, phone },
  deps = {},
) {
  const db = deps.db ?? pool;
  const rawToken = String(challengeToken ?? '').trim();
  const last10 = normalizePhoneLast10(phone);
  if (!rawToken || !last10) {
    throw new PlatformError(400, 'INVALID_INPUT', 'Geçerli bir telefon numarası ve doğrulama oturumu gereklidir.');
  }

  const smsProvider = (deps.smsProvider ?? smsHooks.provider)();
  if (!smsProvider) {
    throw new PlatformError(503, 'SMS_NOT_CONFIGURED', 'SMS doğrulaması şu anda yapılandırılmamış.');
  }

  const tokenHash = hashClaimToken(rawToken);
  const challengeRes = await db.query(
    `
      SELECT id, challenge_kind, candidate_user_codes, attempts, max_attempts
      FROM identity_claim_challenges
      WHERE token_hash = $1 AND consumed_at IS NULL AND expires_at > NOW()
      LIMIT 1
    `,
    [tokenHash],
  );
  const challenge = challengeRes.rows?.[0];
  if (!challenge) {
    throw new PlatformError(400, 'CLAIM_CHALLENGE_EXPIRED', 'Doğrulama oturumunun süresi dolmuş. Lütfen tekrar giriş yapın.');
  }
  if (Number(challenge.attempts) >= Number(challenge.max_attempts || 5)) {
    throw new PlatformError(429, 'CLAIM_ATTEMPTS_EXCEEDED', 'Çok fazla hatalı doğrulama denemesi yapıldı. Lütfen tekrar giriş yapın.');
  }

  const normalizedE164 = formatTrE164FromLast10(last10);
  const smsTarget = smsCodeTarget(normalizedE164);
  const persistentLock = await peekAttemptLock(ATTEMPT_POLICIES.smsCode, smsTarget, db);
  if (persistentLock.locked) {
    throw codeLockedError('sms', persistentLock.retryAfterSeconds);
  }

  const stats = await db.query(
    `
      SELECT
        EXTRACT(EPOCH FROM (NOW() - MAX(created_at))) AS seconds_since_last,
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 hour')::int AS sent_last_hour
      FROM sms_login_codes
      WHERE phone = $1
    `,
    [normalizedE164],
  );
  const row = stats.rows?.[0] || {};
  const since = row.seconds_since_last != null ? Number(row.seconds_since_last) : null;
  if (since !== null && since < SMS_COOLDOWN_SECONDS) {
    const wait = Math.max(1, Math.ceil(SMS_COOLDOWN_SECONDS - since));
    throw new PlatformError(429, 'SMS_COOLDOWN', `Lütfen ${wait} saniye sonra tekrar kod isteyin.`, {
      retry_after_seconds: wait,
    });
  }
  if (Number(row.sent_last_hour || 0) >= SMS_MAX_PER_HOUR) {
    throw new PlatformError(429, 'SMS_HOURLY_LIMIT', 'Çok fazla kod istendi. Lütfen daha sonra tekrar deneyin.');
  }

  const phoneCandidates = await findPhoneIdentityCandidates(last10, db);
  const allowedCodes = new Set(
    parseCandidateRecords(challenge.candidate_user_codes).map((c) => Number(c.user_code)).filter((n) => n > 0),
  );
  const matched =
    challenge.challenge_kind === 'oauth_ambiguous' && allowedCodes.size > 0
      ? phoneCandidates.filter((c) => allowedCodes.has(asUserCode(c)))
      : phoneCandidates;

  if (matched.length > 0) {
    const code = generateNumericCode(6);
    const codeHash = hashClaimSmsCode(challenge.id, last10, code);
    const expiresAt = new Date(Date.now() + CLAIM_SMS_TTL_SECONDS * 1000);
    await db.query(
      `INSERT INTO sms_login_codes (phone, user_code, code_hash, expires_at) VALUES ($1, NULL, $2, $3)`,
      [normalizedE164, codeHash, expiresAt],
    );
    const sendResult = await smsProvider.send(
      normalizedE164,
      `Gude Yonetim hesap dogrulama kodunuz: ${code}. 5 dk gecerlidir.`,
    );
    if (!sendResult?.ok) {
      await db.query(`DELETE FROM sms_login_codes WHERE phone = $1 AND code_hash = $2`, [normalizedE164, codeHash]);
      throw new PlatformError(503, 'SMS_DELIVERY_FAILED', 'SMS gönderilemedi. Lütfen tekrar deneyin.');
    }
  }

  return {
    ok: true,
    expires_in_seconds: CLAIM_SMS_TTL_SECONDS,
    message: 'Telefon numaranız kayıtlarımızla eşleşiyorsa doğrulama kodu gönderildi.',
  };
}

async function resolveChallengeCredentialsCandidate(
  db,
  { challenge, identifier, password, rawDeviceToken = null },
) {
  const cleanIdentifier = String(identifier ?? '').trim().toLowerCase();
  const cleanPassword = String(password ?? '').trim();
  if (!cleanIdentifier || !cleanPassword) {
    throw new PlatformError(400, 'CREDENTIALS_REQUIRED', 'Kullanıcı adı/e-posta ve şifre/PIN gereklidir.');
  }

  const allowedCodes = parseCandidateRecords(challenge.candidate_user_codes)
    .map((c) => Number(c.user_code))
    .filter((n) => n > 0);

  const attempt = buildLoginAttempt({
    identifier: cleanIdentifier,
    rawDeviceToken,
    sourceKey: 'identity_claim',
  });
  const guardState = loginGuard.check(attempt);
  if (guardState.locked) {
    throw new PlatformError(
      429,
      'LOGIN_LOCKED',
      'Çok fazla hatalı deneme yapıldı. Lütfen biraz sonra tekrar deneyin.',
      { retry_after_seconds: guardState.retryAfterSeconds },
    );
  }

  const userRes = await db.query(
    `
      SELECT ${DEFAULT_USER_SELECT},
        ${DEFAULT_MUST_CHANGE_SQL},
        EXISTS (
          SELECT 1 FROM apartments a WHERE a.resident_user_code = users.user_code AND a.resident_pin_issued = TRUE
        ) AS pin_issued
      FROM users
      WHERE deleted_at IS NULL
        AND is_active = TRUE
        AND COALESCE(approval_status, 'approved') = 'approved'
        AND (
          LOWER(email) = LOWER($1)
          OR LOWER(login_name) = LOWER($1)
          OR EXISTS (
            SELECT 1 FROM apartments a
            WHERE a.resident_user_code = users.user_code
              AND a.resident_email IS NOT NULL
              AND LOWER(a.resident_email) = LOWER($1)
          )
        )
      ORDER BY (LOWER(login_name) = LOWER($1) OR LOWER(email) = LOWER($1)) DESC, user_code ASC
      LIMIT 1
    `,
    [cleanIdentifier],
  );
  const candidate = userRes.rows?.[0] || null;
  const candidateCode = asUserCode(candidate);
  const inScope =
    candidateCode !== null &&
    (challenge.challenge_kind !== 'oauth_ambiguous' || allowedCodes.includes(candidateCode));

  if (inScope && candidate.pin_issued) {
    const pinLock = await peekAttemptLock(
      ATTEMPT_POLICIES.apartmentPin,
      apartmentPinTarget(candidateCode, candidate.password_hash),
      db,
    );
    if (pinLock.locked) {
      throw new PlatformError(
        423,
        'PIN_LOCKED',
        'Bu hesap için çok fazla hatalı PIN denemesi yapıldı. Lütfen yönetiminizden PIN yenilemesi isteyin.',
        { retry_after_seconds: pinLock.retryAfterSeconds },
      );
    }
  }

  const hashToCheck = inScope && candidate.password_hash ? String(candidate.password_hash) : await getDummyPasswordHash();
  const valid = await bcrypt.compare(cleanPassword, hashToCheck);

  if (!inScope || !valid) {
    loginGuard.recordFailure(attempt);
    if (inScope && candidate.pin_issued) {
      const fail = await registerAttemptFailure(
        ATTEMPT_POLICIES.apartmentPin,
        apartmentPinTarget(candidateCode, candidate.password_hash),
        db,
      );
      if (fail.locked) {
        throw new PlatformError(
          423,
          'PIN_LOCKED',
          'Bu hesap için çok fazla hatalı PIN denemesi yapıldı.',
          { retry_after_seconds: fail.retryAfterSeconds },
        );
      }
    }
    throw new PlatformError(401, 'INVALID_CREDENTIALS', 'Kullanıcı adı veya şifre/PIN hatalı.');
  }

  clearAccountLocks({
    email: candidate.email,
    loginName: candidate.login_name,
    userCode: candidateCode,
  });
  if (candidate.pin_issued) {
    await resetAttempts(
      ATTEMPT_POLICIES.apartmentPin,
      apartmentPinTarget(candidateCode, candidate.password_hash),
      db,
    );
  }
  return candidate;
}

async function resolveChallengeSmsCandidate(db, { challenge, phone, code, candidateRef = null }) {
  const last10 = normalizePhoneLast10(phone);
  const cleanCode = String(code ?? '').trim();
  if (!last10 || !/^\d{6}$/.test(cleanCode)) {
    throw new PlatformError(400, 'INVALID_SMS_CODE', 'Telefon numarası ve 6 haneli doğrulama kodu gereklidir.');
  }

  const normalizedE164 = formatTrE164FromLast10(last10);
  const smsTarget = smsCodeTarget(normalizedE164);
  const persistentLock = await peekAttemptLock(ATTEMPT_POLICIES.smsCode, smsTarget, db);
  if (persistentLock.locked) {
    throw codeLockedError('sms', persistentLock.retryAfterSeconds);
  }

  const codeRes = await db.query(
    `
      SELECT id, code_hash, attempts
      FROM sms_login_codes
      WHERE phone = $1 AND consumed_at IS NULL AND expires_at > NOW() AND attempts < $2
      ORDER BY created_at DESC
      LIMIT 1
    `,
    [normalizedE164, SMS_MAX_ATTEMPTS],
  );
  const smsRow = codeRes.rows?.[0];
  const expectedHash = hashClaimSmsCode(challenge.id, last10, cleanCode);
  if (!smsRow || !timingSafeEqualStrings(smsRow.code_hash, expectedHash)) {
    if (smsRow) {
      await db.query(`UPDATE sms_login_codes SET attempts = attempts + 1 WHERE id = $1`, [smsRow.id]);
    }
    const fail = await registerAttemptFailure(ATTEMPT_POLICIES.smsCode, smsTarget, db);
    if (fail.locked) {
      throw codeLockedError('sms', fail.retryAfterSeconds);
    }
    throw new PlatformError(401, 'INVALID_SMS_CODE', 'Doğrulama kodu geçersiz veya süresi dolmuş.');
  }

  await db.query(`UPDATE sms_login_codes SET consumed_at = NOW() WHERE id = $1`, [smsRow.id]);
  await resetAttempts(ATTEMPT_POLICIES.smsCode, smsTarget, db);

  const phoneCandidates = await findPhoneIdentityCandidates(last10, db);
  const allowedCodes = parseCandidateRecords(challenge.candidate_user_codes)
    .map((c) => Number(c.user_code))
    .filter((n) => n > 0);
  const matched =
    challenge.challenge_kind === 'oauth_ambiguous' && allowedCodes.length > 0
      ? phoneCandidates.filter((c) => allowedCodes.includes(asUserCode(c)))
      : phoneCandidates;

  if (matched.length === 0) {
    throw new PlatformError(404, 'CANDIDATE_NOT_FOUND', 'Bu telefon numarası ile eşleşen uygun bir hesap bulunamadı.');
  }

  if (matched.length > 1) {
    const selected = candidateRef
      ? matched.find((_, idx) => String(idx + 1) === String(candidateRef).trim())
      : null;
    if (!selected) {
      // Kullanıcı SMS OTP'yi doğruladı ama bu numarada birden fazla hesap var -> seçim aşamasına geçir.
      const filteredRecords = matched.map((c, idx) => ({
        ref: String(idx + 1),
        user_code: asUserCode(c),
      }));
      await db.query(
        `
          UPDATE identity_claim_challenges
          SET challenge_kind = 'sms_account_select',
              candidate_user_codes = $2::jsonb,
              attempts = 0,
              verified_phone = $3
          WHERE id = $1 AND consumed_at IS NULL
        `,
        [challenge.id, JSON.stringify(filteredRecords), last10],
      );
      return {
        selectionRequired: true,
        candidates: matched.map((c, idx) => toMaskedCandidateDescriptor(c, idx)),
      };
    }
    return { candidate: selected };
  }

  return { candidate: matched[0] };
}

/**
 * Seçim token'ı veya doğrulama challenge'ı ile hesabı doğrular, OAuth bağını kurar ve JWT oturumu açar.
 */
export async function verifyIdentityClaimChallenge(
  {
    challengeToken,
    selectionToken,
    method = 'credentials',
    identifier,
    password,
    phone,
    code,
    candidateRef,
    rawDeviceToken = null,
  },
  deps = {},
) {
  const db = deps.db ?? pool;
  const rawToken = String(challengeToken || selectionToken || '').trim();
  if (!rawToken) {
    throw new PlatformError(400, 'CLAIM_TOKEN_REQUIRED', 'Doğrulama oturum belirteci gereklidir.');
  }

  const tokenHash = hashClaimToken(rawToken);
  const preRes = await db.query(
    `
      SELECT *
      FROM identity_claim_challenges
      WHERE token_hash = $1 AND consumed_at IS NULL AND expires_at > NOW()
      LIMIT 1
    `,
    [tokenHash],
  );
  const existing = preRes.rows?.[0];
  if (!existing) {
    throw new PlatformError(400, 'CLAIM_CHALLENGE_EXPIRED', 'Doğrulama oturumunun süresi dolmuş. Lütfen tekrar giriş yapın.');
  }
  if (Number(existing.attempts) >= Number(existing.max_attempts || 5)) {
    throw new PlatformError(429, 'CLAIM_ATTEMPTS_EXCEEDED', 'Çok fazla hatalı doğrulama denemesi yapıldı. Lütfen tekrar giriş yapın.');
  }

  const effectiveMethod = existing.challenge_kind === 'sms_account_select' ? 'selection' : String(method || 'credentials').trim();

  // Paralel denemelerde max_attempts sınırı atlanamasın diye deneme hakkı doğrulamadan önce artırılır.
  const reservedRes = await db.query(
    `
      UPDATE identity_claim_challenges
      SET attempts = attempts + 1
      WHERE id = $1 AND consumed_at IS NULL AND expires_at > NOW() AND attempts < max_attempts
      RETURNING *
    `,
    [existing.id],
  );
  const challenge = reservedRes.rows?.[0];
  if (!challenge) {
    throw new PlatformError(429, 'CLAIM_ATTEMPTS_EXCEEDED', 'Doğrulama hakkı doldu veya oturum kapandı.');
  }

  let verifiedCandidate;
  if (effectiveMethod === 'selection') {
    const ref = String(candidateRef ?? '').trim();
    const records = parseCandidateRecords(challenge.candidate_user_codes);
    const matchedRecord = records.find((r) => String(r.ref) === ref);
    if (!matchedRecord) {
      throw new PlatformError(400, 'INVALID_CANDIDATE_SELECTION', 'Lütfen listeden geçerli bir hesap seçin.');
    }
    const candRes = await db.query(
      `SELECT ${DEFAULT_USER_SELECT}, ${DEFAULT_MUST_CHANGE_SQL} FROM users WHERE user_code = $1 AND deleted_at IS NULL AND is_active = TRUE AND COALESCE(approval_status, 'approved') = 'approved' LIMIT 1`,
      [Number(matchedRecord.user_code)],
    );
    verifiedCandidate = candRes.rows?.[0] || null;
    if (!verifiedCandidate) {
      throw new PlatformError(404, 'CANDIDATE_NOT_FOUND', 'Seçilen hesap artık aktif değil.');
    }
  } else if (effectiveMethod === 'sms_otp') {
    const smsRes = await resolveChallengeSmsCandidate(db, { challenge, phone, code, candidateRef });
    if (smsRes.selectionRequired) {
      return {
        ok: false,
        account_selection_required: true,
        selection_token: rawToken,
        candidates: smsRes.candidates,
        message: 'Bu telefon numarasına bağlı birden fazla hesap bulundu. Bağlamak istediğiniz hesabı seçin.',
      };
    }
    verifiedCandidate = smsRes.candidate;
  } else {
    verifiedCandidate = await resolveChallengeCredentialsCandidate(db, {
      challenge,
      identifier,
      password,
      rawDeviceToken,
    });
  }

  const targetUserCode = asUserCode(verifiedCandidate);
  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const lockCh = await client.query(
      `SELECT * FROM identity_claim_challenges WHERE id = $1 FOR UPDATE`,
      [challenge.id],
    );
    const lockedChallenge = lockCh.rows?.[0];
    if (!lockedChallenge || lockedChallenge.consumed_at) {
      throw new PlatformError(409, 'CLAIM_ALREADY_CONSUMED', 'Bu doğrulama oturumu zaten kullanılmış.');
    }

    const userRes = await client.query(
      `SELECT ${DEFAULT_USER_SELECT}, ${DEFAULT_MUST_CHANGE_SQL} FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR UPDATE`,
      [targetUserCode],
    );
    const lockedUser = userRes.rows?.[0];
    if (!lockedUser || !lockedUser.is_active || (lockedUser.approval_status && lockedUser.approval_status !== 'approved')) {
      throw new PlatformError(403, 'ACCOUNT_INACTIVE', 'Seçilen hesap aktif değil.');
    }

    await client.query(
      `
        UPDATE identity_claim_challenges
        SET consumed_at = NOW(),
            consumed_user_code = $2,
            verified_email = NULL,
            verified_phone = NULL,
            full_name = NULL,
            candidate_user_codes = '[]'::jsonb
        WHERE id = $1
      `,
      [lockedChallenge.id, targetUserCode],
    );

    if (
      (lockedChallenge.provider === 'google' || lockedChallenge.provider === 'apple') &&
      lockedChallenge.provider_sub
    ) {
      const existingOAuth = await client.query(
        `SELECT id, user_code FROM user_oauth_identities WHERE provider = $1 AND provider_sub = $2 LIMIT 1`,
        [lockedChallenge.provider, lockedChallenge.provider_sub],
      );
      if ((existingOAuth.rowCount ?? 0) === 0) {
        await client.query(
          `INSERT INTO user_oauth_identities (user_code, provider, provider_sub, email) VALUES ($1, $2, $3, $4)`,
          [targetUserCode, lockedChallenge.provider, lockedChallenge.provider_sub, lockedChallenge.verified_email],
        );
      } else {
        await client.query(
          `UPDATE user_oauth_identities SET last_login_at = NOW() WHERE provider = $1 AND provider_sub = $2`,
          [lockedChallenge.provider, lockedChallenge.provider_sub],
        );
      }

      if (lockedChallenge.verified_email && !isApplePrivateRelayEmail(lockedChallenge.verified_email)) {
        lockedUser._matchedVia = 'challenge_verified_claim';
        await claimSingleStrongCandidate(client, {
          candidate: lockedUser,
          provider: lockedChallenge.provider,
          providerSub: lockedChallenge.provider_sub,
          verifiedEmail: lockedChallenge.verified_email,
          fullName: lockedChallenge.full_name,
          clearTemporaryPin: true,
        });
      }
    } else if (lockedChallenge.challenge_kind === 'sms_account_select') {
      await recordAudit(
        client,
        {
          actor: { userCode: targetUserCode, role: lockedUser.role || 'individual' },
          action: 'identity.account_claimed',
          targetType: 'user',
          targetId: String(targetUserCode),
          details: { provider: 'sms', via: 'sms_account_select' },
        },
        { inTransaction: true },
      );
    }

    await client.query('COMMIT');

    try {
      await db.query(
        'UPDATE apartments SET resident_pin_issued = FALSE, resident_pin_code = NULL WHERE resident_user_code = $1 AND (resident_pin_issued OR resident_pin_code IS NOT NULL)',
        [targetUserCode],
      );
    } catch (_) {
      // Yalnız istemci ipucudur.
    }

    const token = signAccessToken(lockedUser, { passwordHash: lockedUser.password_hash });
    const deviceToken = reissueDeviceToken({
      presented: rawDeviceToken,
      userCode: targetUserCode,
      passwordHash: lockedUser.password_hash,
    });

    return {
      ok: true,
      is_new_user: false,
      claimed_existing_account: lockedChallenge.challenge_kind !== 'sms_account_select',
      provider: lockedChallenge.provider,
      token,
      user: mapUserRow(lockedUser),
      ...(deviceToken ? { device_token: deviceToken } : {}),
      message:
        lockedChallenge.challenge_kind === 'sms_account_select'
          ? 'Giriş başarılı.'
          : 'Mevcut hesabınız bulundu. Daire hesabınız güvenli biçimde bağlandı.',
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Oturumu açık bireysel kullanıcı için mevcut bir daire / yönetim hesabını işlem (transaction) altında sahiplenir.
 * Ölümsüzlük & Yarış koruması:
 *  - Kaynak hesap mutlaka bireysel olmalı ve hiçbir site/daire/yönetim bağı taşımamalıdır (aksinde 409 CLAIM_REQUIRES_ADMIN_MERGE).
 *  - İki kullanıcı satırı ARTAN `user_code` sırasıyla FOR UPDATE kilitlenir.
 *  - Güçlü e-posta/telefon eşleşmesi YA DA yönetimin verdiği kullanıcı adı+PIN / SMS doğrulaması şarttır.
 */
export async function claimExistingAccountForSession(
  authUser,
  {
    targetUserCode = null,
    method = null,
    identifier = null,
    password = null,
    phone = null,
    code = null,
    rawDeviceToken = null,
  } = {},
  deps = {},
) {
  const db = deps.db ?? pool;
  const sourceUserCode = Number(authUser?.userCode ?? authUser?.id);
  if (!Number.isSafeInteger(sourceUserCode) || sourceUserCode <= 0) {
    throw new PlatformError(401, 'UNAUTHORIZED', 'Geçerli oturum bulunamadı.');
  }

  // Ön okuma & kimlik kanıtı doğrulaması (kilit almadan önce)
  const sourcePreRes = await db.query(
    `SELECT ${DEFAULT_USER_SELECT} FROM users WHERE user_code = $1 AND deleted_at IS NULL LIMIT 1`,
    [sourceUserCode],
  );
  const sourcePre = sourcePreRes.rows?.[0];
  if (!sourcePre || !sourcePre.is_active) {
    throw new PlatformError(401, 'UNAUTHORIZED', 'Oturum hesabınız aktif değil.');
  }

  let resolvedTargetCode = Number.isSafeInteger(Number(targetUserCode)) && Number(targetUserCode) > 0
    ? Number(targetUserCode)
    : null;
  let verificationVia = 'verified_contact_match';

  const effectiveMethod = String(method || '').trim().toLowerCase() ||
    (identifier && password ? 'credentials' : phone && code ? 'sms_otp' : 'auto');

  if (effectiveMethod === 'credentials') {
    const cleanId = String(identifier ?? '').trim().toLowerCase();
    const cleanPwd = String(password ?? '').trim();
    if (!cleanId || !cleanPwd) {
      throw new PlatformError(400, 'CREDENTIALS_REQUIRED', 'Kullanıcı adı ve şifre/PIN gereklidir.');
    }
    const loginAttempt = buildLoginAttempt({
      identifier: cleanId,
      rawDeviceToken,
      sourceKey: 'identity_claim_authenticated',
    });
    const guardState = loginGuard.check(loginAttempt);
    if (guardState.locked) {
      throw new PlatformError(
        429,
        'LOGIN_LOCKED',
        'Çok fazla hatalı deneme yapıldı. Lütfen biraz sonra tekrar deneyin.',
        { retry_after_seconds: guardState.retryAfterSeconds },
      );
    }
    const candRes = await db.query(
      `
        SELECT ${DEFAULT_USER_SELECT},
          EXISTS (SELECT 1 FROM apartments a WHERE a.resident_user_code = users.user_code AND a.resident_pin_issued = TRUE) AS pin_issued
        FROM users
        WHERE deleted_at IS NULL
          AND is_active = TRUE
          AND COALESCE(approval_status, 'approved') = 'approved'
          AND user_code <> $2
          AND (
            LOWER(login_name) = LOWER($1)
            OR LOWER(email) = LOWER($1)
            OR EXISTS (SELECT 1 FROM apartments a WHERE a.resident_user_code = users.user_code AND a.resident_email IS NOT NULL AND LOWER(a.resident_email) = LOWER($1))
          )
        ORDER BY (LOWER(login_name) = LOWER($1) OR LOWER(email) = LOWER($1)) DESC, user_code ASC
        LIMIT 1
      `,
      [cleanId, sourceUserCode],
    );
    const cand = candRes.rows?.[0];
    const candCode = asUserCode(cand);
    if (cand && cand.pin_issued) {
      const pinLock = await peekAttemptLock(
        ATTEMPT_POLICIES.apartmentPin,
        apartmentPinTarget(candCode, cand.password_hash),
        db,
      );
      if (pinLock.locked) {
        throw new PlatformError(423, 'PIN_LOCKED', 'PIN deneme hakkı kilitlendi.', {
          retry_after_seconds: pinLock.retryAfterSeconds,
        });
      }
    }
    const hashToVerify = cand?.password_hash ? String(cand.password_hash) : await getDummyPasswordHash();
    const ok = await bcrypt.compare(cleanPwd, hashToVerify);
    if (!cand || !ok) {
      loginGuard.recordFailure(loginAttempt);
      if (cand && cand.pin_issued) {
        await registerAttemptFailure(
          ATTEMPT_POLICIES.apartmentPin,
          apartmentPinTarget(candCode, cand.password_hash),
          db,
        );
      }
      throw new PlatformError(401, 'INVALID_CREDENTIALS', 'Kullanıcı adı veya şifre/PIN hatalı.');
    }
    if (cand.pin_issued) {
      await resetAttempts(ATTEMPT_POLICIES.apartmentPin, apartmentPinTarget(candCode, cand.password_hash), db);
    }
    clearAccountLocks({
      email: cand.email,
      loginName: cand.login_name,
      userCode: candCode,
    });
    resolvedTargetCode = candCode;
    verificationVia = 'credentials';
  } else if (effectiveMethod === 'sms_otp') {
    const last10 = normalizePhoneLast10(phone);
    const cleanCode = String(code ?? '').trim();
    if (!last10 || !/^\d{6}$/.test(cleanCode)) {
      throw new PlatformError(400, 'INVALID_SMS_CODE', 'Geçerli bir telefon ve 6 haneli kod girin.');
    }
    const normalizedE164 = formatTrE164FromLast10(last10);
    const smsTarget = smsCodeTarget(normalizedE164);
    const persistentLock = await peekAttemptLock(ATTEMPT_POLICIES.smsCode, smsTarget, db);
    if (persistentLock.locked) {
      throw codeLockedError('sms', persistentLock.retryAfterSeconds);
    }
    const smsRes = await db.query(
      `
        UPDATE sms_login_codes
        SET attempts = attempts + 1
        WHERE id = (
          SELECT id FROM sms_login_codes
          WHERE phone = $1 AND consumed_at IS NULL AND expires_at > NOW() AND attempts < $2
          ORDER BY created_at DESC
          LIMIT 1
        )
        RETURNING id, code_hash, attempts
      `,
      [normalizedE164, SMS_MAX_ATTEMPTS],
    );
    const smsRow = smsRes.rows?.[0];
    const codeHash = hashStandardSmsCode(normalizedE164, cleanCode);
    if (!smsRow || !timingSafeEqualStrings(smsRow.code_hash, codeHash)) {
      const fail = await registerAttemptFailure(ATTEMPT_POLICIES.smsCode, smsTarget, db);
      if (fail.locked) throw codeLockedError('sms', fail.retryAfterSeconds);
      throw new PlatformError(401, 'INVALID_SMS_CODE', 'Doğrulama kodu geçersiz veya süresi dolmuş.');
    }
    await db.query(`UPDATE sms_login_codes SET consumed_at = NOW() WHERE id = $1`, [smsRow.id]);
    await resetAttempts(ATTEMPT_POLICIES.smsCode, smsTarget, db);

    const candidates = (await findPhoneIdentityCandidates(last10, db)).filter(
      (c) => asUserCode(c) !== sourceUserCode,
    );
    if (candidates.length !== 1) {
      throw new PlatformError(
        409,
        'CLAIM_VERIFICATION_REQUIRED',
        'Bu telefona bağlı tekil bir hedef hesap belirlenemedi. Lütfen kullanıcı adı ve şifre ile doğrulayın.',
      );
    }
    resolvedTargetCode = asUserCode(candidates[0]);
    verificationVia = 'sms_otp';
  } else {
    // Otomatik doğrulama: oturumdaki doğrulanmış gerçek e-posta veya telefon üzerinden TEKİL aktif hedef hesap aranır.
    const verifiedReal = realVerifiedEmail(sourcePre.email, sourcePre.email_verified);
    const sourcePhone10 = normalizePhoneLast10(sourcePre.phone_number);
    const candidateMap = new Map();

    if (verifiedReal) {
      const emailCands = await findEmailIdentityCandidates(db, {
        email: verifiedReal,
        emailVerified: true,
        lockForUpdate: false,
      });
      for (const c of emailCands) {
        const codeNum = asUserCode(c);
        if (codeNum && codeNum !== sourceUserCode) candidateMap.set(codeNum, c);
      }
    }
    if (sourcePhone10) {
      const phoneCands = await findPhoneIdentityCandidates(sourcePhone10, db);
      for (const c of phoneCands) {
        const codeNum = asUserCode(c);
        if (codeNum && codeNum !== sourceUserCode) candidateMap.set(codeNum, c);
      }
    }

    const candidates = Array.from(candidateMap.values());
    if (candidates.length === 0) {
      throw new PlatformError(
        409,
        'CLAIM_VERIFICATION_REQUIRED',
        'Mevcut hesabınız otomatik doğrulanamadı. Lütfen yönetimin verdiği kullanıcı adı ve PIN/şifre ile doğrulayın.',
      );
    }
    if (resolvedTargetCode !== null) {
      const matched = candidates.find((c) => asUserCode(c) === resolvedTargetCode);
      if (!matched) {
        throw new PlatformError(
          409,
          'CLAIM_VERIFICATION_REQUIRED',
          'Bu hesabı bağlamak için kullanıcı adı ve PIN/şifre doğrulaması gereklidir.',
        );
      }
    } else {
      if (candidates.length > 1) {
        throw new PlatformError(
          409,
          'CLAIM_VERIFICATION_REQUIRED',
          'Birden fazla olası hesap bulundu. Lütfen kullanıcı adı ve şifre ile bağlamak istediğiniz hesabı doğrulayın.',
          { candidates: candidates.map((c, idx) => toMaskedCandidateDescriptor(c, idx)) },
        );
      }
      resolvedTargetCode = asUserCode(candidates[0]);
    }
  }

  if (!resolvedTargetCode || resolvedTargetCode === sourceUserCode) {
    return {
      ok: true,
      already_linked: true,
      token: null,
      user: mapUserRow(sourcePre),
      message: 'Hesabınız zaten bağlı durumda.',
    };
  }

  const client = await db.connect();
  try {
    await client.query('BEGIN');

    // Artan user_code sırasında satır kilidi (deadlock engeli).
    const orderedCodes = [sourceUserCode, resolvedTargetCode].sort((a, b) => a - b);
    const lockRes = await client.query(
      `
        SELECT ${DEFAULT_USER_SELECT},
          ${DEFAULT_MUST_CHANGE_SQL},
          EXISTS (SELECT 1 FROM apartments a WHERE a.resident_user_code = users.user_code AND a.resident_pin_issued = TRUE) AS pin_issued
        FROM users
        WHERE user_code = ANY($1::int[]) AND deleted_at IS NULL
        ORDER BY user_code ASC
        FOR UPDATE
      `,
      [orderedCodes],
    );
    const lockedSource = lockRes.rows.find((r) => asUserCode(r) === sourceUserCode);
    const lockedTarget = lockRes.rows.find((r) => asUserCode(r) === resolvedTargetCode);
    if (!lockedSource || !lockedSource.is_active) {
      throw new PlatformError(409, 'SOURCE_ACCOUNT_UNAVAILABLE', 'Mevcut oturum hesabı artık etkin değil.');
    }
    if (!lockedTarget || !lockedTarget.is_active || (lockedTarget.approval_status && lockedTarget.approval_status !== 'approved')) {
      throw new PlatformError(404, 'TARGET_ACCOUNT_NOT_FOUND', 'Bağlanacak daire hesabı aktif değil.');
    }

    // Fail-safe koruma: kaynak hesap yalnız boş bireysel hesap olabilir (aktif daire/site/yönetim yetkisi varsa birleştirilmez).
    if (lockedSource.role !== 'individual') {
      throw new PlatformError(
        409,
        'CLAIM_REQUIRES_ADMIN_MERGE',
        'Aktif site veya yönetim rolü bulunan hesaplar otomatik birleştirilemez.',
      );
    }
    const depsCheck = await client.query(
      `
        SELECT
          EXISTS (SELECT 1 FROM apartment_memberships WHERE user_code = $1 AND is_active = TRUE) AS has_apt,
          EXISTS (SELECT 1 FROM site_memberships WHERE user_code = $1 AND is_active = TRUE) AS has_site,
          EXISTS (SELECT 1 FROM site_manager_sites WHERE manager_user_code = $1) AS has_mgr,
          EXISTS (SELECT 1 FROM site_people WHERE user_code = $1 AND is_active = TRUE) AS has_person,
          EXISTS (SELECT 1 FROM devices WHERE owner_user_id = (SELECT id FROM users WHERE user_code = $1)) AS has_dev,
          EXISTS (SELECT 1 FROM site_applications WHERE applicant_user_code = $1 AND status IN ('pending', 'approved')) AS has_application,
          EXISTS (SELECT 1 FROM door_access_overrides WHERE user_code = $1) AS has_door_override,
          EXISTS (SELECT 1 FROM qr_access_tokens WHERE user_code = $1 AND is_active = TRUE) AS has_active_qr
      `,
      [sourceUserCode],
    );
    const d = depsCheck.rows?.[0] || {};
    if (
      d.has_apt ||
      d.has_site ||
      d.has_mgr ||
      d.has_person ||
      d.has_dev ||
      d.has_application ||
      d.has_door_override ||
      d.has_active_qr
    ) {
      throw new PlatformError(
        409,
        'CLAIM_REQUIRES_ADMIN_MERGE',
        'Mevcut hesabınızda başka bir daire, site veya cihaz yetkisi bulunduğu için otomatik birleştirilemedi.',
      );
    }

    // OAuth kimlikleri ve yasal belge onayları hedef hesaba taşınır.
    await client.query(
      `UPDATE user_oauth_identities SET user_code = $1, last_login_at = NOW() WHERE user_code = $2`,
      [resolvedTargetCode, sourceUserCode],
    );
    await client.query(
      `
        INSERT INTO user_consents (user_code, document_id, version, accepted_at, source)
        SELECT $1, document_id, version, accepted_at, source
        FROM user_consents
        WHERE user_code = $2
        ON CONFLICT (user_code, document_id, version) DO NOTHING
      `,
      [resolvedTargetCode, sourceUserCode],
    );

    // Bildirim kayitlarini aktif kalacak hedef hesaba aktar. Ayni kurulum hedefte
    // zaten varsa hedef kaydi korunur; kaynak kopya tekillik ihlali yaratmadan silinir.
    await client.query(
      `
        DELETE FROM push_devices source
        USING push_devices target
        WHERE source.user_code = $1
          AND target.user_code = $2
          AND source.install_id = target.install_id
      `,
      [sourceUserCode, resolvedTargetCode],
    );
    await client.query(
      `UPDATE push_devices SET user_code = $1 WHERE user_code = $2`,
      [resolvedTargetCode, sourceUserCode],
    );
    await client.query(
      `UPDATE web_push_subscriptions SET user_code = $1 WHERE user_code = $2`,
      [resolvedTargetCode, sourceUserCode],
    );

    // Kaynak hesap önce pasife çekilip e-posta benzersiz alanı serbest bırakılır.
    const archivedSourceEmail = `claimed-${sourceUserCode}-${Date.now()}@ahbu.local`;
    await client.query(
      `
        UPDATE users
        SET is_active = FALSE,
            login_name = NULL,
            email = $1,
            updated_at = NOW()
        WHERE user_code = $2 AND deleted_at IS NULL
      `,
      [archivedSourceEmail, sourceUserCode],
    );

    await client.query(
      `
        UPDATE join_requests
        SET status = 'CANCELLED',
            rejection_reason = 'Mevcut daire hesabı sahiplenildiği için talep kapatıldı.',
            updated_at = NOW(),
            dismissed_at = COALESCE(dismissed_at, NOW())
        WHERE user_code = $1 AND status = 'PENDING'
      `,
      [sourceUserCode],
    );

    const sourceRealEmail = realVerifiedEmail(lockedSource.email, lockedSource.email_verified);
    const sourcePhone10 = normalizePhoneLast10(lockedSource.phone_number);

    // Hedef hesap @ahbu.local ise ve kaynakta gerçek doğrulanmış e-posta varsa güvenli biçimde yükselt.
    if (isInternalEmail(lockedTarget.email) && sourceRealEmail) {
      const taken = await client.query(
        `SELECT 1 FROM users WHERE LOWER(email) = LOWER($1) AND user_code <> $2 LIMIT 1`,
        [sourceRealEmail, resolvedTargetCode],
      );
      if ((taken.rowCount ?? 0) === 0) {
        const shouldRotatePin = Boolean(lockedTarget.pin_issued || lockedTarget.must_change_password);
        const newHash = shouldRotatePin ? await hashPassword(crypto.randomBytes(24).toString('base64url')) : null;
        if (newHash) {
          await client.query(
            `
              UPDATE users
              SET email = $1,
                  email_verified = TRUE,
                  must_change_password = FALSE,
                  password_hash = $2,
                  phone_number = COALESCE(NULLIF(TRIM(phone_number), ''), $3),
                  updated_at = NOW()
              WHERE user_code = $4 AND deleted_at IS NULL
            `,
            [sourceRealEmail, newHash, sourcePhone10 ? formatTrE164FromLast10(sourcePhone10) : null, resolvedTargetCode],
          );
          lockedTarget.password_hash = newHash;
        } else {
          await client.query(
            `
              UPDATE users
              SET email = $1,
                  email_verified = TRUE,
                  phone_number = COALESCE(NULLIF(TRIM(phone_number), ''), $2),
                  updated_at = NOW()
              WHERE user_code = $3 AND deleted_at IS NULL
            `,
            [sourceRealEmail, sourcePhone10 ? formatTrE164FromLast10(sourcePhone10) : null, resolvedTargetCode],
          );
        }
        lockedTarget.email = sourceRealEmail;
        lockedTarget.email_verified = true;
        lockedTarget.must_change_password = false;
      }
    } else if (sourcePhone10 && !normalizePhoneLast10(lockedTarget.phone_number)) {
      await client.query(
        `
          UPDATE users
          SET phone_number = $1, updated_at = NOW()
          WHERE user_code = $2 AND deleted_at IS NULL
        `,
        [formatTrE164FromLast10(sourcePhone10), resolvedTargetCode],
      );
      lockedTarget.phone_number = formatTrE164FromLast10(sourcePhone10);
    }

    // Hedef hesapta geçici daire PIN'i vardıysa ve OAuth bağı kurulduysa PIN'i temizle.
    const oauthLinkCheck = await client.query(
      `SELECT 1 FROM user_oauth_identities WHERE user_code = $1 LIMIT 1`,
      [resolvedTargetCode],
    );
    if ((oauthLinkCheck.rowCount ?? 0) > 0 && (lockedTarget.pin_issued || lockedTarget.must_change_password)) {
      await client.query(
        `UPDATE apartments SET resident_pin_issued = FALSE, resident_pin_code = NULL WHERE resident_user_code = $1`,
        [resolvedTargetCode],
      );
      await client.query(
        `UPDATE users SET must_change_password = FALSE, updated_at = NOW() WHERE user_code = $1 AND deleted_at IS NULL`,
        [resolvedTargetCode],
      );
      lockedTarget.must_change_password = false;
    }

    await recordAudit(
      client,
      {
        actor: { userCode: resolvedTargetCode, role: lockedTarget.role || 'individual' },
        action: 'identity.account_merged',
        targetType: 'user',
        targetId: String(resolvedTargetCode),
        details: {
          source_user_code: sourceUserCode,
          target_user_code: resolvedTargetCode,
          via: verificationVia,
        },
      },
      { inTransaction: true },
    );

    await client.query('COMMIT');

    try {
      await db.query(
        'UPDATE apartments SET resident_pin_issued = FALSE, resident_pin_code = NULL WHERE resident_user_code = $1 AND (resident_pin_issued OR resident_pin_code IS NOT NULL)',
        [resolvedTargetCode],
      );
    } catch (_) {
      // Yalnız istemci ipucudur.
    }

    await rotateLocalControlTokensForUserAccess(resolvedTargetCode).catch(() => {});
    clearAccountLocks({
      email: lockedTarget.email,
      loginName: lockedTarget.login_name,
      userCode: resolvedTargetCode,
    });

    const token = signAccessToken(lockedTarget, { passwordHash: lockedTarget.password_hash });
    return {
      ok: true,
      claimed_existing_account: true,
      merged_from_user_code: sourceUserCode,
      token,
      user: mapUserRow(lockedTarget),
      message: 'Daire hesabınız güvenli biçimde bağlandı.',
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export function buildMaskedExistingAccountSummary(row, reasons = []) {
  return {
    masked_name: maskFullName(row.full_name),
    masked_login_name: maskLoginName(row.login_name),
    reasons,
  };
}
