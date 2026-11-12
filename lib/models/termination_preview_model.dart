/// 360° Daireden Ayrılma ve İlişik Kesme Önizleme Modeli.
class TerminationPreview {
  const TerminationPreview({
    required this.residencyId,
    required this.relation,
    this.moveInDate,
    required this.isMinor,
    required this.personId,
    this.userCode,
    required this.fullName,
    this.phone,
    this.email,
    required this.isAdmin,
    required this.apartmentId,
    required this.apartmentNo,
    required this.blockName,
    required this.remainingMembers,
    this.defaultSuccessorUserCode,
    required this.activeVehicles,
    required this.upcomingReservations,
    required this.activeGuestPasses,
    required this.debt,
    required this.siteRoles,
    required this.meters,
  });

  final int residencyId;
  final String relation;
  final String? moveInDate;
  final bool isMinor;

  final int personId;
  final int? userCode;
  final String fullName;
  final String? phone;
  final String? email;
  final bool isAdmin;

  final int apartmentId;
  final String apartmentNo;
  final String blockName;

  final List<TerminationRemainingMember> remainingMembers;
  final int? defaultSuccessorUserCode;

  final List<TerminationVehicle> activeVehicles;
  final List<TerminationReservation> upcomingReservations;
  final List<TerminationGuestPass> activeGuestPasses;

  final TerminationDebt debt;
  final TerminationSiteRoles siteRoles;
  final List<TerminationMeter> meters;

  String get apartmentFullLabel {
    final b = blockName.trim();
    if (b.isEmpty) return 'No: $apartmentNo';
    return '$b - No: $apartmentNo';
  }

  factory TerminationPreview.fromJson(Map<String, dynamic> json) {
    final res = json['residency'] as Map<String, dynamic>? ?? {};
    final p = json['person'] as Map<String, dynamic>? ?? {};
    final apt = json['apartment'] as Map<String, dynamic>? ?? {};
    final d = json['debt'] as Map<String, dynamic>? ?? {};
    final sr = json['siteRoles'] as Map<String, dynamic>? ?? {};

    final remainingList = (json['remainingMembers'] as List<dynamic>?)
            ?.map((m) => TerminationRemainingMember.fromJson(m as Map<String, dynamic>))
            .toList(growable: false) ??
        const [];

    final vehiclesList = (json['activeVehicles'] as List<dynamic>?)
            ?.map((v) => TerminationVehicle.fromJson(v as Map<String, dynamic>))
            .toList(growable: false) ??
        const [];

    final reservationsList = (json['upcomingReservations'] as List<dynamic>?)
            ?.map((r) => TerminationReservation.fromJson(r as Map<String, dynamic>))
            .toList(growable: false) ??
        const [];

    final guestPassesList = (json['activeGuestPasses'] as List<dynamic>?)
            ?.map((g) => TerminationGuestPass.fromJson(g as Map<String, dynamic>))
            .toList(growable: false) ??
        const [];

    final metersList = (json['meters'] as List<dynamic>?)
            ?.map((m) => TerminationMeter.fromJson(m as Map<String, dynamic>))
            .toList(growable: false) ??
        const [];

    return TerminationPreview(
      residencyId: (res['id'] as num?)?.toInt() ?? 0,
      relation: (res['relation'] as String?) ?? 'resident',
      moveInDate: res['moveInDate'] as String?,
      isMinor: res['isMinor'] == true,
      personId: (p['id'] as num?)?.toInt() ?? 0,
      userCode: (p['userCode'] as num?)?.toInt(),
      fullName: (p['fullName'] as String?) ?? '',
      phone: p['phone'] as String?,
      email: p['email'] as String?,
      isAdmin: p['isAdmin'] == true,
      apartmentId: (apt['id'] as num?)?.toInt() ?? 0,
      apartmentNo: (apt['apartmentNo'] as String?) ?? '',
      blockName: (apt['blockName'] as String?) ?? '',
      remainingMembers: remainingList,
      defaultSuccessorUserCode: (json['defaultSuccessorUserCode'] as num?)?.toInt(),
      activeVehicles: vehiclesList,
      upcomingReservations: reservationsList,
      activeGuestPasses: guestPassesList,
      debt: TerminationDebt.fromJson(d),
      siteRoles: TerminationSiteRoles.fromJson(sr),
      meters: metersList,
    );
  }
}

