// Telefon + SMS koduyla giris. 6 hane, 5 dk gecerli, kod basina en cok 5 deneme, telefon basina 15 dk'da en cok 3 kod. SMS kapaliysa 503 SMS_UNAVAILABLE.
// Kullanici varligi sizmaz: kayitli/kayitsiz telefon ayni 200 yanitini alir. Kod yalniz HMAC ozeti olarak saklanir, tek kullanimliktir.
import crypto from 'node:crypto';
import { pool } from '../db.js';
import {
  createIdentityClaimChallenge,
  findPhoneIdentityCandidates,
  verifyIdentityClaimChallenge,
} from './identity_resolution_service.js';
import { signAccessToken } from '../jwt.js';
import { mapUserRow } from '../utils/helpers.js';
import {
  ATTEMPT_POLICIES,
  codeLockedError,
  peekAttemptLock,
  registerAttemptFailure,
  resetAttempts,
  smsCodeTarget,
} from '../security/attempt_limits.js';
import { PlatformError } from './errors.js';
import { normalizePersonPhone } from './people_common.js';
import { smsHooks } from './sms_provider.js';

export const CODE_TTL_SECONDS = 300;
export const MAX_ATTEMPTS = 5;
export const MAX_CODES_PER_WINDOW = 3;
export const WINDOW_MINUTES = 15;

const unavailable = () => new PlatformError(503, 'SMS_UNAVAILABLE', 'SMS ile giriş şu an kullanılamıyor.');
const badCode = () => new PlatformError(401, 'SMS_CODE_INVALID', 'Kod hatalı ya da süresi dolmuş.');

export const generateCode = () => String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');

export function hashCode(phone, code, pepper = process.env.SMS_CODE_PEPPER || process.env.JWT_SECRET || '') {
  return crypto.createHmac('sha256', String(pepper)).update(`${phone}:${code}`).digest('hex');
}

const safeEqual = (a, b) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};

export function smsStatus() {
  const provider = smsHooks.provider();
  return { enabled: provider !== null, provider: provider?.name ?? null, whatsapp: false };
}

/** Telefon -> tek, etkin, dogrulanmis kullanici (birden cok eslesme = belirsiz -> null). */
async function findUserByPhone(phone, db = pool) {
  const last10 = phone.slice(-10);
  const result = await db.query(
    `SELECT user_code FROM users
     WHERE is_active = TRUE AND email_verified = TRUE AND deleted_at IS NULL AND COALESCE(approval_status, 'approved') = 'approved'
       AND RIGHT(regexp_replace(COALESCE(phone_number, ''), '\\D', '', 'g'), 10) = $1
     LIMIT 2`,
    [last10],
  );
  return result.rows?.length === 1 ? Number(result.rows[0].user_code) : null;
}

export async function requestSmsCode(rawPhone, db = pool) {
  const provider = smsHooks.provider();
  if (!provider) throw unavailable();
  const phone = normalizePersonPhone(rawPhone);
  if (!phone) throw new PlatformError(400, 'INVALID_BODY', 'Telefon numarası zorunlu.');
  const recent = await db.query(
    `SELECT COUNT(*)::int AS n FROM sms_login_codes WHERE phone = $1 AND created_at > NOW() - make_interval(mins => $2)`,
    [phone, WINDOW_MINUTES],
  );
  if (Number(recent.rows[0].n) >= MAX_CODES_PER_WINDOW) {
    throw new PlatformError(429, 'SMS_RATE_LIMITED', 'Çok fazla kod istediniz. Biraz sonra tekrar deneyin.');
  }
  let userCode = await findUserByPhone(phone, db);
  const multiCandidates = await findPhoneIdentityCandidates(phone, db);
  if (multiCandidates.length > 1) {
    userCode = null;
  } else if (userCode === null && multiCandidates.length === 1) {
    userCode = Number(multiCandidates[0].user_code);
  }
  const code = generateCode();
  await db.query(
    `INSERT INTO sms_login_codes (phone, user_code, code_hash, expires_at) VALUES ($1, $2, $3, NOW() + make_interval(secs => $4))`,
    [phone, userCode, hashCode(phone, code), CODE_TTL_SECONDS],
  );
  if (userCode !== null || multiCandidates.length > 1) {
    try {
      await provider.send(phone, `Giriş kodunuz: ${code}. 5 dakika geçerlidir, kimseyle paylaşmayın.`);
    } catch (error) {
      console.error('[sms] gonderim hatasi:', error?.name || 'ERROR');
    }
  }
  return { ok: true, expires_in: CODE_TTL_SECONDS };
}

