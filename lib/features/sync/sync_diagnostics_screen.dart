import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../auth_session.dart';
import '../../connectivity_status_service.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../offline/local_cache_store.dart';
import '../../offline/offline_repository.dart';
import '../../sync_refresh_notifier.dart';
import '../my_farm/my_farm_screen.dart';
import '../scan/pending_scan_queue_store.dart';
import '../soil_health/soil_health_screen.dart';

class SyncDiagnosticsScreen extends StatefulWidget {
  final Future<void> Function()? onTriggerSync;

  const SyncDiagnosticsScreen({super.key, this.onTriggerSync});

  @override
  State<SyncDiagnosticsScreen> createState() => _SyncDiagnosticsScreenState();
}

class _SyncDiagnosticsScreenState extends State<SyncDiagnosticsScreen> {
  bool _loading = true;
  bool _offlineModeActive = false;
  bool _hasServerToken = false;
  int _pendingScans = 0;
  OfflineSyncSummary _summary = const OfflineSyncSummary(
    pendingCount: 0,
    failedCount: 0,
    conflictCount: 0,
    deletedCount: 0,
  );
  List<OfflineSyncEntitySummary> _entitySummaries = const <OfflineSyncEntitySummary>[];
  List<OfflineConflictItem> _conflicts = const <OfflineConflictItem>[];
  List<_CacheStatus> _caches = const <_CacheStatus>[];

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
      });

      final repo = OfflineRepository.instance;
      final offlineModeActive = await AuthSession.isOfflineModeActive();
      final hasServerToken = await ApiClient.hasServerSessionCapability();
      var pendingScans = 0;
    try {
      pendingScans = (await PendingScanQueueStore.instance.listAll()).length;
    } catch (_) {
      pendingScans = 0;
    }
    final summary = await repo.getSyncSummary();
    final entitySummaries = await repo.getSyncSummaryByEntity();
    final conflicts = await repo.getConflictItems();
    final caches = await _loadCacheStatuses();

    if (!mounted) return;
      setState(() {
        _offlineModeActive = offlineModeActive;
        _hasServerToken = hasServerToken;
        _pendingScans = pendingScans;
      _summary = summary;
      _entitySummaries = entitySummaries;
      _conflicts = conflicts;
      _caches = caches;
      _loading = false;
    });
  }

  Future<List<_CacheStatus>> _loadCacheStatuses() async {
    const keys = <_CacheKey>[
      _CacheKey('sync_cache_profile', 'profile_cache_v1'),
      _CacheKey('sync_cache_weather_summary', 'weather_summary_cache_v1'),
      _CacheKey('sync_cache_weather_records', 'weather_records_cache_v1'),
      _CacheKey('sync_cache_home_weather', 'home_weather_cache_v1'),
      _CacheKey('sync_cache_disease_history', 'disease_history_cache_v1'),
      _CacheKey('sync_cache_crop_health', 'crop_health_history_cache_v1'),
      _CacheKey('sync_cache_prevention_crops', 'disease_prevention_crops_cache_v1'),
      _CacheKey('sync_cache_crop_reference', 'reference_crops_cache_v1'),
      _CacheKey('sync_cache_region_reference', 'reference_regions_cache_v1'),
      _CacheKey('sync_cache_my_farm_alerts', 'my_farm_alerts_cache_v1'),
      _CacheKey('sync_cache_my_farm_reports', 'my_farm_reports_cache_v1'),
    ];

    final results = <_CacheStatus>[];
    for (final item in keys) {
      final updatedAt = await LocalCacheStore.instance.readUpdatedAt(item.key);
      results.add(_CacheStatus(labelKey: item.labelKey, updatedAt: updatedAt));
    }
    return results;
  }

  Future<void> _triggerSync() async {
    if (widget.onTriggerSync == null) return;
    await widget.onTriggerSync!.call();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(L.t(lang, 'sync_diagnostics_title')),
            actions: [
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: L.t(lang, 'sync_refresh_diagnostics'),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: ValueListenableBuilder(
              valueListenable: ConnectivityStatusService.instance.notifier,
              builder: (context, ApiConnectivityStatus status, _) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _OverviewCard(
                      languageCode: lang,
                        loading: _loading,
                        status: status,
                        offlineModeActive: _offlineModeActive,
                        hasServerToken: _hasServerToken,
                        summary: _summary,
                      pendingScans: _pendingScans,
                      onTriggerSync: widget.onTriggerSync == null ? null : _triggerSync,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      L.t(lang, 'sync_entity_breakdown_title'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const LinearProgressIndicator(minHeight: 3)
                    else
                      for (final item in _entitySummaries)
                        _EntitySummaryCard(summary: item),
                    if (!_loading) ...[
                      const SizedBox(height: 16),
                      Text(
                        L.t(lang, 'sync_conflict_items_title'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_conflicts.isEmpty)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                            title: Text(L.t(lang, 'sync_conflict_items_empty')),
                          ),
                        )
                      else
                        for (final item in _conflicts)
                          _ConflictItemCard(
                            languageCode: lang,
                            item: item,
                          ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      L.t(lang, 'sync_cached_datasets_title'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final cache in _caches) _CacheStatusTile(cache: cache),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L.t(lang, 'sync_operational_guidance_title'),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(L.t(lang, 'sync_guidance_pending')),
                            const SizedBox(height: 4),
                            Text(L.t(lang, 'sync_guidance_failed')),
                            const SizedBox(height: 4),
                            Text(L.t(lang, 'sync_guidance_conflict')),
                            const SizedBox(height: 4),
                            Text(L.t(lang, 'sync_guidance_deleted')),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final String languageCode;
  final bool loading;
  final ApiConnectivityStatus status;
  final bool offlineModeActive;
  final bool hasServerToken;
  final OfflineSyncSummary summary;
  final int pendingScans;
  final Future<void> Function()? onTriggerSync;

  const _OverviewCard({
    required this.languageCode,
    required this.loading,
    required this.status,
    required this.offlineModeActive,
    required this.hasServerToken,
    required this.summary,
    required this.pendingScans,
    required this.onTriggerSync,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor();
    final headline = _headline();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync_problem_outlined, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    headline,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                if (onTriggerSync != null)
                  FilledButton.tonalIcon(
                    onPressed: onTriggerSync,
                    icon: const Icon(Icons.sync),
                    label: Text(L.t(languageCode, 'sync_action_sync_now')),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading)
              const LinearProgressIndicator(minHeight: 3)
            else
              Text(
                _detail(),
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  label: L.t(
                    languageCode,
                    'sync_metric_pending',
                    params: {'count': '${summary.pendingCount}'},
                  ),
                  color: Colors.amber.shade700,
                ),
                _MetricChip(
                  label: L.t(
                    languageCode,
                    'sync_metric_failed',
                    params: {'count': '${summary.failedCount}'},
                  ),
                  color: Colors.red.shade700,
                ),
                _MetricChip(
                  label: L.t(
                    languageCode,
                    'sync_metric_conflicts',
                    params: {'count': '${summary.conflictCount}'},
                  ),
                  color: Colors.deepOrange.shade700,
                ),
                _MetricChip(
                  label: L.t(
                    languageCode,
                    'sync_metric_deletes',
                    params: {'count': '${summary.deletedCount}'},
                  ),
                  color: Colors.blueGrey.shade700,
                ),
                _MetricChip(
                  label: L.t(
                    languageCode,
                    'sync_metric_queued_scans',
                    params: {'count': '$pendingScans'},
                  ),
                  color: Colors.orange.shade800,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _headline() {
    if (summary.conflictCount > 0) return L.t(languageCode, 'sync_overview_conflicts');
    if (summary.failedCount > 0) return L.t(languageCode, 'sync_overview_failed');
    if (offlineModeActive && !hasServerToken) {
      return L.t(languageCode, 'sync_overview_online_sign_in_required');
    }
    if (offlineModeActive) return L.t(languageCode, 'sync_overview_offline_mode');
    switch (status.state) {
      case ApiConnectivityState.apiOnline:
        return L.t(languageCode, 'sync_overview_ready');
      case ApiConnectivityState.internetOnly:
        return L.t(languageCode, 'sync_overview_internet_only');
      case ApiConnectivityState.offline:
        return L.t(languageCode, 'sync_overview_offline');
    }
  }

  String _detail() {
    if (summary.conflictCount > 0) {
      return L.t(languageCode, 'sync_overview_detail_conflicts');
    }
    if (summary.failedCount > 0) {
      return L.t(languageCode, 'sync_overview_detail_failed');
    }
    if (offlineModeActive && !hasServerToken) {
      return L.t(languageCode, 'sync_overview_detail_online_sign_in_required');
    }
    if (offlineModeActive) {
      return L.t(languageCode, 'sync_overview_detail_offline_mode');
    }
    if (summary.totalIssues > 0 || pendingScans > 0) {
      return L.t(languageCode, 'sync_overview_detail_pending');
    }
    if (status.state != ApiConnectivityState.apiOnline && status.message.trim().isNotEmpty) {
      return status.message;
    }
    return L.t(languageCode, 'sync_overview_detail_clean');
  }

  Color _statusColor() {
    if (summary.conflictCount > 0) return Colors.deepOrange.shade700;
    if (summary.failedCount > 0) return Colors.red.shade700;
    if (offlineModeActive || status.state != ApiConnectivityState.apiOnline) {
      return Colors.orange.shade700;
    }
    return Colors.green.shade700;
  }
}

class _EntitySummaryCard extends StatelessWidget {
  final OfflineSyncEntitySummary summary;

  const _EntitySummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(_label(summary.entityKey)),
        subtitle: Text(
          L.t(
            LanguageStore.notifier.value,
            'sync_entity_subtitle',
            params: {
              'pending': '${summary.pendingCount}',
              'failed': '${summary.failedCount}',
              'conflicts': '${summary.conflictCount}',
              'deletes': '${summary.deletedCount}',
            },
          ),
        ),
        trailing: summary.totalIssues == 0
            ? const Icon(Icons.check_circle_outline, color: Colors.green)
            : const Icon(Icons.chevron_right),
      ),
    );
  }

  String _label(String key) {
    switch (key) {
      case 'farms':
        return L.t(LanguageStore.notifier.value, 'sync_entity_farms');
      case 'plots':
        return L.t(LanguageStore.notifier.value, 'sync_entity_plots');
      case 'plantings':
        return L.t(LanguageStore.notifier.value, 'sync_entity_plantings');
      case 'soil_health':
        return L.t(LanguageStore.notifier.value, 'sync_entity_soil_health');
      default:
        return key;
    }
  }
}

class _ConflictItemCard extends StatelessWidget {
  final String languageCode;
  final OfflineConflictItem item;

  const _ConflictItemCard({
    required this.languageCode,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final reviewHint = _reviewHint(item.entityKey);
    final reviewAction = _reviewAction();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.rule_folder_outlined, color: Colors.deepOrange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_entityLabel(item.entityKey)),
            if ((item.details ?? '').trim().isNotEmpty) Text(item.details!.trim()),
            if ((item.conflictReason ?? '').trim().isNotEmpty)
              Text(
                L.t(
                  languageCode,
                  'sync_conflict_reason',
                  params: {'value': item.conflictReason!.trim()},
                ),
              ),
            if ((item.syncError ?? '').trim().isNotEmpty)
              Text(
                L.t(
                  languageCode,
                  'sync_conflict_error',
                  params: {'value': item.syncError!.trim()},
                ),
              ),
            if (item.localUpdatedAt != null)
              Text(
                L.t(
                  languageCode,
                  'sync_conflict_updated_at',
                  params: {'time': item.localUpdatedAt!.toLocal().toString()},
                ),
              ),
            if (reviewHint.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                reviewHint,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (reviewAction != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => reviewAction.onPressed(context),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(reviewAction.label),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _entityLabel(String key) {
    switch (key) {
      case 'farms':
        return L.t(languageCode, 'sync_entity_farms');
      case 'plots':
        return L.t(languageCode, 'sync_entity_plots');
      case 'plantings':
        return L.t(languageCode, 'sync_entity_plantings');
      case 'soil_health':
        return L.t(languageCode, 'sync_entity_soil_health');
      default:
        return key;
    }
  }

  String _reviewHint(String key) {
    switch (key) {
      case 'farms':
        return L.t(languageCode, 'sync_conflict_review_hint_farms');
      case 'plots':
        return L.t(languageCode, 'sync_conflict_review_hint_plots');
      case 'plantings':
        return L.t(languageCode, 'sync_conflict_review_hint_plantings');
      case 'soil_health':
        return L.t(languageCode, 'sync_conflict_review_hint_soil_health');
      default:
        return '';
    }
  }

  _ConflictReviewAction? _reviewAction() {
    switch (item.entityKey) {
      case 'farms':
      case 'plots':
      case 'plantings':
        return _ConflictReviewAction(
          label: L.t(languageCode, 'sync_action_review_in_my_farm'),
          onPressed: (context) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MyFarmScreen(),
              ),
            );
          },
        );
      case 'soil_health':
        return _ConflictReviewAction(
          label: L.t(languageCode, 'sync_action_review_in_soil_health'),
          onPressed: (context) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SoilHealthScreen(),
              ),
            );
          },
        );
      default:
        return null;
    }
  }
}

class _CacheStatusTile extends StatelessWidget {
  final _CacheStatus cache;

  const _CacheStatusTile({required this.cache});

  @override
  Widget build(BuildContext context) {
    final updatedAt = cache.updatedAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          updatedAt == null ? Icons.cloud_off_outlined : Icons.history_toggle_off,
        ),
        title: Text(L.t(LanguageStore.notifier.value, cache.labelKey)),
        subtitle: Text(
          updatedAt == null
              ? L.t(LanguageStore.notifier.value, 'sync_no_saved_data_yet')
              : L.t(
                  LanguageStore.notifier.value,
                  'sync_last_saved_at',
                  params: {'time': updatedAt.toLocal().toString()},
                ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MetricChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _CacheKey {
  final String labelKey;
  final String key;

  const _CacheKey(this.labelKey, this.key);
}

class _CacheStatus {
  final String labelKey;
  final DateTime? updatedAt;

  const _CacheStatus({required this.labelKey, required this.updatedAt});
}

class _ConflictReviewAction {
  final String label;
  final void Function(BuildContext context) onPressed;

  const _ConflictReviewAction({
    required this.label,
    required this.onPressed,
  });
}
