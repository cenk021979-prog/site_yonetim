// 360° Daireden Ayrılma, İkamet Sonu, Otopark/Plaka, Rezervasyon ve Site Görev Devir Çekirdek Servisi.
// Bu modül; bir sakin veya yöneticinin ayrılma sürecini tüm bağlı varlıklarıyla (araçlar, kapı, misafir, rezervasyon, borç ve görevler)
// tek bir atomik transaction içinde güvenle yönetir.

import { pool } from '../db.js';
import { recordAudit } from './audit_service.js';
import { rotateTokensForSite } from '../services/local_token_service.js';
import { pickAdminSuccessor } from './apartment_admin_successor.js';
import { releaseUserReservations } from './reservation_service.js';
import { tenantDebtMinor } from './finance_exit_notice.js';
import { formatMinor } from './finance_4b_common.js';
import { closeResidency } from './people_service.js';
import { logResidencyEvent } from './residency_log.js';

/**
 * Ayrılma öncesi tüm bağlı varlıkları ve durumları listeleyen önizleme (Preview).
 */
export async function previewResidencyTermination(db, { siteCode, apartmentId, residencyId, personId }) {
  const sCode = Number(siteCode);
  const aId = Number(apartmentId);
  const rId = Number(residencyId);

  // 1. İkamet ve Kişi Sorgusu
  const resQuery = await db.query(
    `
      SELECT r.id AS residency_id, r.apartment_id, r.person_id, r.relation, r.move_in_date, r.is_minor,
             sp.id AS sp_id, sp.user_code, sp.full_name, sp.phone, sp.email, sp.is_active AS person_active,
             a.resident_user_code, a.apartment_no, b.name AS block_name
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id
      INNER JOIN apartments a ON a.id = r.apartment_id
      LEFT JOIN site_blocks b ON b.id = a.block_id
      WHERE r.id = $1 AND r.site_code = $2 AND r.apartment_id = $3 AND r.is_current = TRUE
      LIMIT 1
    `,
    [rId, sCode, aId],
  );

  const row = resQuery.rows?.[0];
  if (!row) {
    throw new Error('Aktif ikamet kaydı bulunamadı.');
  }

  const userCode = row.user_code ? Number(row.user_code) : null;
  const pId = Number(row.person_id);

  // 2. Daire Adminliği Durumu
  let isAdmin = false;
  if (userCode !== null) {
    if (row.resident_user_code !== null && Number(row.resident_user_code) === userCode) {
      isAdmin = true;
    } else {
      const mem = await db.query(
        `SELECT role, is_active FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2`,
        [aId, userCode],
      );
      if (mem.rows?.[0]?.is_active === true && mem.rows[0].role === 'APARTMENT_ADMIN') {
        isAdmin = true;
      }
    }
  }

  // 3. Dairede Kalan Diğer Aktif Sakinler (Halef Adayları)
  const remainingQuery = await db.query(
    `
      SELECT r.id AS residency_id, r.person_id, r.relation, r.is_minor,
             sp.full_name, sp.phone, sp.user_code,
             am.role AS membership_role
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE
      LEFT JOIN apartment_memberships am ON am.apartment_id = r.apartment_id AND am.user_code = sp.user_code AND am.is_active = TRUE
      WHERE r.apartment_id = $1 AND r.is_current = TRUE AND r.id <> $2
      ORDER BY r.created_at ASC
    `,
    [aId, rId],
  );
  const remainingMembers = remainingQuery.rows ?? [];

  // Sistem varsayılan halefi
  let defaultSuccessorUserCode = null;
  if (isAdmin && userCode !== null) {
    defaultSuccessorUserCode = await pickAdminSuccessor(db, aId, userCode);
  }

  // 4. Bağlı Aktif Araç Plakaları
  const vehiclesQuery = await db.query(
    `
      SELECT id, plate, plate_display, note
      FROM vehicles
      WHERE site_code = $1 AND is_active = TRUE AND (person_id = $2 OR (apartment_id = $3 AND $4 = 0))
      ORDER BY id ASC
    `,
    [sCode, pId, aId, remainingMembers.length],
  );
  const activeVehicles = vehiclesQuery.rows ?? [];

  // 5. İleri Tarihli Rezervasyonlar
  let upcomingReservations = [];
  if (userCode !== null) {
    const hasRes = await db.query("SELECT (to_regclass('public.reservations') IS NOT NULL) AS ok");
    if (hasRes.rows?.[0]?.ok === true) {
      const resUpcoming = await db.query(
        `
          SELECT r.id, r.area_id, r.starts_at, r.ends_at, r.slot_count, r.status,
                 ra.name AS area_name
          FROM reservations r
          LEFT JOIN reservation_areas ra ON ra.id = r.area_id
          WHERE r.site_code = $1 AND r.user_code = $2 AND r.status IN ('beklemede', 'onaylandi') AND r.ends_at > NOW()
          ORDER BY r.starts_at ASC
        `,
        [sCode, userCode],
      );
      upcomingReservations = resUpcoming.rows ?? [];
    }
  }

  // 6. Aktif Geçici Misafir Linkleri (Guest Passes)
  let activeGuestPasses = [];
  if (userCode !== null) {
    const passes = await db.query(
      `
        SELECT id, title, token, pass_type, expires_at, used_count, max_uses
        FROM guest_passes
        WHERE site_code = $1 AND created_by_user_code = $2 AND is_active = TRUE AND expires_at > NOW()
        ORDER BY expires_at ASC
      `,
      [sCode, userCode],
    );
    activeGuestPasses = passes.rows ?? [];
  }

  // 7. Finansal Borç Durumu
  let openDebtMinor = 0n;
  try {
    openDebtMinor = await tenantDebtMinor(db, { siteCode: sCode, apartmentId: aId });
  } catch (_) {}

  // 8. Site Yönetim Görevleri (Yönetici, Denetçi, Kurul Üyesi, Görevli)
  let siteDuties = [];
  const dutiesHas = await db.query("SELECT (to_regclass('public.site_team_duties') IS NOT NULL) AS ok");
  if (dutiesHas.rows?.[0]?.ok === true) {
    const dRes = await db.query(
      `
        SELECT id, duty, title, public_phone, created_at
        FROM site_team_duties
        WHERE site_code = $1 AND person_id = $2 AND ended_at IS NULL
      `,
      [sCode, pId],
    );
    siteDuties = dRes.rows ?? [];
  }
  let isSiteManager = false;
  if (userCode !== null) {
    const smRes = await db.query(
      `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND user_code = $2 LIMIT 1`,
      [sCode, userCode],
    );
    isSiteManager = smRes.rowCount > 0;
  }

  return {
    residency: {
      id: rId,
      relation: row.relation,
      moveInDate: row.move_in_date,
      isMinor: row.is_minor === true,
    },
    person: {
      id: pId,
      userCode,
      fullName: row.full_name,
      phone: row.phone,
      email: row.email,
      isAdmin,
    },
    apartment: {
      id: aId,
      apartmentNo: row.apartment_no,
      blockName: row.block_name ?? '',
    },
    remainingMembers: remainingMembers.map((m) => ({
      residencyId: Number(m.residency_id),
      personId: Number(m.person_id),
      userCode: m.user_code ? Number(m.user_code) : null,
      fullName: m.full_name,
      phone: m.phone,
      relation: m.relation,
      membershipRole: m.membership_role,
    })),
    defaultSuccessorUserCode,
    activeVehicles,
    upcomingReservations,
    activeGuestPasses,
    debt: {
      balanceMinor: openDebtMinor.toString(),
      balanceFormatted: formatMinor(openDebtMinor),
      hasDebt: openDebtMinor > 0n,
    },
    siteRoles: {
      isSiteManager,
      duties: siteDuties,
      hasRoles: isSiteManager || siteDuties.length > 0,
    },
  };
}

