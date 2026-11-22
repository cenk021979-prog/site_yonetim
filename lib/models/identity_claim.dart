class IdentityCandidate {
  const IdentityCandidate({
    required this.candidateRef,
    this.maskedName,
    this.maskedLoginName,
    this.maskedEmail,
    this.maskedPhone,
    this.accountType,
  });

  final String candidateRef;
  final String? maskedName;
  final String? maskedLoginName;
  final String? maskedEmail;
  final String? maskedPhone;
  final String? accountType;

  String get displayLabel {
    final parts = <String>[
      if (maskedName != null && maskedName!.trim().isNotEmpty)
        maskedName!.trim(),
      if (maskedLoginName != null && maskedLoginName!.trim().isNotEmpty)
        maskedLoginName!.trim(),
      if (maskedPhone != null && maskedPhone!.trim().isNotEmpty)
        maskedPhone!.trim(),
      if (maskedEmail != null && maskedEmail!.trim().isNotEmpty)
        maskedEmail!.trim(),
    ];
    if (parts.isEmpty) {
      return accountType == 'resident_managed'
          ? 'Daire hesabı'
          : 'Kayıtlı hesap';
    }
    return parts.join(' • ');
  }

  factory IdentityCandidate.fromJson(Map<String, dynamic> json) {
    return IdentityCandidate(
      candidateRef: (json['candidate_ref'] ?? json['candidateRef'] ?? '')
          .toString(),
      maskedName: json['masked_name'] as String?,
      maskedLoginName: json['masked_login_name'] as String?,
      maskedEmail: json['masked_email'] as String?,
      maskedPhone: json['masked_phone'] as String?,
      accountType: json['account_type'] as String?,
    );
  }
}

class IdentityClaimChallenge {
  const IdentityClaimChallenge({
    required this.challengeToken,
    this.provider,
    this.expiresInSeconds = 600,
    this.candidates = const <IdentityCandidate>[],
    this.verificationMethods = const <String>['credentials'],
    this.message,
  });

  final String challengeToken;
  final String? provider;
  final int expiresInSeconds;
  final List<IdentityCandidate> candidates;
  final List<String> verificationMethods;
  final String? message;

  bool get supportsCredentials => verificationMethods.contains('credentials');
  bool get supportsSmsOtp => verificationMethods.contains('sms_otp');

  factory IdentityClaimChallenge.fromPayload(
    Map<String, dynamic> payload, {
    String? fallbackMessage,
  }) {
    final rawCands = payload['candidates'];
    final candidates = rawCands is List
        ? rawCands
              .whereType<Map>()
              .map(
                (e) => IdentityCandidate.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(growable: false)
        : const <IdentityCandidate>[];
    final rawMethods = payload['verification_methods'];
    final methods = rawMethods is List
        ? rawMethods.map((e) => e.toString()).toList(growable: false)
        : const <String>['credentials'];
    return IdentityClaimChallenge(
      challengeToken: (payload['challenge_token'] ?? '').toString(),
      provider: payload['provider'] as String?,
      expiresInSeconds: (payload['expires_in_seconds'] as num?)?.toInt() ?? 600,
      candidates: candidates,
      verificationMethods: methods.isEmpty ? const ['credentials'] : methods,
      message:
          (payload['error'] ?? payload['message']) as String? ??
          fallbackMessage,
    );
  }
}

class SmsSelectionChallenge {
  const SmsSelectionChallenge({
    required this.selectionToken,
    this.expiresInSeconds = 600,
    this.candidates = const <IdentityCandidate>[],
    this.message,
  });

  final String selectionToken;
  final int expiresInSeconds;
  final List<IdentityCandidate> candidates;
  final String? message;

  factory SmsSelectionChallenge.fromPayload(Map<String, dynamic> payload) {
    final rawCands = payload['candidates'];
    final candidates = rawCands is List
        ? rawCands
              .whereType<Map>()
              .map(
                (e) => IdentityCandidate.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(growable: false)
        : const <IdentityCandidate>[];
    return SmsSelectionChallenge(
      selectionToken: (payload['selection_token'] ?? '').toString(),
      expiresInSeconds: (payload['expires_in_seconds'] as num?)?.toInt() ?? 600,
      candidates: candidates,
      message: payload['message'] as String?,
    );
  }
}

class IdentityAuthResult {
  const IdentityAuthResult({
    this.error,
    this.claimedExistingAccount = false,
    this.claimMessage,
    this.canClaimExistingAccount = false,
    this.isApplePrivateRelay = false,
    this.claimChallenge,
    this.smsSelection,
  });

  final String? error;
  final bool claimedExistingAccount;
  final String? claimMessage;
  final bool canClaimExistingAccount;
  final bool isApplePrivateRelay;
  final IdentityClaimChallenge? claimChallenge;
  final SmsSelectionChallenge? smsSelection;

  bool get ok =>
      error == null && claimChallenge == null && smsSelection == null;
}
