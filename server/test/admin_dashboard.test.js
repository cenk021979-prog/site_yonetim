import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { getSuperUserDashboardSummary } from '../src/services/admin_dashboard_service.js';

describe('Süper Kullanıcı Dashboard Özeti', () => {
  it('tüm metrik gruplarını doğru alanlarla ve sayısal tiplerle derler', async () => {
    const fakeDb = {
      query: async (sql) => {
        if (/site_applications/i.test(sql)) {
          return { rows: [{ pending_site_applications: 3, pending_module_requests: 2 }] };
        }
        if (/FROM sites/i.test(sql)) {
          return { rows: [{ total: 10, active: 8, passive: 2 }] };
        }
        if (/FROM apartments/i.test(sql)) {
          return { rows: [{ total: 150, occupied: 120, empty: 30 }] };
        }
        if (/FROM users/i.test(sql)) {
          return { rows: [{ total: 200, site_managers: 10, apartment_users: 180, super_users: 2, individuals: 8 }] };
        }
        if (/FROM site_doors/i.test(sql)) {
          return { rows: [{ total: 14, active: 12 }] };
        }
        if (/FROM devices d/i.test(sql)) {
          return { rows: [{ total_devices: 12, online_devices: 9, offline_devices: 3, esp32_c3_count: 8, esp32_wroom_count: 4 }] };
        }
        if (/FROM door_access_logs/i.test(sql)) {
          return { rows: [{ today_door_passes: 45 }] };
        }
        if (/FROM client_error_reports/i.test(sql)) {
          return { rows: [{ total_reports_24h: 5, unique_errors_24h: 2 }] };
        }
        if (/FROM feedback_reports/i.test(sql)) {
          return { rows: [{ total_feedbacks: 7 }] };
        }
        return { rows: [] };
      },
    };

    const summary = await getSuperUserDashboardSummary(fakeDb);

    assert.equal(summary.ok, true);
    assert.deepEqual(summary.attention, {
      pending_site_applications: 3,
      pending_module_requests: 2,
      unresolved_client_errors: 5,
      unique_client_errors: 2,
      total_feedbacks: 7,
    });
    assert.deepEqual(summary.platform, {
      total_sites: 10,
      active_sites: 8,
      passive_sites: 2,
      total_apartments: 150,
      occupied_apartments: 120,
      empty_apartments: 30,
      total_users: 200,
      site_managers: 10,
      apartment_users: 180,
      super_users: 2,
      individuals: 8,
    });
    assert.deepEqual(summary.iot, {
      total_doors: 14,
      active_doors: 12,
      total_devices: 12,
      online_devices: 9,
      offline_devices: 3,
      esp32_c3_count: 8,
      esp32_wroom_count: 4,
      today_door_passes: 45,
    });
    assert.equal(summary.system.database, 'connected');
    assert.equal(typeof summary.system.uptime_seconds, 'number');
  });

  it('veritabanı sorguları boş veya hata dönse bile güvenli varsayılanlarla çökmeyip döner', async () => {
    const errorDb = {
      query: async () => {
        throw new Error('DB connection timeout');
      },
    };

    const summary = await getSuperUserDashboardSummary(errorDb);

    assert.equal(summary.ok, true);
    assert.equal(summary.platform.total_sites, 0);
    assert.equal(summary.platform.active_sites, 0);
    assert.equal(summary.iot.online_devices, 0);
    assert.equal(summary.attention.pending_site_applications, 0);
  });
});
