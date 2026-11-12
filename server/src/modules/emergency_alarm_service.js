import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { alarmError, alarmId, alarmNotFound, alarmUserCode, mapAlarm, parseAlarmInput } from './emergency_alarm_common.js';
import { alarmAccountEligibleSql, assertAlarmResident, isAlarmResidentSql, isManagerSql, isSecuritySql, recipientAccessSql, validVendorSql } from './emergency_alarm_access.js';
import { alarmSiteLock, selectAlarmRecipients } from './emergency_alarm_recipients.js';
import { notifyAlarmRecipients } from './emergency_alarm_push.js';
import { cleanText, clipChars } from '../utils/safe_text.js';
import { elevatorScopeSql } from './emergency_elevator_scope.js';

export const emergencyAlarmHooks = { notify: notifyAlarmRecipients };
const audit = (db, actor, action, siteCode, id, details = {}) => recordAudit(db, {
  actor: actorFromAuthUser(actor), action, siteCode, targetType: 'emergency_alarm', targetId: String(id), details,
}, { inTransaction: true });

export async function listAlarmElevators({ authUser, siteCode: rawSite }, db = pool) {
  const siteCode = alarmId(rawSite, 'site_code');
  await assertAlarmResident(db, authUser, siteCode);
  const found = await db.query(`SELECT eq.id, eq.name, eq.location, eq.block_id,
    (SELECT sb.block_name FROM site_blocks sb WHERE sb.id = eq.block_id AND sb.site_code = eq.site_code) AS block_name
    FROM equipment_items eq WHERE eq.site_code = $1 AND eq.kind = 'asansor' AND eq.is_active = TRUE
      AND ${elevatorScopeSql('eq', '$1', '$2')} ORDER BY eq.name, eq.id`, [siteCode, alarmUserCode(authUser)]);
  return { elevators: found.rows.map((r) => ({ id: Number(r.id), name: r.name, location: r.location, block_id: r.block_id == null ? null : Number(r.block_id), block_name: r.block_name ?? null })) };
}

export async function listAlarmLocations({ authUser, siteCode: rawSite }, db = pool) {
  const siteCode = alarmId(rawSite, 'site_code');
  await assertAlarmResident(db, authUser, siteCode);
  const found = await db.query('SELECT id, block_name FROM site_blocks WHERE site_code = $1 ORDER BY block_name, id', [siteCode]);
  return { locations: [{ id: 'site', name: 'Tüm site / Ortak alan', block_id: null }, ...found.rows.map((r) => ({ id: `block:${r.id}`, name: r.block_name, block_id: Number(r.id) }))] };
}

