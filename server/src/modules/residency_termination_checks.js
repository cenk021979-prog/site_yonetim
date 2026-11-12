// Ayrılma akışının giriş/sayaç doğrulamaları. Finans borcu ve tahsilat burada yeniden hesaplanmaz.
import { actorFromAuthUser } from './audit_service.js';
import { PlatformError } from './errors.js';
import { dateToIso, invalidBody, normalizeDateInput, parsePositiveId, todayIso } from './people_common.js';
import { parseReadingValue } from './metering_common.js';
import { insertReading } from './metering_service.js';

export function terminationIds({ siteCode, apartmentId, residencyId }) {
  const ids = [siteCode, apartmentId, residencyId].map((id) => parsePositiveId(id));
  if (ids.some((id) => id === null)) throw invalidBody('id', 'Site, daire ve ikamet kimlikleri geçersiz.');
  return { sCode: ids[0], aId: ids[1], rId: ids[2] };
}

export function terminationInput({ moveOutDate, successorUserCode, debtDisposition, finalMeterReadings }, now = new Date()) {
  const date = normalizeDateInput(moveOutDate, 'move_out_date') ?? todayIso(now);
  if (date > todayIso(now)) throw invalidBody('move_out_date', 'Çıkış tarihi gelecekte olamaz.');
  if (!['KEEP_ON_DEBTOR', 'PAID', 'TRANSFER_TO_OWNER'].includes(debtDisposition)) {
    throw invalidBody('debt_disposition', 'Borç işlemi seçimi geçersiz.');
  }
  const successor = successorUserCode == null ? null : parsePositiveId(successorUserCode);
  if (successorUserCode != null && successor === null) throw invalidBody('successor_user_code');
  if (!Array.isArray(finalMeterReadings) || finalMeterReadings.length > 50) throw invalidBody('final_meter_readings');
  const ids = new Set();
  const readings = finalMeterReadings.map((reading) => {
    const meterId = parsePositiveId(reading?.meterId);
    const parsed = parseReadingValue(reading?.readingValue);
    const readingDate = normalizeDateInput(reading?.readingDate, 'reading_date') ?? date;
    if (meterId === null || !parsed || ids.has(meterId)) {
      throw invalidBody('final_meter_readings', 'Sayaç ve endeks geçerli olmalı; aynı sayaç iki kez gönderilemez.');
    }
    if (readingDate > todayIso(now)) throw invalidBody('reading_date', 'Okuma tarihi gelecekte olamaz.');
    ids.add(meterId);
    return { meterId, date: readingDate, parsed };
  }).sort((a, b) => a.meterId - b.meterId);
  return { date, successor, readings };
}

export function assertMoveOutAfterEntry(date, moveInDate) {
  const moveIn = dateToIso(moveInDate);
  if (moveIn && date < moveIn) throw invalidBody('move_out_date', 'Çıkış tarihi giriş tarihinden önce olamaz.');
}

/** Çağıran metering:<site> kilidini alır; tüm okumalar ayrılmayla aynı transaction'dadır. */
export async function saveTerminationReadings(client, { siteCode, apartmentId, readings, actor }) {
  for (const reading of readings) {
    const meter = await client.query(
      'SELECT id, is_active FROM meters WHERE id = $1 AND site_code = $2 AND apartment_id = $3 FOR KEY SHARE',
      [reading.meterId, siteCode, apartmentId],
    );
    if (!meter.rows?.[0] || meter.rows[0].is_active !== true) {
      throw new PlatformError(404, 'METER_NOT_FOUND', 'Sayaç bu daireye ait değil veya etkin değil.');
    }
    await insertReading(client, { ...reading, siteCode, source: 'manual', userCode: actorFromAuthUser(actor).userCode });
  }
}
