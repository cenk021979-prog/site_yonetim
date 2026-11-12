import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/plate_statistics.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';

Future<void> showPlateStatisticsDialog(
  BuildContext context, {
  required PlateRecognitionService service,
  required int siteCode,
  int? gateId,
  String? gateName,
}) => showDialog<void>(
  context: context,
  builder: (_) => _StatisticsDialog(
    service: service,
    siteCode: siteCode,
    gateId: gateId,
    gateName: gateName,
  ),
);

class _StatisticsDialog extends StatefulWidget {
  const _StatisticsDialog({
    required this.service,
    required this.siteCode,
    this.gateId,
    this.gateName,
  });
  final PlateRecognitionService service;
  final int siteCode;
  final int? gateId;
  final String? gateName;
  @override
  State<_StatisticsDialog> createState() => _StatisticsDialogState();
}

class _StatisticsDialogState extends State<_StatisticsDialog> {
  String _period = 'week';
  String? _anchor;
  late Future<PlateStatistics?> _future = _load();
  Future<PlateStatistics?> _load() async {
    try {
      return await widget.service.statistics(
        widget.siteCode,
        gateId: widget.gateId,
        anchor: _anchor,
      );
    } catch (_) {
      // Attach the error handler immediately, including refreshes before next frame.
      return null;
    }
  }

  void _move(PlatePeriodStatistics period, bool next) {
    // Anchor at the first day of the adjacent period; month-end never rolls over.
    final target =
        (next
                ? period.endsAt
                : period.startsAt.subtract(const Duration(days: 1)))
            .toUtc()
            .add(const Duration(hours: 3));
    setState(() {
      _anchor =
          '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      _future = _load();
    });
  }

  String _date(DateTime value) {
    final tr = value.toUtc().add(const Duration(hours: 3));
    return '${tr.day.toString().padLeft(2, '0')}.${tr.month.toString().padLeft(2, '0')}.${tr.year}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Expanded(
          child: Text('Raporlar', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => setState(() {
            _future = _load();
          }),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    content: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: FutureBuilder<PlateStatistics?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return const Text(
                'Rapor yüklenemedi. Yenileyerek tekrar deneyin.',
              );
            }
            final period = snapshot.data!.periods[_period];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.gateName ?? 'Tüm kapılar',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Önceki dönem',
                      onPressed: period == null
                          ? null
                          : () => _move(period, false),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _period,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'day',
                            child: Text(
                              'Gün',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'week',
                            child: Text(
                              'Hafta',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'month',
                            child: Text(
                              'Ay',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _period = value);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sonraki dönem',
                      onPressed:
                          period == null ||
                              !period.endsAt.isBefore(
                                snapshot.data!.currentServerTime,
                              )
                          ? null
                          : () => _move(period, true),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                if (period != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_date(period.startsAt)} – ${_date(period.endsAt.subtract(const Duration(microseconds: 1)))}',
                        ),
                        Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            Text('Giriş: ${period.entries}'),
                            Text('Çıkış: ${period.exits}'),
                            if (period.unknown > 0)
                              Text('Yönsüz: ${period.unknown}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                const Text(
                  'İstanbul saatine göre kaydedilen plaka olaylarıdır. İzin ve ret kayıtları dahildir; fiziksel geçiş sayısı değildir.',
                ),
              ],
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Kapat'),
      ),
    ],
  );
}
