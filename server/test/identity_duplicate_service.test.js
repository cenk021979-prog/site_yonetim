import test from 'node:test';
import assert from 'node:assert/strict';

import {
  assertJoinIdentitySafe,
  findPossibleExistingAccount,
  identityKey,
} from '../src/modules/identity_duplicate_service.js';

function dbFor(current, candidates) {
  let call = 0;
  return {
    async query() {
      call += 1;
      return call === 1
        ? { rowCount: current ? 1 : 0, rows: current ? [current] : [] }
        : { rowCount: candidates.length, rows: candidates };
    },
  };
}

const current = {
  user_code: 85330,
  full_name: 'suayip.kaymaz',
  email: 'new@example.com',
  login_name: null,
  phone_number: null,
};

const existing = {
  user_code: 67628,
  full_name: 'Şuayip Kaymaz',
  email: 'suayip.kaymaz.1136.6070832089@ahbu.local',
  login_name: 'suayip.kaymaz',
  phone_number: '05000000000',
  person_emails: [],
  person_phones: [],
  resident_emails: [],
  apartment_labels: ['A Blok - Daire 3'],
};

test('identityKey Türkçe harf, boşluk ve noktayı aynı kimlik anahtarına indirger', () => {
  assert.equal(identityKey('Şuayip Kaymaz'), 'suayipkaymaz');
  assert.equal(identityKey('suayip.kaymaz'), 'suayipkaymaz');
});
test('mevcut kullanıcı adı/ad eşleşmesi olası hesabı bulur; dahili e-posta eşleşme sayılmaz', async () => {
  const result = await findPossibleExistingAccount(dbFor(current, [existing]), {
    siteCode: 6070832089,
    userCode: 85330,
  });
  assert.equal(result.userCode, 67628);
  assert.deepEqual(result.reasons.sort(), ['login_name', 'name']);
  assert.equal(result.maskedLoginName, 'su***az');
  assert.deepEqual(result.apartmentLabels, ['A Blok - Daire 3']);
});

test('eşleşme doğrulanmadan katılım 409 ACCOUNT_CLAIM_REQUIRED ile durur', async () => {
  await assert.rejects(
    () => assertJoinIdentitySafe(dbFor(current, [existing]), {
      siteCode: 6070832089,
      userCode: 85330,
      audience: 'resident',
    }),
    (error) => error.statusCode === 409 &&
      error.code === 'ACCOUNT_CLAIM_REQUIRED' &&
      error.extra?.candidate_login_hint === 'su***az',
  );
});

test('farklı kişi geçişi gerekçesiz açılamaz; gerekçeli doğrulama denetime uygun özet döndürür', async () => {
  await assert.rejects(
    () => assertJoinIdentitySafe(dbFor(current, [existing]), {
      siteCode: 6070832089,
      userCode: 85330,
      confirmedDistinctPerson: true,
      confirmationReason: 'kısa',
    }),
    (error) => error.code === 'DUPLICATE_CONFIRMATION_REASON_REQUIRED',
  );

  const result = await assertJoinIdentitySafe(dbFor(current, [existing]), {
    siteCode: 6070832089,
    userCode: 85330,
    confirmedDistinctPerson: true,
    confirmationReason: 'Kimlik belgesiyle farklı kişi olduğu doğrulandı.',
  });
  assert.equal(result.userCode, 67628);
  assert.equal(result.confirmationReason, 'Kimlik belgesiyle farklı kişi olduğu doğrulandı.');
});

test('aynı ad dışında sinyal yoksa farklı kişi engellenmez', async () => {
  const result = await findPossibleExistingAccount(
    dbFor({ ...current, full_name: 'Ahmet Yılmaz', email: 'ahmet2@example.com' }, [
      { ...existing, full_name: 'Mehmet Yılmaz', login_name: 'mehmet.yilmaz' },
    ]),
    { siteCode: 1, userCode: 2 },
  );
  assert.equal(result, null);
});