export async function createEmergencyAlarm({ authUser, body }, db = pool) {
  if (authUser?.trial) throw alarmError(403, 'TRIAL_ACTION_DENIED', 'Deneme oturumunda acil alarm oluşturulamaz.');
  const input = parseAlarmInput(body);
  const userCode = alarmUserCode(authUser);
  const client = await db.connect();
  let result;
  try {
    await client.query('BEGIN');
    const user = await client.query('SELECT user_code, full_name FROM users WHERE user_code = $1 AND is_active = TRUE AND deleted_at IS NULL FOR KEY SHARE', [userCode]);
    if (!user.rows?.length) throw alarmError(403, 'ACCOUNT_INACTIVE', 'Hesap etkin değil.');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`emergency_user:${userCode}`]);
    const site = await assertAlarmResident(client, authUser, input.siteCode);
    await alarmSiteLock(client, input.siteCode);
    const prior = (await client.query('SELECT a.*, s.name AS site_name FROM emergency_alarms a JOIN sites s ON s.site_code = a.site_code WHERE a.created_by = $1 AND a.idempotency_key = $2', [userCode, input.key])).rows?.[0];
    if (prior) {
      if (Number(prior.site_code) !== input.siteCode || prior.kind !== input.kind || Number(prior.equipment_id ?? 0) !== Number(input.equipmentId ?? 0) || (prior.request_location ?? null) !== input.locationId) {
        throw alarmError(409, 'IDEMPOTENCY_CONFLICT', 'Bu işlem anahtarı farklı bir alarm için kullanılmış.');
      }
      result = { alarm: mapAlarm(prior), delivery: prior.delivery, replayed: true };
    } else {
      const rate = (await client.query(`SELECT COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 minute')::INTEGER AS minute_count,
        COUNT(*)::INTEGER AS hour_count FROM emergency_alarms WHERE created_by = $1 AND created_at > NOW() - INTERVAL '1 hour'`, [userCode])).rows[0];
      if (Number(rate.minute_count) >= 6 || Number(rate.hour_count) >= 60) throw alarmError(429, 'ALARM_RATE_LIMIT', 'Çok sayıda alarm oluşturdunuz. Biraz sonra tekrar deneyin.', { retry_after_seconds: 60 });
      let equipment = null;
      let location = null;
      if (input.kind === 'elevator') {
        equipment = (await client.query(`SELECT eq.id, eq.name, eq.location, eq.vendor_id FROM equipment_items eq
          WHERE eq.id = $1 AND eq.site_code = $2 AND eq.kind = 'asansor' AND eq.is_active = TRUE
            AND ${elevatorScopeSql('eq', '$2', '$3')} FOR KEY SHARE OF eq`, [input.equipmentId, input.siteCode, userCode])).rows?.[0];
        if (!equipment) throw alarmError(400, 'ELEVATOR_NOT_AVAILABLE', 'Bu sitede kayıtlı aktif bir asansör seçin.');
        location = equipment.location;
      } else if (input.locationId === 'site') {
        location = 'Ortak alan';
      } else {
        const block = (await client.query('SELECT block_name FROM site_blocks WHERE id = $1 AND site_code = $2 FOR KEY SHARE', [alarmId(input.locationId.slice(6)), input.siteCode])).rows?.[0];
        if (!block) throw alarmError(400, 'LOCATION_NOT_AVAILABLE', 'Bu sitenin kayıtlı blok veya ortak alanını seçin.');
        location = block.block_name;
      }
      // Older block records have no length constraint; selecting one must not fail a new alarm CHECK.
      location = location == null ? null : clipChars(cleanText(String(location)).replace(/\s+/g, ' ').trim(), 120) || null;
      const selected = await selectAlarmRecipients(client, { siteCode: input.siteCode, kind: input.kind, vendorId: equipment?.vendor_id ?? null, locationId: input.locationId });
      const actorName = clipChars(cleanText(String(user.rows[0].full_name ?? '')).replace(/\s+/g, ' ').trim(), 200) || null;
      const created = (await client.query(`INSERT INTO emergency_alarms (site_code, created_by, kind, equipment_id, vendor_id, equipment_name, location, request_location, idempotency_key, delivery, created_by_name)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::JSONB,$11) RETURNING *`,
      [input.siteCode, userCode, input.kind, input.equipmentId, equipment?.vendor_id ?? null, equipment?.name ?? null, location, input.locationId, input.key, JSON.stringify(selected.delivery), actorName])).rows[0];
      if (selected.rows.length) await client.query(`INSERT INTO emergency_alarm_recipients (alarm_id, user_code, role)
        SELECT $1, recipients.user_code, recipients.role FROM UNNEST($2::INTEGER[], $3::TEXT[]) AS recipients(user_code, role) ON CONFLICT DO NOTHING`,
      [created.id, selected.rows.map((r) => r.user_code), selected.rows.map((r) => r.role)]);
      await audit(client, authUser, 'emergency.alarm_created', input.siteCode, created.id, { kind: input.kind, equipment_id: input.equipmentId, recipients: selected.rows.length });
      result = { alarm: mapAlarm({ ...created, site_name: site.site_name }), delivery: selected.delivery, replayed: false };
    }
    await client.query('COMMIT');
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); throw error; }
  finally { client.release(); }
  // Provider failure never turns a committed alarm into a transport error or a false playback claim.
  if (!result.replayed) void Promise.resolve().then(() => emergencyAlarmHooks.notify(result.alarm, db)).catch(() => {});
  return result;
}

export const RECEIVER_FLAGS_SQL = `SELECT
  EXISTS (SELECT 1 FROM users au WHERE au.user_code = $1 AND ${alarmAccountEligibleSql('au')}) AND
  EXISTS (SELECT 1 FROM sites s WHERE s.approval_status = 'approved' AND ${isManagerSql('s.site_code', '$1')}) AS manager,
  EXISTS (SELECT 1 FROM users au WHERE au.user_code = $1 AND ${alarmAccountEligibleSql('au')}) AND
  (EXISTS (SELECT 1 FROM emergency_responders er JOIN sites s ON s.site_code = er.site_code AND s.approval_status = 'approved'
    WHERE er.user_code = $1 AND NOT ${isManagerSql('er.site_code', '$1')} AND (
      (er.role = 'security' AND ${isSecuritySql('er.site_code', '$1')}) OR (er.role = 'elevator_service' AND ${validVendorSql('er.site_code', 'er.vendor_id')})
    )) OR EXISTS (SELECT 1 FROM sites s WHERE s.approval_status = 'approved'
      AND NOT ${isManagerSql('s.site_code', '$1')} AND ${isAlarmResidentSql('s.site_code', '$1')})) AS sound`;

export const ALARM_FEED_SQL = `SELECT a.*, s.name AS site_name, (r.role <> 'manager') AS sound_enabled, r.received_at, r.played_at
  FROM emergency_alarm_recipients r JOIN emergency_alarms a ON a.id = r.alarm_id
  JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
  WHERE r.user_code = $1 AND r.acknowledged_at IS NULL AND a.status <> 'resolved' AND ${recipientAccessSql()}
  ORDER BY a.id DESC LIMIT 101`;

