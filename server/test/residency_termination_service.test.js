import { describe, it, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  previewResidencyTermination,
  executeResidencyTermination,
} from '../src/modules/residency_termination_service.js';

describe('Residency Termination Service (360° Departure)', () => {
  let mockDb;
  let queries = [];
  const originalConnect = pool.connect;
  const originalQuery = pool.query;
  after(() => { pool.connect = originalConnect; pool.query = originalQuery; });

  beforeEach(() => {
    queries = [];
    mockDb = {
      query: async (text, params) => {
        queries.push({ text: text.trim(), params: params || [] });
        // Handle preview queries
        if (text.includes('FROM apartment_residencies r')) {
          if (text.includes('INNER JOIN site_people sp') && text.includes('WHERE r.id = $1')) {
            return {
              rows: [
                {
                  residency_id: 101,
                  apartment_id: 50,
                  person_id: 301,
                  relation: 'tenant',
                  move_in_date: '2026-01-01',
                  is_minor: false,
                  sp_id: 301,
                  user_code: 4001,
                  full_name: 'Ahmet Kiracı',
                  phone: '+905551234567',
                  email: 'ahmet@example.com',
                  person_active: true,
                  resident_user_code: 4001,
                  apartment_no: '12',
                  block_name: 'A Blok',
                },
              ],
              rowCount: 1,
            };
          }
          if (text.includes('WHERE r.apartment_id = $1 AND r.is_current = TRUE AND r.id <> $2')) {
            return {
              rows: [
                {
                  residency_id: 102,
                  person_id: 302,
                  relation: 'family_member',
                  is_minor: false,
                  full_name: 'Ayşe Kiracı',
                  phone: '+905559876543',
                  user_code: 4002,
                  membership_role: 'RESIDENT',
                },
              ],
              rowCount: 1,
            };
          }
        }
        if (text.includes('FROM vehicles')) {
          return {
            rows: [{ id: 1, plate: '34ABC123', plate_display: '34 ABC 123', note: 'Sedan' }],
            rowCount: 1,
          };
        }
        if (text.includes("to_regclass('public.reservations')")) {
          return { rows: [{ ok: true }], rowCount: 1 };
        }
        if (text.includes('FROM reservations r')) {
          return {
            rows: [
              {
                id: 10,
                area_id: 2,
                starts_at: '2026-11-15T10:00:00Z',
                ends_at: '2026-11-15T11:00:00Z',
                slot_count: 1,
                status: 'onaylandi',
                area_name: 'Tenis Kortu',
              },
            ],
            rowCount: 1,
          };
        }
        if (text.includes('FROM guest_passes')) {
          return {
            rows: [
              {
                id: 20,
                title: 'Kurye',
                token: 'tok-123',
                pass_type: 'single_use',
                expires_at: '2026-11-11T18:00:00Z',
                used_count: 0,
                max_uses: 1,
              },
            ],
            rowCount: 1,
          };
        }
        if (text.includes("to_regclass('public.meters')")) {
          return { rows: [{ ok: true }], rowCount: 1 };
        }
        if (text.includes('FROM meters m')) {
          return {
            rows: [
              {
                id: 8,
                kind: 'water',
                serial_no: 'SU-2026-99',
                last_reading_value: 142.5,
                last_reading_date: '2026-11-01',
              },
            ],
            rowCount: 1,
          };
        }
        if (text.includes("to_regclass('public.site_team_duties')")) {
          return { rows: [{ ok: true }], rowCount: 1 };
        }
        if (text.includes('FROM site_team_duties')) {
          return {
            rows: [{ id: 5, duty: 'board_member', title: 'Yönetim Kurulu Üyesi', created_at: '2026-01-01' }],
            rowCount: 1,
          };
        }
        if (text.includes('FROM site_manager_sites')) {
          return { rows: [], rowCount: 0 };
        }
        if (text.includes("to_regclass('public.ledger_entries')")) {
          return { rows: [{ ok: true }], rowCount: 1 };
        }
        if (text.includes('FROM ledger_entries')) {
          return { rows: [{ balance: '125000' }], rowCount: 1 };
        }
        return { rows: [], rowCount: 0 };
      },
      connect: async () => {
        return {
          query: async (text, params) => {
            queries.push({ text: text.trim(), params: params || [] });
            if (text.includes('SELECT id, site_code, resident_user_code, resident_email FROM apartments')) {
              return {
                rows: [{ id: 50, site_code: 1, resident_user_code: 4001, resident_email: null }],
                rowCount: 1,
              };
            }
            if (text.includes('FROM apartment_residencies r') && text.includes('FOR UPDATE OF r')) {
              return {
                rows: [
                  {
                    id: 101,
                    apartment_id: 50,
                    person_id: 301,
                    relation: 'tenant',
                    move_in_date: '2026-01-01',
                    user_code: 4001,
                    full_name: 'Ahmet Kiracı',
                  },
                ],
                rowCount: 1,
              };
            }
            if (text.includes('UPDATE apartment_residencies')) {
              return { rows: [{ id: 101 }], rowCount: 1 };
            }
            if (text.includes('UPDATE vehicles')) {
              return { rows: [{ id: 1, plate: '34ABC123' }], rowCount: 1 };
            }
            if (text.includes('UPDATE guest_passes')) {
              return { rows: [{ id: 20 }], rowCount: 1 };
            }
            if (text.includes("to_regclass('public.reservations')")) {
              return { rows: [{ present: true }], rowCount: 1 };
            }
            if (text.includes('UPDATE reservations')) {
              return { rows: [{ id: 10 }], rowCount: 1 };
            }
            if (text.includes("to_regclass('public.meters')")) {
          return { rows: [{ ok: true }], rowCount: 1 };
        }
        if (text.includes('FROM meters m')) {
          return {
            rows: [
              {
                id: 8,
                kind: 'water',
                serial_no: 'SU-2026-99',
                last_reading_value: 142.5,
                last_reading_date: '2026-11-01',
              },
            ],
            rowCount: 1,
          };
        }
        if (text.includes("to_regclass('public.site_team_duties')")) {
              return { rows: [{ ok: true }], rowCount: 1 };
            }
            if (text.includes('UPDATE site_team_duties')) {
              return { rows: [{ id: 5 }], rowCount: 1 };
            }
            if (text.includes('FROM apartment_memberships')) {
              return { rows: [{ id: 1, user_code: 4002, role: 'APARTMENT_ADMIN', is_active: true }], rowCount: 1 };
            }
            if (text.includes('SELECT 1 FROM apartment_residencies WHERE person_id = $1 AND is_current = TRUE')) {
              return { rows: [], rowCount: 0 };
            }
            return { rows: [], rowCount: 0 };
          },
          release: () => {},
        };
      },
    };
    // Token rotation/finance follow-up must never open a real DB connection in this unit suite.
    pool.query = async () => ({ rows: [], rowCount: 0 });
    pool.connect = mockDb.connect;
  });

  it('previewResidencyTermination should return all linked assets, debts, vehicles and roles', async () => {
    const preview = await previewResidencyTermination(mockDb, {
      siteCode: 1,
      apartmentId: 50,
      residencyId: 101,
      personId: 301,
    });

    assert.equal(preview.person.fullName, 'Ahmet Kiracı');
    assert.equal(preview.person.isAdmin, true);
    assert.equal(preview.apartment.apartmentNo, '12');
    assert.equal(preview.remainingMembers.length, 1);
    assert.equal(preview.remainingMembers[0].fullName, 'Ayşe Kiracı');
    assert.equal(preview.activeVehicles.length, 1);
    assert.equal(preview.activeVehicles[0].plate, '34ABC123');
    assert.equal(preview.upcomingReservations.length, 1);
    assert.equal(preview.activeGuestPasses.length, 1);
    assert.equal(preview.debt.hasDebt, true);
    assert.equal(preview.siteRoles.duties.length, 1);
    assert.equal(preview.siteRoles.duties[0].duty, 'board_member');
    assert.equal(preview.meters.length, 1);
    assert.equal(preview.meters[0].serialNo, 'SU-2026-99');
  });

  it('executeResidencyTermination should execute 360 departure inside a transaction', async () => {
    const actor = { id: 999, user_code: 999, role: 'site_manager' };
    const result = await executeResidencyTermination(mockDb, {
      siteCode: 1,
      apartmentId: 50,
      residencyId: 101,
      moveOutDate: '2026-11-10',
      successorUserCode: 4002,
      terminateSiteRoles: true,
      debtDisposition: 'PAID',
      actor,
    });

    assert.equal(result.ok, true);
    assert.equal(result.released.vehicles, 1);
    assert.equal(result.released.guestPasses, 1);
    assert.equal(result.released.reservations, 1);
    assert.equal(result.released.siteRolesEnded, true);
    assert.equal(result.released.newAdminUserCode, 4002);

    // Verify SQL commands were executed in transaction
    const sqls = queries.map((q) => q.text);
    assert.ok(sqls.includes('BEGIN'));
    assert.ok(sqls.includes('COMMIT'));
    assert.ok(sqls.some((s) => s.includes('UPDATE vehicles')));
    assert.ok(sqls.some((s) => s.includes('UPDATE guest_passes')));
    assert.ok(sqls.some((s) => s.includes('UPDATE reservations')));
    assert.ok(sqls.some((s) => s.includes('UPDATE site_team_duties')));
    assert.deepEqual(queries.filter((q) => q.text.includes('pg_advisory_xact_lock')).slice(0, 2).map((q) => q.params[0]), ['people_sync:1', 'finance_post:1']);
  });

  function interceptClient(replace) {
    const connect = mockDb.connect;
    mockDb.connect = async () => {
      const client = await connect();
      const query = client.query;
      client.query = async (sql, params = []) => replace(sql, params, () => query(sql, params));
      return client;
    };
  }
  const execute = (extra = {}) => executeResidencyTermination(mockDb, {
    siteCode: 1, apartmentId: 50, residencyId: 101, moveOutDate: '2026-11-10',
    actor: { user_code: 999, role: 'site_manager' }, ...extra,
  });
  const rolledBack = () => {
    assert.ok(queries.some((q) => q.text === 'ROLLBACK'));
    assert.equal(queries.some((q) => q.text === 'COMMIT'), false);
  };

  it('invalid IDs and future dates are rejected before opening a transaction', async () => {
    await assert.rejects(execute({ apartmentId: -1 }), { code: 'INVALID_BODY' });
    await assert.rejects(execute({ moveOutDate: '2099-01-01' }), { code: 'INVALID_BODY' });
    assert.equal(queries.length, 0);
  });
  it('move out cannot precede the residency entry date', async () => {
    await assert.rejects(execute({ moveOutDate: '2025-12-31' }), { code: 'INVALID_BODY' });
    rolledBack();
  });
  it('a self-successor is not accepted', async () => {
    await assert.rejects(execute({ successorUserCode: 4001 }), { code: 'INVALID_BODY' });
    rolledBack();
  });
  it('PAID cannot hide an unpaid tenant balance or write a payment implicitly', async () => {
    interceptClient(async (sql, params, next) => {
      if (sql.includes("to_regclass('public.ledger_entries')")) return { rows: [{ ok: true }], rowCount: 1 };
      if (sql.startsWith('SELECT COALESCE(SUM(l.amount_minor)')) return { rows: [{ balance: '180000' }], rowCount: 1 };
      return next();
    });
    await assert.rejects(execute({ debtDisposition: 'PAID' }), { code: 'DEBT_NOT_PAID' });
    rolledBack();
  });
  it('a meter outside the departing apartment rolls the whole operation back', async () => {
    await assert.rejects(execute({ finalMeterReadings: [{ meterId: 8, readingDate: '10.11.2026', readingValue: 150 }] }), { code: 'METER_NOT_FOUND' });
    rolledBack();
  });
  it('meter insert failure and reservation cancellation failure are not swallowed', async () => {
    interceptClient(async (sql, params, next) => {
      if (sql.startsWith('SELECT id, is_active FROM meters')) return { rows: [{ id: 8, is_active: true }], rowCount: 1 };
      if (sql.startsWith('INSERT INTO meter_readings')) throw new Error('synthetic meter failure');
      return next();
    });
    await assert.rejects(execute({ finalMeterReadings: [{ meterId: 8, readingValue: 150 }] }), /synthetic meter failure/);
    rolledBack();
  });
  it('reservation cancellation failure rolls back the departure', async () => {
    interceptClient(async (sql, params, next) => {
      if (sql.includes('UPDATE reservations')) throw new Error('synthetic reservation failure');
      return next();
    });
    await assert.rejects(execute(), /synthetic reservation failure/);
    rolledBack();
  });
  it('preview cannot turn a failed debt query into a zero-balance result', async () => {
    const query = mockDb.query;
    mockDb.query = async (sql, params) => {
      if (sql.includes("to_regclass('public.ledger_entries')")) throw new Error('synthetic debt query failure');
      return query(sql, params);
    };
    await assert.rejects(previewResidencyTermination(mockDb, { siteCode: 1, apartmentId: 50, residencyId: 101 }), /synthetic debt query failure/);
  });
});
