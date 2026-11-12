// Secondary channel only. Persisted in-app inbox is authoritative; FCM acceptance is not device delivery or playback.
import { pool } from '../db.js';
import { pushDeviceHooks } from './push_devices.js';
import { alarmAccountEligibleSql, isManagerSql, recipientAccessSql } from './emergency_alarm_access.js';

async function notify(alarm, db, managersOnly) {
  try {
    if (!pushDeviceHooks.available()) return { available: false, accepted: 0 };
    const devices = await db.query(`SELECT d.fcm_token, r.role FROM emergency_alarm_recipients r
      JOIN emergency_alarms a ON a.id = r.alarm_id AND a.site_code = $2 AND a.status <> 'resolved'
      JOIN sites s ON s.site_code = a.site_code AND s.approval_status = 'approved'
      JOIN users u ON u.user_code = r.user_code AND ${alarmAccountEligibleSql()}
      JOIN push_devices d ON d.user_code = r.user_code AND d.notifications_enabled
      WHERE r.alarm_id = $1 AND r.acknowledged_at IS NULL AND ${managersOnly ? `r.role = 'manager' AND ${isManagerSql('$2', 'r.user_code')}` : recipientAccessSql()}`, [alarm.id, alarm.site_code]);
    const client = pushDeviceHooks.client();
    let accepted = 0;
    for (const device of devices.rows ?? []) {
      const sound = device.role != null && device.role !== 'manager';
      const result = await client.send({
        token: device.fcm_token,
        notification: { title: 'Site acil bildirimi', body: `${alarm.kind === 'elevator' ? 'Asansör' : 'Yangın'} alarmı oluşturuldu. Uygulamadaki bildirimi inceleyin.` },
        data: { type: 'emergency', alarm_id: String(alarm.id), site_code: String(alarm.site_code), sound_enabled: String(sound) },
        android: { priority: 'HIGH', ttl: '300s', collapse_key: `emergency-${alarm.id}`, notification: { channel_id: sound ? 'emergency_alarm' : 'emergency_info', tag: `emergency-${alarm.id}`, ...(sound ? { sound: 'emergency_alarm' } : {}) } },
        apns: { headers: { 'apns-priority': '10', 'apns-push-type': 'alert', 'apns-collapse-id': `emergency-${alarm.id}`, 'apns-expiration': String(Math.floor(Date.now() / 1000) + 300) }, payload: { aps: { 'interruption-level': sound ? 'active' : 'passive', ...(sound ? { sound: 'default' } : {}) } } },
      });
      if (result?.kind === 'ok') accepted += 1;
    }
    return { available: true, accepted };
  } catch { return { available: true, accepted: 0 }; }
}

// Kept for old callers that explicitly request manager information only.
export const notifyAlarmManagers = (alarm, db = pool) => notify(alarm, db, true);
export const notifyAlarmRecipients = (alarm, db = pool) => notify(alarm, db, false);
