// Katılım ve yönetici onayında olası mevcut hesap / mükerrer kişi çözümleme yardımcısı.
// Kurallar:
//  - Güçlü sinyaller: doğrulanmış gerçek e-posta (@ahbu.local/@deleted.invalid/@privaterelay hariç) ve telefon (son 10 hane).
//  - Zayıf sinyaller: ad soyad benzerliği, login_name benzerliği.
//  - Yalnız zayıf sinyal (isim/kullanıcı adı benzerliği) ASLA katılım talebini veya yönetici onayını engellemez (409 fırlatmaz).
import { PlatformError } from './errors.js';
import {
  maskEmail,
  maskFullName,
  maskLoginName,
  maskPhone,
  normalizeContactEmail,
  normalizeFullName,
  normalizeLoginName,
  normalizePhoneLast10,
} from './identity_resolution_helpers.js';

export const STRONG_MATCH_REASONS = new Set(['email', 'phone']);
export const WEAK_MATCH_REASONS = new Set(['name', 'login_name']);

export function identityKey(input) {
  if (typeof input === 'string') {
    return normalizeFullName(input).replace(/[^a-z0-9]/g, '');
  }
  const { email, phone, fullName } = input || {};
  const cleanEmail = normalizeContactEmail(email) || '';
  const cleanPhone = normalizePhoneLast10(phone) || '';
  const cleanName = normalizeFullName(fullName).replace(/[^a-z0-9]/g, '');
  return `${cleanEmail}|${cleanPhone}|${cleanName}`;
}

function matchReasons(current, candidate, { allowEmailMatch = true } = {}) {
  const reasons = [];
  const candidateEmails = new Set(
    [
      normalizeContactEmail(candidate.email),
      normalizeContactEmail(candidate.resident_email),
      normalizeContactEmail(candidate.person_email),
    ].filter(Boolean),
  );
  if (allowEmailMatch && current.email && candidateEmails.has(current.email)) {
    reasons.push('email');
  }
  const candPhone = normalizePhoneLast10(candidate.phone_number ?? candidate.person_phone);
  if (current.phone && candPhone && current.phone === candPhone) {
    reasons.push('phone');
  }
  const candLogin = normalizeLoginName(candidate.login_name);
  if (current.loginName && candLogin && current.loginName === candLogin) {
    reasons.push('login_name');
  }
  const candName = normalizeFullName(candidate.full_name);
  if (current.fullName && candName && current.fullName.length >= 4 && current.fullName === candName) {
    reasons.push('name');
  }
  return reasons;
}