export async function verifySmsCode(rawPhone, rawCode, db = pool) {
  if (!smsHooks.provider()) throw unavailable();
  const phone = normalizePersonPhone(rawPhone);
  const code = String(rawCode ?? '').trim();
  if (!phone || !/^\d{6}$/.test(code)) throw badCode();
  // Kalici birikimli kilit (kodlar arasi, telefon basina; auth_attempt_limits): kilitliyken kod karsilastirilmaz ve deneme hakki harcanmaz (423).
  const limitTarget = smsCodeTarget(phone);
  const lock = await peekAttemptLock(ATTEMPT_POLICIES.smsCode, limitTarget, db);
  if (lock.locked) throw codeLockedError('sms', lock.retryAfterSeconds);
  // Deneme hakki once ayrilir (yaris guvenli); en yeni acik kod uzerinde. Kod basina 5 yanlis -> kod kullanilamaz, yeni kod istenir.
  const claimed = await db.query(
    `UPDATE sms_login_codes SET attempts = attempts + 1
     WHERE id = (SELECT id FROM sms_login_codes WHERE phone = $1 AND consumed_at IS NULL AND expires_at > NOW() AND attempts < $2
                 ORDER BY created_at DESC LIMIT 1)
     RETURNING id, user_code, code_hash`,
    [phone, MAX_ATTEMPTS],
  );
  const row = claimed.rows?.[0];
  if (!row || !safeEqual(row.code_hash, hashCode(phone, code))) {
    // Yalniz GERCEKTEN karsilastirilan (acik kod bulunan) yanlis deneme birikimli sayaca yazilir: kod istemeden gonderilen bos denemeler
    // baskasinin SMS girisini kilitleyemez. Kilidi koyan yanlis 423 alir (kayitli / kayitsiz telefon ayni davranir: kullanici varligi sizmaz).
    if (row) {
      const failure = await registerAttemptFailure(ATTEMPT_POLICIES.smsCode, limitTarget, db);
      if (failure.locked) throw codeLockedError('sms', failure.retryAfterSeconds);
    }
    throw badCode();
  }
  let targetUserCode = row.user_code !== null && row.user_code !== undefined ? Number(row.user_code) : null;
  let phoneCandidates = null;
  if (targetUserCode === null) {
    phoneCandidates = await findPhoneIdentityCandidates(phone, db);
    if (phoneCandidates.length === 0) {
      // Kayitsiz telefon icin dogru kod bilgisi dahi hesap varligini sizdirmamali:
      // eski davranis gibi basarisiz deneme sayilir ve kod tuketilmez.
      const failure = await registerAttemptFailure(ATTEMPT_POLICIES.smsCode, limitTarget, db);
      if (failure.locked) throw codeLockedError('sms', failure.retryAfterSeconds);
      throw badCode();
    }
    if (phoneCandidates.length === 1) {
      targetUserCode = Number(phoneCandidates[0].user_code);
    }
  }

  const used = await db.query(`UPDATE sms_login_codes SET consumed_at = NOW() WHERE id = $1 AND consumed_at IS NULL RETURNING id`, [row.id]);
  if (!used.rows?.length) throw badCode();
  // Dogru kod: birikimli sayac ve kilit seviyesi sifirlanir.
  await resetAttempts(ATTEMPT_POLICIES.smsCode, limitTarget, db);

  if (targetUserCode === null) {
    if (phoneCandidates.length > 1) {
      const challenge = await createIdentityClaimChallenge(db, {
        kind: 'sms_account_select',
        provider: 'sms',
        verifiedPhone: phone,
        candidates: phoneCandidates,
      });
      return {
        ok: false,
        account_selection_required: true,
        selection_token: challenge.token,
        expires_in_seconds: challenge.expiresInSeconds,
        candidates: challenge.candidates,
        message: 'Bu telefon numarasına bağlı birden fazla hesap bulundu. Giriş yapmak istediğiniz hesabı seçin.',
      };
    }
  }

  // deleted_at IS NULL: kimliksizleştirilmiş (silinmiş) hesaba SMS ile oturum açılmaz. must_change_password: yönetimin verdiği geçici parola / PIN
  // henüz değişmediyse bayrak oturum yanıtına girer (POST /auth/login, OAuth ve auth_middleware ile AYNI tanım: bayrak VEYA dairede "PIN verildi").
  const userRes = await db.query(
    `SELECT user_code AS id, full_name, email, login_name, role, is_active, email_verified, approval_status, phone_number, created_at, password_hash,
            (COALESCE(users.must_change_password, FALSE) OR EXISTS (
              SELECT 1 FROM apartments a WHERE a.resident_user_code = users.user_code AND a.resident_pin_issued = TRUE
            )) AS must_change_password
     FROM users WHERE user_code = $1 AND deleted_at IS NULL`,
    [targetUserCode],
  );
  const user = userRes.rows?.[0];
  if (!user || !user.is_active || (!user.email_verified && !String(user.email || '').toLowerCase().endsWith('@ahbu.local')) || (user.approval_status && user.approval_status !== 'approved')) throw badCode();
  return { token: signAccessToken(mapUserRow(user), { passwordHash: user.password_hash }), user: mapUserRow(user) };
}

export async function verifySmsSelection({ selectionToken, candidateRef, rawDeviceToken = null }, deps = {}) {
  return verifyIdentityClaimChallenge(
    {
      selectionToken,
      method: 'selection',
      candidateRef,
      rawDeviceToken,
    },
    deps,
  );
}

/** Bakim: bir gunden eski kodlari siler. */
export async function purgeSmsCodes(db = pool) {
  await db.query(`DELETE FROM sms_login_codes WHERE created_at < NOW() - INTERVAL '1 day'`);
}
