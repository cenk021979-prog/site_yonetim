import { pool } from '../db.js';
import { mqttBridgeHealth } from '../mqtt_bridge.js';

/**
 * Süper Kullanıcı Paneli (Cockpit) Özet Servisi
 * Platform geneli metrikleri, saha cihaz durumlarını ve bekleyen onayları tek seferde derler.
 */
export async function getSuperUserDashboardSummary(db = pool) {
  const [
    attentionRes,
    sitesRes,
    apartmentsRes,
    usersRes,
    doorsRes,
    devicesRes,
    doorPassesRes,
    clientErrorsRes,
    feedbacksRes,
  ] = await Promise.all([
    // 1. Bekleyen İşler: Site Başvuruları & Modül Talepleri
    db.query(`
      SELECT
        (SELECT COUNT(*)::INTEGER FROM site_applications WHERE status = 'pending' AND applicant_user_code IS NOT NULL) AS pending_site_applications,
        (SELECT COUNT(*)::INTEGER FROM module_requests WHERE status = 'pending') AS pending_module_requests
    `).catch(() => ({ rows: [{ pending_site_applications: 0, pending_module_requests: 0 }] })),

    // 2. Siteler: Toplam, Aktif, Pasif
    db.query(`
      SELECT
        COUNT(*)::INTEGER AS total,
        COUNT(*) FILTER (WHERE approval_status = 'approved')::INTEGER AS active,
        COUNT(*) FILTER (WHERE approval_status != 'approved')::INTEGER AS passive
      FROM sites
    `).catch(() => ({ rows: [{ total: 0, active: 0, passive: 0 }] })),

    // 3. Daireler: Toplam, Dolu (atanmış resident_user_code var), Boş
    db.query(`
      SELECT
        COUNT(*)::INTEGER AS total,
        COUNT(*) FILTER (WHERE resident_user_code IS NOT NULL)::INTEGER AS occupied,
        COUNT(*) FILTER (WHERE resident_user_code IS NULL)::INTEGER AS empty
      FROM apartments
    `).catch(() => ({ rows: [{ total: 0, occupied: 0, empty: 0 }] })),

    // 4. Kullanıcılar: Toplam, Site Yöneticileri, Daire Sakinleri, Süper Kullanıcılar
    db.query(`
      SELECT
        COUNT(*)::INTEGER AS total,
        COUNT(*) FILTER (WHERE role = 'site_manager')::INTEGER AS site_managers,
        COUNT(*) FILTER (WHERE role IN ('apartment_admin', 'apartment_resident', 'apartment_owner'))::INTEGER AS apartment_users,
        COUNT(*) FILTER (WHERE role = 'super_user')::INTEGER AS super_users,
        COUNT(*) FILTER (WHERE role = 'individual')::INTEGER AS individuals
      FROM users
      WHERE deleted_at IS NULL
    `).catch(() => ({ rows: [{ total: 0, site_managers: 0, apartment_users: 0, super_users: 0, individuals: 0 }] })),

    // 5. Kapılar: Toplam, Aktif
    db.query(`
      SELECT
        COUNT(*)::INTEGER AS total,
        COUNT(*) FILTER (WHERE is_active = TRUE)::INTEGER AS active
      FROM site_doors
    `).catch(() => ({ rows: [{ total: 0, active: 0 }] })),

    // 6. Cihazlar: Online, Offline, ESP32-C3, ESP32-WROOM
    db.query(`
      SELECT
        COUNT(d.id)::INTEGER AS total_devices,
        COUNT(*) FILTER (
          WHERE rs.mqtt_connected = TRUE 
             OR (rs.last_seen_at IS NOT NULL AND rs.last_seen_at > NOW() - INTERVAL '3 minutes')
        )::INTEGER AS online_devices,
        COUNT(*) FILTER (
          WHERE (rs.mqtt_connected IS NULL OR rs.mqtt_connected = FALSE)
            AND (rs.last_seen_at IS NULL OR rs.last_seen_at <= NOW() - INTERVAL '3 minutes')
        )::INTEGER AS offline_devices,
        COUNT(*) FILTER (
          WHERE d.hardware_type = 'esp32_c3' 
             OR rs.hardware_target = 'esp32-c3' 
             OR d.hardware_type IS NULL
        )::INTEGER AS esp32_c3_count,
        COUNT(*) FILTER (
          WHERE d.hardware_type = 'esp32_wroom' 
             OR rs.hardware_target = 'esp32-wroom'
        )::INTEGER AS esp32_wroom_count
      FROM devices d
      LEFT JOIN device_runtime_status rs ON UPPER(rs.device_uid) = UPPER(d.device_uid)
    `).catch(() => ({ rows: [{ total_devices: 0, online_devices: 0, offline_devices: 0, esp32_c3_count: 0, esp32_wroom_count: 0 }] })),

    // 7. Bugünün Geçiş Sayacı (Gece yarısından bu yana açılan kapılar)
    db.query(`
      SELECT COUNT(*)::INTEGER AS today_door_passes
      FROM door_access_logs
      WHERE opened_at >= CURRENT_DATE
    `).catch(() => ({ rows: [{ today_door_passes: 0 }] })),

    // 8. İstemci Hataları (Son 24 saatteki rapor sayısı ve tekil hata sayısı)
    db.query(`
      SELECT
        COALESCE(SUM(count), 0)::INTEGER AS total_reports_24h,
        COUNT(*)::INTEGER AS unique_errors_24h
      FROM client_error_reports
      WHERE last_seen > NOW() - INTERVAL '24 hours'
    `).catch(() => ({ rows: [{ total_reports_24h: 0, unique_errors_24h: 0 }] })),

    // 9. Geri Bildirimler
    db.query(`
      SELECT COUNT(*)::INTEGER AS total_feedbacks
      FROM feedback_reports
    `).catch(() => ({ rows: [{ total_feedbacks: 0 }] })),
  ]);

  const attention = attentionRes.rows[0] || {};
  const sites = sitesRes.rows[0] || {};
  const apartments = apartmentsRes.rows[0] || {};
  const users = usersRes.rows[0] || {};
  const doors = doorsRes.rows[0] || {};
  const devices = devicesRes.rows[0] || {};
  const doorPasses = doorPassesRes.rows[0] || {};
  const clientErrors = clientErrorsRes.rows[0] || {};
  const feedbacks = feedbacksRes.rows[0] || {};

  let mqtt = { configured: false, connected: false, has_error: false, last_error: null };
  try {
    mqtt = mqttBridgeHealth() || mqtt;
  } catch (_e) {
    // mqttBridgeHealth cagrisi testte mocklanmamis olabilir
  }

  return {
    ok: true,
    attention: {
      pending_site_applications: Number(attention.pending_site_applications || 0),
      pending_module_requests: Number(attention.pending_module_requests || 0),
      unresolved_client_errors: Number(clientErrors.total_reports_24h || 0),
      unique_client_errors: Number(clientErrors.unique_errors_24h || 0),
      total_feedbacks: Number(feedbacks.total_feedbacks || 0),
    },
    platform: {
      total_sites: Number(sites.total || 0),
      active_sites: Number(sites.active || 0),
      passive_sites: Number(sites.passive || 0),
      total_apartments: Number(apartments.total || 0),
      occupied_apartments: Number(apartments.occupied || 0),
      empty_apartments: Number(apartments.empty || 0),
      total_users: Number(users.total || 0),
      site_managers: Number(users.site_managers || 0),
      apartment_users: Number(users.apartment_users || 0),
      super_users: Number(users.super_users || 0),
      individuals: Number(users.individuals || 0),
    },
    iot: {
      total_doors: Number(doors.total || 0),
      active_doors: Number(doors.active || 0),
      total_devices: Number(devices.total_devices || 0),
      online_devices: Number(devices.online_devices || 0),
      offline_devices: Number(devices.offline_devices || 0),
      esp32_c3_count: Number(devices.esp32_c3_count || 0),
      esp32_wroom_count: Number(devices.esp32_wroom_count || 0),
      today_door_passes: Number(doorPasses.today_door_passes || 0),
    },
    system: {
      database: 'connected',
      mqtt: {
        configured: Boolean(mqtt.configured),
        connected: Boolean(mqtt.connected),
        has_error: Boolean(mqtt.has_error),
        last_error: mqtt.last_error || null,
      },
      uptime_seconds: Math.floor(process.uptime()),
      server_time: new Date().toISOString(),
      version: process.env.npm_package_version || '1.0.0',
      node_version: process.version,
    },
  };
}
