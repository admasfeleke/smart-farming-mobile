import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../offline/local_cache_store.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../sync_refresh_notifier.dart';
import '../../widgets/farm_ui.dart';

class WeatherOverviewSnapshot {
  final String? locationText;
  final String? regionText;
  final String? latLonText;
  final String tempText;
  final String detailText;
  final String statusKey;
  final DateTime? lastUpdated;

  const WeatherOverviewSnapshot({
    required this.locationText,
    required this.regionText,
    required this.latLonText,
    required this.tempText,
    required this.detailText,
    required this.statusKey,
    required this.lastUpdated,
  });
}

class WeatherScreen extends StatefulWidget {
  final WeatherOverviewSnapshot? snapshot;

  const WeatherScreen({super.key, this.snapshot});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  static const String _weatherSummaryCacheKey = 'weather_summary_cache_v1';
  static const String _weatherRecordsCacheKey = 'weather_records_cache_v1';

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = <String, dynamic>{};
  Map<String, dynamic> _analysis = <String, dynamic>{};
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  DateTime? _cachedUpdatedAt;

  @override
  void initState() {
    super.initState();
    syncRefreshNotifier.addListener(_handleSyncRefresh);
    _load();
  }

  @override
  void dispose() {
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    super.dispose();
  }

  void _handleSyncRefresh() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await _loadCached();

