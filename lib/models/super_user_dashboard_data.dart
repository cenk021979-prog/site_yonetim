import 'package:flutter/foundation.dart';

@immutable
class SuperUserAttentionData {
  const SuperUserAttentionData({
    this.pendingSiteApplications = 0,
    this.pendingModuleRequests = 0,
    this.unresolvedClientErrors = 0,
    this.uniqueClientErrors = 0,
    this.totalFeedbacks = 0,
  });

  final int pendingSiteApplications;
  final int pendingModuleRequests;
  final int unresolvedClientErrors;
  final int uniqueClientErrors;
  final int totalFeedbacks;

  bool get hasPendingActions =>
      pendingSiteApplications > 0 ||
      pendingModuleRequests > 0 ||
      unresolvedClientErrors > 0;

  factory SuperUserAttentionData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SuperUserAttentionData();
    return SuperUserAttentionData(
      pendingSiteApplications: (json['pending_site_applications'] as num?)?.toInt() ?? 0,
      pendingModuleRequests: (json['pending_module_requests'] as num?)?.toInt() ?? 0,
      unresolvedClientErrors: (json['unresolved_client_errors'] as num?)?.toInt() ?? 0,
      uniqueClientErrors: (json['unique_client_errors'] as num?)?.toInt() ?? 0,
      totalFeedbacks: (json['total_feedbacks'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class SuperUserPlatformData {
  const SuperUserPlatformData({
    this.totalSites = 0,
    this.activeSites = 0,
    this.passiveSites = 0,
    this.totalApartments = 0,
    this.occupiedApartments = 0,
    this.emptyApartments = 0,
    this.totalUsers = 0,
    this.siteManagers = 0,
    this.apartmentUsers = 0,
    this.superUsers = 0,
    this.individuals = 0,
  });

  final int totalSites;
  final int activeSites;
  final int passiveSites;
  final int totalApartments;
  final int occupiedApartments;
  final int emptyApartments;
  final int totalUsers;
  final int siteManagers;
  final int apartmentUsers;
  final int superUsers;
  final int individuals;

  int get occupancyPercentage =>
      totalApartments > 0 ? ((occupiedApartments / totalApartments) * 100).round() : 0;

  factory SuperUserPlatformData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SuperUserPlatformData();
    return SuperUserPlatformData(
      totalSites: (json['total_sites'] as num?)?.toInt() ?? 0,
      activeSites: (json['active_sites'] as num?)?.toInt() ?? 0,
      passiveSites: (json['passive_sites'] as num?)?.toInt() ?? 0,
      totalApartments: (json['total_apartments'] as num?)?.toInt() ?? 0,
      occupiedApartments: (json['occupied_apartments'] as num?)?.toInt() ?? 0,
      emptyApartments: (json['empty_apartments'] as num?)?.toInt() ?? 0,
      totalUsers: (json['total_users'] as num?)?.toInt() ?? 0,
      siteManagers: (json['site_managers'] as num?)?.toInt() ?? 0,
      apartmentUsers: (json['apartment_users'] as num?)?.toInt() ?? 0,
      superUsers: (json['super_users'] as num?)?.toInt() ?? 0,
      individuals: (json['individuals'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class SuperUserIotData {
  const SuperUserIotData({
    this.totalDoors = 0,
    this.activeDoors = 0,
    this.totalDevices = 0,
    this.onlineDevices = 0,
    this.offlineDevices = 0,
    this.esp32C3Count = 0,
    this.esp32WroomCount = 0,
    this.todayDoorPasses = 0,
  });

  final int totalDoors;
  final int activeDoors;
  final int totalDevices;
  final int onlineDevices;
  final int offlineDevices;
  final int esp32C3Count;
  final int esp32WroomCount;
  final int todayDoorPasses;

  factory SuperUserIotData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SuperUserIotData();
    return SuperUserIotData(
      totalDoors: (json['total_doors'] as num?)?.toInt() ?? 0,
      activeDoors: (json['active_doors'] as num?)?.toInt() ?? 0,
      totalDevices: (json['total_devices'] as num?)?.toInt() ?? 0,
      onlineDevices: (json['online_devices'] as num?)?.toInt() ?? 0,
      offlineDevices: (json['offline_devices'] as num?)?.toInt() ?? 0,
      esp32C3Count: (json['esp32_c3_count'] as num?)?.toInt() ?? 0,
      esp32WroomCount: (json['esp32_wroom_count'] as num?)?.toInt() ?? 0,
      todayDoorPasses: (json['today_door_passes'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class SuperUserMqttData {
  const SuperUserMqttData({
    this.configured = false,
    this.connected = false,
    this.hasError = false,
    this.lastError,
  });

  final bool configured;
  final bool connected;
  final bool hasError;
  final String? lastError;

  factory SuperUserMqttData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SuperUserMqttData();
    return SuperUserMqttData(
      configured: json['configured'] == true,
      connected: json['connected'] == true,
      hasError: json['has_error'] == true,
      lastError: json['last_error'] as String?,
    );
  }
}

@immutable
class SuperUserSystemData {
  const SuperUserSystemData({
    this.database = 'connected',
    this.mqtt = const SuperUserMqttData(),
    this.uptimeSeconds = 0,
    this.serverTime,
    this.version = '1.0.0',
    this.nodeVersion = '',
  });

  final String database;
  final SuperUserMqttData mqtt;
  final int uptimeSeconds;
  final String? serverTime;
  final String version;
  final String nodeVersion;

  String get uptimeFormatted {
    if (uptimeSeconds <= 0) return 'Yeni başlatıldı';
    final days = uptimeSeconds ~/ 86400;
    final hours = (uptimeSeconds % 86400) ~/ 3600;
    final minutes = (uptimeSeconds % 3600) ~/ 60;
    if (days > 0) return '$days gün $hours sa';
    if (hours > 0) return '$hours sa $minutes dk';
    return '$minutes dk';
  }

  factory SuperUserSystemData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SuperUserSystemData();
    return SuperUserSystemData(
      database: json['database'] as String? ?? 'connected',
      mqtt: SuperUserMqttData.fromJson(json['mqtt'] as Map<String, dynamic>?),
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
      serverTime: json['server_time'] as String?,
      version: json['version'] as String? ?? '1.0.0',
      nodeVersion: json['node_version'] as String? ?? '',
    );
  }
}

@immutable
class SuperUserDashboardData {
  const SuperUserDashboardData({
    this.attention = const SuperUserAttentionData(),
    this.platform = const SuperUserPlatformData(),
    this.iot = const SuperUserIotData(),
    this.system = const SuperUserSystemData(),
  });

  final SuperUserAttentionData attention;
  final SuperUserPlatformData platform;
  final SuperUserIotData iot;
  final SuperUserSystemData system;

  factory SuperUserDashboardData.fromJson(Map<String, dynamic> json) {
    return SuperUserDashboardData(
      attention: SuperUserAttentionData.fromJson(json['attention'] as Map<String, dynamic>?),
      platform: SuperUserPlatformData.fromJson(json['platform'] as Map<String, dynamic>?),
      iot: SuperUserIotData.fromJson(json['iot'] as Map<String, dynamic>?),
      system: SuperUserSystemData.fromJson(json['system'] as Map<String, dynamic>?),
    );
  }
}
