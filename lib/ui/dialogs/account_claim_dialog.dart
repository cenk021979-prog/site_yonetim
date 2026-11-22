import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/identity_claim.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class AccountClaimDialog extends StatefulWidget {
  const AccountClaimDialog({
    super.key,
    required this.authService,
    this.challenge,
    this.title,
    this.subtitle,
    this.showSkipButton = false,
  });

  final AuthService authService;
  final IdentityClaimChallenge? challenge;
  final String? title;
  final String? subtitle;
  final bool showSkipButton;

  static Future<IdentityAuthResult?> showForChallenge(
    BuildContext context, {
    required AuthService authService,
    required IdentityClaimChallenge challenge,
  }) {
    return showDialog<IdentityAuthResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          AccountClaimDialog(authService: authService, challenge: challenge),
    );
  }

  static Future<IdentityAuthResult?> showForAuthenticatedSession(
    BuildContext context, {
    required AuthService authService,
    String? title,
    String? subtitle,
    bool showSkipButton = true,
  }) {
    return showDialog<IdentityAuthResult>(
      context: context,
      barrierDismissible: !showSkipButton,
      builder: (_) => AccountClaimDialog(
        authService: authService,
        title: title,
        subtitle: subtitle,
        showSkipButton: showSkipButton,
      ),
    );
  }

  @override
  State<AccountClaimDialog> createState() => _AccountClaimDialogState();
}

class _AccountClaimDialogState extends State<AccountClaimDialog> {
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _smsCodeCtrl = TextEditingController();

  String _method = 'credentials';
  bool _obscurePassword = true;
  bool _isBusy = false;
  bool _smsSent = false;
  String? _error;
  String? _infoMessage;
  SmsSelectionChallenge? _smsSelection;
  String? _selectedCandidateRef;
  List<IdentityCandidate> _overrideCandidates = const <IdentityCandidate>[];

  @override
  void initState() {
    super.initState();
    final ch = widget.challenge;
    if (ch != null && !ch.supportsCredentials && ch.supportsSmsOtp) {
      _method = 'sms_otp';
    }
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _smsCodeCtrl.dispose();
    super.dispose();
  }

  bool get _supportsSms {
    final ch = widget.challenge;
    if (ch == null) return true;
    return ch.supportsSmsOtp;
  }

  List<IdentityCandidate> get _candidates {
    if (_overrideCandidates.isNotEmpty) return _overrideCandidates;
    return widget.challenge?.candidates ?? const <IdentityCandidate>[];
  }

