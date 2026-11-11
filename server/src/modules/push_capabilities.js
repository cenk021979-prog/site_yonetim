// An individual account gains only device registration for its actual alarm role;
// it never gains site membership, door access or a general announcement role.
import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { isPushAvailable } from './push_credentials.js';
import { alarmAccountEligibleSql, isAlarmResidentSql, isManagerSql, isSecuritySql, validVendorSql } from './emergency_alarm_access.js';

export const EMERGENCY_PUSH_ELIGIBILITY_SQL = `SELECT EXISTS (
  SELECT 1 FROM users u WHERE u.user_code=$1 AND ${alarmAccountEligibleSql()}
    AND EXISTS (SELECT 1 FROM sites s WHERE s.approval_status='approved' AND (
      ${isManagerSql('s.site_code', 'u.user_code')}
      OR ${isAlarmResidentSql('s.site_code', 'u.user_code')}
      OR EXISTS (SELECT 1 FROM emergency_responders er WHERE er.site_code=s.site_code AND er.user_code=u.user_code AND (
        (er.role='security' AND ${isSecuritySql('s.site_code', 'u.user_code')})
        OR (er.role='elevator_service' AND ${validVendorSql('s.site_code', 'er.vendor_id')})
      ))
    ))
) AS eligible`;

export async function pushCapabilities(authUser, db = pool) {
  let canRegister = !authUser?.trial && ['apartment_owner', 'site_manager'].includes(authUser?.role);
  if (!authUser?.trial && authUser?.role === 'individual') {
    const userCode = Number(authUser.user_code ?? authUser.userCode ?? authUser.id);
    if (Number.isSafeInteger(userCode) && userCode > 0) {
      canRegister = (await db.query(EMERGENCY_PUSH_ELIGIBILITY_SQL, [userCode])).rows?.[0]?.eligible === true;
    }
  }
  return { push_available: isPushAvailable(), can_register: canRegister, emergency_only: canRegister && authUser?.role === 'individual' };
}

export async function assertPushRegistrationAllowed(authUser, db = pool) {
  const capabilities = await pushCapabilities(authUser, db);
  if (!capabilities.can_register) {
    throw new PlatformError(403, 'PUSH_REGISTRATION_FORBIDDEN', 'Bu hesabın telefon bildirimi alabilecek aktif bir görevi veya daire bağı bulunmuyor.');
  }
}
