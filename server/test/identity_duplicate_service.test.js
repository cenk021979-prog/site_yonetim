import assert from 'node:assert/strict';
import test from 'node:test';

import {
  assertJoinIdentitySafe,
  findPossibleExistingAccount,
  identityKey,
} from '../src/modules/identity_duplicate_service.js';

function makeDuplicateMockDb(rows = []) {
  return {
    async query(sql, params = []) {
      const text = String(sql);
      if (text.includes('SELECT email_verified FROM users')) {
        return { rows: [{ email_verified: true }], rowCount: 1 };
      }
      if (text.includes('SELECT full_name, email, email_verified')) {
        return {
          rows: [
            {
              full_name: 'Ayşe Yılmaz',
              email: 'ayse@example.com',
              email_verified: true,
              phone_number: '05321112233',
              login_name: 'ayse.yilmaz',
            },
          ],
          rowCount: 1,
        };
      }
      if (text.includes('FROM users u') && text.includes('UNION ALL')) {
        const excludeCode = params[0];
        return {
          rows: rows.filter((r) => r.user_code == null || Number(r.user_code) !== Number(excludeCode)),
          rowCount: rows.length,
        };
      }
      return { rows: [], rowCount: 0 };
    },
  };
}

test('identityKey Türkçe harf, boşluk ve noktayı aynı kimlik anahtarına indirger', () => {
  assert.equal(identityKey('Şüayip  Kaymaz.'), 'suayipkaymaz');
  assert.equal(identityKey('suayip kaymaz'), 'suayipkaymaz');
});

test('Yalnız ad veya kullanıcı adı benzerliği (zayıf sinyal) ENGEL OLUŞTURMAZ, 409 fırlatmaz', async () => {
  const db = makeDuplicateMockDb([
    {
      user_code: 42,
      full_name: 'Ayşe Yılmaz',
      email: 'daire42@ahbu.local',
      login_name: 'ayse.yilmaz',
      phone_number: null,
      resident_email: null,
      person_email: null,
      person_phone: null,
      source: 'user',
    },
  ]);

  const match = await findPossibleExistingAccount(db, {
    userCode: 99,
    siteCode: 1001,
    fullName: 'Ayşe Yılmaz',
    email: 'farkli.ayse@gmail.com',
    phone: '05559998877',
    loginName: 'ayse.yilmaz',
  });

  assert.ok(match);
  assert.equal(match.strength, 'weak');
  assert.equal(match.is_strong_match, false);
  assert.deepEqual(match.strong_reasons, []);
  assert.ok(match.weak_reasons.includes('name'));

  // Katılım başvurusu ve yönetici onayı zayıf eşleşmede ASLA bloklanmaz
  const res = await assertJoinIdentitySafe(db, {
    userCode: 99,
    siteCode: 1001,
    fullName: 'Ayşe Yılmaz',
    email: 'farkli.ayse@gmail.com',
    phone: '05559998877',
    loginName: 'ayse.yilmaz',
    audience: 'resident',
  });
  assert.equal(res, null);

  const mgrRes = await assertJoinIdentitySafe(db, {
    userCode: 99,
    siteCode: 1001,
    fullName: 'Ayşe Yılmaz',
    email: 'farkli.ayse@gmail.com',
    phone: '05559998877',
    loginName: 'ayse.yilmaz',
    audience: 'manager',
  });
  assert.equal(mgrRes, null);
});

test('Güçlü sinyal (doğrulanmış e-posta veya telefon) başka aktif hesapla eşleşirse 409 ACCOUNT_CLAIM_REQUIRED döner', async () => {
  const db = makeDuplicateMockDb([
    {
      user_code: 55,
      full_name: 'Ahmet Demir',
      email: 'daire55@ahbu.local',
      login_name: 'ahmet.d5',
      phone_number: '+905321234567',
      resident_email: 'ahmet.demir@gmail.com',
      person_email: null,
      person_phone: null,
      source: 'user',
    },
  ]);

  await assert.rejects(
    () =>
      assertJoinIdentitySafe(db, {
        userCode: 120,
        siteCode: 1001,
        fullName: 'Farklı Başlık',
        email: 'ahmet.demir@gmail.com',
        phone: null,
        audience: 'resident',
      }),
    (err) => {
      assert.equal(err.statusCode, 409);
      assert.equal(err.code, 'ACCOUNT_CLAIM_REQUIRED');
      assert.equal(err.extra.existing_account.match_strength, 'strong');
      assert.equal(err.extra.existing_account.can_claim_in_place, true);
      assert.ok(err.extra.existing_account.reasons.includes('email'));
      // Maskelenmemiş hassas bilgi sızmaz
      assert.equal(err.extra.existing_account.user_code, undefined);
      assert.notEqual(err.extra.existing_account.masked_login_name, 'ahmet.d5');
      return true;
    },
  );
});

test('Hesapsız site_people kaydı (user_code: null) başka hesap değildir, katılımı engellemez', async () => {
  const db = makeDuplicateMockDb([
    {
      user_code: null,
      full_name: 'Ahmet Demir',
      email: 'ahmet.demir@gmail.com',
      login_name: null,
      phone_number: '05321234567',
      resident_email: null,
      person_email: 'ahmet.demir@gmail.com',
      person_phone: '05321234567',
      source: 'site_person',
    },
  ]);

  const res = await assertJoinIdentitySafe(db, {
    userCode: 120,
    siteCode: 1001,
    fullName: 'Ahmet Demir',
    email: 'ahmet.demir@gmail.com',
    phone: '05321234567',
    audience: 'resident',
  });
  assert.equal(res, null);
});

test('Farklı kişi geçişi en az 10 karakter gerekçe ister; gerekçeli onay denetim özeti döndürür', async () => {
  const db = makeDuplicateMockDb([
    {
      user_code: 77,
      full_name: 'Mehmet Kaya',
      email: 'mehmet@example.com',
      login_name: 'mehmet.kaya',
      phone_number: '05329998877',
      resident_email: null,
      person_email: null,
      person_phone: null,
      source: 'user',
    },
  ]);

  await assert.rejects(
    () =>
      assertJoinIdentitySafe(db, {
        userCode: 120,
        siteCode: 1001,
        fullName: 'Yeni Kullanıcı',
        email: 'mehmet@example.com',
        confirmedDistinctPerson: true,
        confirmationReason: 'kisa',
      }),
    (err) => err.statusCode === 400 && err.code === 'DUPLICATE_CONFIRMATION_REASON_REQUIRED',
  );

  const override = await assertJoinIdentitySafe(db, {
    userCode: 120,
    siteCode: 1001,
    fullName: 'Yeni Kullanıcı',
    email: 'mehmet@example.com',
    confirmedDistinctPerson: true,
    confirmationReason: 'Ortak aile e-postası kullanılıyor, farklı sakinim.',
  });
  assert.equal(override.userCode, 77);
  assert.ok(override.reasons.includes('email'));
  assert.ok(override.overrideReason.length >= 10);
});
