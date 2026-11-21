import { PlatformError } from './errors.js';

const INTERNAL_EMAIL_SUFFIX = '@ahbu.local';
const MIN_IDENTITY_KEY_LENGTH = 5;

export function identityKey(value) {
  return String(value ?? '')
    .trim()
    .toLocaleLowerCase('tr-TR')
    .replaceAll('ı', 'i')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]/g, '');
}
function normalizedPhone(value) {
  const digits = String(value ?? '').replace(/\D/g, '');
  return digits.length >= 10 ? digits.slice(-10) : '';
}

function realEmail(value) {
  const email = String(value ?? '').trim().toLowerCase();
  return email && !email.endsWith(INTERNAL_EMAIL_SUFFIX) && !email.endsWith('@deleted.invalid')
    ? email
    : '';
}

function values(value) {
  return Array.isArray(value) ? value : [];
}

function maskedLogin(value) {
  const text = String(value ?? '').trim();
  if (!text) return null;
  if (text.length <= 4) return `${text[0]}***`;
  return `${text.slice(0, 2)}***${text.slice(-2)}`;
}

function matchReasons(current, candidate) {
  const reasons = [];
  const currentEmail = realEmail(current.email);
  const candidateEmails = new Set([
    realEmail(candidate.email),
    ...values(candidate.person_emails).map(realEmail),
    ...values(candidate.resident_emails).map(realEmail),
  ].filter(Boolean));
  if (currentEmail && candidateEmails.has(currentEmail)) reasons.push('email');

  const currentPhone = normalizedPhone(current.phone_number);
  const candidatePhones = new Set([
    normalizedPhone(candidate.phone_number),
    ...values(candidate.person_phones).map(normalizedPhone),
  ].filter(Boolean));
  if (currentPhone && candidatePhones.has(currentPhone)) reasons.push('phone');

  const currentName = identityKey(current.full_name);
  const currentLogin = identityKey(current.login_name);
  const currentEmailLocal = identityKey(currentEmail.split('@')[0]);
  const candidateName = identityKey(candidate.full_name);
  const candidateLogin = identityKey(candidate.login_name);
  if (
    currentName.length >= MIN_IDENTITY_KEY_LENGTH &&
    candidateName.length >= MIN_IDENTITY_KEY_LENGTH &&
    currentName === candidateName
  ) reasons.push('name');
  if (
    candidateLogin.length >= MIN_IDENTITY_KEY_LENGTH &&
    [currentName, currentLogin, currentEmailLocal].some((key) => key === candidateLogin)
  ) reasons.push('login_name');
  return [...new Set(reasons)];
}

export async function findPossibleExistingAccount(db, { siteCode, userCode }) {
  const currentRes = await db.query(
    `SELECT user_code, full_name, email, login_name, phone_number
     FROM users
     WHERE user_code = $1 AND deleted_at IS NULL AND is_active = TRUE
     LIMIT 1`,
    [Number(userCode)],
  );
  const current = currentRes.rows?.[0];
  if (!current) return null;

  const candidates = await db.query(
    `WITH tied AS (
       SELECT a.site_code, a.id AS apartment_id, am.user_code
       FROM apartment_memberships am
       JOIN apartments a ON a.id = am.apartment_id
       WHERE a.site_code = $1 AND a.is_active = TRUE AND am.is_active = TRUE
       UNION
       SELECT a.site_code, a.id AS apartment_id, a.resident_user_code AS user_code
       FROM apartments a
       WHERE a.site_code = $1 AND a.is_active = TRUE AND a.resident_user_code IS NOT NULL
     )
     SELECT
       u.user_code,
       u.full_name,
       u.email,
       u.login_name,
       u.phone_number,
       ARRAY_REMOVE(ARRAY_AGG(DISTINCT sp.email), NULL) AS person_emails,
       ARRAY_REMOVE(ARRAY_AGG(DISTINCT sp.phone), NULL) AS person_phones,
       ARRAY_REMOVE(ARRAY_AGG(DISTINCT a.resident_email), NULL) AS resident_emails,
       ARRAY_REMOVE(ARRAY_AGG(DISTINCT CONCAT_WS(' - ', NULLIF(b.block_name, ''), NULLIF(a.unit_label, ''))), '') AS apartment_labels
     FROM tied t
     JOIN users u ON u.user_code = t.user_code
     JOIN apartments a ON a.id = t.apartment_id
     LEFT JOIN site_blocks b ON b.id = a.block_id
     LEFT JOIN site_people sp ON sp.site_code = t.site_code AND sp.user_code = u.user_code AND sp.is_active = TRUE
     WHERE u.user_code <> $2 AND u.deleted_at IS NULL AND u.is_active = TRUE
     GROUP BY u.user_code, u.full_name, u.email, u.login_name, u.phone_number
     ORDER BY u.user_code`,
    [Number(siteCode), Number(userCode)],
  );

  let best = null;
  for (const candidate of candidates.rows ?? []) {
    const reasons = matchReasons(current, candidate);
    if (reasons.length === 0) continue;
    const score = reasons.reduce((total, reason) => total + ({ email: 100, phone: 80, login_name: 60, name: 40 }[reason] ?? 0), 0);
    if (!best || score > best.score) {
      best = {
        score,
        reasons,
        userCode: Number(candidate.user_code),
        fullName: candidate.full_name,
        maskedLoginName: maskedLogin(candidate.login_name),
        apartmentLabels: values(candidate.apartment_labels).filter(Boolean).slice(0, 3),
      };
    }
  }
  return best;
}

export async function assertJoinIdentitySafe(
  db,
  { siteCode, userCode, confirmedDistinctPerson = false, confirmationReason = null, audience = 'resident' },
) {
  const match = await findPossibleExistingAccount(db, { siteCode, userCode });
  if (!match) return null;

  const reason = String(confirmationReason ?? '').trim();
  if (confirmedDistinctPerson) {
    if (reason.length < 10) {
      throw new PlatformError(
        400,
        'DUPLICATE_CONFIRMATION_REASON_REQUIRED',
        'Farklı kişi doğrulaması için en az 10 karakterlik bir açıklama yazınız.',
      );
    }
    return { ...match, confirmationReason: reason.slice(0, 300) };
  }

  const apartmentText = match.apartmentLabels.length > 0
    ? ` (${match.apartmentLabels.join(', ')})`
    : '';
  const message = audience === 'manager'
    ? `Bu başvuru, sitedeki "${match.fullName}"${apartmentText} hesabıyla eşleşiyor. Mevcut hesaba yönlendirin veya farklı kişi olduğunu gerekçesiyle doğrulayın.`
    : 'Bu sitede size ait olabilecek mevcut bir hesap bulundu. Yönetimin verdiği kullanıcı adıyla giriş yapın; gerçekten farklı bir kişiyseniz bunu gerekçesiyle doğrulayabilirsiniz.';
  const extra = audience === 'manager'
    ? {
        candidate_name: match.fullName,
        candidate_login_hint: match.maskedLoginName,
        candidate_apartments: match.apartmentLabels,
        match_reasons: match.reasons,
      }
    : {
        candidate_login_hint: match.maskedLoginName,
        match_reasons: match.reasons,
      };
  throw new PlatformError(409, 'ACCOUNT_CLAIM_REQUIRED', message, extra);
}

