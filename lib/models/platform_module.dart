import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/management_type.dart';
import 'package:site_kapi_kontrol/models/management_terms.dart';
import 'package:site_kapi_kontrol/models/menu_layout.dart';

/// Katalogdaki modül kodları (sunucuda sabit: `server/src/modules/catalog.js`).
abstract final class PlatformModuleCodes {
  static const String doorControl = 'door_control';
  static const String people = 'people';
  static const String announcements = 'announcements';
  static const String finance = 'finance';

  /// Rezervasyon ve Konsiyerj. TEMEL modül (Kural 25): her sitede açık.
  static const String reservation = 'reservation';

  /// İş Takibi. TEMEL modül (Kural 25): her sitede açık.
  static const String workTracking = 'work_tracking';
  static const String metering = 'metering';
  static const String onlinePayment = 'online_payment';

  /// Anket ve Oylama (F11.01). TEMEL modül (Kural 25): her sitede açık.
  static const String survey = 'survey';

  /// Ziyaretçi ve Kargo (kapı kaydı; F11.03). Varsayılan KAPALI.
  static const String visitorLog = 'visitor_log';

  /// Firma ve Sözleşme Takibi. Varsayılan KAPALI.
  static const String contracts = 'contracts';

  /// Ekipman ve Bakım (envanter, bakım planı / kaydı, teklifler). TEMEL modül (Kural 25): her sitede açık.
  static const String equipment = 'equipment';

  /// Karar Defteri (yönetim / genel / denetim kurulu kararları). Varsayılan KAPALI.
  static const String decisionBook = 'decision_book';

  /// Rehber (yönetim kadrosu ve faydalı telefonlar; sakin ekranı). Varsayılan KAPALI.
  static const String directory = 'directory';

  /// İşletme Projesi (bütçe). Varsayılan KAPALI.
  static const String budget = 'budget';

  /// Dosya Deposu: Belgeler (yönetmelik, tutanak, sözleşme; Faz 3b-A) + sitenin Google Drive bağlantısı (D1) TEK modül. TEMEL modül (Kural 25):
  /// her sitede açık (Google Drive bağlantısı ayrıca kurulur). Eski `documents` (Belgeler) kodu 084'te buna katıldı; ayrı Belgeler modülü yoktur.
  static const String driveStorage = 'drive_storage';

  /// Komşu Panosu (sakin ilanları, yönetici onayı). TEMEL modül (Kural 25): her sitede açık.
  static const String neighborBoard = 'neighbor_board';

  /// Faaliyet Raporu (yıllık rapor taslağı, PDF). TEMEL modül (Kural 25): her sitede açık.
  static const String annualReport = 'annual_report';

  /// Kamera ve Plaka (plaka olayı kaydı; kapı açmaz). Varsayılan KAPALI.
  static const String plateCameras = 'plate_cameras';

  /// Plaka Tanıma (misafir plaka izni, kara liste, olay kararları; kapı açma "Yakında…"). Varsayılan KAPALI.
  static const String plateRecognition = 'plate_recognition';
  static const String emergency = 'emergency';
}

int compareTurkishStrings(String a, String b) {
  const turkishOrder = <int, int>{
    // a / A
    0x61: 1, 0x41: 1,
    // b / B
    0x62: 2, 0x42: 2,
    // c / C
    0x63: 3, 0x43: 3,
    // ç / Ç
    0xe7: 4, 0xc7: 4,
    // d / D
    0x64: 5, 0x44: 5,
    // e / E
    0x65: 6, 0x45: 6,
    // f / F
    0x66: 7, 0x46: 7,
    // g / G
    0x67: 8, 0x47: 8,
    // ğ / Ğ
    0x11f: 9, 0x11e: 9,
    // h / H
    0x68: 10, 0x48: 10,
    // ı / I
    0x131: 11, 0x49: 11,
    // i / İ
    0x69: 12, 0x130: 12,
    // j / J
    0x6a: 13, 0x4a: 13,
    // k / K
    0x6b: 14, 0x4b: 14,
    // l / L
    0x6c: 15, 0x4c: 15,
    // m / M
    0x6d: 16, 0x4d: 16,
    // n / N
    0x6e: 17, 0x4e: 17,
    // o / O
    0x6f: 18, 0x4f: 18,
    // ö / Ö
    0xf6: 19, 0xd6: 19,
    // p / P
    0x70: 20, 0x50: 20,
    // r / R
    0x71: 21, 0x51: 21,
    // s / S
    0x72: 22, 0x52: 22,
    // ş / Ş
    0x15f: 23, 0x15e: 23,
    // t / T
    0x74: 24, 0x54: 24,
    // u / U
    0x75: 25, 0x55: 25,
    // ü / Ü
    0xfc: 26, 0xdc: 26,
    // v / V
    0x76: 27, 0x56: 27,
    // y / Y
    0x79: 28, 0x59: 28,
    // z / Z
    0x7a: 29, 0x5a: 29,
  };

  final aRunes = a.runes.toList();
  final bRunes = b.runes.toList();
  final minLen = aRunes.length < bRunes.length ? aRunes.length : bRunes.length;

  for (var i = 0; i < minLen; i++) {
    final codeA = aRunes[i];
    final codeB = bRunes[i];
    if (codeA == codeB) continue;

    final rankA = turkishOrder[codeA];
    final rankB = turkishOrder[codeB];

    if (rankA != null && rankB != null) {
      if (rankA != rankB) return rankA.compareTo(rankB);
      final diff = codeA.compareTo(codeB);
      if (diff != 0) return diff;
    } else if (rankA != null) {
      return -1;
    } else if (rankB != null) {
      return 1;
    } else {
      final diff = codeA.compareTo(codeB);
      if (diff != 0) return diff;
    }
  }
  return aRunes.length.compareTo(bRunes.length);
}