class TerminationRemainingMember {
  const TerminationRemainingMember({
    required this.residencyId,
    required this.personId,
    this.userCode,
    required this.fullName,
    this.phone,
    required this.relation,
    this.membershipRole,
  });

  final int residencyId;
  final int personId;
  final int? userCode;
  final String fullName;
  final String? phone;
  final String relation;
  final String? membershipRole;

  factory TerminationRemainingMember.fromJson(Map<String, dynamic> json) {
    return TerminationRemainingMember(
      residencyId: (json['residencyId'] as num?)?.toInt() ?? 0,
      personId: (json['personId'] as num?)?.toInt() ?? 0,
      userCode: (json['userCode'] as num?)?.toInt(),
      fullName: (json['fullName'] as String?) ?? '',
      phone: json['phone'] as String?,
      relation: (json['relation'] as String?) ?? 'resident',
      membershipRole: json['membershipRole'] as String?,
    );
  }
}

class TerminationVehicle {
  const TerminationVehicle({
    required this.id,
    required this.plate,
    this.plateDisplay,
    this.note,
  });

  final int id;
  final String plate;
  final String? plateDisplay;
  final String? note;

  factory TerminationVehicle.fromJson(Map<String, dynamic> json) {
    return TerminationVehicle(
      id: (json['id'] as num?)?.toInt() ?? 0,
      plate: (json['plate'] as String?) ?? '',
      plateDisplay: json['plate_display'] as String?,
      note: json['note'] as String?,
    );
  }
}

class TerminationReservation {
  const TerminationReservation({
    required this.id,
    required this.areaId,
    this.areaName,
    required this.startsAt,
    required this.endsAt,
    required this.slotCount,
    required this.status,
  });

  final int id;
  final int areaId;
  final String? areaName;
  final String startsAt;
  final String endsAt;
  final int slotCount;
  final String status;

  factory TerminationReservation.fromJson(Map<String, dynamic> json) {
    return TerminationReservation(
      id: (json['id'] as num?)?.toInt() ?? 0,
      areaId: (json['area_id'] as num?)?.toInt() ?? 0,
      areaName: json['area_name'] as String?,
      startsAt: (json['starts_at'] as String?) ?? '',
      endsAt: (json['ends_at'] as String?) ?? '',
      slotCount: (json['slot_count'] as num?)?.toInt() ?? 1,
      status: (json['status'] as String?) ?? '',
    );
  }
}

class TerminationGuestPass {
  const TerminationGuestPass({
    required this.id,
    required this.title,
    required this.token,
    required this.passType,
    required this.expiresAt,
  });

  final int id;
  final String title;
  final String token;
  final String passType;
  final String expiresAt;

  factory TerminationGuestPass.fromJson(Map<String, dynamic> json) {
    return TerminationGuestPass(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      token: (json['token'] as String?) ?? '',
      passType: (json['pass_type'] as String?) ?? '',
      expiresAt: (json['expires_at'] as String?) ?? '',
    );
  }
}

class TerminationDebt {
  const TerminationDebt({
    required this.balanceMinor,
    required this.balanceFormatted,
    required this.hasDebt,
    this.liabilityTransfer,
  });

  final String balanceMinor;
  final String balanceFormatted;
  final bool hasDebt;
  final TerminationLiabilityTransfer? liabilityTransfer;