    try {
      final summaryResponse = await ApiClient.getWeatherDataSummary();
      final records = <Map<String, dynamic>>[];
      var page = 1;
      const perPage = 50;

      while (page <= 2) {
        final result = await ApiClient.getWeatherDataPage(page: page, perPage: perPage);
        records.addAll(result.items);
        if (!result.pagination.hasMore || result.items.length < perPage) {
          break;
        }
        page += 1;
      }

      if (!mounted) return;
      await LocalCacheStore.instance.write(_weatherSummaryCacheKey, _summaryPayload(summaryResponse));
      await LocalCacheStore.instance.write(_weatherRecordsCacheKey, records);
      setState(() {
        _summary = summaryResponse['summary'] is Map<String, dynamic>
            ? summaryResponse['summary'] as Map<String, dynamic>
            : <String, dynamic>{};
        _analysis = summaryResponse['analysis'] is Map<String, dynamic>
            ? summaryResponse['analysis'] as Map<String, dynamic>
            : <String, dynamic>{};
        _records = records;
        _cachedUpdatedAt = DateTime.now();
        _loading = false;
      });
    } on ApiUnauthorized {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _summary.isNotEmpty || _records.isNotEmpty
            ? L.t(
                LanguageStore.notifier.value,
                'weather_showing_saved_data',
                params: {'error': e.toString()},
              )
            : e.toString();
      });
    }
  }

  Future<void> _loadCached() async {
    final summaryEntry = await LocalCacheStore.instance.read(_weatherSummaryCacheKey);
    final records = await LocalCacheStore.instance.readList(_weatherRecordsCacheKey);
    final payload = summaryEntry?.payload;
    final summary = payload is Map<String, dynamic>
        ? payload
        : (payload is Map ? payload.cast<String, dynamic>() : <String, dynamic>{});
    final summaryMap = summary['summary'] is Map<String, dynamic>
        ? summary['summary'] as Map<String, dynamic>
        : <String, dynamic>{};
    final analysisMap = summary['analysis'] is Map<String, dynamic>
        ? summary['analysis'] as Map<String, dynamic>
        : <String, dynamic>{};
    final recordItems = (records ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    if (!mounted) return;
    if (summaryMap.isNotEmpty || recordItems.isNotEmpty) {
      setState(() {
        _summary = summaryMap;
        _analysis = analysisMap;
        _records = recordItems;
        _cachedUpdatedAt = summaryEntry?.updatedAt;
      });
    }
  }

  Map<String, dynamic> _summaryPayload(Map<String, dynamic> response) {
    return <String, dynamic>{
      'summary': response['summary'] is Map<String, dynamic>
          ? response['summary'] as Map<String, dynamic>
          : <String, dynamic>{},
      'analysis': response['analysis'] is Map<String, dynamic>
          ? response['analysis'] as Map<String, dynamic>
          : <String, dynamic>{},
    };
  }

  String _metric(dynamic value, {String suffix = '', int decimals = 1}) {
    if (value == null) return '--';
    if (value is num) {
      final normalized = decimals == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(decimals);
      return '$normalized$suffix';
    }
    final text = value.toString().trim();
    return text.isEmpty ? '--' : '$text$suffix';
  }

  String _recordedAt(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return L.t(LanguageStore.notifier.value, 'weather_unknown_time');
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM dd, yyyy HH:mm').format(parsed.toLocal());
  }

  String _analysisText(String lang, String key) {
    const values = <String, Map<String, String>>{
      'en': {
        'watch_items': 'Watch items',
        'actions': 'Recommended actions',
      },
      'am': {
        'watch_items': 'የሚታዩ ነገሮች',
        'actions': 'የሚመከሩ እርምጃዎች',
      },
      'om': {
        'watch_items': 'Wantoota hordofuu',
        'actions': 'Tarkaanfiiwwan gorfaman',
      },
      'ti': {
        'watch_items': 'ዝከታተሉ ነገራት',
        'actions': 'ዝምከሩ ስጉምትታት',
      },
    };
    return values[lang]?[key] ?? values['en']![key]!;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(L.t(lang, 'weatherStation')),
          ),
          body: FarmSurface(
            padding: EdgeInsets.zero,
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.snapshot != null) _CurrentWeatherCard(snapshot: widget.snapshot!, lang: lang),
                if (widget.snapshot != null) const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      L.t(lang, 'weather_refresh_failed', params: {'error': _error!}),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (_cachedUpdatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      L.t(
                        lang,
                        'weather_saved_updated_at',
                        params: {'time': DateFormat('MMM dd, HH:mm').format(_cachedUpdatedAt!)},
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  FarmPanel(
                    color: const Color(0xFFFFFDF5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F7D12).withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.monitor_heart_outlined,
                                color: Color(0xFF4F7D12),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                L.t(lang, 'weather_monitoring_title'),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1E2A12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          (_analysis['headline']?.toString().trim().isNotEmpty ?? false)
                              ? _analysis['headline'].toString()
                              : L.t(lang, 'weather_monitoring_stable'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        if (_analysis['actions'] is List &&
                            (_analysis['actions'] as List).isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            _analysisText(lang, 'actions'),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...(_analysis['actions'] as List<dynamic>).take(2).map(
                            (item) => _WeatherActionRow(text: item.toString()),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FarmSectionTitle(
                    icon: Icons.insights_rounded,
                    title: L.t(lang, 'weather_summary_title'),
                    subtitle: L.t(lang, 'weatherMonitoringSubtitle'),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _WeatherMetricCard(
                        icon: Icons.thermostat_rounded,
                        color: Colors.orange.shade700,
                        label: L.t(lang, 'weather_avg_temp'),
                        value: _metric(_summary['avg_temperature'], suffix: ' C'),
                      ),
                      _WeatherMetricCard(
                        icon: Icons.water_drop_outlined,
                        color: Colors.blue.shade700,
                        label: L.t(lang, 'weather_avg_humidity'),
                        value: _metric(_summary['avg_humidity'], suffix: '%'),
                      ),
                      _WeatherMetricCard(
                        icon: Icons.grain_rounded,
                        color: Colors.indigo.shade700,
                        label: L.t(lang, 'weather_total_rain'),
                        value: _metric(_summary['total_precipitation'], suffix: ' mm'),
                      ),
                      _WeatherMetricCard(
                        icon: Icons.air_rounded,
                        color: Colors.teal.shade700,
                        label: L.t(lang, 'weather_avg_wind'),
                        value: _metric(_summary['avg_wind_speed'], suffix: ' km/h'),
                      ),
                      _WeatherMetricCard(
                        icon: Icons.opacity_rounded,
                        color: Colors.green.shade700,
                        label: L.t(lang, 'weather_soil_moisture'),
                        value: _metric(_summary['avg_soil_moisture'], suffix: '%'),
                      ),
                      _WeatherMetricCard(
                        icon: Icons.storage_outlined,
                        color: Colors.brown.shade700,
                        label: L.t(lang, 'weather_records_label'),
                        value: _metric(_summary['total_records'], decimals: 0),
                      ),
                    ],
                  ),
                  if (_analysis['watch_items'] is List &&
                      (_analysis['watch_items'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    FarmPanel(
                      color: const Color(0xFFF8FBEC),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.visibility_outlined, color: Colors.amber.shade900),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _analysisText(lang, 'watch_items'),
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ...(_analysis['watch_items'] as List<dynamic>).map(
                            (item) => _WeatherActionRow(text: item.toString()),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FarmSectionTitle(
                    icon: Icons.history_rounded,
                    title: L.t(lang, 'weather_recent_records_title'),
                  ),
                  if (_records.isEmpty)
                    FarmPanel(
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(L.t(lang, 'weather_no_server_records_title')),
                                Text(L.t(lang, 'weather_no_server_records_subtitle')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final record in _records)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FarmPanel(
                          child: _WeatherRecordRow(
                            lang: lang,
                            recordedAt: _recordedAt(record['recorded_at']),
                            temperature: _metric(record['temperature'], suffix: ' C'),
                            humidity: _metric(record['humidity'], suffix: '%'),
                            precipitation: _metric(record['precipitation'], suffix: ' mm'),
                            wind: _metric(record['wind_speed'], suffix: ' km/h'),
                            source: (record['data_source'] ?? L.t(lang, 'weather_source_unknown')).toString(),
                          ),
                        ),
                      ),
                ],
              ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CurrentWeatherCard extends StatelessWidget {
  final WeatherOverviewSnapshot snapshot;
  final String lang;

  const _CurrentWeatherCard({
    required this.snapshot,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final updatedText = snapshot.lastUpdated == null
        ? L.t(lang, 'updated_now')
        : L.t(
            lang,
            'updated_at',
            params: {
              'time': DateFormat('HH:mm').format(snapshot.lastUpdated!.toLocal()),
            },
          );

    return FarmPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/home/field_weather.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF294B14)),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      const Color(0xFF294B14).withValues(alpha: 0.62),
                      const Color(0xFFCFF36A).withValues(alpha: 0.18),
                    ],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                    ),
                    child: const Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 31),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${L.t(lang, 'farm_location')}: ${snapshot.locationText ?? L.t(lang, 'getting_location')}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        if ((snapshot.regionText ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${L.t(lang, 'region')}: ${snapshot.regionText}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.88)),
                          ),
                        ],
                        if ((snapshot.latLonText ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${L.t(lang, 'lat_lon')}: ${snapshot.latLonText}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.84)),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          L.t(lang, snapshot.statusKey),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (snapshot.detailText.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            snapshot.detailText.trim(),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.84)),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          updatedText,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.76),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    child: Text(
                      snapshot.tempText,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherMetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _WeatherMetricCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: FarmPanel(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E2A12),
                ),
              ),
            ],
        ),
      ),
    );
  }
}

class _WeatherActionRow extends StatelessWidget {
  final String text;

  const _WeatherActionRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF4F7D12),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherRecordRow extends StatelessWidget {
  final String lang;
  final String recordedAt;
  final String temperature;
  final String humidity;
  final String precipitation;
  final String wind;
  final String source;

  const _WeatherRecordRow({
    required this.lang,
    required this.recordedAt,
    required this.temperature,
    required this.humidity,
    required this.precipitation,
    required this.wind,
    required this.source,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_outlined, color: Colors.blueGrey.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                recordedAt,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              wind,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.teal.shade800,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WeatherMiniChip(label: L.t(lang, 'temperature'), value: temperature),
            _WeatherMiniChip(label: L.t(lang, 'humidity'), value: humidity),
            _WeatherMiniChip(label: L.t(lang, 'precipitation'), value: precipitation),
            _WeatherMiniChip(label: L.t(lang, 'weather_source_unknown'), value: source),
          ],
        ),
      ],
    );
  }
}

class _WeatherMiniChip extends StatelessWidget {
  final String label;
  final String value;

  const _WeatherMiniChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3CF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF3C640B),
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}
