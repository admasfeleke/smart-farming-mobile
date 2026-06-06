import 'package:flutter/material.dart';
import '../../widgets/app_header.dart';
import '../disease/disease_check_screen.dart';
import '../scan/scan_screen.dart';
import 'crop_health_refresh_notifier.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../api_client.dart';
import '../../offline/local_cache_store.dart';
import '../../sync_refresh_notifier.dart';
import '../../widgets/error_banner.dart';
import '../../localized_value.dart';
import '../../localized_phrase.dart';

class CropHealthScreen extends StatelessWidget {
  const CropHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ScanScreen(initialMode: ScanMode.cropHealth),
                ),
              );
            },
            icon: const Icon(Icons.add_a_photo),
            label: Text(L.t(lang, 'new_scan')),
          ),
          body: Column(
            children: [
              const AppHeader(titleKey: 'crop_health'),
              Expanded(child: _CropHealthBody(theme: theme, languageCode: lang)),
            ],
          ),
        );
      },
    );
  }
}

class _CropHealthBody extends StatefulWidget {
  final ThemeData theme;
  final String languageCode;

  const _CropHealthBody({required this.theme, required this.languageCode});

  @override
  State<_CropHealthBody> createState() => _CropHealthBodyState();
}

class _CropHealthBodyState extends State<_CropHealthBody> {
  static const String _cropHealthCacheKey = 'crop_health_history_cache_v1';

  bool _loading = false;
  String? _error;
  final List<_CropHealthRecord> _records = [];

  @override
  void initState() {
    super.initState();
    cropHealthRefreshNotifier.addListener(_handleRefresh);
    syncRefreshNotifier.addListener(_handleSyncRefresh);
    _load();
  }

  @override
  void dispose() {
    cropHealthRefreshNotifier.removeListener(_handleRefresh);
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    super.dispose();
  }

  void _handleRefresh() {
    _load();
  }

