// Site içi acil alarm sözleşmesi; telefon araması veya resmi yardım hattı değildir.
import { PlatformError } from './errors.js';

export const ALARM_KINDS = Object.freeze(['elevator', 'fire']);
export const RESPONDER_ROLES = Object.freeze(['security', 'elevator_service']);
export const alarmError = (status, code, message, extra) => new PlatformError(status, code, message, extra);
export const alarmNotFound = () => alarmError(404, 'ALARM_NOT_FOUND', 'Alarm bulunamadı veya erişiminiz yok.');
export function alarmId(value, field = 'id') {
  const n = Number(value);
  if (!Number.isSafeInteger(n) || n <= 0) throw alarmError(400, 'INVALID_FIELD', 'Geçersiz kimlik.', { field });
  return n;
}
export const alarmUserCode = (user) => alarmId(user?.user_code ?? user?.userCode ?? user?.id, 'user_code');
export function parseAlarmInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || !ALARM_KINDS.includes(body.kind)) {
    throw alarmError(400, 'INVALID_BODY', 'Alarm türü Asansör veya Yangın olmalıdır.');
  }
  const siteCode = alarmId(body.site_code, 'site_code');
  const equipmentId = body.kind === 'elevator' ? alarmId(body.equipment_id, 'equipment_id') : null;
  if (body.kind === 'fire' && body.equipment_id != null) throw alarmError(400, 'INVALID_BODY', 'Yangın alarmına asansör atanamaz.');
  if (typeof body.idempotency_key !== 'string' || !/^[A-Za-z0-9_-]{8,80}$/.test(body.idempotency_key)) {
    throw alarmError(400, 'INVALID_FIELD', 'İşlem anahtarı 8–80 harf, rakam, alt çizgi veya tire olmalıdır.', { field: 'idempotency_key' });
  }
  const locationId = body.kind === 'fire' ? body.location_id : null;
  if (body.kind === 'fire' && (typeof locationId !== 'string' || !/^(site|block:[1-9][0-9]{0,15})$/.test(locationId))) {
    throw alarmError(400, 'INVALID_FIELD', 'Yangın için kayıtlı blok veya ortak alan seçin.', { field: 'location_id' });
  }
  if (locationId?.startsWith('block:')) alarmId(locationId.slice(6), 'location_id');
  return { siteCode, kind: body.kind, equipmentId, key: body.idempotency_key, locationId };
}
export function mapAlarm(row, soundEnabled = false) {
  return {
    id: Number(row.id), site_code: Number(row.site_code), site_name: row.site_name ?? '', kind: row.kind,
    equipment_id: row.equipment_id == null ? null : Number(row.equipment_id), equipment_name: row.equipment_name ?? null,
    location: row.location ?? null, status: row.status, created_at: new Date(row.created_at).toISOString(), sound_enabled: soundEnabled === true,
    created_by: row.created_by == null ? null : Number(row.created_by), created_by_name: row.created_by_name ?? null,
    scope: row.kind === 'fire' ? (row.request_location === 'site' ? 'site' : 'block') : null,
    acknowledged_at: row.acknowledged_at == null ? null : new Date(row.acknowledged_at).toISOString(),
    resolved_at: row.resolved_at == null ? null : new Date(row.resolved_at).toISOString(),
  };
}
