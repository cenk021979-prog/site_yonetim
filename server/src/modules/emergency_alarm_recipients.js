// Explicit alarm assignments grant only alarm access; never a general site/door role.
import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { alarmError, alarmId, RESPONDER_ROLES } from './emergency_alarm_common.js';
import { alarmAccountEligibleSql, isAlarmResidentSql, isManagerSql, isSecuritySql, validVendorSql } from './emergency_alarm_access.js';

export const alarmSiteLock = async (db, siteCode) => db.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`emergency_site:${siteCode}`]);
export const MANAGER_RECIPIENTS_SQL = `SELECT u.user_code, 'manager'::TEXT AS role FROM users u WHERE ${alarmAccountEligibleSql()} AND ${isManagerSql('$1', 'u.user_code')} ORDER BY u.user_code`;
export const SOUND_RECIPIENTS_SQL = `SELECT er.user_code, er.role FROM emergency_responders er
  JOIN users u ON u.user_code = er.user_code AND ${alarmAccountEligibleSql()}
  WHERE er.site_code = $1 AND NOT ${isManagerSql('$1', 'er.user_code')} AND (
    (er.role = 'security' AND ${isSecuritySql('$1', 'er.user_code')})
    OR (er.role = 'elevator_service' AND $2::TEXT = 'elevator' AND er.vendor_id = $3::BIGINT AND ${validVendorSql('$1', 'er.vendor_id')})
  ) ORDER BY er.user_code`;

export const FIRE_RESIDENT_RECIPIENTS_SQL = `SELECT u.user_code, 'resident'::TEXT AS role FROM users u
  WHERE ${alarmAccountEligibleSql()} AND NOT ${isManagerSql('$1', 'u.user_code')}
    AND ${isAlarmResidentSql('$1', 'u.user_code', '$2::BIGINT')} ORDER BY u.user_code`;

export async function selectAlarmRecipients(db, { siteCode, kind, vendorId, locationId }) {
  const managers = (await db.query(MANAGER_RECIPIENTS_SQL, [siteCode])).rows ?? [];
  const responders = (await db.query(SOUND_RECIPIENTS_SQL, [siteCode, kind, vendorId])).rows ?? [];
  const residents = kind === 'fire' ? (await db.query(FIRE_RESIDENT_RECIPIENTS_SQL,
    [siteCode, locationId?.startsWith('block:') ? Number(locationId.slice(6)) : null])).rows ?? [] : [];
  // Manager remains silent; explicit security assignment takes precedence over resident membership.
  const unique = new Map();
  for (const recipient of [...managers, ...responders, ...residents]) {
    const key = String(recipient.user_code);
    if (!unique.has(key)) unique.set(key, recipient);
  }
  const rows = [...unique.values()];
  const residentCount = rows.filter((r) => r.role === 'resident').length;
  const security = responders.filter((r) => r.role === 'security').length;
  const service = responders.filter((r) => r.role === 'elevator_service').length;
  const warnings = [];
  if (!security) warnings.push('NO_SECURITY_ACCOUNT');
  if (kind === 'elevator' && !vendorId) warnings.push('NO_ELEVATOR_VENDOR');
  if (kind === 'elevator' && vendorId && !service) warnings.push('NO_ELIGIBLE_SERVICE_ACCOUNT');
  if (!managers.length) warnings.push('NO_MANAGER_ACCOUNT');
  if (kind === 'fire' && !residentCount) warnings.push('NO_RESIDENT_ACCOUNT');
  return { rows, delivery: { security_assigned: security, service_assigned: service, manager_notified: managers.length,
    ...(kind === 'fire' ? { resident_assigned: residentCount } : {}), warnings } };
}

export async function getAlarmResponders(siteCode, db = pool) {
  const responders = await db.query(`SELECT er.id, er.user_code, u.full_name AS user_name, u.login_name, er.role, er.vendor_id, v.name AS vendor_name,
    (${alarmAccountEligibleSql()} AND NOT ${isManagerSql('er.site_code', 'er.user_code')} AND
      ((er.role = 'security' AND ${isSecuritySql('er.site_code', 'er.user_code')}) OR (er.role = 'elevator_service' AND ${validVendorSql('er.site_code', 'er.vendor_id')}))) AS eligible
    FROM emergency_responders er JOIN users u ON u.user_code = er.user_code
    LEFT JOIN contract_vendors v ON v.id = er.vendor_id AND v.site_code = er.site_code
    WHERE er.site_code = $1 ORDER BY er.role, u.full_name, er.id`, [siteCode]);
  const staff = await db.query(`SELECT DISTINCT u.user_code, u.full_name AS user_name FROM users u JOIN site_memberships sm ON sm.user_code = u.user_code
    WHERE sm.site_code = $1 AND sm.is_active = TRUE AND sm.role = 'STAFF' AND ${alarmAccountEligibleSql()}
      AND NOT ${isManagerSql('$1', 'u.user_code')} ORDER BY u.full_name, u.user_code`, [siteCode]);
  const vendors = await db.query(`SELECT cv.id, cv.name, ${validVendorSql('cv.site_code', 'cv.id')} AS has_active_contract
    FROM contract_vendors cv WHERE cv.site_code = $1 AND cv.is_active = TRUE AND cv.category = 'asansor' ORDER BY cv.name, cv.id`, [siteCode]);
  const numberFields = (r) => ({ ...r, ...(r.id != null ? { id: Number(r.id) } : {}), ...(r.user_code != null ? { user_code: Number(r.user_code) } : {}), ...(r.vendor_id != null ? { vendor_id: Number(r.vendor_id) } : {}) });
  return { responders: responders.rows.map(numberFields), security_candidates: staff.rows.map(numberFields), vendors: vendors.rows.map(numberFields) };
}

