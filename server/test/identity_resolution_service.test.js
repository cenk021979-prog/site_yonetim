import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-key-at-least-32-chars-long-0123456789';

import {
  isApplePrivateRelayEmail,
  isDeletedEmail,
  isInternalEmail,
  maskEmail,
  maskFullName,
  maskLoginName,
  maskPhone,
  normalizePhoneLast10,
  realVerifiedEmail,
} from '../src/modules/identity_resolution_helpers.js';
import {
  IDENTITY_RESOLUTION_DDL,
  IDENTITY_RESOLUTION_TABLES,
  ensureIdentityResolutionSchema,
} from '../src/modules/identity_resolution_schema.js';
import {
  claimExistingAccountForSession,
  requestIdentityClaimSmsCode,
  verifyIdentityClaimChallenge,
} from '../src/modules/identity_resolution_service.js';
import { authenticateWithOAuth, oauthHooks } from '../src/modules/oauth_login.js';
import { requestSmsCode, verifySmsCode, verifySmsSelection } from '../src/modules/sms_login.js';
import { smsHooks } from '../src/modules/sms_provider.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_SOURCE = fs.readFileSync(path.resolve(__dirname, '../src/db.js'), 'utf8');
const MIGRATION_138 = fs.readFileSync(
  path.resolve(__dirname, '../migrations/138_identity_resolution.sql'),
  'utf8',
);

