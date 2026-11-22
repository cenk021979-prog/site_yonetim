import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/identity_claim.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/account_claim_dialog.dart';
import 'package:site_kapi_kontrol/ui/pages/sms_login_page.dart';

import 'dialog_layout_harness.dart';

class _FakeClaimAuth extends AuthService {
  _FakeClaimAuth({this.verifyResult, this.smsOutcome})
    : super(api: AuthApi(baseUrl: 'http://localhost'));

  IdentityAuthResult? verifyResult;
  IdentityAuthResult? smsOutcome;
  int verifyCalls = 0;
  int smsCodeRequestCalls = 0;
  int selectionCompleteCalls = 0;
  String? lastSelectionCandidateRef;

  @override
  Future<IdentityAuthResult> completeSmsAccountSelection({
    required String selectionToken,
    required String candidateRef,
  }) async {
    selectionCompleteCalls += 1;
    lastSelectionCandidateRef = candidateRef;
    return const IdentityAuthResult();
  }

  @override
  Future<bool> smsLoginEnabled() async => true;

  @override
  Future<String?> requestSmsCode({required String phone}) async {
    smsCodeRequestCalls += 1;
    return null;
  }

  @override
  Future<({bool ok, String? error})> requestIdentityClaimSmsCode({
    required String challengeToken,
    required String phone,
  }) async {
    smsCodeRequestCalls += 1;
    return (ok: true, error: null);
  }

  @override
  Future<IdentityAuthResult> verifyIdentityClaimChallenge({
    required String challengeToken,
    required String method,
    String? identifier,
    String? password,
    String? phone,
    String? code,
    String? candidateRef,
  }) async {
    verifyCalls += 1;
    return verifyResult ??
        const IdentityAuthResult(
          claimedExistingAccount: true,
          claimMessage:
              'Mevcut hesabınız bulundu. Daire hesabınız güvenli biçimde bağlandı.',
        );
  }

  @override
  Future<IdentityAuthResult> loginWithSmsWithResult({
    required String phone,
    required String code,
  }) async {
    return smsOutcome ?? const IdentityAuthResult();
  }
}

IdentityClaimChallenge _ambiguousChallenge() => const IdentityClaimChallenge(
  challengeToken: 'ch-tok-1',
  provider: 'google',
  candidates: [
    IdentityCandidate(
      candidateRef: '1',
      maskedName: 'F**** K***',
      maskedLoginName: 'fat***a',
      maskedPhone: '05** *** **11',
      accountType: 'resident_managed',
    ),
    IdentityCandidate(
      candidateRef: '2',
      maskedName: 'H**** K***',
      maskedLoginName: 'has***a',
      maskedPhone: '05** *** **22',
      accountType: 'resident_managed',
    ),
  ],
  verificationMethods: ['credentials', 'sms_otp'],
  message:
      'Bu e-posta adresiyle birden fazla hesap kayıtlı. Hesabınızı doğrulayarak devam edebilirsiniz.',
);