  void _handleSyncRefresh() {
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    final cached = await _loadCached();
    setState(() {
      _loading = true;
      _error = null;
      if (!cached) {
        _records.clear();
      }
    });
    try {
      final fetched = <_CropHealthRecord>[];
      var page = 1;
      const perPage = 50;
      while (true) {
        final result = await ApiClient.getCropHealthRecordsPage(page: page, perPage: perPage);
        fetched.addAll(result.items.map(_mapCropHealth));
        if (!result.pagination.hasMore) break;
        final nextPage = result.pagination.currentPage + 1;
        if (nextPage <= page) break;
        page = nextPage;
      }
      await LocalCacheStore.instance.write(
        _cropHealthCacheKey,
        fetched.map(_cropHealthRecordToJson).toList(growable: false),
      );
      if (mounted) {
        setState(() {
          _records
            ..clear()
            ..addAll(fetched);
          _loading = false;
        });
      }
    } on ApiUnauthorized {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _records.isNotEmpty
              ? L.t(widget.languageCode, 'crop_health_showing_saved_history')
              : L.t(widget.languageCode, 'crop_health_load_failed');
        });
      }
    }
  }

  Future<bool> _loadCached() async {
    final cached = await LocalCacheStore.instance.readList(_cropHealthCacheKey);
    final items = (cached ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => _cropHealthRecordFromJson(item.cast<String, dynamic>()))
        .toList();
    if (items.isEmpty || !mounted) return items.isNotEmpty;
    setState(() {
      _records
        ..clear()
        ..addAll(items);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showErrorBanner(context, message: _error!, onRetry: _load);
      });
    }

    if (_loading && _records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_records.isEmpty) {
      return _EmptyState(
        languageCode: widget.languageCode,
        onStart: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const ScanScreen(initialMode: ScanMode.cropHealth),
            ),
          );
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (_loading) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L.t(widget.languageCode, 'disease_prevention_loading'),
                    style: widget.theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ],
        _SummaryCard(
          theme: widget.theme,
          languageCode: widget.languageCode,
          records: _records,
        ),
        const SizedBox(height: 16),
        _MonitoringCard(
          theme: widget.theme,
          languageCode: widget.languageCode,
          records: _records,
        ),
        const SizedBox(height: 16),
        Text(
          L.t(widget.languageCode, 'crop_health_timeline_title'),
          style: widget.theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          L.t(widget.languageCode, 'crop_health_timeline_subtitle'),
          style: widget.theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        for (var r in _records) _HistoryItem(record: r, languageCode: widget.languageCode),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ThemeData theme;
  final String languageCode;
  final List<_CropHealthRecord> records;

  const _SummaryCard({
    required this.theme,
    required this.languageCode,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final worstSeverity = _worstCropHealthSeverity(records);
    final summary = worstSeverity == 'low'
        ? L.t(languageCode, 'good_status')
        : LocalizedValue.severity(languageCode, worstSeverity);
    final total = records.length;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.eco, color: Colors.green, size: 32),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t(languageCode, 'crop_health_overview_title'), style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Spacer(),
            Text(
              L.t(languageCode, 'crop_health_records_count', params: {'count': '$total'}),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonitoringCard extends StatelessWidget {
  final ThemeData theme;
  final String languageCode;
  final List<_CropHealthRecord> records;

  const _MonitoringCard({
    required this.theme,
    required this.languageCode,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    final latest = records.isEmpty ? null : records.reduce((a, b) {
      final aDate = DateTime.tryParse(a.date) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b.date) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aDate.isAfter(bDate) ? a : b;
    });
    final highCount = records.where((r) => _cropHealthSeverityRank(r.status) >= 2).length;
    final mediumCount = records.where((r) => _normalizedCropHealthSeverity(r.status) == 'medium').length;
    final lowCount = records.where((r) => _normalizedCropHealthSeverity(r.status) == 'low').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L.t(languageCode, 'crop_health_monitoring_title'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              L.t(languageCode, 'crop_health_monitoring_subtitle'),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HealthChip(
                  label: L.t(languageCode, 'crop_health_low_count', params: {'count': '$lowCount'}),
                  backgroundColor: Colors.green.shade100,
                  textColor: Colors.green.shade800,
                ),
                _HealthChip(
                  label: L.t(languageCode, 'crop_health_medium_count', params: {'count': '$mediumCount'}),
                  backgroundColor: Colors.orange.shade100,
                  textColor: Colors.orange.shade800,
                ),
                _HealthChip(
                  label: L.t(languageCode, 'crop_health_high_count', params: {'count': '$highCount'}),
                  backgroundColor: Colors.red.shade100,
                  textColor: Colors.red.shade800,
                ),
              ],
            ),
            if (latest != null) ...[
              const SizedBox(height: 12),
              Text(
                L.t(
                  languageCode,
                  'crop_health_latest_observation',
                  params: {
                    'crop': latest.crop,
                    'field': latest.field,
                    'date': _friendlyDate(latest.date),
                  },
                ),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ScanScreen(initialMode: ScanMode.cropHealth),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_a_photo),
                  label: Text(L.t(languageCode, 'new_scan')),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiseaseCheckScreen(showHeader: false),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history),
                  label: Text(L.t(languageCode, 'crop_health_open_disease_history')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final _CropHealthRecord record;
  final String languageCode;

  const _HistoryItem({required this.record, required this.languageCode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _cropHealthSeverityColor(record.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showCropHealthDetails(context, record),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 44,
                      color: Colors.green.shade100,
                      child: const Icon(Icons.image, color: Colors.green),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      LocalizedValue.severity(languageCode, record.status),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HealthChip(label: LocalizedValue.crop(languageCode, record.crop)),
                  _HealthChip(label: record.field),
                  _HealthChip(
                    label:
                        '${LocalizedValue.severityLabel(languageCode)}: ${LocalizedValue.severity(languageCode, record.status)}',
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                    textColor: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _friendlyDate(record.date),
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthChip extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;

  const _HealthChip({
    required this.label,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor ?? Colors.black87,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onStart;
  final String languageCode;

  const _EmptyState({required this.onStart, required this.languageCode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.eco, size: 72, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              L.t(languageCode, 'no_crop_health'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              L.t(languageCode, 'start_first_scan_crop'),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.add_a_photo),
              label: Text(L.t(languageCode, 'start_scan')),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropHealthRecord {
  final String crop;
  final String field;
  final String status;
  final String date;

  _CropHealthRecord({
    required this.crop,
    required this.field,
    required this.status,
    required this.date,
  });
}

_CropHealthRecord _mapCropHealth(Map<String, dynamic> json) {
  final cropName = json['crop_name']?.toString();
  final cropId = json['crop_id']?.toString();
  final plotName = json['plot_name']?.toString();
  final plotId = json['plot_id']?.toString();
  final status = _normalizedCropHealthSeverity(json['status']?.toString() ?? '');
  final date = json['scanned_at']?.toString() ?? '';

  final cropLabel = cropName?.isNotEmpty == true
      ? LocalizedValue.crop(LanguageStore.notifier.value, cropName!)
      : (cropId != null
            ? '${LocalizedValue.fixed(LanguageStore.notifier.value, 'crop_short')} $cropId'
            : '');
  final plotLabel = plotName?.isNotEmpty == true
      ? plotName!
      : (plotId != null
            ? '${LocalizedValue.fixed(LanguageStore.notifier.value, 'plot_short')} $plotId'
            : '');

  return _CropHealthRecord(
    crop: cropLabel,
    field: plotLabel,
    status: status,
    date: date,
  );
}

Map<String, dynamic> _cropHealthRecordToJson(_CropHealthRecord record) {
  return <String, dynamic>{
    'crop': record.crop,
    'field': record.field,
    'status': record.status,
    'date': record.date,
  };
}

_CropHealthRecord _cropHealthRecordFromJson(Map<String, dynamic> json) {
  return _CropHealthRecord(
    crop: json['crop']?.toString() ?? '',
    field: json['field']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    date: json['date']?.toString() ?? '',
  );
}

String _friendlyDate(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final d = parsed.toLocal();
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd $hh:$min';
}

void _showCropHealthDetails(BuildContext context, _CropHealthRecord record) {
  final severity = _normalizedCropHealthSeverity(record.status);
  final statusColor = _cropHealthSeverityColor(severity);
  final nextAction = severity == 'low'
      ? Phrase.t(LanguageStore.notifier.value, 'crop_health_next_good')
      : severity == 'medium'
          ? Phrase.t(LanguageStore.notifier.value, 'crop_health_next_warning')
          : Phrase.t(LanguageStore.notifier.value, 'crop_health_next_bad');

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + media.viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                LocalizedValue.severity(LanguageStore.notifier.value, record.status),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _HealthChip(
                label:
                    '${LocalizedValue.severityLabel(LanguageStore.notifier.value)}: '
                    '${LocalizedValue.severity(LanguageStore.notifier.value, record.status)}',
                backgroundColor: statusColor.withValues(alpha: 0.12),
                textColor: statusColor,
              ),
              const SizedBox(height: 10),
              Text(nextAction, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(L.t(LanguageStore.notifier.value, 'technical_details')),
                children: [
                  Align(alignment: Alignment.centerLeft, child: Text(record.crop)),
                  Align(alignment: Alignment.centerLeft, child: Text(record.field)),
                  Align(alignment: Alignment.centerLeft, child: Text(_friendlyDate(record.date))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ScanScreen(initialMode: ScanMode.cropHealth),
                          ),
                        );
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: Text(L.t(LanguageStore.notifier.value, 'rescan')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: Text(L.t(LanguageStore.notifier.value, 'close')),
                    ),
                  ),
                ],
              ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _normalizedCropHealthSeverity(String raw) {
  final value = raw.trim().toLowerCase();
  switch (value) {
    case 'critical':
      return 'critical';
    case 'high':
    case 'bad':
      return 'high';
    case 'medium':
    case 'warning':
      return 'medium';
    case 'low':
    case 'good':
    case 'healthy':
      return 'low';
    default:
      return 'medium';
  }
}

int _cropHealthSeverityRank(String severity) {
  switch (_normalizedCropHealthSeverity(severity)) {
    case 'low':
      return 0;
    case 'medium':
      return 1;
    case 'high':
      return 2;
    case 'critical':
      return 3;
    default:
      return 1;
  }
}

String _worstCropHealthSeverity(List<_CropHealthRecord> records) {
  var worst = 'low';
  for (final record in records) {
    final severity = _normalizedCropHealthSeverity(record.status);
    if (_cropHealthSeverityRank(severity) > _cropHealthSeverityRank(worst)) {
      worst = severity;
    }
  }
  return worst;
}

Color _cropHealthSeverityColor(String severity) {
  switch (_normalizedCropHealthSeverity(severity)) {
    case 'low':
      return Colors.green.shade700;
    case 'medium':
      return Colors.orange.shade700;
    case 'high':
      return Colors.red.shade700;
    case 'critical':
      return Colors.red.shade800;
    default:
      return Colors.orange.shade700;
  }
}