function createStatefulMockDb({
  users = [],
  apartments = [],
  sitePeople = [],
  siteMemberships = [],
  apartmentMemberships = [],
  siteManagerSites = [],
  oauthIdentities = [],
  userConsents = [],
  joinRequests = [],
  devices = [],
} = {}) {
  const state = {
    nextUserCode: 200,
    nextOAuthId: 10,
    nextChallengeId: 1,
    nextSmsId: 1,
    users: users.map((u) => ({ deleted_at: null, approval_status: 'approved', is_active: true, ...u })),
    apartments: apartments.map((a) => ({ ...a })),
    sitePeople: sitePeople.map((sp) => ({ is_active: true, ...sp })),
    siteMemberships: siteMemberships.map((sm) => ({ is_active: true, ...sm })),
    apartmentMemberships: apartmentMemberships.map((am) => ({ is_active: true, ...am })),
    siteManagerSites: siteManagerSites.map((sms) => ({ ...sms })),
    oauthIdentities: oauthIdentities.map((o) => ({ ...o })),
    challenges: [],
    smsCodes: [],
    userConsents: userConsents.map((c) => ({ ...c })),
    joinRequests: joinRequests.map((jr) => ({ ...jr })),
    devices: devices.map((d) => ({ ...d })),
    audits: [],
    attemptLimits: new Map(),
  };

  function userHasPin(uCode) {
    return state.apartments.some((a) => Number(a.resident_user_code) === Number(uCode) && a.resident_pin_issued === true);
  }

  function mapUser(u, extra = {}) {
    return {
      ...u,
      id: u.user_code,
      db_id: u.user_code,
      must_change_password: Boolean(u.must_change_password) || userHasPin(u.user_code),
      pin_issued: userHasPin(u.user_code),
      ...extra,
    };
  }

  function phoneTail(raw) {
    return String(raw || '').replace(/\D/g, '').slice(-10);
  }

  async function query(rawSql, params = []) {
    const sql = String(rawSql).replace(/\s+/g, ' ').trim();

    if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)/i.test(sql)) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('DELETE FROM identity_claim_challenges WHERE expires_at')) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('INSERT INTO audit_log')) {
      const actionStr = params.find((p) => typeof p === 'string' && p.startsWith('identity.')) ?? params[1] ?? params[0];
      state.audits.push({ action: actionStr, params });
      return { rows: [{ id: state.audits.length }], rowCount: 1 };
    }
    if (sql.includes('FROM auth_attempt_limits') && sql.startsWith('SELECT')) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('INTO auth_attempt_limits') || sql.startsWith('DELETE FROM auth_attempt_limits')) {
      if (sql.startsWith('DELETE')) {
        state.attemptLimits.clear();
        return { rows: [], rowCount: 0 };
      }
      return {
        rows: [{ fail_count: 1, lock_level: 0, locked_until: null, locked: false, retry_after_seconds: null }],
        rowCount: 1,
      };
    }
    if (sql.includes('FROM user_oauth_identities o LEFT JOIN users u')) {
      const [provider, sub] = params;
      const ident = state.oauthIdentities.find((o) => o.provider === provider && o.provider_sub === sub);
      if (!ident) return { rows: [], rowCount: 0 };
      const u = state.users.find((x) => Number(x.user_code) === Number(ident.user_code));
      if (!u) return { rows: [{ identity_id: ident.id, linked_user_code: ident.user_code, user_code: null, deleted_at: null }], rowCount: 1 };
      return {
        rows: [
          mapUser(u, {
            identity_id: ident.id,
            linked_user_code: ident.user_code,
          }),
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('UPDATE user_oauth_identities SET last_login_at = NOW(), email = COALESCE')) {
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('UPDATE user_oauth_identities SET user_code = $1')) {
      const [target, source] = params;
      for (const o of state.oauthIdentities) {
        if (Number(o.user_code) === Number(source)) o.user_code = Number(target);
      }
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('SELECT id, user_code FROM user_oauth_identities WHERE provider = $1 AND provider_sub = $2')) {
      const found = state.oauthIdentities.filter((o) => o.provider === params[0] && o.provider_sub === params[1]);
      return { rows: found, rowCount: found.length };
    }
    if (sql.includes('SELECT 1 FROM user_oauth_identities WHERE user_code = $1')) {
      const found = state.oauthIdentities.filter((o) => Number(o.user_code) === Number(params[0]));
      return { rows: found, rowCount: found.length };
    }
    if (sql.includes('INSERT INTO user_oauth_identities')) {
      const [uCode, prov, sub, email] = params;
      const existing = state.oauthIdentities.find((o) => o.provider === prov && o.provider_sub === sub);
      if (existing) {
        existing.user_code = Number(uCode);
        existing.email = email ?? existing.email;
      } else {
        state.oauthIdentities.push({ id: state.nextOAuthId++, user_code: Number(uCode), provider: prov, provider_sub: sub, email });
      }
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('FROM users WHERE LOWER(email) = LOWER($1) AND deleted_at IS NULL')) {
      const email = String(params[0] || '').toLowerCase();
      const matched = state.users
        .filter((u) => u.deleted_at === null && String(u.email || '').toLowerCase() === email)
        .sort((a, b) => a.user_code - b.user_code)
        .map((u) => mapUser(u));
      return { rows: matched, rowCount: matched.length };
    }
    if (sql.includes('FROM users WHERE deleted_at IS NULL AND is_active = TRUE') && sql.includes('apartments a')) {
      // Secondary email lookup OR credentials lookup
      if (sql.includes('LOWER(login_name) = LOWER($1)')) {
        const cleanId = String(params[0] || '').toLowerCase();
        const excl = params.length > 1 ? Number(params[1]) : null;
        const matched = state.users.filter((u) => {
          if (u.deleted_at !== null || !u.is_active) return false;
          if (excl && Number(u.user_code) === excl) return false;
          const aptMatch = state.apartments.some(
            (a) => Number(a.resident_user_code) === Number(u.user_code) && String(a.resident_email || '').toLowerCase() === cleanId,
          );
          return (
            String(u.login_name || '').toLowerCase() === cleanId ||
            String(u.email || '').toLowerCase() === cleanId ||
            aptMatch
          );
        });
        return { rows: matched.map((u) => mapUser(u)), rowCount: matched.length };
      }
      const verifiedEmail = String(params[0] || '').toLowerCase();
      const matched = [];
      for (const u of state.users) {
        if (u.deleted_at !== null || !u.is_active || String(u.email || '').toLowerCase() === verifiedEmail) continue;
        const aptMatch = state.apartments.some(
          (a) => Number(a.resident_user_code) === Number(u.user_code) && String(a.resident_email || '').toLowerCase() === verifiedEmail,
        );
        const spMatch = state.sitePeople.some(
          (sp) => Number(sp.user_code) === Number(u.user_code) && sp.is_active && String(sp.email || '').toLowerCase() === verifiedEmail,
        );
        if (aptMatch || spMatch) {
          matched.push(mapUser(u, { _matched_via: aptMatch ? 'apartment_resident_email' : 'site_people_email' }));
        }
      }
      return { rows: matched, rowCount: matched.length };
    }
    if (sql.includes('FROM users WHERE LOWER(email) = LOWER($1) AND user_code <> $2')) {
      const [email, code] = params;
      const hit = state.users.filter((u) => String(u.email || '').toLowerCase() === String(email).toLowerCase() && Number(u.user_code) !== Number(code));
      return { rows: hit, rowCount: hit.length };
    }
    if (sql.includes('SELECT user_code FROM users WHERE is_active = TRUE AND email_verified = TRUE')) {
      const last10 = params[0];
      const hit = state.users.filter((u) => u.is_active && u.email_verified && !u.deleted_at && phoneTail(u.phone_number) === last10);
      return { rows: hit.map((u) => ({ user_code: u.user_code })), rowCount: hit.length };
    }
    if (sql.includes('SELECT DISTINCT ON (u.user_code)')) {
      const last10 = params[0];
      const matched = [];
      for (const u of state.users) {
        if (!u.is_active || u.deleted_at !== null) continue;
        if (!(u.email_verified || String(u.email || '').toLowerCase().endsWith('@ahbu.local'))) continue;
        const userPhoneOk = phoneTail(u.phone_number) === last10;
        const spMatch = state.sitePeople.find(
          (sp) => Number(sp.user_code) === Number(u.user_code) && sp.is_active && phoneTail(sp.phone) === last10,
        );
        if (userPhoneOk || spMatch) {
          matched.push(
            mapUser(u, {
              has_site_membership: state.siteMemberships.some((sm) => Number(sm.user_code) === Number(u.user_code) && sm.is_active),
              person_phone: spMatch?.phone ?? null,
            }),
          );
        }
      }
      return { rows: matched, rowCount: matched.length };
    }
    if (sql.includes('INSERT INTO users (')) {
      const [fullName, email, passwordHash] = params;
      const newUser = {
        user_code: state.nextUserCode++,
        full_name: fullName,
        email,
        login_name: null,
        role: 'individual',
        is_active: true,
        email_verified: true,
        approval_status: 'approved',
        phone_number: null,
        password_hash: passwordHash,
        must_change_password: false,
        deleted_at: null,
        created_at: new Date().toISOString(),
      };
      state.users.push(newUser);
      return { rows: [mapUser(newUser)], rowCount: 1 };
    }
    if (sql.includes('UPDATE users SET email = $1')) {
      if (params.length === 4) {
        const [email, pwdHash, fullOrPhone, uCode] = params;
        const u = state.users.find((x) => Number(x.user_code) === Number(uCode) && !x.deleted_at);
        if (!u) return { rows: [], rowCount: 0 };
        u.email = email;
        u.email_verified = true;
        u.must_change_password = false;
        u.password_hash = pwdHash;
        if (fullOrPhone && sql.includes('phone_number')) u.phone_number = u.phone_number || fullOrPhone;
        return { rows: [u], rowCount: 1 };
      }
      const [email, , uCode] = params;
      const u = state.users.find((x) => Number(x.user_code) === Number(uCode) && !x.deleted_at);
      if (u) {
        u.email = email;
        u.email_verified = true;
      }
      return { rows: u ? [u] : [], rowCount: u ? 1 : 0 };
    }
    if (sql.includes('UPDATE users SET password_hash = $2, must_change_password = FALSE')) {
      const [uCode, hash] = params;
      const u = state.users.find((x) => Number(x.user_code) === Number(uCode) && !x.deleted_at);
      if (!u) return { rows: [], rowCount: 0 };
      u.password_hash = hash;
      u.must_change_password = false;
      u.email_verified = true;
      return { rows: [{ password_hash: u.password_hash }], rowCount: 1 };
    }
    if (sql.includes('UPDATE users SET is_active = FALSE, login_name = NULL, email = $1')) {
      const [archivedEmail, uCode] = params;
      const u = state.users.find((x) => Number(x.user_code) === Number(uCode) && !x.deleted_at);
      if (u) {
        u.is_active = false;
        u.login_name = null;
        u.email = archivedEmail;
      }
      return { rows: [], rowCount: u ? 1 : 0 };
    }
    if (sql.includes('UPDATE users SET must_change_password = FALSE')) {
      const u = state.users.find((x) => Number(x.user_code) === Number(params[0]) && !x.deleted_at);
      if (u) u.must_change_password = false;
      return { rows: [], rowCount: u ? 1 : 0 };
    }
    if (sql.includes('UPDATE apartments SET resident_pin_issued = FALSE')) {
      const uCode = Number(params[0]);
      for (const a of state.apartments) {
        if (Number(a.resident_user_code) === uCode) {
          a.resident_pin_issued = false;
          a.resident_pin_code = null;
        }
      }
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('UPDATE site_people sp SET user_code = $1')) {
      const [uCode, realEmail] = params;
      for (const sp of state.sitePeople) {
        if (sp.user_code == null && sp.is_active && String(sp.email || '').toLowerCase() === String(realEmail || '').toLowerCase()) {
          sp.user_code = Number(uCode);
          sp.email = null;
        }
      }
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO identity_claim_challenges')) {
      const [tokenHash, kind, prov, sub, vEmail, vPhone, fullName, candJson, expiresAt] = params;
      const rec = {
        id: state.nextChallengeId++,
        token_hash: tokenHash,
        challenge_kind: kind,
        provider: prov,
        provider_sub: sub,
        verified_email: vEmail,
        verified_phone: vPhone,
        full_name: fullName,
        candidate_user_codes: JSON.parse(candJson),
        attempts: 0,
        max_attempts: 5,
        expires_at: expiresAt,
        consumed_at: null,
        consumed_user_code: null,
      };
      state.challenges.push(rec);
      return { rows: [rec], rowCount: 1 };
    }
    if (sql.includes('FROM identity_claim_challenges WHERE token_hash = $1')) {
      const ch = state.challenges.find(
        (c) => c.token_hash === params[0] && !c.consumed_at && new Date(c.expires_at).getTime() > Date.now(),
      );
      return { rows: ch ? [ch] : [], rowCount: ch ? 1 : 0 };
    }
    if (sql.includes('FROM identity_claim_challenges WHERE id = $1 FOR UPDATE')) {
      const ch = state.challenges.find((c) => Number(c.id) === Number(params[0]));
      return { rows: ch ? [ch] : [], rowCount: ch ? 1 : 0 };
    }
    if (sql.includes('UPDATE identity_claim_challenges SET attempts = attempts + 1')) {
      const ch = state.challenges.find(
        (c) =>
          Number(c.id) === Number(params[0]) &&
          !c.consumed_at &&
          new Date(c.expires_at).getTime() > Date.now() &&
          c.attempts < c.max_attempts,
      );
      if (!ch) return { rows: [], rowCount: 0 };
      ch.attempts += 1;
      return { rows: [ch], rowCount: 1 };
    }
    if (sql.includes('UPDATE identity_claim_challenges SET consumed_at = NOW()')) {
      const ch = state.challenges.find((c) => Number(c.id) === Number(params[0]));
      if (ch) {
        ch.consumed_at = new Date().toISOString();
        ch.consumed_user_code = Number(params[1]);
      }
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('SELECT COUNT(*)::int AS n FROM sms_login_codes')) {
      return { rows: [{ n: 0 }], rowCount: 1 };
    }
    if (sql.includes('FROM sms_login_codes WHERE phone = $1') && sql.includes('seconds_since_last')) {
      return { rows: [{ seconds_since_last: null, sent_last_hour: 0 }], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO sms_login_codes')) {
      const [phone, uCode, codeHash, rawExp] = params;
      const expDate = typeof rawExp === 'number' ? new Date(Date.now() + rawExp * 1000) : rawExp;
      state.smsCodes.push({
        id: state.nextSmsId++,
        phone,
        user_code: uCode,
        code_hash: codeHash,
        attempts: 0,
        expires_at: expDate,
        consumed_at: null,
        created_at: new Date(),
      });
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('UPDATE sms_login_codes SET attempts = attempts + 1')) {
      const [phone, maxAtt] = params;
      const open = [...state.smsCodes]
        .reverse()
        .find((c) => c.phone === phone && !c.consumed_at && new Date(c.expires_at).getTime() > Date.now() && c.attempts < maxAtt);
      if (!open) return { rows: [], rowCount: 0 };
      open.attempts += 1;
      return { rows: [{ id: open.id, user_code: open.user_code, code_hash: open.code_hash }], rowCount: 1 };
    }
    if (sql.includes('UPDATE sms_login_codes SET consumed_at = NOW()')) {
      const target = state.smsCodes.find((c) => Number(c.id) === Number(params[0]) && !c.consumed_at);
      if (!target) return { rows: [], rowCount: 0 };
      target.consumed_at = new Date().toISOString();
      return { rows: [{ id: target.id }], rowCount: 1 };
    }
    if (sql.includes('FROM sms_login_codes WHERE phone = $1 AND consumed_at IS NULL')) {
      const [phone, maxAtt] = params;
      const open = [...state.smsCodes]
        .reverse()
        .find((c) => c.phone === phone && !c.consumed_at && new Date(c.expires_at).getTime() > Date.now() && c.attempts < maxAtt);
      return { rows: open ? [open] : [], rowCount: open ? 1 : 0 };
    }
    if (sql.includes('FROM users WHERE user_code = $1 AND deleted_at IS NULL')) {
      const u = state.users.find((x) => Number(x.user_code) === Number(params[0]) && !x.deleted_at);
      return { rows: u ? [mapUser(u)] : [], rowCount: u ? 1 : 0 };
    }
    if (sql.includes('FROM users WHERE user_code = ANY($1::int[]) AND deleted_at IS NULL')) {
      const codes = new Set(params[0].map(Number));
      const matched = state.users
        .filter((x) => codes.has(Number(x.user_code)) && !x.deleted_at)
        .sort((a, b) => a.user_code - b.user_code)
        .map((x) => mapUser(x));
      return { rows: matched, rowCount: matched.length };
    }
    if (sql.includes('AS has_apt') && sql.includes('AS has_site')) {
      const uCode = Number(params[0]);
      return {
        rows: [
          {
            has_apt: state.apartmentMemberships.some((m) => Number(m.user_code) === uCode && m.is_active),
            has_site: state.siteMemberships.some((m) => Number(m.user_code) === uCode && m.is_active),
            has_mgr: state.siteManagerSites.some((m) => Number(m.manager_user_code) === uCode),
            has_person: state.sitePeople.some((sp) => Number(sp.user_code) === uCode && sp.is_active),
            has_dev: state.devices.some((d) => Number(d.owner_user_id) === uCode),
          },
        ],
        rowCount: 1,
      };
    }
    if (sql.includes('INSERT INTO user_consents')) {
      const [target, source] = params;
      for (const c of [...state.userConsents]) {
        if (Number(c.user_code) === Number(source)) {
          state.userConsents.push({ ...c, user_code: Number(target) });
        }
      }
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('UPDATE join_requests SET status = \'CANCELLED\'')) {
      const uCode = Number(params[0]);
      for (const jr of state.joinRequests) {
        if (Number(jr.user_code) === uCode && jr.status === 'PENDING') {
          jr.status = 'CANCELLED';
        }
      }
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('FROM site_manager_invites') || sql.includes('FROM site_manager_sites')) {
      return { rows: [], rowCount: 0 };
    }
    return { rows: [], rowCount: 0 };
  }

  return {
    state,
    query,
    async connect() {
      return {
        query,
        release() {},
      };
    },
  };
}

test('migration 138 ve ensureIdentityResolutionSchema db.js baglantisi ve DDL uyumu', async () => {
  assert.ok(DB_SOURCE.includes('ensureIdentityResolutionSchema(client)'));
  assert.ok(DB_SOURCE.indexOf('await ensureOAuthSchema(client)') < DB_SOURCE.indexOf('await ensureIdentityResolutionSchema(client)'));

  for (const table of IDENTITY_RESOLUTION_TABLES) {
    assert.ok(MIGRATION_138.includes(`CREATE TABLE IF NOT EXISTS ${table}`));
  }
  const normalizedMig = MIGRATION_138.replace(/--.*$/gm, '').replace(/\s+/g, ' ').trim();
  const normalizedDdl = IDENTITY_RESOLUTION_DDL.join(' ').replace(/\s+/g, ' ').trim();
  assert.ok(normalizedMig.includes(normalizedDdl.slice(0, 80)));

  let ddlCalls = 0;
  await ensureIdentityResolutionSchema({
    async query(sql) {
      if (String(sql).includes('to_regclass')) return { rows: [{ n: IDENTITY_RESOLUTION_TABLES.length }] };
      ddlCalls += 1;
      return { rows: [] };
    },
  });
  assert.equal(ddlCalls, 0);

  let createdCalls = 0;
  await ensureIdentityResolutionSchema({
    async query(sql) {
      if (String(sql).includes('to_regclass')) return { rows: [{ n: 0 }] };
      createdCalls += 1;
      return { rows: [] };
    },
  });
  assert.equal(createdCalls, IDENTITY_RESOLUTION_DDL.length);
});

test('normalizasyon ve maskeleme yardımcıları PII sızdırmaz', () => {
  assert.equal(isInternalEmail('d12@ahbu.local'), true);
  assert.equal(isInternalEmail('ali@gmail.com'), false);
  assert.equal(isDeletedEmail('deleted-99@deleted.invalid'), true);
  assert.equal(isApplePrivateRelayEmail('xyz@privaterelay.appleid.com'), true);
  assert.equal(realVerifiedEmail('xyz@privaterelay.appleid.com', true), null);
  assert.equal(realVerifiedEmail('ali@gmail.com', false), null);
  assert.equal(realVerifiedEmail('Ali@Gmail.com', true), 'ali@gmail.com');
  assert.equal(normalizePhoneLast10('+90 532 123 45 67'), '5321234567');
  assert.equal(maskLoginName('ahmet.yilmaz'), 'ahm***z');
  assert.equal(maskEmail('ali.yilmaz@gmail.com'), 'al***z@gm***.com');
  assert.equal(maskPhone('+90 532 123 45 67'), '05** *** **67');
  assert.equal(maskFullName('Ahmet Yılmaz'), 'A**** Y*****');
});

test('Google tekil güçlü eşleşmede @ahbu.local dairesini otomatik bağlar ve gerçek e-postaya yükseltir', async () => {
  const pinHash = await bcrypt.hash('1234', 4);
  const db = createStatefulMockDb({
    users: [
      {
        user_code: 42,
        full_name: 'Ayşe Yılmaz',
        email: 'a42@ahbu.local',
        login_name: 'ayse.yilmaz',
        role: 'individual',
        email_verified: false,
        password_hash: pinHash,
        must_change_password: true,
      },
    ],
    apartments: [{ id: 7, site_code: 1001, resident_user_code: 42, resident_email: 'ayse@gmail.com', resident_pin_issued: true }],
    sitePeople: [{ id: 9, site_code: 1001, user_code: null, email: 'ayse@gmail.com' }],
  });

  const prevVerify = oauthHooks.verifyProviderToken;
  oauthHooks.verifyProviderToken = async () => ({
    sub: 'google-sub-42',
    email: 'ayse@gmail.com',
    emailVerified: true,
    fullName: 'Ayşe Yılmaz',
  });

  try {
    const res = await authenticateWithOAuth({ provider: 'google', idToken: 'fake-token', db });
    assert.equal(res.ok, true);
    assert.equal(res.is_new_user, false);
    assert.equal(res.claimed_existing_account, true);
    assert.equal(res.user.id, 42);
    assert.equal(res.user.email, 'ayse@gmail.com');
    assert.equal(db.state.users.length, 1);
    assert.equal(db.state.oauthIdentities.length, 1);
    assert.equal(db.state.oauthIdentities[0].user_code, 42);
    assert.equal(db.state.apartments[0].resident_pin_issued, false);
    assert.equal(db.state.sitePeople[0].user_code, 42);
    // Eski geçici 1234 şifresi iptal edilmiş olmalı
    assert.equal(await bcrypt.compare('1234', db.state.users[0].password_hash), false);
    assert.ok(db.state.audits.some((a) => a.action === 'identity.account_claimed'));
  } finally {
    oauthHooks.verifyProviderToken = prevVerify;
  }
});

test('Çoklu güçlü eşleşmede otomatik birleştirme yapılmaz; maskeli challenge üretilir ve credentials ile doğrulanır', async () => {
  const pwdHash = await bcrypt.hash('Gizli123!', 4);
  const db = createStatefulMockDb({
    users: [
      {
        user_code: 11,
        full_name: 'Fatma Kaya',
        email: 'd11@ahbu.local',
        login_name: 'fatma.kaya',
        role: 'individual',
        email_verified: false,
        password_hash: pwdHash,
      },
      {
        user_code: 12,
        full_name: 'Hasan Kaya',
        email: 'd12@ahbu.local',
        login_name: 'hasan.kaya',
        role: 'individual',
        email_verified: false,
        password_hash: pwdHash,
      },
    ],
    apartments: [
      { id: 1, site_code: 1001, resident_user_code: 11, resident_email: 'ortak@gmail.com' },
      { id: 2, site_code: 1001, resident_user_code: 12, resident_email: 'ortak@gmail.com' },
    ],
  });

  const prevVerify = oauthHooks.verifyProviderToken;
  oauthHooks.verifyProviderToken = async () => ({
    sub: 'google-ambig-sub',
    email: 'ortak@gmail.com',
    emailVerified: true,
    fullName: 'Fatma Kaya',
  });

  try {
    let thrown = null;
    await assert.rejects(
      () => authenticateWithOAuth({ provider: 'google', idToken: 'tok', db }),
      (err) => {
        thrown = err;
        assert.equal(err.statusCode, 409);
        assert.equal(err.code, 'OAUTH_ACCOUNT_AMBIGUOUS');
        assert.equal(err.extra.claim_verification_required, true);
        assert.equal(err.extra.candidates.length, 2);
        // Tam ad veya dahili e-posta sızmamalı
        assert.equal(err.extra.candidates[0].masked_name, 'F**** K***');
        assert.equal(err.extra.candidates[0].masked_login_name, 'fat***a');
        assert.equal(err.extra.candidates[0].user_code, undefined);
        return true;
      },
    );
    assert.equal(db.state.users.length, 2);

    // Yanlış şifre denemesi reddedilmeli
    await assert.rejects(
      () =>
        verifyIdentityClaimChallenge(
          {
            challengeToken: thrown.extra.challenge_token,
            method: 'credentials',
            identifier: 'fatma.kaya',
            password: 'wrong',
          },
          { db },
        ),
      (err) => err.statusCode === 401 && err.code === 'INVALID_CREDENTIALS',
    );

    // Doğru kullanıcı adı ve şifreyle doğrulama hesabı bağlamalı
    const verified = await verifyIdentityClaimChallenge(
      {
        challengeToken: thrown.extra.challenge_token,
        method: 'credentials',
        identifier: 'fatma.kaya',
        password: 'Gizli123!',
      },
      { db },
    );
    assert.equal(verified.ok, true);
    assert.equal(verified.claimed_existing_account, true);
    assert.equal(verified.user.id, 11);
    assert.equal(db.state.oauthIdentities[0].user_code, 11);

    // Aynı challenge tekrar kullanılamaz (replay koruması)
    await assert.rejects(
      () =>
        verifyIdentityClaimChallenge(
          {
            challengeToken: thrown.extra.challenge_token,
            method: 'credentials',
            identifier: 'fatma.kaya',
            password: 'Gizli123!',
          },
          { db },
        ),
      (err) => err.statusCode === 400 && err.code === 'CLAIM_CHALLENGE_EXPIRED',
    );
  } finally {
    oauthHooks.verifyProviderToken = prevVerify;
  }
});

test('Apple Hide My Email relay ilk girişte normal hesap açar ve is_apple_private_relay ipucu verir; sonraki giriş sub ile tanır', async () => {
  const db = createStatefulMockDb({
    users: [
      {
        user_code: 30,
        full_name: 'Cem Demir',
        email: 'c30@ahbu.local',
        login_name: 'cem.demir',
        role: 'individual',
        email_verified: false,
        password_hash: await bcrypt.hash('1234', 4),
      },
    ],
  });

  const prevVerify = oauthHooks.verifyProviderToken;
  oauthHooks.verifyProviderToken = async () => ({
    sub: 'apple-sub-relay-1',
    email: 'hidden@privaterelay.appleid.com',
    emailVerified: true,
    fullName: 'Cem Demir',
  });

  try {
    const first = await authenticateWithOAuth({ provider: 'apple', idToken: 'apple-tok-1', db });
    assert.equal(first.ok, true);
    assert.equal(first.is_new_user, true);
    assert.equal(first.is_apple_private_relay, true);
    assert.equal(first.can_claim_existing_account, true);
    // Ad benzerliğine dayanarak 30 ile otomatik birleştirme YAPILMAZ!
    assert.notEqual(first.user.id, 30);

    // İkinci girişte aynı Apple sub e-posta olmadan da doğrudan giriş yapar
    oauthHooks.verifyProviderToken = async () => ({
      sub: 'apple-sub-relay-1',
      email: null,
      emailVerified: false,
      fullName: null,
    });
    const second = await authenticateWithOAuth({ provider: 'apple', idToken: 'apple-tok-2', db });
    assert.equal(second.ok, true);
    assert.equal(second.is_new_user, false);
    assert.equal(second.user.id, first.user.id);
  } finally {
    oauthHooks.verifyProviderToken = prevVerify;
  }
});

test('SMS çoklu hesap paylaşımı: tek seferlik OTP doğrulamadan sonra maskeli seçim sunar, hesapları birleştirmez', async () => {
  const sentMessages = [];
  const db = createStatefulMockDb({
    users: [
      {
        user_code: 61,
        full_name: 'Anne Üye',
        email: 'anne@example.com',
        login_name: 'anne.uye',
        role: 'individual',
        email_verified: true,
        phone_number: '05321110000',
        password_hash: 'h1',
      },
      {
        user_code: 62,
        full_name: 'Çocuk Üye',
        email: 'c62@ahbu.local',
        login_name: 'cocuk.uye',
        role: 'individual',
        email_verified: false,
        phone_number: '+905321110000',
        password_hash: 'h2',
      },
    ],
  });

  const prevSms = smsHooks.provider;
  smsHooks.provider = () => ({
    name: 'mock',
    async send(phone, text) {
      sentMessages.push({ phone, text });
      return { ok: true, code: '00' };
    },
  });

  try {
    await requestSmsCode('05321110000', db);
    assert.equal(sentMessages.length, 1);
    const otp = /\b(\d{6})\b/.exec(sentMessages[0].text)?.[1];
    assert.ok(otp);

    const step1 = await verifySmsCode('05321110000', otp, db);
    assert.equal(step1.ok, false);
    assert.equal(step1.account_selection_required, true);
    assert.ok(step1.selection_token);
    assert.equal(step1.candidates.length, 2);

    const step2 = await verifySmsSelection(
      { selectionToken: step1.selection_token, candidateRef: '2' },
      { db },
    );
    assert.equal(step2.ok, true);
    assert.ok(step2.token);
    assert.equal(step2.user.id, 62);
    // İki hesap da aktif ve ayrı kalır
    assert.equal(db.state.users.filter((u) => u.is_active).length, 2);
  } finally {
    smsHooks.provider = prevSms;
  }
});

test('claimExistingAccountForSession: kullanılmayan bireysel hesabı mevcut daire hesabıyla güvenli biçimde birleştirir; aktif yetkili hesabı reddeder', async () => {
  const db = createStatefulMockDb({
    users: [
      {
        user_code: 10,
        full_name: 'Mehmet Öz',
        email: 'm10@ahbu.local',
        login_name: 'mehmet.oz',
        role: 'individual',
        email_verified: false,
        password_hash: await bcrypt.hash('1234', 4),
        must_change_password: true,
      },
      {
        user_code: 90,
        full_name: 'Mehmet Öz',
        email: 'mehmet.oz@gmail.com',
        login_name: null,
        role: 'individual',
        email_verified: true,
        phone_number: '05334445566',
        password_hash: 'h90',
      },
      {
        user_code: 91,
        full_name: 'Başka Yetkili',
        email: 'yetkili@gmail.com',
        role: 'individual',
        email_verified: true,
        password_hash: 'h91',
      },
    ],
    apartments: [{ id: 5, site_code: 1001, resident_user_code: 10, resident_email: 'mehmet.oz@gmail.com', resident_pin_issued: true }],
    oauthIdentities: [{ id: 3, user_code: 90, provider: 'google', provider_sub: 'g-90', email: 'mehmet.oz@gmail.com' }],
    joinRequests: [{ id: 8, user_code: 90, status: 'PENDING' }],
    siteMemberships: [{ site_code: 1002, user_code: 91, is_active: true }],
  });

  // Başka sitede aktif üyeliği olan hesap birleştirilemez
  await assert.rejects(
    () =>
      claimExistingAccountForSession(
        { id: 91, userCode: 91, role: 'individual' },
        { identifier: 'mehmet.oz', password: '1234', method: 'credentials' },
        { db },
      ),
    (err) => err.statusCode === 409 && err.code === 'CLAIM_REQUIRES_ADMIN_MERGE',
  );

  // Kullanılmayan bireysel hesap (90) doğrudan mevcut daire hesabıyla (10) birleşir
  const res = await claimExistingAccountForSession({ id: 90, userCode: 90, role: 'individual' }, {}, { db });
  assert.equal(res.ok, true);
  assert.equal(res.claimed_existing_account, true);
  assert.equal(res.user.id, 10);
  assert.equal(res.user.email, 'mehmet.oz@gmail.com');
  assert.ok(res.token);
  assert.equal(db.state.users.find((u) => u.user_code === 90).is_active, false);
  assert.equal(db.state.oauthIdentities[0].user_code, 10);
  assert.equal(db.state.joinRequests[0].status, 'CANCELLED');
  assert.equal(db.state.apartments[0].resident_pin_issued, false);
  assert.ok(db.state.audits.some((a) => a.action === 'identity.account_merged'));
});

test('claimExistingAccountForSession: standart SMS HMAC koduyla hedef hesabi sahiplenir', async () => {
  const phone = '+905322223344';
  const code = '123456';
  const db = createStatefulMockDb({
    users: [
      { user_code: 20, full_name: 'Daire Hesabi', email: 'd20@ahbu.local', role: 'individual', email_verified: false, phone_number: phone, password_hash: 'h20' },
      { user_code: 95, full_name: 'Yeni Hesap', email: 'yeni@example.com', role: 'individual', email_verified: true, password_hash: 'h95' },
    ],
    apartments: [{ id: 7, site_code: 1001, resident_user_code: 20, resident_pin_issued: false }],
  });
  db.state.smsCodes.push({
    id: db.state.nextSmsId++,
    phone,
    user_code: null,
    code_hash: crypto.createHmac('sha256', process.env.JWT_SECRET).update(`${phone}:${code}`).digest('hex'),
    attempts: 0,
    expires_at: new Date(Date.now() + 300_000),
    consumed_at: null,
    created_at: new Date(),
  });

  const res = await claimExistingAccountForSession(
    { id: 95, userCode: 95, role: 'individual' },
    { method: 'sms_otp', phone, code },
    { db },
  );

  assert.equal(res.claimed_existing_account, true);
  assert.equal(res.user.id, 20);
  assert.ok(db.state.smsCodes[0].consumed_at);
  assert.equal(db.state.users.find((u) => u.user_code === 95).is_active, false);
});

test('requestIdentityClaimSmsCodeChallenge telefonda eşleşme yoksa bile sızdırmaz nötr cevap döner', async () => {
  const db = createStatefulMockDb({ users: [] });
  const token = crypto.randomBytes(16).toString('hex');
  db.state.challenges.push({
    id: 99,
    token_hash: crypto.createHash('sha256').update(token).digest('hex'),
    challenge_kind: 'apple_relay_claim',
    provider: 'apple',
    provider_sub: 'apple-sub',
    candidate_user_codes: [],
    attempts: 0,
    max_attempts: 5,
    expires_at: new Date(Date.now() + 600_000),
    consumed_at: null,
  });

  const sent = [];
  const res = await requestIdentityClaimSmsCode(
    { challengeToken: token, phone: '05320001122' },
    {
      db,
      smsProvider: () => ({
        name: 'mock',
        async send(p, t) {
          sent.push({ p, t });
          return { ok: true, code: '00' };
        },
      }),
    },
  );
  assert.equal(res.ok, true);
  assert.equal(sent.length, 0);
});