void main() {
  layoutMatrix('AccountClaimDialog (çoklu güçlü eşleşme doğrulama taşmasız)', (
    t,
    width,
    height,
    scale,
    dark,
  ) async {
    final auth = _FakeClaimAuth();
    await openDialogAt(
      t,
      (ctx) => AccountClaimDialog.showForChallenge(
        ctx,
        authService: auth,
        challenge: _ambiguousChallenge(),
      ),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );

    expect(find.text('Mevcut hesabınız bulundu'), findsOneWidget);
    expect(
      find.text('Hesabınızı doğrulamak için bir yöntem seçin'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('claim_identifier_field')),
      findsOneWidget,
    );
  });

  testWidgets(
    'AccountClaimDialog: yanlış denemede hata gösterir, doğru denemede bağlayıp kapanır',
    (t) async {
      final auth = _FakeClaimAuth(
        verifyResult: const IdentityAuthResult(
          error: 'Kullanıcı adı veya şifre/PIN hatalı.',
        ),
      );
      IdentityAuthResult? dialogResult;
      await openDialogAt(
        t,
        (ctx) async {
          dialogResult = await AccountClaimDialog.showForChallenge(
            ctx,
            authService: auth,
            challenge: _ambiguousChallenge(),
          );
        },
        width: 380,
        height: 800,
        scale: 1.0,
        dark: false,
      );

      await t.enterText(
        find.byKey(const ValueKey('claim_identifier_field')),
        'fatma.kaya',
      );
      await t.enterText(
        find.byKey(const ValueKey('claim_password_field')),
        'wrong',
      );
      await t.ensureVisible(find.byKey(const ValueKey('claim_submit_btn')));
      await t.tap(find.byKey(const ValueKey('claim_submit_btn')));
      await t.pumpAndSettle();

      expect(auth.verifyCalls, 1);
      expect(find.text('Kullanıcı adı veya şifre/PIN hatalı.'), findsOneWidget);
      expect(dialogResult, isNull);

      auth.verifyResult = const IdentityAuthResult(
        claimedExistingAccount: true,
        claimMessage:
            'Mevcut hesabınız bulundu. Daire hesabınız güvenli biçimde bağlandı.',
      );
      await t.ensureVisible(find.byKey(const ValueKey('claim_submit_btn')));
      await t.tap(find.byKey(const ValueKey('claim_submit_btn')));
      await t.pumpAndSettle();

      expect(auth.verifyCalls, 2);
      expect(dialogResult, isNotNull);
      expect(dialogResult!.ok, isTrue);
      expect(dialogResult!.claimedExistingAccount, isTrue);
    },
  );

  testWidgets(
    'AccountClaimDialog: SMS OTP yöntemine geçiş çalışır ve kod ister',
    (t) async {
      final auth = _FakeClaimAuth();
      await openDialogAt(
        t,
        (ctx) => AccountClaimDialog.showForChallenge(
          ctx,
          authService: auth,
          challenge: _ambiguousChallenge(),
        ),
        width: 360,
        height: 780,
        scale: 1.0,
        dark: true,
      );

      await t.ensureVisible(find.byKey(const ValueKey('claim_method_sms')));
      await t.tap(find.byKey(const ValueKey('claim_method_sms')));
      await t.pumpAndSettle();

      await t.enterText(
        find.byKey(const ValueKey('claim_phone_field')),
        '05321112233',
      );
      await t.ensureVisible(find.byKey(const ValueKey('claim_send_sms_btn')));
      await t.tap(find.byKey(const ValueKey('claim_send_sms_btn')));
      await t.pumpAndSettle();

      expect(auth.smsCodeRequestCalls, 1);
      expect(
        find.byKey(const ValueKey('claim_sms_code_field')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SmsLoginPage: aynı telefonu paylaşan hesaplarda OTP sonrası maskeli seçim ekranı açılır',
    (t) async {
      final auth = _FakeClaimAuth(
        smsOutcome: const IdentityAuthResult(
          smsSelection: SmsSelectionChallenge(
            selectionToken: 'sel-tok-1',
            candidates: [
              IdentityCandidate(
                candidateRef: '1',
                maskedName: 'A*** Ü**',
                maskedLoginName: 'ann***e',
              ),
              IdentityCandidate(
                candidateRef: '2',
                maskedName: 'Ç**** Ü**',
                maskedLoginName: 'coc***e',
              ),
            ],
            message: 'Bu telefon numarasına bağlı birden fazla hesap bulundu.',
          ),
        ),
      );

      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SmsLoginPage(authService: auth),
                    ),
                  ),
                  child: const Text('Ac'),
                ),
              ),
            ),
          ),
        ),
      );

      await t.tap(find.text('Ac'));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField).first, '5321110000');
      await t.tap(find.text('Kod Gönder'));
      await t.pumpAndSettle();
      expect(auth.smsCodeRequestCalls, 1);

      await t.enterText(find.byType(TextField).last, '123456');
      await t.tap(find.text('Giriş Yap'));
      await t.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('sms_select_candidate_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sms_select_candidate_2')),
        findsOneWidget,
      );

      await t.tap(find.byKey(const ValueKey('sms_select_candidate_2')));
      await t.tap(find.byKey(const ValueKey('sms_complete_selection_btn')));
      await t.pumpAndSettle();

      expect(auth.selectionCompleteCalls, 1);
      expect(auth.lastSelectionCandidateRef, '2');
    },
  );
}