  Future<void> _requestSms() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 10) {
      setState(() => _error = 'Geçerli bir telefon numarası girin.');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
      _infoMessage = null;
    });
    String? err;
    final ch = widget.challenge;
    if (ch != null) {
      final res = await widget.authService.requestIdentityClaimSmsCode(
        challengeToken: ch.challengeToken,
        phone: phone,
      );
      err = res.error;
    } else {
      err = await widget.authService.requestSmsCode(phone: phone);
    }
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      if (err != null) {
        _error = err;
      } else {
        _smsSent = true;
        _infoMessage =
            'Doğrulama kodu gönderildi (varsa kayıtlı telefonunuza).';
      }
    });
  }

  Future<void> _submit() async {
    if (_isBusy) return;
    final ch = widget.challenge;

    if (_smsSelection != null) {
      final ref = _selectedCandidateRef;
      if (ref == null || ref.isEmpty) {
        setState(() => _error = 'Lütfen listeden hesabınızı seçin.');
        return;
      }
      setState(() {
        _isBusy = true;
        _error = null;
      });
      final res = ch != null
          ? await widget.authService.verifyIdentityClaimChallenge(
              challengeToken: ch.challengeToken,
              method: 'selection',
              candidateRef: ref,
            )
          : await widget.authService.completeSmsAccountSelection(
              selectionToken: _smsSelection!.selectionToken,
              candidateRef: ref,
            );
      if (!mounted) return;
      if (res.ok) {
        Navigator.of(context).pop(res);
      } else {
        setState(() {
          _isBusy = false;
          _error = res.error ?? 'Seçim tamamlanamadı.';
        });
      }
      return;
    }

    if (_method == 'credentials') {
      if (_identifierCtrl.text.trim().isEmpty ||
          _passwordCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Kullanıcı adı/e-posta ve şifre/PIN girin.');
        return;
      }
    } else {
      if (_phoneCtrl.text.trim().length < 10 ||
          _smsCodeCtrl.text.trim().length != 6) {
        setState(() => _error = 'Telefon numarası ve 6 haneli kodu girin.');
        return;
      }
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    final IdentityAuthResult res;
    if (ch != null) {
      res = await widget.authService.verifyIdentityClaimChallenge(
        challengeToken: ch.challengeToken,
        method: _method,
        identifier: _method == 'credentials'
            ? _identifierCtrl.text.trim()
            : null,
        password: _method == 'credentials' ? _passwordCtrl.text.trim() : null,
        phone: _method == 'sms_otp' ? _phoneCtrl.text.trim() : null,
        code: _method == 'sms_otp' ? _smsCodeCtrl.text.trim() : null,
      );
    } else {
      res = await widget.authService.claimExistingAccountInPlace(
        method: _method,
        identifier: _method == 'credentials'
            ? _identifierCtrl.text.trim()
            : null,
        password: _method == 'credentials' ? _passwordCtrl.text.trim() : null,
        phone: _method == 'sms_otp' ? _phoneCtrl.text.trim() : null,
        code: _method == 'sms_otp' ? _smsCodeCtrl.text.trim() : null,
      );
    }

    if (!mounted) return;
    if (res.smsSelection != null) {
      setState(() {
        _isBusy = false;
        _smsSelection = res.smsSelection;
        _selectedCandidateRef = res.smsSelection!.candidates.isNotEmpty
            ? res.smsSelection!.candidates.first.candidateRef
            : null;
      });
      return;
    }
    if (res.claimChallenge != null &&
        res.claimChallenge!.candidates.isNotEmpty) {
      setState(() {
        _isBusy = false;
        _overrideCandidates = res.claimChallenge!.candidates;
        _error = res.error;
      });
      return;
    }
    if (res.ok) {
      Navigator.of(context).pop(res);
      return;
    }
    setState(() {
      _isBusy = false;
      _error = res.error ?? 'Doğrulama başarısız.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final titleText = widget.title ?? 'Mevcut hesabınız bulundu';
    final subtitleText =
        widget.subtitle ??
        widget.challenge?.message ??
        'Güvenliğiniz için daire hesabınızı doğrulayarak mevcut hesabınızla bağlayın.';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titleText,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                subtitleText,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (_candidates.isNotEmpty && _smsSelection == null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.65,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Eşleşen maskeli kayıtlar',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final cand in _candidates)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  cand.displayLabel,
                                  style: textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (_smsSelection != null) ...[
                Text(
                  'Bağlamak istediğiniz hesabı seçin',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                for (final cand in _smsSelection!.candidates)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      key: ValueKey(
                        'claim_select_candidate_${cand.candidateRef}',
                      ),
                      borderRadius: BorderRadius.circular(12),
                      onTap: _isBusy
                          ? null
                          : () => setState(
                              () => _selectedCandidateRef = cand.candidateRef,
                            ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedCandidateRef == cand.candidateRef
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: _selectedCandidateRef == cand.candidateRef
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                cand.displayLabel,
                                style: textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ] else ...[
                Text(
                  'Hesabınızı doğrulamak için bir yöntem seçin',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('claim_method_credentials'),
                      label: const Text('Kullanıcı adı + Şifre/PIN'),
                      selected: _method == 'credentials',
                      onSelected: _isBusy
                          ? null
                          : (_) => setState(() {
                              _method = 'credentials';
                              _error = null;
                            }),
                    ),
                    if (_supportsSms)
                      ChoiceChip(
                        key: const ValueKey('claim_method_sms'),
                        label: const Text('Telefon SMS Kodu'),
                        selected: _method == 'sms_otp',
                        onSelected: _isBusy
                            ? null
                            : (_) => setState(() {
                                _method = 'sms_otp';
                                _error = null;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_method == 'credentials') ...[
                  TextField(
                    key: const ValueKey('claim_identifier_field'),
                    controller: _identifierCtrl,
                    enabled: !_isBusy,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı adı veya e-posta',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('claim_password_field'),
                    controller: _passwordCtrl,
                    enabled: !_isBusy,
                    obscureText: _obscurePassword,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Şifre veya daire PIN kodu',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  TextField(
                    key: const ValueKey('claim_phone_field'),
                    controller: _phoneCtrl,
                    enabled: !_isBusy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefon numarası',
                      hintText: '05xx xxx xx xx',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('claim_send_sms_btn'),
                      onPressed: _isBusy ? null : _requestSms,
                      icon: const Icon(Icons.sms_outlined, size: 18),
                      label: Text(
                        _smsSent
                            ? 'Kodu Yeniden Gönder'
                            : 'Doğrulama Kodu Gönder',
                      ),
                    ),
                  ),
                  if (_infoMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _infoMessage!,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('claim_sms_code_field'),
                    controller: _smsCodeCtrl,
                    enabled: !_isBusy,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: '6 haneli doğrulama kodu',
                      prefixIcon: Icon(Icons.pin_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: scheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('claim_cancel_btn'),
                    onPressed: _isBusy
                        ? null
                        : () => Navigator.of(context).pop(null),
                    child: Text(
                      widget.showSkipButton
                          ? 'Yeni hesapla devam et'
                          : 'Vazgeç',
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('claim_submit_btn'),
                    onPressed: _isBusy ? null : _submit,
                    child: _isBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _smsSelection != null
                                ? 'Seçili Hesabı Bağla'
                                : 'Hesabı Doğrula ve Bağla',
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
