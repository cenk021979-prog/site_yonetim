// Merkezi kimlik çözümleme ve maskeleme yardımcıları.
import crypto from 'node:crypto';
import { foldText } from './people_common.js';
import { isReservedEmail } from '../utils/reserved_email.js';

export const INTERNAL_EMAIL_SUFFIX = '@ahbu.local';
export const APPLE_PRIVATE_RELAY_SUFFIX = '@privaterelay.appleid.com';

export function isIdentityResolverEnabled(env = process.env) {
  const raw = String(env?.IDENTITY_RESOLVER_ENABLED ?? '').trim().toLowerCase();
  if (!raw) return true;
  return !['0', 'false', 'off', 'no'].includes(raw);
}

export function isInternalEmail(email) {
  const clean = String(email ?? '').trim().toLowerCase();
  if (!clean) return true;
  return clean.endsWith(INTERNAL_EMAIL_SUFFIX);
}

export function isDeletedEmail(email) {
  const clean = String(email ?? '').trim().toLowerCase();
  return clean ? isReservedEmail(clean) : false;
}

export function isApplePrivateRelayEmail(email) {
  const clean = String(email ?? '').trim().toLowerCase();
  return Boolean(clean && clean.endsWith(APPLE_PRIVATE_RELAY_SUFFIX));
}

export function normalizeContactEmail(email) {
  const clean = String(email ?? '').trim().toLowerCase();
  if (!clean || !clean.includes('@')) return null;
  if (isInternalEmail(clean) || isDeletedEmail(clean) || isApplePrivateRelayEmail(clean)) {
    return null;
  }
  return clean;
}

export function realVerifiedEmail(email, emailVerified) {
  if (emailVerified !== true) return null;
  return normalizeContactEmail(email);
}

export function normalizePhoneLast10(phone) {
  const digits = String(phone ?? '').replace(/\D/g, '');
  if (digits.length < 10) return null;
  const tail = digits.slice(-10);
  if (/^0+$/.test(tail)) return null;
  return tail;
}

export function formatTrE164FromLast10(last10) {
  const clean = normalizePhoneLast10(last10);
  return clean ? `+90${clean}` : null;
}

export function normalizeFullName(fullName) {
  return foldText(String(fullName ?? '').trim().replace(/\s+/g, ' '));
}

export function normalizeLoginName(loginName) {
  const clean = String(loginName ?? '').trim().toLowerCase();
  return clean || null;
}

export function maskLoginName(loginName) {
  const clean = String(loginName ?? '').trim();
  if (!clean) return null;
  if (clean.length <= 2) return `${clean[0]}*`;
  if (clean.length <= 4) return `${clean[0]}***${clean[clean.length - 1]}`;
  return `${clean.slice(0, 3)}***${clean[clean.length - 1]}`;
}

export function maskEmail(email) {
  const clean = normalizeContactEmail(email);
  if (!clean) return null;
  const at = clean.indexOf('@');
  if (at <= 0) return null;
  const local = clean.slice(0, at);
  const domain = clean.slice(at + 1);
  const maskedLocal =
    local.length <= 2
      ? `${local[0]}***`
      : `${local.slice(0, 2)}***${local[local.length - 1]}`;
  const dot = domain.indexOf('.');
  const domainHead = dot > 0 ? domain.slice(0, dot) : domain;
  const domainTail = dot > 0 ? domain.slice(dot) : '';
  const maskedDomainHead = domainHead.length <= 2 ? `${domainHead[0] ?? '*'}**` : `${domainHead.slice(0, 2)}***`;
  return `${maskedLocal}@${maskedDomainHead}${domainTail}`;
}

export function maskPhone(phone) {
  const tail = normalizePhoneLast10(phone);
  if (!tail) return null;
  return `0${tail[0]}** *** **${tail.slice(-2)}`;
}

export function maskFullName(fullName) {
  const clean = String(fullName ?? '').trim();
  if (!clean) return null;
  return clean
    .split(/\s+/)
    .filter(Boolean)
    .map((part) => (part.length <= 1 ? '*' : `${part[0]}${'*'.repeat(Math.min(Math.max(part.length - 1, 2), 5))}`))
    .join(' ');
}

export function toMaskedCandidateDescriptor(candidate, index = 0) {
  const isManaged =
    isInternalEmail(candidate.email) ||
    candidate._matchedVia === 'apartment_resident_email' ||
    Boolean(candidate.has_site_membership);
  return {
    candidate_ref: String(candidate.candidate_ref ?? index + 1),
    masked_name: maskFullName(candidate.full_name),
    masked_login_name: maskLoginName(candidate.login_name),
    masked_email: maskEmail(candidate.email),
    masked_phone: maskPhone(candidate.phone_number ?? candidate.person_phone),
    account_type: isManaged ? 'resident_managed' : 'individual',
  };
}

export function generateClaimToken() {
  return crypto.randomBytes(32).toString('base64url');
}

export function hashClaimToken(rawToken) {
  return crypto.createHash('sha256').update(String(rawToken ?? ''), 'utf8').digest('hex');
}
