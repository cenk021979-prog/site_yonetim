import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  previewResidencyTermination,
  executeResidencyTermination,
} from '../src/modules/residency_termination_service.js';

describe('Residency Termination Service (360° Departure)', () => {
  let mockDb;
  let queries = [];

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
  });
});
