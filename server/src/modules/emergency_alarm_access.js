import { pool } from '../db.js';
import { alarmError, alarmUserCode } from './emergency_alarm_common.js';

// authRequired rejects false/NULL verification and exact pending/rejected states. NULL legacy approval is allowed.
// The global super-user feed is deliberately empty, so it can never be an actual alarm recipient.
export const alarmAccountEligibleSql = (alias = 'u') => `(${alias}.is_active IS TRUE AND ${alias}.deleted_at IS NULL
  AND ${alias}.email_verified IS TRUE AND COALESCE(${alias}.approval_status, '') NOT IN ('pending', 'rejected')
  AND ${alias}.role IS DISTINCT FROM 'super_user')`;

// Door overrides / STAFF / global role alone do not make a resident.
export const RESIDENT_SITES_SQL = `SELECT DISTINCT s.site_code, s.name AS site_name, s.address, s.city, s.district
  FROM sites s WHERE s.approval_status = 'approved' AND (
    EXISTS (SELECT 1 FROM apartment_memberships am JOIN apartments ap ON ap.id = am.apartment_id
      WHERE am.user_code = $1 AND am.is_active = TRUE AND ap.is_active = TRUE AND ap.site_code = s.site_code)
    OR EXISTS (SELECT 1 FROM apartments ap WHERE ap.site_code = s.site_code AND ap.is_active = TRUE AND ap.resident_user_code = $1)
    OR EXISTS (SELECT 1 FROM site_people sp JOIN apartment_residencies ar ON ar.person_id = sp.id AND ar.is_current = TRUE
      JOIN apartments ap ON ap.id = ar.apartment_id AND ap.site_code = sp.site_code AND ap.is_active = TRUE
      WHERE sp.site_code = s.site_code AND sp.user_code = $1 AND sp.is_active = TRUE)
  ) ORDER BY s.name, s.site_code`;

export const isManagerSql = (site, user) => `(EXISTS (SELECT 1 FROM site_manager_sites sms WHERE sms.site_code = ${site} AND sms.manager_user_code = ${user})
  OR EXISTS (SELECT 1 FROM site_memberships sm WHERE sm.site_code = ${site} AND sm.user_code = ${user} AND sm.is_active = TRUE AND sm.role IN ('SITE_OWNER', 'SITE_ADMIN')))`;
export const isSecuritySql = (site, user) => `EXISTS (SELECT 1 FROM site_memberships sm WHERE sm.site_code = ${site} AND sm.user_code = ${user} AND sm.is_active = TRUE AND sm.role = 'STAFF')`;
export const validVendorSql = (site, vendor) => `EXISTS (SELECT 1 FROM contract_vendors cv WHERE cv.id = ${vendor} AND cv.site_code = ${site} AND cv.is_active = TRUE AND cv.category = 'asansor'
  AND EXISTS (SELECT 1 FROM site_contracts sc WHERE sc.vendor_id = cv.id AND sc.site_code = cv.site_code AND sc.category = 'asansor' AND sc.status = 'aktif'
    AND sc.start_date <= (NOW() AT TIME ZONE 'Europe/Istanbul')::DATE AND (sc.end_date IS NULL OR sc.end_date >= (NOW() AT TIME ZONE 'Europe/Istanbul')::DATE)))`;

// Real apartment associations only. A door override or generic site STAFF role never grants a fire broadcast.
export const isAlarmResidentSql = (site, user, block = 'NULL::BIGINT') => `EXISTS (
  SELECT 1 FROM apartments rap WHERE rap.site_code = ${site} AND rap.is_active = TRUE
    AND (${block} IS NULL OR rap.block_id = ${block}) AND (
      rap.resident_user_code = ${user}
      OR EXISTS (SELECT 1 FROM apartment_memberships ram WHERE ram.apartment_id = rap.id AND ram.user_code = ${user} AND ram.is_active = TRUE)
      OR EXISTS (SELECT 1 FROM apartment_residencies rar JOIN site_people rsp ON rsp.id = rar.person_id
        WHERE rar.apartment_id = rap.id AND rar.is_current = TRUE AND rsp.site_code = rap.site_code AND rsp.user_code = ${user} AND rsp.is_active = TRUE)
    ))`;
export const fireResidentAccessSql = (site, user, location) => `((${location} = 'site' AND ${isAlarmResidentSql(site, user)})
  OR (${location} ~ '^block:[1-9][0-9]{0,15}$' AND ${isAlarmResidentSql(site, user, `(CASE WHEN ${location} ~ '^block:[1-9][0-9]{0,15}$' THEN SUBSTRING(${location} FROM 7)::BIGINT END)`)}))`;

// Rechecked for every feed/ACK; a saved recipient row is not an enduring authorization.
export const recipientAccessSql = (a = 'a', r = 'r') => `EXISTS (SELECT 1 FROM users au WHERE au.user_code = ${r}.user_code AND ${alarmAccountEligibleSql('au')}) AND (
  (${r}.role = 'manager' AND ${isManagerSql(`${a}.site_code`, `${r}.user_code`)})
  OR (${r}.role = 'resident' AND ${a}.kind = 'fire' AND NOT ${isManagerSql(`${a}.site_code`, `${r}.user_code`)}
    AND ${fireResidentAccessSql(`${a}.site_code`, `${r}.user_code`, `${a}.request_location`)})
  OR (${r}.role <> 'manager' AND NOT ${isManagerSql(`${a}.site_code`, `${r}.user_code`)} AND EXISTS (
    SELECT 1 FROM emergency_responders er WHERE er.site_code = ${a}.site_code AND er.user_code = ${r}.user_code AND er.role = ${r}.role AND (
      (er.role = 'security' AND ${isSecuritySql(`${a}.site_code`, `${r}.user_code`)})
      OR (er.role = 'elevator_service' AND ${a}.kind = 'elevator' AND er.vendor_id = ${a}.vendor_id AND ${validVendorSql(`${a}.site_code`, 'er.vendor_id')}
        AND EXISTS (SELECT 1 FROM equipment_items eq WHERE eq.id = ${a}.equipment_id AND eq.site_code = ${a}.site_code AND eq.is_active = TRUE AND eq.vendor_id = er.vendor_id))
    )
  ))
)`;

export async function listAlarmSites(authUser, db = pool) {
  if (authUser?.role === 'super_user') return { sites: [] };
  const result = await db.query(RESIDENT_SITES_SQL, [alarmUserCode(authUser)]);
  return { sites: (result.rows ?? []).filter((r) => !authUser?.trial || Number(r.site_code) === Number(authUser.trial.siteCode))
    .map((r) => ({ ...r, site_code: Number(r.site_code), can_create: !authUser?.trial, can_edit: false })) };
}
export async function assertAlarmResident(db, authUser, siteCode) {
  const { sites } = await listAlarmSites(authUser, db);
  const site = sites.find((s) => s.site_code === siteCode);
  if (!site) throw alarmError(403, 'NOT_A_RESIDENT', 'Yalnız bağlı olduğunuz sitede sakin olarak alarm oluşturabilirsiniz.');
  return site;
}
