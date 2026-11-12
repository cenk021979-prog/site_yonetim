/// Server aggregates recognition records, never proof of physical passage.
class PlatePeriodStatistics {
  const PlatePeriodStatistics({
    required this.entries,
    required this.exits,
    required this.unknown,
    required this.startsAt,
    required this.endsAt,
  });
  factory PlatePeriodStatistics.fromJson(Map<String, dynamic> json) =>
      PlatePeriodStatistics(
        entries: (json['entries'] as num?)?.toInt() ?? 0,
        exits: (json['exits'] as num?)?.toInt() ?? 0,
        unknown: (json['unknown'] as num?)?.toInt() ?? 0,
        startsAt: DateTime.parse(json['starts_at'] as String).toUtc(),
        endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
      );
  final int entries, exits, unknown;
  final DateTime startsAt, endsAt;
  bool contains(DateTime instant) =>
      !instant.toUtc().isBefore(startsAt) && instant.toUtc().isBefore(endsAt);
}

class PlateStatistics {
  PlateStatistics({
    required this.periods,
    required this.serverTime,
    this.gateId,
    Duration Function()? elapsed,
  }) : _elapsed = elapsed,
       _clock = Stopwatch()..start();
  factory PlateStatistics.fromJson(Map<String, dynamic> json) =>
      PlateStatistics(
        gateId: (json['gate_id'] as num?)?.toInt(),
        serverTime: DateTime.parse(json['server_time'] as String).toUtc(),
        periods: {
          for (final entry in (json['periods'] as Map<String, dynamic>).entries)
            entry.key: PlatePeriodStatistics.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
        },
      );
  final int? gateId;
  final Map<String, PlatePeriodStatistics> periods;
  final DateTime serverTime;
  final Stopwatch _clock;
  final Duration Function()? _elapsed;

  /// Wall-clock changes on the client never shift the server's calendar day.
  DateTime get currentServerTime =>
      serverTime.add(_elapsed?.call() ?? _clock.elapsed);
  Duration? get untilMidnight {
    final day = today;
    return day?.endsAt.difference(currentServerTime);
  }

  PlatePeriodStatistics? get today {
    final day = periods['day'];
    return day != null && day.contains(currentServerTime) ? day : null;
  }
}