export async function findPossibleExistingAccount(
  db,
  { userCode = null, siteCode = null, fullName = null, email = null, phone = null, loginName = null },
) {
  let effFullName = fullName;
  let effEmail = email;
  let effPhone = phone;
  let effLoginName = loginName;
  let allowEmailMatch = true;

  if (userCode != null && !effFullName && !effEmail && !effPhone && !effLoginName) {
    const userState = await db.query(
      `SELECT full_name, email, email_verified, phone_number, login_name FROM users WHERE user_code = $1 AND deleted_at IS NULL LIMIT 1`,
      [Number(userCode)],
    );
    const u = userState.rows?.[0];
    if (!u) return null;
    effFullName = u.full_name ?? null;
    effEmail = u.email ?? null;
    effPhone = u.phone_number ?? null;
    effLoginName = u.login_name ?? null;
    allowEmailMatch = u.email_verified === true;
  } else if (userCode != null && normalizeContactEmail(effEmail)) {
    const userState = await db.query(
      `SELECT email_verified FROM users WHERE user_code = $1 AND deleted_at IS NULL LIMIT 1`,
      [Number(userCode)],
    );
    if (userState.rows?.[0]?.email_verified !== true) {
      allowEmailMatch = false;
    }
  }

  const current = {
    email: normalizeContactEmail(effEmail),
    phone: normalizePhoneLast10(effPhone),
    fullName: normalizeFullName(effFullName),
    loginName: normalizeLoginName(effLoginName),
  };
  if (!current.email && !current.phone && !current.fullName && !current.loginName) {
    return null;
  }
  allowEmailMatch = allowEmailMatch && Boolean(current.email);

  const candidates = await db.query(
    `
      SELECT
        u.user_code,
        u.full_name,
        u.email,
        u.login_name,
        u.phone_number,
        (
          SELECT a.resident_email
          FROM apartments a
          WHERE a.resident_user_code = u.user_code AND a.resident_email IS NOT NULL
          ORDER BY a.id ASC
          LIMIT 1
        ) AS resident_email,
        NULL::text AS person_email,
        NULL::text AS person_phone,
        'user'::text AS source
      FROM users u
      WHERE u.deleted_at IS NULL
        AND u.is_active = TRUE
        AND COALESCE(u.approval_status, 'approved') = 'approved'
        AND ($1::int IS NULL OR u.user_code <> $1::int)
        AND (
          ($2::text IS NOT NULL AND (
            LOWER(COALESCE(u.email, '')) = LOWER($2::text)
            OR EXISTS (
              SELECT 1 FROM apartments a
              WHERE a.resident_user_code = u.user_code
                AND a.resident_email IS NOT NULL
                AND LOWER(a.resident_email) = LOWER($2::text)
            )
            OR EXISTS (
              SELECT 1 FROM site_people sp
              WHERE sp.user_code = u.user_code
                AND sp.is_active = TRUE
                AND sp.email IS NOT NULL
                AND LOWER(sp.email) = LOWER($2::text)
            )
          ))
          OR ($3::text IS NOT NULL AND RIGHT(regexp_replace(COALESCE(u.phone_number, ''), '\\D', '', 'g'), 10) = $3::text)
          OR ($4::text IS NOT NULL AND LOWER(COALESCE(u.login_name, '')) = LOWER($4::text))
          OR ($5::text IS NOT NULL AND LOWER(regexp_replace(COALESCE(u.full_name, ''), '\\s+', ' ', 'g')) = LOWER($5::text))
        )
      UNION ALL
      SELECT
        sp.user_code,
        COALESCE(u.full_name, sp.full_name) AS full_name,
        COALESCE(u.email, sp.email) AS email,
        u.login_name,
        COALESCE(u.phone_number, sp.phone) AS phone_number,
        NULL::text AS resident_email,
        sp.email AS person_email,
        sp.phone AS person_phone,
        'site_person'::text AS source
      FROM site_people sp
      LEFT JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL
      WHERE ($6::bigint IS NULL OR sp.site_code = $6::bigint)
        AND sp.is_active = TRUE
        AND ($1::int IS NULL OR sp.user_code IS DISTINCT FROM $1::int)
        AND (
          ($2::text IS NOT NULL AND LOWER(COALESCE(sp.email, u.email, '')) = LOWER($2::text))
          OR ($3::text IS NOT NULL AND RIGHT(regexp_replace(COALESCE(sp.phone, u.phone_number, ''), '\\D', '', 'g'), 10) = $3::text)
          OR ($5::text IS NOT NULL AND LOWER(regexp_replace(COALESCE(sp.full_name, u.full_name, ''), '\\s+', ' ', 'g')) = LOWER($5::text))
        )
      LIMIT 25
    `,
      [
      userCode == null ? null : Number(userCode),
      allowEmailMatch ? current.email : null,
      current.phone,
      current.loginName,
      effFullName ? String(effFullName).trim().replace(/\s+/g, ' ') : null,
      siteCode == null ? null : Number(siteCode),
    ],
  );

  let best = null;
  for (const candidate of candidates.rows ?? []) {
    const reasons = matchReasons(current, candidate, { allowEmailMatch });
    if (reasons.length === 0) continue;
    const strongReasons = reasons.filter((r) => STRONG_MATCH_REASONS.has(r));
    const weakReasons = reasons.filter((r) => WEAK_MATCH_REASONS.has(r));
    const isStrongMatch = strongReasons.length > 0;
    const score =
      reasons.reduce((total, reason) => total + ({ email: 100, phone: 80, login_name: 60, name: 40 }[reason] ?? 0), 0) +
      (isStrongMatch ? 1000 : 0) +
      (candidate.user_code != null ? 10 : 0);
    if (!best || score > best.score) {
      const candUserCode = candidate.user_code == null ? null : Number(candidate.user_code);
      best = {
        user_code: candUserCode,
        userCode: candUserCode,
        full_name: candidate.full_name ?? null,
        email: candidate.email ?? candidate.resident_email ?? candidate.person_email ?? null,
        login_name: candidate.login_name ?? null,
        phone_number: candidate.phone_number ?? candidate.person_phone ?? null,
        source: candidate.source,
        reasons,
        strong_reasons: strongReasons,
        weak_reasons: weakReasons,
        strength: isStrongMatch ? 'strong' : 'weak',
        is_strong_match: isStrongMatch,
        masked_name: maskFullName(candidate.full_name),
        masked_login_name: maskLoginName(candidate.login_name),
        masked_email: maskEmail(candidate.email ?? candidate.resident_email ?? candidate.person_email),
        masked_phone: maskPhone(candidate.phone_number ?? candidate.person_phone),
        score,
      };
    }
  }
  return best;
}