int compareModulesByName(PlatformModule a, PlatformModule b) =>
    compareTurkishStrings(a.name, b.name);

DateTime? _parseDate(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

int _asInt(Object? raw, [int fallback = 0]) {
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

/// Bir platform modülü: katalog satırı (`/app/modules/catalog`) ya da bir sitenin modül durumu
/// (`/manager/sites/:siteCode/modules`). Katalogda yalnız `code/name/description/core/status` gelir;
/// kalan alanlar için sunucudaki hesapla aynı varsayılanlar kullanılır.
@immutable
class PlatformModule {
  const PlatformModule({
    required this.code,
    required this.name,
    this.description = '',
    this.core = false,
    this.status = 'available',
    this.enabled = false,
    this.toggleable = false,
    bool? canToggle,
    this.requestStatus,
    this.updatedAt,
    this.updatedBy,
    this.recommended = false,
    this.isPlatformActive = true,
  }) : canToggle = canToggle ?? toggleable;

  final String code;
  final String name;
  final String description;

  /// Çekirdek modül: her sitede hep açık, kapatılamaz.
  final bool core;

  /// `available` ya da `coming_soon`.
  final String status;

  /// Bu sitede hesaplanmış açık/kapalı durumu.
  final bool enabled;

  /// Katalog özelliği: açılıp kapatılabilir bir modül mü (`!core && status == available`).
  final bool toggleable;

  /// ÇAĞIRAN bu modülü şimdi anahtarla açıp kapatabilir mi? Faz 1.1: yalnız süper kullanıcı VE modül
  /// [toggleable] ise true (site yöneticisi modül TALEP eder). Eski sunucuda alan yoksa [toggleable].
  final bool canToggle;

  /// O siteye ait bekleyen modül talebi varsa `"pending"`, yoksa null (eski sunucuda alan yok = null).
  final String? requestStatus;

  /// Bu modül için bekleyen bir talep var mı?
  bool get hasPendingRequest => requestStatus == 'pending';

  final DateTime? updatedAt;
  final String? updatedBy;

  /// Sitenin yönetim türü için ÖNERİLEN modül mü (`recommended`, F9)? Eski sunucuda alan yok = false.
  final bool recommended;

  /// Platform genelinde modül aktif mi (yalnızca süper kullanıcı için yönetilir)?
  final bool isPlatformActive;

  bool get isAvailable => status == 'available';
  bool get isComingSoon => status == 'coming_soon';

  /// Modül satırı olmayan sitede katalog varsayılanı (sunucudaki `computeModuleEnabled` ile aynı
  /// sıra): `available` olmayan modül KAPALI (çekirdek `people`/`announcements` de, ekranları
  /// gelene dek); çekirdek modül açık; ek modüller sunucu durumu gelene kadar kapalıdır.
  static bool defaultEnabled(
    String code, {
    bool core = false,
    String status = 'available',
  }) {
    if (status != 'available') return false;
    if (core) return true;
    return false;
  }

  factory PlatformModule.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    final core = json['core'] == true;
    final status = json['status']?.toString() ?? 'available';
    final toggleable = json['toggleable'] is bool
        ? json['toggleable'] as bool
        : (status == 'available');
    return PlatformModule(
      code: code,
      name: json['name']?.toString() ?? code,
      description: json['description']?.toString() ?? '',
      core: core,
      status: status,
      enabled: json['enabled'] is bool
          ? json['enabled'] as bool
          : defaultEnabled(code, core: core, status: status),
      toggleable: toggleable,
      canToggle: json['can_toggle'] is bool
          ? json['can_toggle'] as bool
          : toggleable,
      requestStatus:
          json['request_status'] is String &&
              (json['request_status'] as String).trim().isNotEmpty
          ? (json['request_status'] as String).trim()
          : null,
      updatedAt: _parseDate(json['updated_at']),
      updatedBy: json['updated_by']?.toString(),
      recommended: json['recommended'] == true,
      isPlatformActive: json['is_platform_active'] != false,
    );
  }

  PlatformModule copyWith({
    bool? enabled,
    String? requestStatus,
    bool clearRequestStatus = false,
    bool? isPlatformActive,
  }) {
    return PlatformModule(
      code: code,
      name: name,
      description: description,
      core: core,
      status: status,
      enabled: enabled ?? this.enabled,
      toggleable: toggleable,
      canToggle: canToggle,
      requestStatus: clearRequestStatus
          ? null
          : (requestStatus ?? this.requestStatus),
      updatedAt: updatedAt,
      updatedBy: updatedBy,
      recommended: recommended,
      isPlatformActive: isPlatformActive ?? this.isPlatformActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlatformModule &&
      other.code == code &&
      other.name == name &&
      other.description == description &&
      other.core == core &&
      other.status == status &&
      other.enabled == enabled &&
      other.toggleable == toggleable &&
      other.canToggle == canToggle &&
      other.requestStatus == requestStatus &&
      other.updatedAt == updatedAt &&
      other.updatedBy == updatedBy;

  @override
  int get hashCode => Object.hash(
    code,
    name,
    description,
    core,
    status,
    enabled,
    toggleable,
    canToggle,
    requestStatus,
    updatedAt,
    updatedBy,
  );
}

/// Bir sitenin modül durumu (`GET/PUT /manager/sites/:siteCode/modules...` gövdesi).
@immutable
class SiteModulesState {
  const SiteModulesState({
    required this.siteCode,
    required this.siteName,
    this.managementType = ManagementType.apartmentSite,
    this.managementTypeLabel = 'Apartman ve Site',
    this.modules = const <PlatformModule>[],
    this.managementTerms = ManagementTerms.defaults,
  });

  final int siteCode;
  final String siteName;
  final ManagementType managementType;
  final String managementTypeLabel;
  final List<PlatformModule> modules;

  /// Türün arayüz terimleri (`management_terms`, F9); eski sunucuda varsayılan.
  final ManagementTerms managementTerms;

  PlatformModule? module(String code) {
    for (final m in modules) {
      if (m.code == code) return m;
    }
    return null;
  }

  factory SiteModulesState.fromJson(Map<String, dynamic> json) {
    final type = ManagementType.fromApi(json['management_type']);
    final label = json['management_type_label'];
    final rawModules = json['modules'];
    return SiteModulesState(
      siteCode: _asInt(json['site_code'] ?? json['id']),
      siteName: json['site_name']?.toString() ?? '',
      managementType: type,
      managementTypeLabel: label is String && label.trim().isNotEmpty
          ? label.trim()
          : type.label,
      modules: rawModules is List
          ? (rawModules
                .whereType<Map>()
                .map(
                  (m) => PlatformModule.fromJson(Map<String, dynamic>.from(m)),
                )
                .toList()
              ..sort(compareModulesByName))
          : const <PlatformModule>[],
      managementTerms: ManagementTerms.fromJson(json['management_terms']),
    );
  }
}

/// `GET /app/my-modules` içindeki bir site: kullanıcının o sitedeki rolü ve modül durumları.
@immutable
class MySiteModules {
  const MySiteModules({
    required this.siteCode,
    required this.siteName,
    this.managementType = ManagementType.apartmentSite,
    this.role = 'resident',
    this.modules = const <String, bool>{},
    this.doorAccess = true,
    this.managementTerms = ManagementTerms.defaults,
    this.recommendedModules = const <String>[],
    this.menuLayout,
  });

  final int siteCode;
  final String siteName;
  final ManagementType managementType;

  /// Ana menüde (çekmece + Panel vitrini) öne çıkan modüller (`menu_layout`, K8). YETENEKTEN ayrı katmandır: [modules] hangi
  /// modülün AÇIK olduğunu söyler, bu alan yalnız menüde nelerin öne çıktığını (kalanlar "Tüm işlemler"de). Eski sunucuda alan
  /// yoktur (null): menü kısaltılmaz, her açık modül öne çıkar.
  final SiteMenuLayout? menuLayout;

  /// `manager`, `resident`, `board_member` ya da `staff`.
  final String role;

  /// Kullanıcının bu sitede GERÇEK bir kapı erişim yolu var mı (yönetici, daire/sakin, kapı izni)?
  /// Yalnız BOARD_MEMBER/STAFF bağı olanlarda false. Eski sunucuda alan yoksa true (fail-open).
  /// "Geçiş Kontrol kapalı" kararı yalnız bu alanı true olan siteler üzerinden verilir.
  final bool doorAccess;

  /// Katalogdaki tüm kodlar için hesaplanmış açık/kapalı.
  final Map<String, bool> modules;

  /// Türün arayüz terimleri (`management_terms`, F9); eski sunucuda varsayılan.
  final ManagementTerms managementTerms;

  /// Bu tür için önerilen modül kodları (`recommended_modules`, F9); eski sunucuda boş. Bilinmeyen kod
  /// listede kalır, katalogda eşleşmediği için gösterilmez.
  final List<String> recommendedModules;

  /// Kullanıcı bu sitede Yönetim Kurulu / Denetçi (salt okunur) mu?
  bool get isBoardMember => role == 'board_member';

  /// Kod listede yoksa (eski sunucu / yeni modül) katalog varsayılanı.
  bool isEnabled(String code) =>
      modules[code] ?? PlatformModule.defaultEnabled(code);

  factory MySiteModules.fromJson(Map<String, dynamic> json) {
    final rawModules = json['modules'];
    final modules = <String, bool>{};
    if (rawModules is Map) {
      rawModules.forEach((key, value) {
        if (value is bool) modules[key.toString()] = value;
      });
    }
    return MySiteModules(
      siteCode: _asInt(json['site_code'] ?? json['id']),
      siteName: json['site_name']?.toString() ?? '',
      managementType: ManagementType.fromApi(json['management_type']),
      role: json['role']?.toString() ?? 'resident',
      modules: Map<String, bool>.unmodifiable(modules),
      doorAccess: json['door_access'] is bool
          ? json['door_access'] as bool
          : true,
      managementTerms: ManagementTerms.fromJson(json['management_terms']),
      recommendedModules: json['recommended_modules'] is List
          ? List<String>.unmodifiable(
              (json['recommended_modules'] as List).whereType<String>(),
            )
          : const <String>[],
      menuLayout: SiteMenuLayout.tryParse(json['menu_layout']),
    );
  }

  // menuLayout eşitliğe dahildir: yönetici kompakt menüyü değiştirince [ModuleAccess] bunu "değişti" görür ve menü hemen yenilenir.
  @override
  bool operator ==(Object other) =>
      other is MySiteModules &&
      other.siteCode == siteCode &&
      other.siteName == siteName &&
      other.managementType == managementType &&
      other.role == role &&
      other.doorAccess == doorAccess &&
      other.menuLayout == menuLayout &&
      mapEquals(other.modules, modules);

  @override
  int get hashCode => Object.hash(
    siteCode,
    siteName,
    managementType,
    role,
    doorAccess,
    menuLayout,
    Object.hashAllUnordered(
      modules.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// `GET /app/my-modules` yanıtı. Süper kullanıcıda `scope == 'all'` ve site listesi boştur
/// (menüler modüllerden etkilenmez).
@immutable
class MyModulesResult {
  const MyModulesResult({
    this.scope = 'sites',
    this.sites = const <MySiteModules>[],
  });

  final String scope;
  final List<MySiteModules> sites;

  bool get isAll => scope == 'all';

  /// Kullanıcının GERÇEK kapı erişimi olan siteler ([MySiteModules.doorAccess]). "Geçiş Kontrol
  /// kapalı" kararı yalnız bunlar üzerinden verilir (yalnız kurul/görevli bağı olan site sayılmaz).
  List<MySiteModules> get doorAccessSites =>
      sites.where((s) => s.doorAccess).toList(growable: false);

  /// Kullanıcı en az bir sitede kapı erişimine sahip VE o sitelerin HEPSİNDE [code] kapalı mı?
  ///
  /// Süper kullanıcıda (`scope: all`) ve kapı erişimi olan hiç sitesi olmayanda (yalnız kurul/görevli
  /// bağı ya da hiç site) false: ona gösterilecek kapı yoktur, menü ve ekranlar değişmez.
  /// [PlatformModuleCodes.doorControl] dışındaki modüllerde tüm siteler dikkate alınır.
  bool isDisabledEverywhere(String code) {
    if (isAll) return false;
    final relevant = code == PlatformModuleCodes.doorControl
        ? doorAccessSites
        : sites;
    return relevant.isNotEmpty && !relevant.any((s) => s.isEnabled(code));
  }

  factory MyModulesResult.fromJson(Map<String, dynamic> json) {
    final rawSites = json['sites'];
    return MyModulesResult(
      scope: json['scope']?.toString() ?? 'sites',
      sites: rawSites is List
          ? rawSites
                .whereType<Map>()
                .map(
                  (s) => MySiteModules.fromJson(Map<String, dynamic>.from(s)),
                )
                .toList(growable: false)
          : const <MySiteModules>[],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MyModulesResult &&
      other.scope == scope &&
      listEquals(other.sites, sites);

  @override
  int get hashCode => Object.hash(scope, Object.hashAll(sites));
}
