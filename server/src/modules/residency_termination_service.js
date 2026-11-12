// 360° Daireden Ayrılma, İkamet Sonu, Otopark/Plaka, Rezervasyon ve Site Görev Devir Çekirdek Servisi.
// Bu modül; bir sakin veya yöneticinin ayrılma sürecini tüm bağlı varlıklarıyla (araçlar, kapı, misafir, rezervasyon, borç ve görevler)
// ayrılma/sayaç/erişim yazmalarını aynı transaction içinde yönetir. İsteğe bağlı borç devri
// mevcut finans servisiyle ayrı işlemde yapılır; başarısızlık yanıtta ayrıca belirtilir.

import { recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { peopleLockKey } from './people_sync.js';
import { financeLockKey } from './finance_common.js';
import { dateOnly, meteringLockKey } from './metering_service.js';
import { releaseDutyMembership } from './team_service.js';
import { invalidBody } from './people_common.js';
import { siteTiePredicate } from './people_sync_sql.js';
import { assertMoveOutAfterEntry, saveTerminationReadings, terminationIds, terminationInput } from './residency_termination_checks.js';
import { rotateTokensForSite } from '../services/local_token_service.js';
import { pickAdminSuccessor } from './apartment_admin_successor.js';
import { releaseUserReservations } from './reservation_service.js';
import { tenantDebtMinor } from './finance_exit_notice.js';
import { formatMinor } from './finance_4b_common.js';
import { closeResidency } from './people_service.js';
import { logResidencyEvent } from './residency_log.js';
import { previewLiabilityTransfer, createLiabilityTransfer } from './finance_liability_service.js';

/**
 * Ayrılma öncesi tüm bağlı varlıkları ve durumları listeleyen önizleme (Preview).
 */
export async function previewResidencyTermination(db, { siteCode, apartmentId, residencyId }) {
  const { sCode, aId, rId } = terminationIds({ siteCode, apartmentId, residencyId });

  // 1. İkamet ve Kişi Sorgusu
  const resQuery = await db.query(
    `
      SELECT r.id AS residency_id, r.apartment_id, r.person_id, r.relation, r.move_in_date, r.is_minor,
             sp.id AS sp_id, sp.user_code, sp.full_name, sp.phone, sp.email, sp.is_active AS person_active,
             a.resident_user_code, a.unit_label AS apartment_no, b.block_name
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
    throw new PlatformError(404, 'RESIDENCY_NOT_FOUND', 'Aktif ikamet kaydı bulunamadı.');
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
        SELECT id, title, pass_type, expires_at, used_count, max_uses
        FROM guest_passes
        WHERE site_code = $1 AND created_by_user_code = $2 AND is_active = TRUE AND expires_at > NOW()
        ORDER BY expires_at ASC
      `,
      [sCode, userCode],
    );
    activeGuestPasses = passes.rows ?? [];
  }

  // 7. Finansal Borç Durumu & Malike Devir Önizlemesi
  const openDebtMinor = row.relation === 'tenant'
    ? await tenantDebtMinor(db, { siteCode: sCode, apartmentId: aId })
    : 0n;

  let liabilityTransfer = null;
  if (row.relation === 'tenant' && openDebtMinor > 0n) {
    try {
      const p = await previewLiabilityTransfer(sCode, aId, new Date(), db);
      liabilityTransfer = {
        hasOwner: p.has_owner === true,
        canTransfer: p.can_transfer === true,
        itemCount: p.item_count ?? 0,
        totalMinor: p.total_minor ?? '0',
        previewHash: p.preview_hash ?? null,
        ownerBalanceMinor: p.owner_balance_minor ?? '0',
      };
    } catch (_) {}
  }

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
      `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
      [sCode, userCode],
    );
    isSiteManager = smRes.rowCount > 0;
  }

  // 9. Daireye Bağlı Sayaçlar (Meters)
  let activeMeters = [];
  const hasMeters = await db.query("SELECT (to_regclass('public.meters') IS NOT NULL) AS ok");
  if (hasMeters.rows?.[0]?.ok === true) {
    const mRes = await db.query(
      `
        SELECT m.id, m.kind, m.serial_no,
               (
                 SELECT r.value
                 FROM meter_readings r
                 WHERE r.meter_id = m.id
                 ORDER BY r.reading_date DESC, r.id DESC
                 LIMIT 1
               ) AS last_reading_value,
               (
                 SELECT r.reading_date
                 FROM meter_readings r
                 WHERE r.meter_id = m.id
                 ORDER BY r.reading_date DESC, r.id DESC
                 LIMIT 1
               ) AS last_reading_date
        FROM meters m
        WHERE m.site_code = $1 AND m.apartment_id = $2 AND m.is_active = TRUE
        ORDER BY m.kind, m.id
      `,
      [sCode, aId],
    );
    activeMeters = (mRes.rows ?? []).map((r) => ({
      id: Number(r.id),
      kind: r.kind,
      serialNo: r.serial_no,
      lastReadingValue: r.last_reading_value != null ? Number(r.last_reading_value) : null,
      lastReadingDate: dateOnly(r.last_reading_date),
    }));
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
      liabilityTransfer,
    },
    siteRoles: {
      isSiteManager,
      duties: siteDuties,
      hasRoles: isSiteManager || siteDuties.length > 0,
    },
    meters: activeMeters,
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
  finalMeterReadings = [],
  actor,
  actorRole = null,
  reason = 'move_out',
}) {
  const { sCode, aId, rId } = terminationIds({ siteCode, apartmentId, residencyId });
  const input = terminationInput({ moveOutDate, successorUserCode, debtDisposition, finalMeterReadings });

  const client = await db.connect();
  let accessClosed;
  let residencyRelation;
  let leavingFullName;
  const released = {
    vehicles: 0,
    reservations: 0,
    guestPasses: 0,
    siteRolesEnded: false,
    newAdminUserCode: null,
    debtDisposition,
    debtTransferred: null,
  };

  try {
    await client.query('BEGIN');
    // Günlük paylaşım ve üyelik akışlarıyla aynı sıra; daire satırından önce alınır.
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [peopleLockKey(sCode)]);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [financeLockKey(sCode)]);
    if (input.readings.length > 0) {
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [meteringLockKey(sCode)]);
    }

    // 1. Daire ve İkamet Kilidi
    const aptLock = await client.query(
      `SELECT id, site_code, resident_user_code, resident_email FROM apartments WHERE id = $1 AND site_code = $2 FOR UPDATE`,
      [aId, sCode],
    );
    const apartment = aptLock.rows?.[0];
    if (!apartment) {
      throw new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bulunamadı.');
    }

    const resLock = await client.query(
      `
        SELECT r.id, r.apartment_id, r.person_id, r.relation, r.move_in_date, sp.user_code, sp.full_name
        FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id
        WHERE r.id = $1 AND r.site_code = $2 AND r.apartment_id = $3 AND r.is_current = TRUE
        FOR UPDATE OF r
      `,
      [rId, sCode, aId],
    );
    const residencyRow = resLock.rows?.[0];
    if (!residencyRow) {
      throw new PlatformError(409, 'RESIDENCY_NOT_CURRENT', 'Aktif ikamet kaydı bulunamadı veya daha önce sonlandırılmış.');
    }

    const leavingUserCode = residencyRow.user_code ? Number(residencyRow.user_code) : null;
    const personId = Number(residencyRow.person_id);
    residencyRelation = residencyRow.relation;
    leavingFullName = residencyRow.full_name;
    assertMoveOutAfterEntry(input.date, residencyRow.move_in_date);
    if (debtDisposition === 'TRANSFER_TO_OWNER' && residencyRelation !== 'tenant') {
      throw invalidBody('debt_disposition', 'Malike devir yalnız kiracı borcu için yapılabilir.');
    }

    // 2. Açık Yönetim / Daire Adminliği Devri (Eğer açıkça bir halef belirtilmişse)
    if (input.successor !== null) {
      const succ = input.successor;
      const currentMember = await client.query(
        'SELECT role, is_active FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2',
        [aId, leavingUserCode],
      );
      const wasAdmin = leavingUserCode !== null && (Number(apartment.resident_user_code) === leavingUserCode
        || (currentMember.rows?.[0]?.is_active === true && currentMember.rows[0].role === 'APARTMENT_ADMIN'));
      if (!wasAdmin || succ === leavingUserCode) throw invalidBody('successor_user_code', 'Yalnız ayrılan daire admini için başka bir halef seçilebilir.');
      // Halef dairenin üyesi mi kontrol et
      const memCheck = await client.query(
        `SELECT id FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE`,
        [aId, succ],
      );
      if (memCheck.rowCount === 0) throw invalidBody('successor_user_code', 'Halef dairenin etkin bir üyesi olmalıdır.');
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
      moveOutDate: input.date,
      actor,
      actorRole,
      reason,
    });
    accessClosed = closeRes.accessClosed;
    if (debtDisposition === 'PAID' && residencyRelation === 'tenant'
      && await tenantDebtMinor(client, { siteCode: sCode, apartmentId: aId }) > 0n) {
      throw new PlatformError(409, 'DEBT_NOT_PAID', 'Kiracı hesabında açık borç var. Tahsilatı finans ekranında kaydedip özeti yenileyin; bu seçim tahsilat oluşturmaz.');
    }

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
          AND apartment_id = $3 AND (person_id = $2 OR $4::BOOLEAN = TRUE)
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
            AND NOT ${siteTiePredicate('guest_passes.created_by_user_code', '$1')}
          RETURNING id
        `,
        [sCode, leavingUserCode],
      );
      released.guestPasses = gpRes.rowCount ?? 0;
    }

    // 6. İleri Tarihli Rezervasyonlar (Reservations) İptali
    if (leavingUserCode !== null) {
      const resRel = await releaseUserReservations(client, leavingUserCode, sCode, aId);
      released.reservations = resRel.reservations ?? 0;
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
        await releaseDutyMembership(client, { siteCode: sCode, userCode: leavingUserCode });
        await client.query(
          `UPDATE site_memberships SET is_active = FALSE, updated_at = NOW()
           WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN')`,
          [sCode, leavingUserCode],
        );
        await client.query(
          `DELETE FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2`,
          [sCode, leavingUserCode],
        );
        const otherSites = await client.query(
          `SELECT 1 FROM site_manager_sites WHERE manager_user_code = $1
           UNION ALL SELECT 1 FROM site_memberships WHERE user_code = $1 AND is_active = TRUE AND role IN ('SITE_OWNER', 'SITE_ADMIN') LIMIT 1`,
          [leavingUserCode],
        );
        if (otherSites.rowCount === 0) {
          await client.query(
            `UPDATE users SET role = 'apartment_owner' WHERE user_code = $1 AND role = 'site_manager' AND deleted_at IS NULL`,
            [leavingUserCode],
          );
        }
      }
      released.siteRolesEnded = true;
    }

    // 8. Sayaç Son Okuma Kaydı (Varsa)
    await saveTerminationReadings(client, { siteCode: sCode, apartmentId: aId, readings: input.readings, actor });

    // 9. Finansal Tasfiye Notu & Denetim İzi (Audit)
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

  // 10. İşlem Sonrası: Kiracı Borcunu Malike Devret (Eğer seçildiyse)
  let debtTransferError = null;
  if (debtDisposition === 'TRANSFER_TO_OWNER' && residencyRelation === 'tenant') {
    try {
      const p = await previewLiabilityTransfer(sCode, aId, new Date(), db);
      if (p.can_transfer && BigInt(p.total_minor) > 0n) {
        await createLiabilityTransfer({
          siteCode: sCode,
          rawApartmentId: aId,
          body: {
            expected_total_minor: p.total_minor,
            expected_hash: p.preview_hash,
            reason: `Daireden ayrılma (${leavingFullName || 'Kiracı'}) borç devri`,
            idempotency_key: `term_debt_${rId}`,
          },
          actor,
        });
        released.debtTransferred = {
          totalMinor: p.total_minor,
          itemCount: p.item_count,
        };
      } else if (BigInt(p.total_minor) > 0n) {
        throw new PlatformError(409, 'DEBT_TRANSFER_NOT_AVAILABLE', 'Ayrılma tamamlandı; borç devri yapılamadı. Malik kaydını ve borçları Finans bölümünden kontrol edin.');
      }
    } catch (err) {
      // eslint-disable-next-line no-console
      console.warn('[termination] liability transfer failed:', err.code ?? 'TRANSFER_FAILED');
      debtTransferError = err instanceof PlatformError ? err.message : 'Borç devri tamamlanamadı. Finans bölümünden borçları kontrol edip devri yeniden yapın.';
      released.debtTransferError = debtTransferError;
    }
  }

  // Transaction dışı: Token döndürme
  if (accessClosed || released.siteRolesEnded) {
    await rotateTokensForSite({ siteCode: sCode, reason: 'residency_termination_360' }).catch(() => {});
  }

  return {
    ok: true,
    debtTransferFailed: debtTransferError !== null,
    debtTransferError,
    accessClosed,
    released,
  };
}