/**
 * Katılım başvurusu veya yönetici onayı öncesinde güçlü kimlik eşleşmesini denetler.
 *  - Yalnız ad/kullanıcı adı benzerliği (zayıf sinyal) ENGEL OLUŞTURMAZ, `null` döner.
 *  - Hesapsız CRM kaydı (user_code == null) başvuranla zaten eşleştiğinde başvuru engellenmez; onay sırasında bağlanır.
 *  - Başka bir aktif hesapla GÜÇLÜ (doğrulanmış e-posta / telefon) eşleşme varsa ve onay verilmediyse 409 ACCOUNT_CLAIM_REQUIRED döner.
 */
export async function assertJoinIdentitySafe(
  db,
  {
    userCode = null,
    siteCode = null,
    fullName = null,
    email = null,
    phone = null,
    loginName = null,
    confirmDifferentPerson = false,
    confirmedDistinctPerson = false,
    differentPersonReason = null,
    confirmationReason = null,
    audience = 'resident',
  },
) {
  const match = await findPossibleExistingAccount(db, {
    userCode,
    siteCode,
    fullName,
    email,
    phone,
    loginName,
  });
  if (!match) return null;

  // Yalnız ad veya login_name benzerliği ASLA engel değildir.
  if (!match.is_strong_match) {
    return null;
  }

  // Aynı sitede hesabı henüz açılmamış (user_code IS NULL) CRM kaydı başka hesap değildir; başvuru geçer, onayda bağlanır.
  if (match.user_code === null) {
    return null;
  }

  const isConfirmed = confirmDifferentPerson === true || confirmedDistinctPerson === true;
  const trimmedReason = String(confirmationReason ?? differentPersonReason ?? '').trim();
  if (isConfirmed) {
    if (trimmedReason.length < 10) {
      throw new PlatformError(
        400,
        'DUPLICATE_CONFIRMATION_REASON_REQUIRED',
        'Farklı kişi onayı için en az 10 karakterlik bir açıklama girmelisiniz.',
      );
    }
    const sliced = trimmedReason.slice(0, 300);
    return {
      ...match,
      override_reason: sliced,
      overrideReason: sliced,
    };
  }

  const msg =
    audience === 'manager'
      ? 'Bu başvuru mevcut başka bir hesapla aynı e-posta veya telefonu paylaşıyor. Yine de farklı kişi olarak onaylamak için gerekçe girin.'
      : 'Mevcut hesabınız bulundu. Daire hesabınızı doğrudan bağlayabilir veya farklı bir kişiyseniz açıklama yazarak devam edebilirsiniz.';

  throw new PlatformError(409, 'ACCOUNT_CLAIM_REQUIRED', msg, {
    existing_account: {
      masked_name: match.masked_name,
      masked_login_name: match.masked_login_name,
      masked_email: match.masked_email,
      masked_phone: match.masked_phone,
      reasons: match.strong_reasons,
      match_strength: 'strong',
      can_claim_in_place: audience !== 'manager',
    },
  });
}
