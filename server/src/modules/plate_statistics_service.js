// Counts recognition events, not sensor-confirmed vehicle passages. No writes.
import { pool } from '../db.js';
import { invalidField } from './plate_recognition_common.js';

export function statisticsGateId(value) {
  if (value === undefined || value === null || value === '') return null;
  if (!/^\d+$/.test(String(value)) || !Number.isSafeInteger(Number(value)) || Number(value) <= 0) {
    throw invalidField('Geçerli bir kapı seçin.', 'gate_id');
  }
  return Number(value);
}

export function statisticsAnchor(value) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith('0000-')) {
    throw invalidField('Tarih YYYY-MM-DD biçiminde olmalı.', 'anchor');
  }
  const parsed = new Date(`${value}T12:00:00+03:00`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw invalidField('Geçerli bir tarih seçin.', 'anchor');
  }
  return parsed;
}

// PostgreSQL owns calendar boundaries: client timezone and list limits cannot change totals.
export const PLATE_STATISTICS_SQL = `
  WITH periods AS (
    SELECT period, date_trunc(period, $3::timestamptz AT TIME ZONE 'Europe/Istanbul') AS start_local
    FROM unnest(ARRAY['day', 'week', 'month']) AS period
  ), bounds AS (
    SELECT period, start_local AT TIME ZONE 'Europe/Istanbul' AS starts_at,
      (start_local + CASE period WHEN 'day' THEN INTERVAL '1 day'
        WHEN 'week' THEN INTERVAL '1 week' ELSE INTERVAL '1 month' END)
        AT TIME ZONE 'Europe/Istanbul' AS ends_at
    FROM periods
  ), events AS (
    SELECT COALESCE(e.seen_at, d.decided_at) AS seen_at, e.direction
    FROM plate_decisions d
    LEFT JOIN plate_events e ON e.id = d.event_id AND e.site_code = d.site_code
    WHERE d.site_code = $1
      AND ($2::bigint IS NULL OR e.gate_id = $2 OR (e.gate_id IS NULL AND EXISTS (
        SELECT 1 FROM plate_gates g WHERE g.site_code = d.site_code AND g.id = $2 AND g.door_id = d.door_id
      )))
      AND COALESCE(e.seen_at, d.decided_at) >= (SELECT MIN(starts_at) FROM bounds)
      AND COALESCE(e.seen_at, d.decided_at) < (SELECT MAX(ends_at) FROM bounds)
  )
  SELECT b.period, b.starts_at, b.ends_at,
    COUNT(*) FILTER (WHERE e.direction = 'giris')::int AS entries,
    COUNT(*) FILTER (WHERE e.direction = 'cikis')::int AS exits,
    COUNT(*) FILTER (WHERE e.seen_at IS NOT NULL AND (e.direction IS NULL OR e.direction NOT IN ('giris','cikis')))::int AS unknown
  FROM bounds b LEFT JOIN events e ON e.seen_at >= b.starts_at AND e.seen_at < b.ends_at
  GROUP BY b.period, b.starts_at, b.ends_at`;

export async function plateStatistics(siteCode, query = {}, { db = pool, now = new Date() } = {}) {
  const gateId = statisticsGateId(query.gate_id);
  const anchor = statisticsAnchor(query.anchor) ?? now;
  const result = await db.query(PLATE_STATISTICS_SQL, [siteCode, gateId, anchor]);
  return {
    timezone: 'Europe/Istanbul', gate_id: gateId, server_time: now.toISOString(),
    periods: Object.fromEntries(result.rows.map((r) => [r.period, {
      starts_at: new Date(r.starts_at).toISOString(), ends_at: new Date(r.ends_at).toISOString(),
      entries: Number(r.entries), exits: Number(r.exits), unknown: Number(r.unknown),
    }])),
  };
}