  factory TerminationDebt.fromJson(Map<String, dynamic> json) {
    final lt = json['liabilityTransfer'] as Map<String, dynamic>?;
    return TerminationDebt(
      balanceMinor: (json['balanceMinor'] as String?) ?? '0',
      balanceFormatted: (json['balanceFormatted'] as String?) ?? '0 TL',
      hasDebt: json['hasDebt'] == true,
      liabilityTransfer: lt != null ? TerminationLiabilityTransfer.fromJson(lt) : null,
    );
  }
}

class TerminationLiabilityTransfer {
  const TerminationLiabilityTransfer({
    required this.hasOwner,
    required this.canTransfer,
    required this.itemCount,
    required this.totalMinor,
    this.previewHash,
    required this.ownerBalanceMinor,
  });

  final bool hasOwner;
  final bool canTransfer;
  final int itemCount;
  final String totalMinor;
  final String? previewHash;
  final String ownerBalanceMinor;

  factory TerminationLiabilityTransfer.fromJson(Map<String, dynamic> json) {
    return TerminationLiabilityTransfer(
      hasOwner: json['hasOwner'] == true,
      canTransfer: json['canTransfer'] == true,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      totalMinor: (json['totalMinor'] as String?) ?? '0',
      previewHash: json['previewHash'] as String?,
      ownerBalanceMinor: (json['ownerBalanceMinor'] as String?) ?? '0',
    );
  }
}

class TerminationSiteRoles {
  const TerminationSiteRoles({
    required this.isSiteManager,
    required this.duties,
    required this.hasRoles,
  });

  final bool isSiteManager;
  final List<TerminationDuty> duties;
  final bool hasRoles;

  factory TerminationSiteRoles.fromJson(Map<String, dynamic> json) {
    final dList = (json['duties'] as List<dynamic>?)
            ?.map((d) => TerminationDuty.fromJson(d as Map<String, dynamic>))
            .toList(growable: false) ??
        const [];
    return TerminationSiteRoles(
      isSiteManager: json['isSiteManager'] == true,
      duties: dList,
      hasRoles: json['hasRoles'] == true,
    );
  }
}

class TerminationDuty {
  const TerminationDuty({
    required this.id,
    required this.duty,
    this.title,
  });

  final int id;
  final String duty;
  final String? title;

  String get label {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    switch (duty) {
      case 'board_member':
        return 'Yönetim Kurulu Üyesi';
      case 'auditor':
        return 'Denetçi';
      case 'doorman':
        return 'Bina Görevlisi / Kapıcı';
      case 'technical':
        return 'Teknik Personel';
      case 'reception':
        return 'Güvenlik / Resepsiyon';
      default:
        return 'Site Görevlisi';
    }
  }

  factory TerminationDuty.fromJson(Map<String, dynamic> json) {
    return TerminationDuty(
      id: (json['id'] as num?)?.toInt() ?? 0,
      duty: (json['duty'] as String?) ?? '',
      title: json['title'] as String?,
    );
  }
}

class TerminationMeter {
  const TerminationMeter({
    required this.id,
    required this.kind,
    required this.serialNo,
    this.lastReadingValue,
    this.lastReadingDate,
  });

  final int id;
  final String kind;
  final String serialNo;
  final double? lastReadingValue;
  final String? lastReadingDate;

  String get kindLabel {
    switch (kind) {
      case 'water':
        return 'Su Sayacı';
      case 'electricity':
        return 'Elektrik Sayacı';
      case 'heat':
        return 'Isı / Kalorimetre';
      case 'hot_water':
        return 'Sıcak Su Sayacı';
      default:
        return 'Sayaç ($kind)';
    }
  }

  factory TerminationMeter.fromJson(Map<String, dynamic> json) {
    return TerminationMeter(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] as String?) ?? '',
      serialNo: (json['serialNo'] as String?) ?? '',
      lastReadingValue: (json['lastReadingValue'] as num?)?.toDouble(),
      lastReadingDate: json['lastReadingDate'] as String?,
    );
  }
}