export async function saveAlarmResponders({ siteCode, body, actor }, db = pool) {
  if (!Array.isArray(body?.responders) || body.responders.length > 30) throw alarmError(400, 'INVALID_BODY', 'En çok 30 alarm alıcısı gönderilebilir.');
  const input = body.responders.map((r) => {
    if (!r || !RESPONDER_ROLES.includes(r.role)) throw alarmError(400, 'INVALID_BODY', 'Alarm alıcısının görevi geçersiz.');
    const vendorId = r.role === 'elevator_service' ? alarmId(r.vendor_id, 'vendor_id') : null;
    if (r.role === 'security' && r.vendor_id != null) throw alarmError(400, 'INVALID_BODY', 'Güvenlik alıcısına firma atanamaz.');
    const userCode = r.user_code == null ? null : alarmId(r.user_code, 'user_code');
    const login = typeof r.login_name === 'string' ? r.login_name.trim() : '';
    if (!userCode && (!login || login.length > 120)) throw alarmError(400, 'INVALID_BODY', 'Kayıtlı uygulama hesabının kullanıcı adını girin.');
    return { role: r.role, vendorId, userCode, login };
  });
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    await alarmSiteLock(client, siteCode);
    const checked = [];
    for (const r of input) {
      const account = await client.query(`SELECT u.user_code,
        ${isManagerSql('$1', 'u.user_code')} AS is_manager,
        ${isSecuritySql('$1', 'u.user_code')} AS is_security,
        ${validVendorSql('$1', '$4::BIGINT')} AS valid_vendor
        FROM users u WHERE ${alarmAccountEligibleSql()} AND
        (($2::INTEGER IS NOT NULL AND u.user_code = $2) OR ($2::INTEGER IS NULL AND LOWER(u.login_name) = LOWER($3))) LIMIT 1`,
      [siteCode, r.userCode, r.login, r.vendorId]);
      const user = account.rows?.[0];
      if (!user) throw alarmError(400, 'RESPONDER_ACCOUNT_INVALID', 'Alarm alabilecek, e-postası doğrulanmış ve onaylı uygulama hesabı bulunamadı.');
      if (user.is_manager) throw alarmError(400, 'MANAGER_NOTIFICATION_ONLY', 'Site yöneticisi yalnız bildirim alır; sesli alarm alıcısı atanamaz.');
      if (r.role === 'security' && !user.is_security) throw alarmError(400, 'RESPONDER_NOT_STAFF', 'Güvenlik alıcısı bu sitenin aktif görevlisi olmalıdır.');
      if (r.role === 'elevator_service' && !user.valid_vendor) throw alarmError(400, 'SERVICE_CONTRACT_REQUIRED', 'Bu sitede geçerli aktif asansör sözleşmesi olan bir firma seçin.');
      const code = Number(user.user_code);
      if (checked.some((c) => c.userCode === code)) throw alarmError(400, 'DUPLICATE_RESPONDER', 'Aynı hesap bir kez atanabilir.');
      checked.push({ ...r, userCode: code });
    }
    await client.query('DELETE FROM emergency_responders WHERE site_code = $1', [siteCode]);
    for (const r of checked) await client.query('INSERT INTO emergency_responders (site_code, user_code, role, vendor_id) VALUES ($1, $2, $3, $4)', [siteCode, r.userCode, r.role, r.vendorId]);
    await recordAudit(client, { actor: actorFromAuthUser(actor), action: 'emergency.responders_updated', siteCode, targetType: 'site', targetId: String(siteCode), details: { count: checked.length } }, { inTransaction: true });
    await client.query('COMMIT');
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); throw error; }
  finally { client.release(); }
  return getAlarmResponders(siteCode, db);
}
