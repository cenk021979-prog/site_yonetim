import { isAlarmResidentSql } from './emergency_alarm_access.js';

// Use the same scope for discovery and dispatch. A site-wide elevator is shared;
// a block elevator requires a real, active apartment association in that block.
export const elevatorScopeSql = (equipment = 'eq', site = '$1', user = '$2') => `(${equipment}.block_id IS NULL OR EXISTS (
  SELECT 1 FROM site_blocks eblock WHERE eblock.id = ${equipment}.block_id AND eblock.site_code = ${site}
    AND ${isAlarmResidentSql(site, user, `${equipment}.block_id`)}))`;