/**
 * 360° Ayrılma ve İlişik Kesme İşlemini Atomik Olarak İcra Eder.
 */
export async function executeResidencyTermination(db, {
  siteCode,
  apartmentId,
  residencyId,
  moveOutDate,
  successorUserCode = null,
  terminateSiteRoles = false,
  debtDisposition = 'KEEP_ON_DEBTOR', // 'PAID' | 'TRANSFER_TO_OWNER' | 'KEEP_ON_DEBTOR'
  actor,
  actorRole = null,
  reason = 'move_out',
}) {
  const sCode = Number(siteCode);
  const aId = Number(apartmentId);
  const rId = Number(residencyId);

  const client = await db.connect();
  let accessClosed = false;
  const released = {
    vehicles: 0,
    reservations: 0,
    guestPasses: 0,
    siteRolesEnded: false,
    newAdminUserCode: null,
  };

  try {
    await client.query('BEGIN');

    // 1. Daire ve İkamet Kilidi
    const aptLock = await client.query(
      `SELECT id, site_code, resident_user_code, resident_email FROM apartments WHERE id = $1 FOR UPDATE`,
      [aId],
    );
    const apartment = aptLock.rows?.[0];
    if (!apartment) {
      throw new Error('Daire bulunamadı.');
    }

    const resLock = await client.query(
      `
        SELECT r.id, r.apartment_id, r.person_id, r.relation, sp.user_code, sp.full_name
        FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id
        WHERE r.id = $1 AND r.site_code = $2 AND r.apartment_id = $3 AND r.is_current = TRUE
        FOR UPDATE OF r
      `,
      [rId, sCode, aId],
    );
    const residencyRow = resLock.rows?.[0];
    if (!residencyRow) {
      throw new Error('Aktif ikamet kaydı bulunamadı veya daha önce sonlandırılmış.');
    }

    const leavingUserCode = residencyRow.user_code ? Number(residencyRow.user_code) : null;
    const personId = Number(residencyRow.person_id);

    // 2. Açık Yönetim / Daire Adminliği Devri (Eğer açıkça bir halef belirtilmişse)
    if (successorUserCode !== null && leavingUserCode !== null) {
      const succ = Number(successorUserCode);
      // Halef dairenin üyesi mi kontrol et
      const memCheck = await client.query(
        `SELECT id FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE`,
        [aId, succ],
      );
      if (memCheck.rowCount > 0) {
        await client.query(
          `UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN', updated_at = NOW() WHERE apartment_id = $1 AND user_code = $2`,
          [aId, succ],
        );
        await client.query(
          `UPDATE apartments SET resident_user_code = $1, resident_pin_issued = FALSE, resident_pin_code = NULL, resident_email = NULL WHERE id = $2`,
          [succ, aId],
        );
        released.newAdminUserCode = succ;
        await logResidencyEvent(client, {
          apartmentId: aId,
          userCode: succ,
          eventType: 'handover',
          reasonCode: 'handover',
          actor,
          actorRole,
          related: { from_user_code: leavingUserCode, to_user_code: succ },
        });
      }
    }

    // 3. İkameti Kapat (closeResidency)
    const closeRes = await closeResidency(client, {
      siteCode: sCode,
      residency: {
        id: rId,
        person_id: personId,
        apartment_id: aId,
        relation: residencyRow.relation,
      },
      userCode: leavingUserCode,
      moveOutDate: moveOutDate || new Date().toISOString().slice(0, 10),
      actor,
      actorRole,
      reason,
    });
    accessClosed = closeRes.accessClosed;

    // 4. Kalan Sakin Kontrolü & Otopark Plakalarının Temizliği
    const remainingAptRes = await client.query(
      `SELECT 1 FROM apartment_residencies WHERE apartment_id = $1 AND is_current = TRUE LIMIT 1`,
      [aId],
    );
    const vacatingEntireApartment = remainingAptRes.rowCount === 0;

    const vRes = await client.query(
      `
        UPDATE vehicles
        SET is_active = FALSE
        WHERE site_code = $1 AND is_active = TRUE
          AND (person_id = $2 OR (apartment_id = $3 AND $4::BOOLEAN = TRUE))
        RETURNING id, plate
      `,
      [sCode, personId, aId, vacatingEntireApartment],
    );
    released.vehicles = vRes.rowCount ?? 0;

    // 5. Geçici Misafir Linkleri (Guest Passes) İptali
    if (leavingUserCode !== null) {
      const gpRes = await client.query(
        `
          UPDATE guest_passes
          SET is_active = FALSE
          WHERE site_code = $1 AND created_by_user_code = $2 AND is_active = TRUE AND expires_at > NOW()
          RETURNING id
        `,
        [sCode, leavingUserCode],
      );
      released.guestPasses = gpRes.rowCount ?? 0;
    }

    // 6. İleri Tarihli Rezervasyonlar (Reservations) İptali
    if (leavingUserCode !== null) {
      try {
        const resRel = await releaseUserReservations(client, leavingUserCode);
        released.reservations = resRel.reservations ?? 0;
      } catch (_) {}
    }

    // 7. Site Yönetim Görevlerinin Sonlandırılması (Eğer talep edildiyse)
    if (terminateSiteRoles === true) {
      // 7a. site_team_duties
      const dtHas = await client.query("SELECT (to_regclass('public.site_team_duties') IS NOT NULL) AS ok");
      if (dtHas.rows?.[0]?.ok === true) {
        await client.query(
          `UPDATE site_team_duties SET ended_at = NOW(), updated_at = NOW() WHERE site_code = $1 AND person_id = $2 AND ended_at IS NULL`,
          [sCode, personId],
        );
      }
      // 7b. site_manager_sites
      if (leavingUserCode !== null) {
        await client.query(
          `DELETE FROM site_manager_sites WHERE site_code = $1 AND user_code = $2`,
          [sCode, leavingUserCode],
        );
        const otherSites = await client.query(
          `SELECT 1 FROM site_manager_sites WHERE user_code = $1 LIMIT 1`,
          [leavingUserCode],
        );
        if (otherSites.rowCount === 0) {
          await client.query(
            `UPDATE users SET role = 'apartment_owner' WHERE user_code = $1 AND role = 'site_manager'`,
            [leavingUserCode],
          );
        }
      }
      released.siteRolesEnded = true;
    }

    // 8. Finansal Tasfiye Notu & Denetim İzi (Audit)
    await recordAudit(
      client,
      {
        siteCode: sCode,
        actor,
        action: 'residency.terminated_360',
        targetType: 'apartment',
        targetId: aId,
        details: {
          residency_id: rId,
          person_id: personId,
          user_code: leavingUserCode,
          vacating_entire_apartment: vacatingEntireApartment,
          debt_disposition: debtDisposition,
          released_vehicles_count: released.vehicles,
          released_reservations_count: released.reservations,
          released_guest_passes_count: released.guestPasses,
          site_roles_ended: released.siteRolesEnded,
          successor_user_code: released.newAdminUserCode,
        },
      },
      { inTransaction: true },
    );

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }

  // Transaction dışı: Token döndürme
  if (accessClosed) {
    await rotateTokensForSite({ siteCode: sCode, reason: 'residency_termination_360' }).catch(() => {});
  }

  return {
    ok: true,
    accessClosed,
    released,
  };
}