export async function listEmergencyAlarms(authUser, db = pool) {
  if (authUser?.trial) return { alarms: [], can_receive: false, can_sound: false, has_more: false };
  const userCode = alarmUserCode(authUser);
  if (authUser?.role === 'super_user') return { alarms: [], can_receive: false, can_sound: false, has_more: false };
  const flags = (await db.query(RECEIVER_FLAGS_SQL, [userCode])).rows?.[0] ?? {};
  if (!flags.manager && !flags.sound) return { alarms: [], can_receive: false, can_sound: false, has_more: false };
  const rows = (await db.query(ALARM_FEED_SQL, [userCode])).rows;
  return { alarms: rows.slice(0, 100).map((r) => ({ ...mapAlarm(r, r.sound_enabled), received_at: r.received_at, played_at: r.played_at })), can_receive: true, can_sound: flags.sound === true, has_more: rows.length > 100 };
}

export async function listEmergencyAlarmHistory({ authUser, beforeId }, db = pool) {
  if (authUser?.trial || authUser?.role === 'super_user') return { alarms: [], has_more: false };
  const userCode = alarmUserCode(authUser);
  const before = beforeId == null ? null : alarmId(beforeId, 'before_id');
  const rows = (await db.query(`SELECT a.*, s.name AS site_name FROM emergency_alarms a
    JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
    LEFT JOIN emergency_alarm_recipients r ON r.alarm_id = a.id AND r.user_code = $1
    WHERE ($2::BIGINT IS NULL OR a.id < $2) AND EXISTS (SELECT 1 FROM users au WHERE au.user_code = $1 AND ${alarmAccountEligibleSql('au')})
      AND (${isManagerSql('a.site_code', '$1')}
        OR (a.created_by = $1 AND ${isAlarmResidentSql('a.site_code', '$1')})
        OR ${recipientAccessSql()})
    ORDER BY a.id DESC LIMIT 51`, [userCode, before])).rows;
  return { alarms: rows.slice(0, 50).map((r) => mapAlarm(r)), has_more: rows.length > 50 };
}

export async function markEmergencyAlarm({ authUser, rawId, action }, db = pool) {
  if (authUser?.trial) throw alarmError(403, 'TRIAL_ACTION_DENIED', 'Deneme oturumunda acil alarm işlemi yapılamaz.');
  const userCode = alarmUserCode(authUser);
  const id = alarmId(rawId);
  if (!['received', 'played', 'ack', 'resolve'].includes(action)) throw alarmError(400, 'INVALID_ACTION', 'Geçersiz alarm işlemi.');
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const row = (await client.query(`SELECT a.*, r.role AS recipient_role FROM emergency_alarms a
      JOIN emergency_alarm_recipients r ON r.alarm_id = a.id AND r.user_code = $2
      JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
      WHERE a.id = $1 AND ${recipientAccessSql()} FOR UPDATE OF a, r`, [id, userCode])).rows?.[0];
    if (!row || authUser?.role === 'super_user') throw alarmNotFound();
    if (action === 'resolve' && row.recipient_role === 'resident') throw alarmError(403, 'ALARM_RESOLVE_FORBIDDEN', 'Sakin yalnız kendi alarmını susturabilir; olayı yönetim veya görevli kapatır.');
    if (action === 'played' && row.recipient_role === 'manager') throw alarmError(403, 'ALARM_SOUND_FORBIDDEN', 'Yönetici yalnız bildirim alır.');
    if (row.status === 'resolved') {
      await client.query('COMMIT');
      return { ok: true, status: 'resolved' };
    }
    if (action === 'resolve') {
      await client.query("UPDATE emergency_alarms SET status = 'resolved', resolved_at = NOW() WHERE id = $1", [id]);
      await audit(client, authUser, 'emergency.alarm_resolved', Number(row.site_code), id);
    } else {
      const column = { received: 'received_at', played: 'played_at', ack: 'acknowledged_at' }[action];
      const received = column === 'received_at' ? '' : ', received_at = COALESCE(received_at, NOW())';
      await client.query(`UPDATE emergency_alarm_recipients SET ${column} = COALESCE(${column}, NOW())${received} WHERE alarm_id = $1 AND user_code = $2`, [id, userCode]);
      if (action === 'ack' && ['security', 'elevator_service'].includes(row.recipient_role)) await client.query("UPDATE emergency_alarms SET status = 'acknowledged', acknowledged_at = COALESCE(acknowledged_at, NOW()) WHERE id = $1", [id]);
      if (action === 'ack') await audit(client, authUser, 'emergency.alarm_acknowledged', Number(row.site_code), id, { role: row.recipient_role });
    }
    await client.query('COMMIT');
    return { ok: true, status: action === 'resolve' ? 'resolved' : action === 'ack' && ['security', 'elevator_service'].includes(row.recipient_role) ? 'acknowledged' : row.status };
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); throw error; }
  finally { client.release(); }
}
