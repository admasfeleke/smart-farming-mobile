import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../auth_session.dart';
import '../../connectivity_status_service.dart';
import '../../disease_naming.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../models/disease_report_model.dart';
import '../../widgets/farm_ui.dart';
import 'disease_history_cache_store.dart';
import 'disease_refresh_notifier.dart';
import '../scan/offline_treatment_guidance_service.dart';
import '../scan/local_scan_history_store.dart';
import '../scan/pending_scan_queue_store.dart';

//
// Public entry point
//

class DiseaseCheckScreen extends StatefulWidget {
  final bool showHeader;
  const DiseaseCheckScreen({super.key, this.showHeader = true});

  @override
  State<DiseaseCheckScreen> createState() => _DiseaseCheckScreenState();
}

class _DiseaseCheckScreenState extends State<DiseaseCheckScreen> {
  List<PendingScanQueueEntry> _pending = [];
  List<LocalScanHistoryEntry> _syncedLocal = [];
  List<DiseaseReportModel> _reports = [];
  bool _loading = true;
  bool _offlineMode = false;
  String? _errorMessage;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _backgroundProbeRunning = false;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _filter = 'all';
  String _dateFilter = 'all';
  static const Duration _historyConnectivityStaleAfter = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    diseaseReportRefreshNotifier.addListener(_onDiseaseHistoryRefresh);
    _load();
  }

  @override
  void dispose() {
    diseaseReportRefreshNotifier.removeListener(_onDiseaseHistoryRefresh);
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onDiseaseHistoryRefresh() {
    if (!mounted) return;
    unawaited(_load(refresh: true));
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _reports = [];
        _errorMessage = null;
      });
    }
    setState(() => _loading = true);

    // Always load pending queue from local storage
    try {
      _pending = await PendingScanQueueStore.instance.listAll();
    } catch (_) {
      _pending = [];
    }
    try {
      await LocalScanHistoryStore.instance.pruneInvalidEntries();
      _syncedLocal = await LocalScanHistoryStore.instance.listAll();
    } catch (_) {
      _syncedLocal = [];
    }
    final cachedReports = await DiseaseHistoryCacheStore.instance.listAll();
    final offlineCachedReports = List<DiseaseReportModel>.of(cachedReports);
    final offlineSyncedLocal = await _reconcileSyncedLocalEntries(
      offlineCachedReports,
      _syncedLocal,
    );
    final localSubmissionIds = offlineSyncedLocal
        .map((entry) => entry.submissionId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    _pending = _pending
        .where((entry) => !localSubmissionIds.contains(entry.queueId.trim()))
        .toList(growable: false);

    final offline = await AuthSession.isOfflineModeActive();
    final hasToken = await ApiClient.hasServerSessionCapability();
    final connectivity = ConnectivityStatusService.instance.notifier.value;
    final connectivityFresh =
        DateTime.now().difference(connectivity.checkedAt) <=
        _historyConnectivityStaleAfter;
    final canReachApiNow =
        connectivity.state == ApiConnectivityState.apiOnline &&
        connectivityFresh;

    if (offline || !hasToken || !canReachApiNow) {
      if (mounted) {
        setState(() {
          _offlineMode = true;
          _reports = offlineCachedReports;
          _syncedLocal = offlineSyncedLocal;
          _loading = false;
        });
      }
      if (!offline && hasToken && !canReachApiNow) {
        unawaited(_probeServerHistoryInBackground(refresh: refresh));
      }
      return;
    }

    try {
      final result = await ApiClient.getDiseaseReportsPage(
        page: 1,
        perPage: 20,
      );
      await DiseaseHistoryCacheStore.instance.saveAll(result.items);
      final remainingSyncedLocal = await _reconcileSyncedLocalEntries(
        result.items,
        _syncedLocal,
      );
      final localSubmissionIds = remainingSyncedLocal
          .map((entry) => entry.submissionId.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      _pending = _pending
          .where((entry) => !localSubmissionIds.contains(entry.queueId.trim()))
          .toList(growable: false);
      if (mounted) {
        setState(() {
          _reports = result.items;
          _syncedLocal = remainingSyncedLocal;
          _hasMore = result.pagination.currentPage < result.pagination.lastPage;
          _page = 1;
          _offlineMode = false;
          _loading = false;
        });
      }
    } on ApiUnauthorized {
      if (mounted)
        setState(() {
          _loading = false;
          _errorMessage = null;
        });
    } on ApiException catch (e) {
      final connectivityIssue = ApiClient.isConnectivityIssueMessage(e.message);
      if (mounted) {
        setState(() {
          _offlineMode = connectivityIssue;
          _reports = connectivityIssue ? cachedReports : _reports;
          _loading = false;
          _errorMessage = connectivityIssue ? null : e.message;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _errorMessage = e.toString();
        });
    }
  }

  Future<void> _probeServerHistoryInBackground({required bool refresh}) async {
    if (_backgroundProbeRunning || !mounted) {
      return;
    }
    _backgroundProbeRunning = true;
    try {
      final status = await ConnectivityStatusService.instance
          .refreshNow()
          .timeout(const Duration(seconds: 3));
      if (!mounted) {
        return;
      }
      if (status.state == ApiConnectivityState.apiOnline) {
        await _load(refresh: refresh);
      }
    } catch (_) {
      // Keep local/offline view when probe fails.
    } finally {
      _backgroundProbeRunning = false;
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final result = await ApiClient.getDiseaseReportsPage(
        page: next,
        perPage: 20,
      );
      final combined = <DiseaseReportModel>[..._reports, ...result.items];
      await DiseaseHistoryCacheStore.instance.saveAll(combined);
      if (mounted) {
        setState(() {
          _reports = combined;
          _hasMore = result.pagination.currentPage < result.pagination.lastPage;
          _page = next;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _deletePending(String queueId) async {
    PendingScanQueueEntry? match;
    for (final entry in _pending) {
      if (entry.queueId == queueId) {
        match = entry;
        break;
      }
    }
    await PendingScanQueueStore.instance.deleteByQueueId(queueId);
    if (match != null && match.imagePath.trim().isNotEmpty) {
      try {
        final file = File(match.imagePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Ignore local image cleanup failures.
      }
    }
    setState(() => _pending.removeWhere((e) => e.queueId == queueId));
  }

  Future<void> _deleteLocalHistory(LocalScanHistoryEntry entry) async {
    await LocalScanHistoryStore.instance.deleteBySubmissionId(
      entry.submissionId,
    );
    if (entry.imagePath.trim().isNotEmpty) {
      try {
        final file = File(entry.imagePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Ignore local image cleanup failures.
      }
    }
    if (!mounted) return;
    setState(() {
      _syncedLocal.removeWhere(
        (item) => item.submissionId == entry.submissionId,
      );
    });
  }

  Future<List<LocalScanHistoryEntry>> _reconcileSyncedLocalEntries(
    List<DiseaseReportModel> reports,
    List<LocalScanHistoryEntry> localEntries,
  ) async {
    if (localEntries.isEmpty) {
      return localEntries;
    }

    final remaining = <LocalScanHistoryEntry>[];
    for (final entry in localEntries) {
      DiseaseReportModel? matchedReport;
      for (final report in reports) {
        final submissionId = report.clientSubmissionId?.trim();
        if (submissionId != null && submissionId == entry.submissionId) {
          matchedReport = report;
          break;
        }
      }

      if (matchedReport == null) {
        remaining.add(entry);
        continue;
      }

      if (!matchedReport.finding.isInferred &&
          !matchedReport.finding.isVerified) {
        reports.remove(matchedReport);
        remaining.add(entry);
        continue;
      }

      await LocalScanHistoryStore.instance.deleteBySubmissionId(
        entry.submissionId,
      );
      try {
        final file = File(entry.imagePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Ignore local cache cleanup failures.
      }
    }

    return remaining;
  }

  List<PendingScanQueueEntry> _filteredPending() {
    final query = _searchController.text.trim().toLowerCase();
    return _pending
        .where((entry) {
          if (!_matchesPendingFilter(entry)) return false;
          if (!_matchesDateFilter(entry.capturedAtUtc)) return false;
          if (query.isEmpty) return true;
          final haystack = <String>[
            entry.queueId,
            entry.cropId.toString(),
            entry.plotId.toString(),
            _metadataString(entry.scanMetadata, 'crop_name') ?? '',
            _metadataString(entry.scanMetadata, 'plot_name') ?? '',
            _metadataString(entry.scanMetadata, 'offline_local_disease_name') ??
                '',
            _metadataString(entry.scanMetadata, 'offline_local_disease_key') ??
                '',
            _metadataString(entry.scanMetadata, 'offline_local_inference') ??
                '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  List<LocalScanHistoryEntry> _filteredSyncedLocal() {
    final query = _searchController.text.trim().toLowerCase();
    return _syncedLocal
        .where((entry) {
          if (!_matchesLocalFilter(entry)) return false;
          if (!_matchesDateFilter(entry.capturedAtUtc)) return false;
          if (query.isEmpty) return true;
          final haystack = <String>[
            entry.submissionId,
            entry.cropId.toString(),
            entry.plotId.toString(),
            _metadataString(entry.scanMetadata, 'crop_name') ?? '',
            _metadataString(entry.scanMetadata, 'plot_name') ?? '',
            _metadataString(entry.scanMetadata, 'offline_local_disease_name') ??
                '',
            _metadataString(entry.scanMetadata, 'offline_local_disease_key') ??
                '',
            _metadataString(entry.scanMetadata, 'offline_local_inference') ??
                '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  List<DiseaseReportModel> _filteredReports(String lang) {
    final query = _searchController.text.trim().toLowerCase();
    return _reports
        .where((report) {
          if (!_matchesReportFilter(report)) return false;
          if (!_matchesDateFilter(report.reportedAt)) return false;
          if (query.isEmpty) return true;
          final haystack = <String>[
            report.id.toString(),
            report.status,
            report.severity,
            report.diseaseName,
            report.resolvedDiseaseName,
            report.resolvedCanonicalDiseaseName,
            _resolvedFindingDisplayName(report, lang),
            report.provisionalDiseaseName ?? '',
            report.inferredDiseaseName ?? '',
            report.verifiedDiseaseName ?? '',
            report.likelyIssueName ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  bool _matchesPendingFilter(PendingScanQueueEntry entry) {
    final diseaseKey =
        _metadataString(entry.scanMetadata, 'offline_local_disease_key') ?? '';
    return switch (_filter) {
      'all' => true,
      'pending' => true,
      'local' => false,
      'confirmed' => false,
      'healthy' => isHealthyDiseaseKey(diseaseKey),
      'treatment' => false,
      _ => true,
    };
  }

  bool _matchesLocalFilter(LocalScanHistoryEntry entry) {
    final diseaseKey =
        _metadataString(entry.scanMetadata, 'offline_local_disease_key') ?? '';
    return switch (_filter) {
      'all' => true,
      'pending' => true,
      'local' => true,
      'confirmed' => false,
      'healthy' => isHealthyDiseaseKey(diseaseKey),
      'treatment' => false,
      _ => true,
    };
  }

  bool _matchesReportFilter(DiseaseReportModel report) {
    return switch (_filter) {
      'all' => true,
      'pending' => _reportIsPendingReview(report),
      'local' => false,
      'confirmed' =>
        report.finding.isVerified ||
            report.finding.isInferred ||
            report.isConfirmedWorkflowState,
      'healthy' => isHealthyDiseaseKey(report.resolvedCanonicalDiseaseName),
      'treatment' => _reportHasTreatment(report),
      _ => true,
    };
  }

  bool _reportIsPendingReview(DiseaseReportModel report) {
    final status = report.status.toLowerCase();
    return status == 'new' ||
        status == 'reviewing' ||
        status == 'processing' ||
        status == 'queued';
  }

  bool _reportHasTreatment(DiseaseReportModel report) {
    final guidance = report.treatmentGuidance;
    if (guidance == null) {
      return false;
    }
    return guidance.canShowTreatmentDetails &&
        (guidance.activeIngredient?.isNotEmpty == true ||
            guidance.actions.isNotEmpty);
  }

  bool _matchesDateFilter(DateTime value) {
    if (_dateFilter == 'all') return true;
    final local = value.toLocal();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return switch (_dateFilter) {
      'today' => !local.isBefore(startOfToday),
      'week' => !local.isBefore(now.subtract(const Duration(days: 7))),
      'month' => !local.isBefore(now.subtract(const Duration(days: 30))),
      _ => true,
    };
  }

  static String? _metadataString(Map<String, dynamic>? metadata, String key) {
    final value = metadata?[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        final filteredPending = _filteredPending();
        final filteredSyncedLocal = _filteredSyncedLocal();
        final filteredReports = _filteredReports(lang);
        final hasAnyHistory =
            _pending.isNotEmpty ||
            _syncedLocal.isNotEmpty ||
            _reports.isNotEmpty;
        final hasFilteredHistory =
            filteredPending.isNotEmpty ||
            filteredSyncedLocal.isNotEmpty ||
            filteredReports.isNotEmpty;
        // Material ensures showModalBottomSheet and showDialog have a valid
        // Material ancestor whether this screen is used as a tab (inside
        // AppShell's Scaffold) or pushed via Navigator.
        return Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: FarmSurface(
            padding: EdgeInsets.zero,
            child: RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (widget.showHeader)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          L.t(lang, 'scan_history'),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    ),
                  if (_offlineMode)
                    SliverToBoxAdapter(child: _OfflineBanner(lang: lang)),
                  if (_errorMessage != null)
                    SliverToBoxAdapter(
                      child: _ErrorBanner(
                        message: _errorMessage!,
                        onRetry: () => _load(refresh: true),
                      ),
                    ),
                  if (hasAnyHistory)
                    SliverToBoxAdapter(
                      child: _DiseaseHistoryFilters(
                        lang: lang,
                        selectedFilter: _filter,
                        selectedDateFilter: _dateFilter,
                        searchController: _searchController,
                        onFilterChanged: (value) =>
                            setState(() => _filter = value),
                        onDateFilterChanged: (value) =>
                            setState(() => _dateFilter = value),
                        onSearchChanged: (_) => setState(() {}),
                      ),
                    ),
                  //  Pending local queue
                  if (filteredPending.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        icon: Icons.cloud_upload_outlined,
                        label: L.t(lang, 'disease_history_pending_title'),
                        subtitle: L.t(lang, 'disease_history_pending_subtitle'),
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _PendingQueueCard(
                          entry: filteredPending[i],
                          lang: lang,
                          onDelete: () =>
                              _deletePending(filteredPending[i].queueId),
                        ),
                        childCount: filteredPending.length,
                      ),
                    ),
                  ],
                  if (filteredSyncedLocal.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        icon: Icons.history_toggle_off_rounded,
                        label: L.t(lang, 'disease_review_results_title'),
                        subtitle: _dh(lang, 'saved_local_review_pending'),
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _SyncedLocalCard(
                          entry: filteredSyncedLocal[i],
                          lang: lang,
                          onDelete: () =>
                              _deleteLocalHistory(filteredSyncedLocal[i]),
                        ),
                        childCount: filteredSyncedLocal.length,
                      ),
                    ),
                  ],
                  //  Server history
                  if (_loading)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (!hasAnyHistory)
                    SliverFillRemaining(child: _EmptyState(lang: lang))
                  else if (!hasFilteredHistory)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _NoFilteredHistory(lang: lang),
                    )
                  else if (filteredReports.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        icon: Icons.history_rounded,
                        label: L.t(lang, 'disease_review_results_title'),
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _ReportCard(
                          report: filteredReports[i],
                          lang: lang,
                          onTap: () =>
                              _openDetail(context, filteredReports[i], lang),
                        ),
                        childCount: filteredReports.length,
                      ),
                    ),
                    if (_loadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ), // RefreshIndicator
          ),
        ); // Material
      },
    );
  }

  void _openDetail(
    BuildContext context,
    DiseaseReportModel report,
    String lang,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportDetailSheet(report: report, lang: lang),
    );
  }
}

//
// Section header
//

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FarmSectionTitle(
        icon: icon,
        title: label,
        subtitle: subtitle,
        color: color,
      ),
    );
  }
}

class _DiseaseHistoryFilters extends StatelessWidget {
  final String lang;
  final String selectedFilter;
  final String selectedDateFilter;
  final TextEditingController searchController;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onDateFilterChanged;
  final ValueChanged<String> onSearchChanged;

  const _DiseaseHistoryFilters({
    required this.lang,
    required this.selectedFilter,
    required this.selectedDateFilter,
    required this.searchController,
    required this.onFilterChanged,
    required this.onDateFilterChanged,
    required this.onSearchChanged,
  });

  static const List<({String key, String labelKey, IconData icon})> _filters = [
    (key: 'all', labelKey: 'filter_all', icon: Icons.list_alt_rounded),
    (
      key: 'pending',
      labelKey: 'filter_pending',
      icon: Icons.hourglass_top_rounded,
    ),
    (key: 'local', labelKey: 'filter_local', icon: Icons.phone_android_rounded),
    (
      key: 'confirmed',
      labelKey: 'filter_confirmed',
      icon: Icons.verified_outlined,
    ),
    (key: 'healthy', labelKey: 'filter_healthy', icon: Icons.eco_outlined),
    (
      key: 'treatment',
      labelKey: 'filter_treatment',
      icon: Icons.medical_services_outlined,
    ),
  ];
  static const List<({String key, String labelKey})> _dateFilters = [
    (key: 'all', labelKey: 'date_filter_all'),
    (key: 'today', labelKey: 'date_filter_today'),
    (key: 'week', labelKey: 'date_filter_week'),
    (key: 'month', labelKey: 'date_filter_month'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: _dh(lang, 'history_search_hint'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: _dh(lang, 'clear_search'),
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters
                  .map((filter) {
                    final selected = selectedFilter == filter.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: selected,
                        avatar: Icon(
                          filter.icon,
                          size: 16,
                          color: selected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.primary,
                        ),
                        label: Text(_dh(lang, filter.labelKey)),
                        onSelected: (_) => onFilterChanged(filter.key),
                        selectedColor: theme.colorScheme.primary,
                        checkmarkColor: theme.colorScheme.onPrimary,
                        labelStyle: TextStyle(
                          color: selected
                              ? theme.colorScheme.onPrimary
                              : Colors.grey.shade800,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _dateFilters
                  .map((filter) {
                    final selected = selectedDateFilter == filter.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: selected,
                        label: Text(_dh(lang, filter.labelKey)),
                        avatar: Icon(
                          Icons.calendar_today_outlined,
                          size: 15,
                          color: selected
                              ? theme.colorScheme.onSecondaryContainer
                              : Colors.grey.shade700,
                        ),
                        onSelected: (_) => onDateFilterChanged(filter.key),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoFilteredHistory extends StatelessWidget {
  final String lang;
  const _NoFilteredHistory({required this.lang});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 48,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 12),
            Text(
              _dh(lang, 'no_filtered_history_title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _dh(lang, 'no_filtered_history_body'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _resolvedFindingDisplayName(DiseaseReportModel report, String lang) {
  final finding = report.finding;
  if (finding.hasMeaningfulName) {
    final loc = localizedDiseaseLabel(lang, finding.canonicalKey);
    if (loc.isNotEmpty) return loc;
    final humanized = displayDiseaseLabel(finding.canonicalKey);
    if (humanized.isNotEmpty) return humanized;
    return finding.name!;
  }
  if (report.isConfirmedWorkflowState) {
    return _dh(lang, 'disease_confirmed');
  }
  return _dh(lang, 'awaiting_analysis');
}

String _localizedDiseaseNameFromRaw(
  String lang,
  String? rawName,
  String? canonicalKey,
) {
  final key = canonicalKey?.trim().isNotEmpty == true
      ? canonicalKey!.trim()
      : normalizeDiseaseKey(rawName ?? '');
  final localized = localizedDiseaseLabel(lang, key);
  if (localized.isNotEmpty) return localized;
  final display = displayDiseaseLabel(key);
  if (display.isNotEmpty) return display;
  final raw = rawName?.trim();
  return raw == null || raw.isEmpty ? '' : raw;
}

String _dh(String lang, String key, {Map<String, String>? params}) {
  const strings = <String, Map<String, String>>{
    'en': {
      'disease_confirmed': 'Disease confirmed',
      'awaiting_analysis': 'Awaiting analysis',
      'saved_local_review_pending':
          'Saved local finding while server review is pending',
      'unknown_disease': 'Unknown disease',
      'ai_confidence': 'AI: {value}%',
      'on_device_result_pending':
          'On-device result, awaiting expert confirmation',
      'crop_plot_context': 'Crop #{crop} • Plot #{plot}',
      'no_device_result_upload':
          'No on-device result, will analyze when uploaded',
      'waiting_upload': 'Waiting to upload to server',
      'upload_attempt_retry': 'Upload attempt {count}, retrying soon',
      'remove_from_queue': 'Remove from queue',
      'remove_scan_title': 'Remove scan?',
      'cancel': 'Cancel',
      'remove': 'Remove',
      'uploaded_review_pending': 'Uploaded, review pending',
      'likely_issue_detected': 'Likely issue detected',
      'server_review_keep_local':
          'Server review is still pending. Keeping local result visible.',
      'treatment_ready': 'Treatment ready',
      'awaiting_expert_review':
          'Awaiting expert review. Do not apply treatment yet.',
      'active_ingredient': 'Active Ingredient',
      'dosage': 'Dosage',
      'protective_equipment': 'Protective Equipment (PPE)',
      'pre_harvest_interval': 'Pre-Harvest Interval',
      're_entry_interval': 'Re-Entry Interval',
      'what_to_do_now': 'What to do now',
      'what_to_watch_for': 'What to watch for',
      'prevention_next_season': 'Prevention for next season',
      'call_for_help_if': 'Call for help if you see',
      'important_notes': 'Important notes',
      'approved_registry_guidance': 'Approved treatment registry',
      'general_advisory_guidance': 'General advisory guidance',
      'treatment_options': 'Approved treatment options',
      'natural_treatment': 'Natural treatment',
      'modern_treatment': 'Modern treatment',
      'product': 'Product',
      'restrictions': 'Restrictions',
      'application_timing': 'Application timing',
      'max_applications': 'Max applications',
      'next_step': 'Next step',
      'on_device_ai_result': 'On-device AI result',
      'confidence_percent': 'Confidence: {value}%',
      'provisional_pending_title': 'Provisional, awaiting expert confirmation',
      'provisional_pending_body':
          'This result comes from the on-device AI model. It will be reviewed by an agricultural expert once uploaded. Do not apply chemical treatment based on this result alone.',
      'offline_treatment_guide': 'Offline Treatment Guide',
      'bundled_guide': 'Bundled guide',
      'call_for_help_if_short': 'Call for help if',
      'history_search_hint': 'Search disease, status, or scan',
      'clear_search': 'Clear search',
      'filter_all': 'All',
      'filter_pending': 'Pending',
      'filter_local': 'On-device',
      'filter_confirmed': 'Confirmed',
      'filter_healthy': 'Healthy',
      'filter_treatment': 'Treatment',
      'date_filter_all': 'All dates',
      'date_filter_today': 'Today',
      'date_filter_week': 'Last 7 days',
      'date_filter_month': 'Last 30 days',
      'no_filtered_history_title': 'No matching history',
      'no_filtered_history_body':
          'Change the filter or clear the search to see more records.',
      'disease_history_empty_any':
          'No scan history yet. Offline scan results and synced reports will appear here.',
      'delete_local_history': 'Delete local history',
      'delete_local_history_title': 'Delete local scan result?',
      'delete_local_history_body':
          'This removes the on-device scan result and its local photo. It does not delete any report already uploaded to the server.',
      'source_on_device': 'On-device AI',
      'source_server_ai': 'Server AI',
      'source_expert': 'Expert decision',
      'source_likely_issue': 'Likely issue',
      'source_awaiting': 'Awaiting analysis',
      'inference_chain_title': 'How this result was decided',
      'offline_result_label': 'Phone model',
      'server_result_label': 'Server inference',
      'expert_result_label': 'Expert verification',
      'not_available': 'Not available',
      'no_server_ai_yet': 'No server AI result yet',
      'no_expert_decision_yet': 'No expert decision yet',
      'expert_confirmed_diagnosis': 'Expert confirmed diagnosis',
      'ai_provisional_awaiting_expert':
          'AI provisional, awaiting expert confirmation',
    },
    'am': {
      'disease_confirmed': 'በሽታው ተረጋግጧል',
      'awaiting_analysis': 'ትንተና በመጠባበቅ ላይ',
      'saved_local_review_pending': 'የአካባቢ ውጤት ተቀምጧል፣ የሰርቨር ግምገማ በመጠባበቅ ላይ ነው',
      'unknown_disease': 'ያልታወቀ በሽታ',
      'ai_confidence': 'AI: {value}%',
      'on_device_result_pending': 'የመሣሪያ ውጤት ነው፣ የባለሙያ ማረጋገጫ በመጠባበቅ ላይ',
      'crop_plot_context': 'ሰብል #{crop} • ማሳ #{plot}',
      'no_device_result_upload': 'የመሣሪያ ውጤት የለም፣ ሲላክ ይተነተናል',
      'waiting_upload': 'ወደ ሰርቨር ለመላክ በመጠባበቅ ላይ',
      'upload_attempt_retry': 'የመላኪያ ሙከራ {count}፣ በቅርቡ እንደገና ይሞከራል',
      'remove_from_queue': 'ከወረፋ አስወግድ',
      'remove_scan_title': 'ስካኑን ማስወገድ?',
      'cancel': 'ሰርዝ',
      'remove': 'አስወግድ',
      'uploaded_review_pending': 'ተልኳል፣ ግምገማ በመጠባበቅ ላይ',
      'likely_issue_detected': 'ሊሆን የሚችል ችግኝ ተገኝቷል',
      'server_review_keep_local':
          'የሰርቨር ግምገማ አሁንም በመጠባበቅ ላይ ነው። የአካባቢ ውጤቱ ተጠብቆ ይታያል።',
      'treatment_ready': 'ህክምና ዝግጁ ነው',
      'awaiting_expert_review': 'የባለሙያ ግምገማን በመጠባበቅ ላይ። እስካሁን ሕክምና አይፈጽሙ።',
      'active_ingredient': 'ንጥረ ነገር',
      'dosage': 'መጠን',
      'protective_equipment': 'መከላከያ መሳሪያ (PPE)',
      'pre_harvest_interval': 'ከመከር በፊት የመጠበቂያ ጊዜ',
      're_entry_interval': 'ወደ ማሳ መመለሻ ጊዜ',
      'what_to_do_now': 'አሁን ምን ማድረግ እንዳለብዎ',
      'what_to_watch_for': 'ምን እንደሚከታተሉ',
      'prevention_next_season': 'ለሚቀጥለው ወቅት መከላከያ',
      'call_for_help_if': 'ይህን ካዩ እርዳታ ይጠይቁ',
      'important_notes': 'አስፈላጊ ማስታወሻዎች',
      'approved_registry_guidance': 'የተፈቀደ የሕክምና መዝገብ',
      'general_advisory_guidance': 'አጠቃላይ ምክር',
      'treatment_options': 'የተፈቀዱ የሕክምና አማራጮች',
      'natural_treatment': 'ተፈጥሯዊ ሕክምና',
      'modern_treatment': 'ዘመናዊ ሕክምና',
      'product': 'ምርት',
      'restrictions': 'ገደቦች',
      'application_timing': 'የመጠቀሚያ ጊዜ',
      'max_applications': 'ከፍተኛ የመድገም ብዛት',
      'next_step': 'ቀጣይ እርምጃ',
      'on_device_ai_result': 'የመሣሪያ AI ውጤት',
      'confidence_percent': 'እምነት: {value}%',
      'provisional_pending_title': 'ጊዜያዊ ውጤት፣ የባለሙያ ማረጋገጫ በመጠባበቅ ላይ',
      'provisional_pending_body':
          'ይህ ውጤት ከመሣሪያው AI ሞዴል የመጣ ነው። ከተላከ በኋላ በግብርና ባለሙያ ይገምገማል። በዚህ ውጤት ብቻ መሠረት የኬሚካል ሕክምና አይፈጽሙ።',
      'offline_treatment_guide': 'ኦፍላይን የሕክምና መመሪያ',
      'bundled_guide': 'አብሮ የተካተተ መመሪያ',
      'call_for_help_if_short': 'እርዳታ ይጠይቁ ካዩ',
      'expert_confirmed_diagnosis': 'ባለሙያው ምርመራውን አረጋግጧል',
      'ai_provisional_awaiting_expert': 'ጊዜያዊ የAI ውጤት፣ የባለሙያ ማረጋገጫ በመጠባበቅ ላይ',
    },
    'om': {
      'disease_confirmed': 'Dhukkubni mirkanaaʼeera',
      'awaiting_analysis': 'Xiinxalli eeggamaa jira',
      'saved_local_review_pending':
          'Bu’aan naannoo keessaa kuufameera; gamaaggamni sirna irraa eeggamaa jira',
      'unknown_disease': 'Dhukkuba hin beekamne',
      'ai_confidence': 'AI: {value}%',
      'on_device_result_pending':
          'Bu’aa bilbilaa irratti argame; mirkaneessi ogeessaa eeggamaa jira',
      'crop_plot_context': 'Midhaan #{crop} • Lafa #{plot}',
      'no_device_result_upload':
          'Bu’aan bilbilaa irratti hin argamne; yeroo ergamu ni xiinxalama',
      'waiting_upload': 'Sirnatti erguuf eeggamaa jira',
      'upload_attempt_retry':
          'Yaalii ergaa {count}; yeroo dhihoo keessatti irra deebi’ama',
      'remove_from_queue': 'Hiriira keessaa haqi',
      'remove_scan_title': 'Sakaanii kana haquu?',
      'cancel': 'Dhiisi',
      'remove': 'Haqi',
      'uploaded_review_pending': 'Ergameera; gamaaggamni eeggamaa jira',
      'likely_issue_detected': 'Rakkoon ta’uu malu ni mul’ate',
      'server_review_keep_local':
          'Gamaaggamni sirnaa amma iyyuu eeggamaa jira. Bu’aan naannoo keessaa akka mul’atu tursiifameera.',
      'treatment_ready': 'Qorichi qophaa’eera',
      'awaiting_expert_review':
          'Gamaaggama ogeessaa eeggachaa jira. Ammaaf yaalii hin raawwatinaa.',
      'active_ingredient': 'Wantaa hojii irra oolu',
      'dosage': 'Hamma',
      'protective_equipment': 'Meeshaa ittisa (PPE)',
      'pre_harvest_interval': 'Yeroo dura haamamuu',
      're_entry_interval': 'Yeroo deebi’anii seenan',
      'what_to_do_now': 'Amma maal gochuu qabdu',
      'what_to_watch_for': 'Maal hordofuu qabdu',
      'prevention_next_season': 'Yeroo itti aanuuf ittisa',
      'call_for_help_if':
          'Kanneen armaan gadii yoo argitan gargaarsa gaafadhaa',
      'important_notes': 'Yaadannoo barbaachisoo',
      'approved_registry_guidance': 'Galmee yaalii mirkanaaʼe',
      'general_advisory_guidance': 'Gorsa waliigalaa',
      'treatment_options': 'Filannoowwan yaalii mirkanaaʼan',
      'natural_treatment': 'Yaalii uumamaa',
      'modern_treatment': 'Yaalii ammayyaa',
      'product': 'Oomisha',
      'restrictions': 'Daangaa itti fayyadamaa',
      'application_timing': 'Yeroo itti fayyadamaa',
      'max_applications': 'Baayʼina irra deddeebii olaanaa',
      'next_step': 'Tarkaanfii itti aanu',
      'on_device_ai_result': 'Bu’aa AI bilbilaa',
      'confidence_percent': 'Amanamummaa: {value}%',
      'provisional_pending_title':
          'Bu’aa yeroo keessaa, mirkaneessi ogeessaa eeggamaa jira',
      'provisional_pending_body':
          'Bu’aan kun moodeela AI bilbilaa irraa dhufe. Erga ergamee booda ogeessa qonnaatiin ni ilaalama. Bu’aa kana qofaan irratti hundaa’uun qoricha keemikaalaa hin fayyadaminaa.',
      'offline_treatment_guide': 'Qajeelfama yaalii oflaayinii',
      'bundled_guide': 'Qajeelfama keessaa',
      'call_for_help_if_short': 'Gargaarsa gaafadhaa yoo',
      'expert_confirmed_diagnosis': 'Ogeessi bu’aa qorannoo mirkaneesseera',
      'ai_provisional_awaiting_expert':
          'Bu’aa AI yeroo keessaa, mirkaneessa ogeessaa eeggachaa jira',
    },
    'ti': {
      'disease_confirmed': 'ሕማሙ ተረጋጊጹ እዩ',
      'awaiting_analysis': 'ትንተና ይጽበ ኣሎ',
      'saved_local_review_pending': 'ናይ ኣካባቢ ውጽኢት ተቐሚጡ ኣሎ፣ ናይ ሰርቨር ግምገማ ይጽበ ኣሎ',
      'unknown_disease': 'ዘይተፈልጠ ሕማም',
      'ai_confidence': 'AI: {value}%',
      'on_device_result_pending': 'ውጽኢት ኣብ መሳርሒ እዩ፣ ናይ ባለሞያ ምርግጋጽ ይጽበ ኣሎ',
      'crop_plot_context': 'ዝርከብ #{crop} • ቦታ #{plot}',
      'no_device_result_upload': 'ውጽኢት ኣብ መሳርሒ ኣይተረኽበን፣ ምስ ተላእከ ክትንተን እዩ',
      'waiting_upload': 'ናብ ሰርቨር ምልኣኽ ይጽበ ኣሎ',
      'upload_attempt_retry': 'ሙከራ ምልኣኽ {count}፣ ቀልጢፉ ደጊሙ ክፍትን እዩ',
      'remove_from_queue': 'ካብ መስርዕ ኣውጽእ',
      'remove_scan_title': 'እዚ ስካን ትኣልዮ?',
      'cancel': 'ሰርዝ',
      'remove': 'ኣውጽእ',
      'uploaded_review_pending': 'ተላኢኹ ኣሎ፣ ግምገማ ይጽበ ኣሎ',
      'likely_issue_detected': 'ክኸውን ዝኽእል ጸገም ተረኺቡ',
      'server_review_keep_local':
          'ናይ ሰርቨር ግምገማ ክሳብ ሕጂ ይጽበ ኣሎ። ናይ ኣካባቢ ውጽኢት ክርአ ይቕጽል።',
      'treatment_ready': 'ሕክምና ድሉው እዩ',
      'awaiting_expert_review': 'ግምገማ ባለሞያ ይጽበ ኣሎ። ሕክምና ገና ኣይትፈጽሙ።',
      'active_ingredient': 'ንጥረ ነገር',
      'dosage': 'መጠን',
      'protective_equipment': 'መሳርሒ መከላኸሊ (PPE)',
      'pre_harvest_interval': 'ቅድሚ መከር ዝጽበ ግዜ',
      're_entry_interval': 'ዳግም ምእታው ግዜ',
      'what_to_do_now': 'ሕጂ እንታይ ክትገብሩ',
      'what_to_watch_for': 'እንታይ ክትከታተሉ',
      'prevention_next_season': 'ንዝቕጽል ወቕቲ መከላኸሊ',
      'call_for_help_if': 'እዚ እንተርኢኹም ሓገዝ ጸውዑ',
      'important_notes': 'ኣገደስቲ ምልክታት',
      'approved_registry_guidance': 'ዝተፈቐደ መዝገብ ሕክምና',
      'general_advisory_guidance': 'ሓፈሻዊ ምኽሪ',
      'treatment_options': 'ዝተፈቐዱ ኣማራጺታት ሕክምና',
      'natural_treatment': 'ተፈጥሯዊ ሕክምና',
      'modern_treatment': 'ዘመናዊ ሕክምና',
      'product': 'ምርቲ',
      'restrictions': 'ገደባት',
      'application_timing': 'ግዜ መተግበሪ',
      'max_applications': 'ዝለዓለ ቁጽሪ ምድጋም',
      'next_step': 'ቀጻሊ ስጉምቲ',
      'on_device_ai_result': 'ናይ መሳርሒ AI ውጽኢት',
      'confidence_percent': 'እምነት: {value}%',
      'provisional_pending_title': 'ግዜያዊ ውጽኢት፣ ምርግጋጽ ባለሞያ ይጽበ ኣሎ',
      'provisional_pending_body':
          'እዚ ውጽኢት ካብ ናይ መሳርሒ AI ሞዴል መጺኡ እዩ። ምስ ተላእከ ብናይ ሕርሻ ባለሞያ ክግምገም እዩ። በዚ ውጽኢት ጥራይ ተመርኲስኩም ኬሚካላዊ ሕክምና ኣይትግበሩ።',
      'offline_treatment_guide': 'ኦፍላይን መምርሒ ሕክምና',
      'bundled_guide': 'ኣብ መተግበሪ ዝተኻተተ መምርሒ',
      'call_for_help_if_short': 'ሓገዝ ጸውዑ እንተ',
      'expert_confirmed_diagnosis': 'ባለሞያ ምርመራ ኣረጋጊጹ እዩ',
      'ai_provisional_awaiting_expert': 'ግዝያዊ ውጽኢት AI፣ ምርግጋጽ ባለሞያ ይጽበ ኣሎ',
    },
  };
  final table = strings[lang] ?? strings['en']!;
  var value = table[key] ?? strings['en']![key] ?? key;
  params?.forEach((k, v) {
    value = value.replaceAll('{$k}', v);
  });
  return value;
}

//
// Pending queue card  (local scan not yet uploaded)
//

class _PendingQueueCard extends StatelessWidget {
  final PendingScanQueueEntry entry;
  final String lang;
  final VoidCallback onDelete;
  const _PendingQueueCard({
    required this.entry,
    required this.lang,
    required this.onDelete,
  });

  // Pull offline inference fields from scan_metadata
  String? get _offlineDiseaseName =>
      entry.scanMetadata?['offline_local_disease_name']?.toString().trim();
  String? get _offlineDiseaseKey =>
      entry.scanMetadata?['offline_local_disease_key']?.toString().trim();
  String? get _offlineSeverity =>
      entry.scanMetadata?['offline_local_severity']?.toString().trim();
  double? get _offlineConfidence {
    final v = entry.scanMetadata?['offline_local_confidence'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  bool get _hasOfflineResult =>
      _offlineDiseaseName != null && _offlineDiseaseName!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = DateTime.now().toUtc().difference(entry.capturedAtUtc);
    final ageLabel = age.inDays > 0
        ? '${age.inDays}d ago'
        : age.inHours > 0
        ? '${age.inHours}h ago'
        : '${age.inMinutes}m ago';

    final imageFile = File(entry.imagePath);
    final hasImage = imageFile.existsSync();

    // Resolve display name from offline result
    final rawName = _offlineDiseaseName ?? '';
    final canonicalKey = _offlineDiseaseKey ?? normalizeDiseaseKey(rawName);
    final localizedName = localizedDiseaseLabel(lang, canonicalKey);
    final displayName = localizedName.isNotEmpty
        ? localizedName
        : displayDiseaseLabel(canonicalKey).isNotEmpty
        ? displayDiseaseLabel(canonicalKey)
        : rawName;

    final isHealthy = isHealthyDiseaseKey(canonicalKey);
    final severity = _offlineSeverity ?? '';
    final confidence = _offlineConfidence;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _hasOfflineResult ? () => _openOfflineDetail(context) : null,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _hasOfflineResult
                  ? (isHealthy ? Colors.green.shade300 : Colors.orange.shade300)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: hasImage
                      ? Image.file(
                          imageFile,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 64,
                          height: 64,
                          color: Colors.grey.shade100,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.grey,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: upload badge + age
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 13,
                                  color: Color(0xFFD97706),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  L.t(lang, 'disease_history_pending_badge'),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            ageLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Disease name — the most important thing
                      if (_hasOfflineResult) ...[
                        Text(
                          displayName.isNotEmpty
                              ? displayName
                              : _dh(lang, 'unknown_disease'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isHealthy
                                ? Colors.green.shade800
                                : Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (severity.isNotEmpty)
                              _SeverityChip(severity: severity),
                            if (confidence != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _dh(
                                    lang,
                                    'ai_confidence',
                                    params: {
                                      'value': (confidence * 100)
                                          .toStringAsFixed(0),
                                    },
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Provisional notice
                        Text(
                          _dh(lang, 'on_device_result_pending'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.amber.shade800,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ] else ...[
                        // No offline result — show crop/plot context
                        Text(
                          _dh(
                            lang,
                            'crop_plot_context',
                            params: {
                              'crop': '${entry.cropId}',
                              'plot': '${entry.plotId}',
                            },
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dh(lang, 'no_device_result_upload'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],

                      const SizedBox(height: 4),
                      // Upload status
                      Text(
                        entry.attempts == 0
                            ? _dh(lang, 'waiting_upload')
                            : _dh(
                                lang,
                                'upload_attempt_retry',
                                params: {'count': '${entry.attempts}'},
                              ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Delete button
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  tooltip: _dh(lang, 'remove_from_queue'),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(_dh(lang, 'remove_scan_title')),
                        content: Text(
                          L.t(lang, 'disease_pending_scan_delete_confirm'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(_dh(lang, 'cancel')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              _dh(lang, 'remove'),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) onDelete();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openOfflineDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OfflinePendingDetailSheet(entry: entry, lang: lang),
    );
  }
}

class _SyncedLocalCard extends StatelessWidget {
  final LocalScanHistoryEntry entry;
  final String lang;
  final VoidCallback onDelete;

  const _SyncedLocalCard({
    required this.entry,
    required this.lang,
    required this.onDelete,
  });

  PendingScanQueueEntry get _detailEntry => PendingScanQueueEntry(
    queueId: entry.submissionId,
    plotId: entry.plotId,
    cropId: entry.cropId,
    plantingId: entry.plantingId,
    imagePath: entry.imagePath,
    capturedAtUtc: entry.capturedAtUtc,
    attempts: 0,
    nextRetryAtUtc: entry.syncedAtUtc,
    createdAtUtc: entry.capturedAtUtc,
    scanMetadata: entry.scanMetadata,
  );

  String get _offlineDiseaseName =>
      entry.scanMetadata?['offline_local_disease_name']?.toString().trim() ??
      '';

  String get _offlineDiseaseKey {
    final raw = entry.scanMetadata?['offline_local_disease_key']
        ?.toString()
        .trim();
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    return normalizeDiseaseKey(_offlineDiseaseName);
  }

  String? get _offlineSeverity =>
      entry.scanMetadata?['offline_local_severity']?.toString().trim();

  double? get _offlineConfidence {
    final value = entry.scanMetadata?['offline_local_confidence'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageFile = File(entry.imagePath);
    final hasImage = imageFile.existsSync();
    final localizedName = localizedDiseaseLabel(lang, _offlineDiseaseKey);
    final displayName = localizedName.isNotEmpty
        ? localizedName
        : (displayDiseaseLabel(_offlineDiseaseKey).isNotEmpty
              ? displayDiseaseLabel(_offlineDiseaseKey)
              : _offlineDiseaseName);
    final isHealthy = isHealthyDiseaseKey(_offlineDiseaseKey);
    final confidence = _offlineConfidence;
    final syncedLabel = DateFormat(
      'MMM d, HH:mm',
    ).format(entry.syncedAtUtc.toLocal());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) =>
                _OfflinePendingDetailSheet(entry: _detailEntry, lang: lang),
          );
        },
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: const Color(0xFF2563EB).withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: hasImage
                      ? Image.file(
                          imageFile,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 64,
                          height: 64,
                          color: Colors.grey.shade100,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.grey,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.sync_rounded,
                                  size: 13,
                                  color: Color(0xFF1D4ED8),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _dh(lang, 'uploaded_review_pending'),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            syncedLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        displayName.isNotEmpty
                            ? displayName
                            : _dh(lang, 'likely_issue_detected'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isHealthy
                              ? Colors.green.shade800
                              : Colors.grey.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          if ((_offlineSeverity ?? '').isNotEmpty)
                            _SeverityChip(severity: _offlineSeverity!),
                          if (confidence != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _dh(
                                  lang,
                                  'ai_confidence',
                                  params: {
                                    'value': (confidence * 100).toStringAsFixed(
                                      0,
                                    ),
                                  },
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dh(lang, 'server_review_keep_local'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.blue.shade800,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  tooltip: _dh(lang, 'delete_local_history'),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(_dh(lang, 'delete_local_history_title')),
                        content: Text(_dh(lang, 'delete_local_history_body')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(_dh(lang, 'cancel')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              _dh(lang, 'remove'),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      onDelete();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//
// Server report card
//

class _ReportCard extends StatelessWidget {
  final DiseaseReportModel report;
  final String lang;
  final VoidCallback onTap;
  const _ReportCard({
    required this.report,
    required this.lang,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _reportStyle(report);
    final imageUrl = report.originalImageUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: style.borderColor.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasImage) ...[
                  _HistoryNetworkThumb(url: imageUrl, width: 72, height: 72),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status badge + date
                      Row(
                        children: [
                          _StatusBadge(
                            label: style.badgeLabel,
                            color: style.badgeColor,
                            icon: style.badgeIcon,
                          ),
                          const Spacer(),
                          Text(
                            _formatDate(report.reportedAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Disease name  the most important thing for a farmer
                      Text(
                        _displayName(report, lang),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: style.nameColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _InferenceSourceStrip(report: report, lang: lang),
                      const SizedBox(height: 8),
                      // Severity + confidence
                      Row(
                        children: [
                          if (report.severity.isNotEmpty)
                            _SeverityChip(severity: report.severity),
                          if (report.confidenceScore != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              _dh(
                                lang,
                                'ai_confidence',
                                params: {
                                  'value': (report.confidenceScore! * 100)
                                      .toStringAsFixed(0),
                                },
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (_hasTreatment(report))
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.medical_services_outlined,
                                  size: 14,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _dh(lang, 'treatment_ready'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (_isPendingReview(report)) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.hourglass_top_rounded,
                                size: 14,
                                color: Colors.amber.shade800,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _dh(lang, 'awaiting_expert_review'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          L.t(lang, 'disease_history_entry_trailing'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isPendingReview(DiseaseReportModel r) {
    final s = r.status.toLowerCase();
    return s == 'new' || s == 'reviewing' || s == 'processing' || s == 'queued';
  }

  bool _hasTreatment(DiseaseReportModel r) {
    final g = r.treatmentGuidance;
    if (g == null) return false;
    return g.canShowTreatmentDetails &&
        (g.activeIngredient?.isNotEmpty == true || g.actions.isNotEmpty);
  }

  String _displayName(DiseaseReportModel r, String lang) =>
      _resolvedFindingDisplayName(r, lang);

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return DateFormat('dd MMM yyyy').format(local);
  }

  _ReportStyle _reportStyle(DiseaseReportModel r) {
    final s = r.status.toLowerCase();
    final isHealthy = isHealthyDiseaseKey(r.resolvedCanonicalDiseaseName);

    if (isHealthy) {
      return _ReportStyle(
        badgeLabel: 'Healthy',
        badgeColor: Colors.green,
        badgeIcon: Icons.check_circle_outline,
        borderColor: Colors.green,
        nameColor: Colors.green.shade800,
      );
    }
    if (s == 'new' || s == 'reviewing' || s == 'processing' || s == 'queued') {
      return _ReportStyle(
        badgeLabel: 'Under Review',
        badgeColor: Colors.amber.shade700,
        badgeIcon: Icons.pending_outlined,
        borderColor: Colors.amber,
        nameColor: Colors.grey.shade800,
      );
    }
    if (s == 'confirmed' ||
        s == 'completed' ||
        s == 'verified' ||
        s == 'done' ||
        s == 'resolved') {
      return _ReportStyle(
        badgeLabel: 'Confirmed',
        badgeColor: Colors.red.shade700,
        badgeIcon: Icons.verified_outlined,
        borderColor: Colors.red,
        nameColor: Colors.red.shade800,
      );
    }
    if (s == 'rejected' || s == 'dismissed') {
      return _ReportStyle(
        badgeLabel: 'Not Confirmed',
        badgeColor: Colors.grey.shade600,
        badgeIcon: Icons.cancel_outlined,
        borderColor: Colors.grey,
        nameColor: Colors.grey.shade700,
      );
    }
    return _ReportStyle(
      badgeLabel: r.status,
      badgeColor: Colors.blueGrey,
      badgeIcon: Icons.info_outline,
      borderColor: Colors.blueGrey,
      nameColor: Colors.grey.shade800,
    );
  }
}

class _ReportStyle {
  final String badgeLabel;
  final Color badgeColor;
  final IconData badgeIcon;
  final Color borderColor;
  final Color nameColor;
  const _ReportStyle({
    required this.badgeLabel,
    required this.badgeColor,
    required this.badgeIcon,
    required this.borderColor,
    required this.nameColor,
  });
}

class _InferenceSourceStrip extends StatelessWidget {
  final DiseaseReportModel report;
  final String lang;

  const _InferenceSourceStrip({required this.report, required this.lang});

  @override
  Widget build(BuildContext context) {
    final finding = report.finding;
    final source = switch (finding.stage) {
      DiseaseFindingStage.verified => (
        label: _dh(lang, 'source_expert'),
        icon: Icons.verified_user_outlined,
        color: Colors.green.shade700,
      ),
      DiseaseFindingStage.inferred => (
        label: _dh(lang, 'source_server_ai'),
        icon: Icons.cloud_done_outlined,
        color: Colors.blue.shade700,
      ),
      DiseaseFindingStage.provisional => (
        label: _dh(lang, 'source_on_device'),
        icon: Icons.offline_bolt_outlined,
        color: Colors.orange.shade800,
      ),
      DiseaseFindingStage.likelyIssue => (
        label: _dh(lang, 'source_likely_issue'),
        icon: Icons.troubleshoot_outlined,
        color: Colors.blueGrey.shade700,
      ),
      DiseaseFindingStage.pending => (
        label: _dh(lang, 'source_awaiting'),
        icon: Icons.hourglass_top_rounded,
        color: Colors.grey.shade700,
      ),
    };
    final offlineName = _localizedDiseaseNameFromRaw(
      lang,
      report.provisionalDiseaseName,
      report.provisionalCanonicalDiseaseName,
    );
    final serverName = _localizedDiseaseNameFromRaw(
      lang,
      report.inferredDiseaseName,
      report.inferredCanonicalDiseaseName,
    );
    final resolved = _resolvedFindingDisplayName(report, lang);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _StatusBadge(
              label: source.label,
              color: source.color,
              icon: source.icon,
            ),
            if (offlineName.isNotEmpty && offlineName != resolved)
              _CompactSourceLabel(
                label: _dh(lang, 'offline_result_label'),
                value: offlineName,
                color: Colors.orange.shade800,
              ),
            if (serverName.isNotEmpty && serverName != resolved)
              _CompactSourceLabel(
                label: _dh(lang, 'server_result_label'),
                value: serverName,
                color: Colors.blue.shade700,
              ),
          ],
        ),
      ],
    );
  }
}

class _CompactSourceLabel extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _CompactSourceLabel({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        '$label: $value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

//
// Status badge
//

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

//
// Severity chip
//

class _SeverityChip extends StatelessWidget {
  final String severity;
  const _SeverityChip({required this.severity});

  @override
  Widget build(BuildContext context) {
    final s = severity.toLowerCase();
    final color = s == 'critical'
        ? Colors.red.shade900
        : s == 'high'
        ? Colors.red.shade700
        : s == 'medium'
        ? Colors.orange.shade700
        : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

//
// Empty state
//

class _EmptyState extends StatelessWidget {
  final String lang;
  const _EmptyState({required this.lang});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              _dh(lang, 'disease_history_empty_any'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

//
// Offline banner
//

class _OfflineBanner extends StatelessWidget {
  final String lang;
  const _OfflineBanner({required this.lang});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.blue.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                L.t(lang, 'disease_history_showing_saved_history'),
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

//
// Error banner
//

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(L.t(LanguageStore.notifier.value, 'retry')),
            ),
          ],
        ),
      ),
    );
  }
}

//
// Detail bottom sheet
//

class _ReportDetailSheet extends StatefulWidget {
  final DiseaseReportModel report;
  final String lang;
  const _ReportDetailSheet({required this.report, required this.lang});

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
  DiseaseTreatmentGuidance? _offlineGuidance;
  bool _loadingGuidance = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadOfflineGuidance();
  }

  Future<void> _maybeLoadOfflineGuidance() async {
    // Only load offline guidance if server did not provide confirmed treatment
    final g = widget.report.treatmentGuidance;
    if (g != null && g.canShowTreatmentDetails) return;

    final key = widget.report.resolvedCanonicalDiseaseName;
    if (isPendingDiseaseKey(key)) return;

    setState(() => _loadingGuidance = true);
    try {
      final guidance = await OfflineTreatmentGuidanceService.instance
          .guidanceForDiseaseLabel(key, cropName: key.split('_').first);
      if (mounted)
        setState(() {
          _offlineGuidance = guidance;
          _loadingGuidance = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingGuidance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final lang = widget.lang;
    final screenH = MediaQuery.of(context).size.height;

    // Determine which guidance to show
    final serverGuidance = report.treatmentGuidance;
    final showServerTreatment =
        serverGuidance != null && serverGuidance.canShowTreatmentDetails;
    final showOfflineTreatment =
        !showServerTreatment &&
        _offlineGuidance != null &&
        _offlineGuidance!.canShowTreatmentDetails;
    final guidance = showServerTreatment
        ? serverGuidance
        : (showOfflineTreatment ? _offlineGuidance : null);

    final isPending = _isPendingStatus(report.status);
    final isRejected = _isRejectedStatus(report.status);
    final isHealthy = isHealthyDiseaseKey(report.resolvedCanonicalDiseaseName);
    final primaryImage = _primaryCaseImage(report, lang);
    return Container(
      height: screenH * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  //  Header
                  _DetailHeader(
                    report: report,
                    lang: lang,
                    primaryImage: primaryImage,
                  ),
                  const SizedBox(height: 14),
                  _InferenceEvidencePanel(report: report, lang: lang),
                  const SizedBox(height: 20),

                  //  Pending review notice
                  if (isPending && !isHealthy) _PendingReviewNotice(lang: lang),

                  //  Healthy notice
                  if (isHealthy) _HealthyNotice(lang: lang),

                  //  Rejected notice
                  if (isRejected) _RejectedNotice(report: report, lang: lang),

                  //  Expert review summary
                  if (!isPending &&
                      !isRejected &&
                      !isHealthy &&
                      report.reviewedAt != null)
                    _ReviewSummary(report: report, lang: lang),

                  //  Treatment section
                  if (!isPending && !isRejected && !isHealthy) ...[
                    if (_loadingGuidance)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (guidance != null)
                      _TreatmentSection(
                        guidance: guidance,
                        isOffline: !showServerTreatment,
                        lang: lang,
                      )
                    else
                      _NoTreatmentYet(lang: lang),
                  ],

                  if (primaryImage != null)
                    _CasePhotoSection(image: primaryImage),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isPendingStatus(String s) {
    final n = s.toLowerCase();
    return n == 'new' || n == 'reviewing' || n == 'processing' || n == 'queued';
  }

  bool _isRejectedStatus(String s) {
    final n = s.toLowerCase();
    return n == 'rejected' || n == 'dismissed';
  }
}

class _InferenceEvidencePanel extends StatelessWidget {
  final DiseaseReportModel report;
  final String lang;

  const _InferenceEvidencePanel({required this.report, required this.lang});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offlineName = _localizedDiseaseNameFromRaw(
      lang,
      report.provisionalDiseaseName,
      report.provisionalCanonicalDiseaseName,
    );
    final serverName = _localizedDiseaseNameFromRaw(
      lang,
      report.inferredDiseaseName,
      report.inferredCanonicalDiseaseName,
    );
    final expertName = _localizedDiseaseNameFromRaw(
      lang,
      report.verifiedDiseaseName,
      report.verifiedCanonicalDiseaseName,
    );
    final resolvedExpertName =
        expertName.isNotEmpty || !report.isConfirmedWorkflowState
        ? expertName
        : _resolvedFindingDisplayName(report, lang);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7C5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route_outlined,
                size: 18,
                color: Colors.green.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _dh(lang, 'inference_chain_title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1F2D16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InferenceDecisionRow(
            icon: Icons.phone_android_outlined,
            color: Colors.orange.shade800,
            label: _dh(lang, 'offline_result_label'),
            value: offlineName.isEmpty
                ? _dh(lang, 'not_available')
                : offlineName,
            supportingText: _dh(lang, 'source_on_device'),
          ),
          const SizedBox(height: 10),
          _InferenceDecisionRow(
            icon: Icons.cloud_done_outlined,
            color: Colors.blue.shade700,
            label: _dh(lang, 'server_result_label'),
            value: serverName.isEmpty
                ? _dh(lang, 'no_server_ai_yet')
                : serverName,
            supportingText: report.confidenceScore == null
                ? _dh(lang, 'source_server_ai')
                : _dh(
                    lang,
                    'ai_confidence',
                    params: {
                      'value': (report.confidenceScore! * 100).toStringAsFixed(
                        0,
                      ),
                    },
                  ),
          ),
          const SizedBox(height: 10),
          _InferenceDecisionRow(
            icon: Icons.verified_user_outlined,
            color: Colors.green.shade800,
            label: _dh(lang, 'expert_result_label'),
            value: resolvedExpertName.isEmpty
                ? _dh(lang, 'no_expert_decision_yet')
                : resolvedExpertName,
            supportingText: report.reviewedAt == null
                ? _dh(lang, 'source_expert')
                : DateFormat(
                    'dd MMM yyyy, HH:mm',
                  ).format(report.reviewedAt!.toLocal()),
          ),
        ],
      ),
    );
  }
}

class _InferenceDecisionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String supportingText;

  const _InferenceDecisionRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.supportingText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade900,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                supportingText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

//
// Detail header
//

class _DetailHeader extends StatelessWidget {
  final DiseaseReportModel report;
  final String lang;
  final _CaseImagePreview? primaryImage;
  const _DetailHeader({
    required this.report,
    required this.lang,
    required this.primaryImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finding = report.finding;
    final isHealthy = isHealthyDiseaseKey(report.resolvedCanonicalDiseaseName);
    final isConfirmed = report.isConfirmedWorkflowState;
    final name = _resolvedFindingDisplayName(report, lang);

    final nameColor = isHealthy
        ? Colors.green.shade800
        : isConfirmed
        ? Colors.red.shade800
        : Colors.grey.shade800;
    final imageUrl = primaryImage?.url.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Confirmed / provisional label
        if (isConfirmed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _dh(lang, 'expert_confirmed_diagnosis'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          )
        else if (finding.isInferred || finding.isProvisional)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _dh(lang, 'ai_provisional_awaiting_expert'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.amber.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage) ...[
              _ZoomableProtectedImage(
                url: imageUrl,
                width: 116,
                height: 116,
                radius: 16,
                fit: BoxFit.cover,
                heroLabel: primaryImage?.title ?? name,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: nameColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (report.severity.isNotEmpty)
                        _SeverityChip(severity: report.severity),
                      if (report.confidenceScore != null)
                        _MetaChip(
                          icon: Icons.analytics_outlined,
                          label: _dh(
                            lang,
                            'ai_confidence',
                            params: {
                              'value': (report.confidenceScore! * 100)
                                  .toStringAsFixed(0),
                            },
                          ),
                        ),
                      _MetaChip(
                        icon: Icons.calendar_today_outlined,
                        label: DateFormat(
                          'dd MMM yyyy',
                        ).format(report.reportedAt.toLocal()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HistoryNetworkThumb extends StatelessWidget {
  final String? url;
  final double width;
  final double height;

  const _HistoryNetworkThumb({
    required this.url,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return _ProtectedImageBox(
      url: url,
      width: width,
      height: height,
      radius: 12,
      fit: BoxFit.cover,
      fallbackIcon: Icons.image_not_supported_outlined,
    );
  }
}

class _CaseImagePreview {
  final String url;
  final String title;

  const _CaseImagePreview({required this.url, required this.title});
}

_CaseImagePreview? _primaryCaseImage(DiseaseReportModel report, String lang) {
  for (final item in report.evidence) {
    final url = item.url?.trim();
    if (item.isImage && url != null && url.isNotEmpty) {
      return _CaseImagePreview(
        url: url,
        title: L.t(lang, 'disease_expert_evidence'),
      );
    }
  }

  final original = report.originalImageUrl?.trim();
  if (original != null && original.isNotEmpty) {
    return _CaseImagePreview(
      url: original,
      title: L.t(lang, 'disease_original_photo'),
    );
  }

  return null;
}

class _ZoomableProtectedImage extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final double radius;
  final String heroLabel;
  final BoxFit fit;
  final IconData fallbackIcon;

  const _ZoomableProtectedImage({
    required this.url,
    required this.width,
    required this.height,
    required this.radius,
    required this.heroLabel,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.image_not_supported_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final raw = url?.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: raw == null || raw.isEmpty
          ? null
          : () {
              showDialog<void>(
                context: context,
                builder: (dialogContext) =>
                    _ZoomableImageDialog(title: heroLabel, url: raw),
              );
            },
      child: _ProtectedImageBox(
        url: url,
        width: width,
        height: height,
        radius: radius,
        fit: fit,
        fallbackIcon: fallbackIcon,
      ),
    );
  }
}

class _ProtectedImageBox extends StatefulWidget {
  final String? url;
  final double width;
  final double height;
  final double radius;
  final BoxFit fit;
  final IconData fallbackIcon;

  const _ProtectedImageBox({
    required this.url,
    required this.width,
    required this.height,
    this.radius = 12,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.broken_image_outlined,
  });

  @override
  State<_ProtectedImageBox> createState() => _ProtectedImageBoxState();
}

class _ProtectedImageBoxState extends State<_ProtectedImageBox> {
  Future<Map<String, String>?>? _headersFuture;

  @override
  void initState() {
    super.initState();
    _headersFuture = _loadHeaders();
  }

  @override
  void didUpdateWidget(covariant _ProtectedImageBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _headersFuture = _loadHeaders();
    }
  }

  Future<Map<String, String>?> _loadHeaders() async {
    final raw = widget.url?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return await ApiClient.mediaHeaders();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.url?.trim();
    if (raw == null || raw.isEmpty) {
      return _thumbFallback(
        widget.width,
        widget.height,
        widget.radius,
        widget.fallbackIcon,
      );
    }
    if (_isDataImageUri(raw)) {
      final bytes = _decodeDataImageUri(raw);
      if (bytes == null || bytes.isEmpty) {
        return _thumbFallback(
          widget.width,
          widget.height,
          widget.radius,
          widget.fallbackIcon,
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return _thumbFallback(
              widget.width,
              widget.height,
              widget.radius,
              widget.fallbackIcon,
            );
          },
        ),
      );
    }
    return FutureBuilder<Map<String, String>?>(
      future: _headersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final headers = snapshot.data;
        if (headers == null) {
          return _thumbFallback(
            widget.width,
            widget.height,
            widget.radius,
            widget.fallbackIcon,
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: Image.network(
            raw,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
            headers: headers,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              return Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(widget.radius),
                ),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return _thumbFallback(
                widget.width,
                widget.height,
                widget.radius,
                widget.fallbackIcon,
              );
            },
          ),
        );
      },
    );
  }

  Widget _thumbFallback(
    double width,
    double height,
    double radius,
    IconData icon,
  ) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.grey),
    );
  }

  bool _isDataImageUri(String value) => value.startsWith('data:image/');

  Uint8List? _decodeDataImageUri(String value) {
    final commaIndex = value.indexOf(',');
    if (commaIndex <= 0 || commaIndex >= value.length - 1) {
      return null;
    }
    try {
      return base64Decode(value.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade600),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

//
// Notices
//

class _PendingReviewNotice extends StatelessWidget {
  final String lang;
  const _PendingReviewNotice({required this.lang});

  @override
  Widget build(BuildContext context) {
    return _NoticeBox(
      color: Colors.amber,
      icon: Icons.hourglass_top_rounded,
      title: L.t(lang, 'disease_notice_pending_title'),
      body: L.t(lang, 'disease_notice_pending_body'),
    );
  }
}

class _HealthyNotice extends StatelessWidget {
  final String lang;
  const _HealthyNotice({required this.lang});

  @override
  Widget build(BuildContext context) {
    return _NoticeBox(
      color: Colors.green,
      icon: Icons.check_circle_outline,
      title: L.t(lang, 'disease_notice_healthy_title'),
      body: L.t(lang, 'disease_notice_healthy_body'),
    );
  }
}

class _RejectedNotice extends StatelessWidget {
  final DiseaseReportModel report;
  final String lang;
  const _RejectedNotice({required this.report, required this.lang});

  @override
  Widget build(BuildContext context) {
    final reason = report.decisionComment?.isNotEmpty == true
        ? report.decisionComment!
        : L.t(lang, 'disease_notice_rejected_default_body');
    return _NoticeBox(
      color: Colors.grey,
      icon: Icons.cancel_outlined,
      title: L.t(lang, 'disease_notice_rejected_title'),
      body: reason,
    );
  }
}

class _NoTreatmentYet extends StatelessWidget {
  final String lang;
  const _NoTreatmentYet({required this.lang});

  @override
  Widget build(BuildContext context) {
    return _NoticeBox(
      color: Colors.blueGrey,
      icon: Icons.medical_services_outlined,
      title: L.t(lang, 'disease_notice_no_treatment_title'),
      body: L.t(lang, 'disease_notice_no_treatment_body'),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;
  const _NoticeBox({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade800,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

//
// Review summary (expert decision)
//

class _ReviewSummary extends StatelessWidget {
  final DiseaseReportModel report;
  final String lang;
  const _ReviewSummary({required this.report, required this.lang});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                L.t(lang, 'disease_review_summary'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (report.reviewedAt != null)
            _ReviewRow(
              label: L.t(lang, 'disease_reviewed_at'),
              value: DateFormat(
                'dd MMM yyyy, HH:mm',
              ).format(report.reviewedAt!.toLocal()),
            ),
          if (report.verifiedAt != null)
            _ReviewRow(
              label: L.t(lang, 'disease_verified_at'),
              value: DateFormat(
                'dd MMM yyyy, HH:mm',
              ).format(report.verifiedAt!.toLocal()),
            ),
          if (report.decisionReasonCode?.isNotEmpty == true)
            _ReviewRow(
              label: L.t(lang, 'disease_review_reason'),
              value: report.decisionReasonCode!,
            ),
          if (report.decisionComment?.isNotEmpty == true)
            _ReviewRow(
              label: L.t(lang, 'disease_review_note'),
              value: report.decisionComment!,
            ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//
// Treatment section   the core farmer-facing content
//

class _TreatmentSection extends StatelessWidget {
  final DiseaseTreatmentGuidance guidance;
  final bool isOffline;
  final String lang;
  const _TreatmentSection({
    required this.guidance,
    required this.isOffline,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.medical_services_outlined,
                color: Colors.green.shade700,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L.t(lang, 'treatment_plan'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (isOffline)
                    Text(
                      L.t(lang, 'offline_guidance_verify'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Headline / summary
        if (guidance.headline.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Text(
              guidance.headline,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.green.shade900,
              ),
            ),
          ),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: guidance.source == 'database_registry'
                ? Colors.green.shade50
                : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: guidance.source == 'database_registry'
                  ? Colors.green.shade200
                  : Colors.amber.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                guidance.source == 'database_registry'
                    ? Icons.verified_outlined
                    : Icons.info_outline,
                color: guidance.source == 'database_registry'
                    ? Colors.green.shade800
                    : Colors.amber.shade900,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  guidance.source == 'database_registry'
                      ? _dh(lang, 'approved_registry_guidance')
                      : _dh(lang, 'general_advisory_guidance'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: guidance.source == 'database_registry'
                        ? Colors.green.shade900
                        : Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (guidance.treatmentOptions.isNotEmpty) ...[
          _TreatmentGroupHeader(
            icon: Icons.fact_check_outlined,
            label: _dh(lang, 'treatment_options'),
            color: Colors.green.shade800,
          ),
          const SizedBox(height: 8),
          ...guidance.treatmentOptions.map(
            (option) => _TreatmentOptionCard(option: option, lang: lang),
          ),
          const SizedBox(height: 14),
        ],

        //  Chemical inputs
        if (guidance.activeIngredient?.isNotEmpty == true ||
            guidance.dosage?.isNotEmpty == true ||
            guidance.ppe?.isNotEmpty == true ||
            guidance.preHarvestInterval?.isNotEmpty == true ||
            guidance.reEntryInterval?.isNotEmpty == true) ...[
          _TreatmentGroupHeader(
            icon: Icons.science_outlined,
            label: L.t(lang, 'chemical_inputs'),
            color: Colors.red.shade700,
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Column(
              children: [
                if (guidance.activeIngredient?.isNotEmpty == true)
                  _ChemicalRow(
                    icon: Icons.biotech_outlined,
                    label: _dh(lang, 'active_ingredient'),
                    value: guidance.activeIngredient!,
                    highlight: true,
                  ),
                if (guidance.dosage?.isNotEmpty == true)
                  _ChemicalRow(
                    icon: Icons.water_drop_outlined,
                    label: _dh(lang, 'dosage'),
                    value: guidance.dosage!,
                  ),
                if (guidance.ppe?.isNotEmpty == true)
                  _ChemicalRow(
                    icon: Icons.security_outlined,
                    label: _dh(lang, 'protective_equipment'),
                    value: guidance.ppe!,
                    isWarning: true,
                  ),
                if (guidance.preHarvestInterval?.isNotEmpty == true)
                  _ChemicalRow(
                    icon: Icons.event_available_outlined,
                    label: _dh(lang, 'pre_harvest_interval'),
                    value: guidance.preHarvestInterval!,
                    isWarning: true,
                  ),
                if (guidance.reEntryInterval?.isNotEmpty == true)
                  _ChemicalRow(
                    icon: Icons.timer_outlined,
                    label: _dh(lang, 're_entry_interval'),
                    value: guidance.reEntryInterval!,
                    isWarning: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        //  Actions
        if (guidance.actions.isNotEmpty) ...[
          _TreatmentGroupHeader(
            icon: Icons.checklist_outlined,
            label: _dh(lang, 'what_to_do_now'),
            color: Colors.blue.shade700,
          ),
          const SizedBox(height: 8),
          ...guidance.actions.map(
            (a) => _BulletItem(text: a, color: Colors.blue.shade700),
          ),
          const SizedBox(height: 14),
        ],

        //  Monitoring
        if (guidance.monitoring.isNotEmpty) ...[
          _TreatmentGroupHeader(
            icon: Icons.visibility_outlined,
            label: _dh(lang, 'what_to_watch_for'),
            color: Colors.teal.shade700,
          ),
          const SizedBox(height: 8),
          ...guidance.monitoring.map(
            (m) => _BulletItem(text: m, color: Colors.teal.shade700),
          ),
          const SizedBox(height: 14),
        ],

        //  Prevention
        if (guidance.prevention.isNotEmpty) ...[
          _TreatmentGroupHeader(
            icon: Icons.shield_outlined,
            label: _dh(lang, 'prevention_next_season'),
            color: Colors.green.shade700,
          ),
          const SizedBox(height: 8),
          ...guidance.prevention.map(
            (p) => _BulletItem(text: p, color: Colors.green.shade700),
          ),
          const SizedBox(height: 14),
        ],

        //  Escalate if
        if (guidance.escalateIf.isNotEmpty) ...[
          _TreatmentGroupHeader(
            icon: Icons.warning_amber_rounded,
            label: _dh(lang, 'call_for_help_if'),
            color: Colors.orange.shade800,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              children: guidance.escalateIf
                  .map(
                    (e) => _BulletItem(text: e, color: Colors.orange.shade800),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
        ],

        //  Notes
        if (guidance.notes.isNotEmpty) ...[
          _TreatmentGroupHeader(
            icon: Icons.info_outline,
            label: _dh(lang, 'important_notes'),
            color: Colors.grey.shade700,
          ),
          const SizedBox(height: 8),
          ...guidance.notes.map(
            (n) => _BulletItem(text: n, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 14),
        ],

        // Next step
        if (guidance.nextStep.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.indigo.shade700,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dh(lang, 'next_step'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.indigo.shade700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        guidance.nextStep,
                        style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TreatmentOptionCard extends StatelessWidget {
  final DiseaseTreatmentOption option;
  final String lang;

  const _TreatmentOptionCard({required this.option, required this.lang});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = option.title.isNotEmpty
        ? option.title
        : _dh(lang, 'treatment_options');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color(0xFFFFFCF0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.eco_outlined,
                  color: Colors.green.shade800,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.green.shade900,
                  ),
                ),
              ),
            ],
          ),
          if (option.summary?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              option.summary!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade800,
                height: 1.45,
              ),
            ),
          ],
          if (option.naturalTreatment?.isNotEmpty == true)
            _OptionBlock(
              icon: Icons.spa_outlined,
              label: _dh(lang, 'natural_treatment'),
              value: option.naturalTreatment!,
              color: Colors.green.shade700,
            ),
          if (option.modernTreatment?.isNotEmpty == true)
            _OptionBlock(
              icon: Icons.science_outlined,
              label: _dh(lang, 'modern_treatment'),
              value: option.modernTreatment!,
              color: Colors.blue.shade700,
            ),
          if (option.productName?.isNotEmpty == true)
            _OptionFact(
              label: _dh(lang, 'product'),
              value: option.productName!,
            ),
          if (option.activeIngredient?.isNotEmpty == true)
            _OptionFact(
              label: _dh(lang, 'active_ingredient'),
              value: option.activeIngredient!,
            ),
          if (option.dosage?.isNotEmpty == true)
            _OptionFact(label: _dh(lang, 'dosage'), value: option.dosage!),
          if (option.applicationTiming?.isNotEmpty == true)
            _OptionFact(
              label: _dh(lang, 'application_timing'),
              value: option.applicationTiming!,
            ),
          if (option.preHarvestIntervalDays != null)
            _OptionFact(
              label: _dh(lang, 'pre_harvest_interval'),
              value: '${option.preHarvestIntervalDays} days',
            ),
          if (option.reEntryIntervalHours != null)
            _OptionFact(
              label: _dh(lang, 're_entry_interval'),
              value: '${option.reEntryIntervalHours} hours',
            ),
          if (option.maxApplications != null)
            _OptionFact(
              label: _dh(lang, 'max_applications'),
              value: option.maxApplications.toString(),
            ),
          if (option.ppe?.isNotEmpty == true)
            _OptionFact(
              label: _dh(lang, 'protective_equipment'),
              value: option.ppe!,
            ),
          if (option.restrictions?.isNotEmpty == true)
            _OptionBlock(
              icon: Icons.warning_amber_rounded,
              label: _dh(lang, 'restrictions'),
              value: option.restrictions!,
              color: Colors.orange.shade800,
            ),
        ],
      ),
    );
  }
}

class _OptionBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _OptionBlock({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade900,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionFact extends StatelessWidget {
  final String label;
  final String value;

  const _OptionFact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade900,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TreatmentGroupHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _TreatmentGroupHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _ChemicalRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;
  final bool isWarning;
  const _ChemicalRow({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = isWarning
        ? Colors.orange.shade800
        : Colors.grey.shade700;
    final valueColor = highlight ? Colors.red.shade900 : Colors.grey.shade900;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: labelColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  final String text;
  final Color color;
  const _BulletItem({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade800,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CasePhotoSection extends StatelessWidget {
  final _CaseImagePreview image;

  const _CasePhotoSection({required this.image});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Icon(
              Icons.photo_camera_back_outlined,
              size: 18,
              color: Colors.grey.shade700,
            ),
            const SizedBox(width: 8),
            Text(
              image.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ZoomableProtectedImage(
          url: image.url,
          width: double.infinity,
          height: 220,
          radius: 14,
          fit: BoxFit.cover,
          heroLabel: image.title,
          fallbackIcon: Icons.broken_image_outlined,
        ),
      ],
    );
  }
}

class _ZoomableImageDialog extends StatelessWidget {
  final String title;
  final String url;

  const _ZoomableImageDialog({required this.title, required this.url});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      backgroundColor: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Pinch or double tap to zoom',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.black,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Center(
                    child: _ProtectedImageBox(
                      url: url,
                      width: double.infinity,
                      height: double.infinity,
                      radius: 0,
                      fit: BoxFit.contain,
                      fallbackIcon: Icons.broken_image_outlined,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomableLocalFileImage extends StatelessWidget {
  final File file;
  final double width;
  final double height;
  final double radius;
  final BoxFit fit;
  final String title;

  const _ZoomableLocalFileImage({
    required this.file,
    required this.width,
    required this.height,
    required this.radius,
    required this.title,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final exists = file.existsSync();
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: !exists
          ? null
          : () {
              showDialog<void>(
                context: context,
                builder: (dialogContext) =>
                    _ZoomableLocalImageDialog(title: title, file: file),
              );
            },
      child: exists
          ? ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Image.file(
                file,
                width: width,
                height: height,
                fit: fit,
                errorBuilder: (context, error, stackTrace) => _fileFallback(),
              ),
            )
          : _fileFallback(),
    );
  }

  Widget _fileFallback() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
    );
  }
}

class _ZoomableLocalImageDialog extends StatelessWidget {
  final String title;
  final File file;

  const _ZoomableLocalImageDialog({required this.title, required this.file});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      backgroundColor: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Pinch or double tap to zoom',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.black,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

//
// Treatment section  shown only when expert confirmed
//

//
// Offline pending detail sheet
// Shows the on-device TFLite result + bundled treatment guidance
// before the scan is uploaded to the server.
//

class _OfflinePendingDetailSheet extends StatefulWidget {
  final PendingScanQueueEntry entry;
  final String lang;
  const _OfflinePendingDetailSheet({required this.entry, required this.lang});

  @override
  State<_OfflinePendingDetailSheet> createState() =>
      _OfflinePendingDetailSheetState();
}

class _OfflinePendingDetailSheetState
    extends State<_OfflinePendingDetailSheet> {
  DiseaseTreatmentGuidance? _guidance;
  bool _loadingGuidance = true;

  String? get _rawName => widget
      .entry
      .scanMetadata?['offline_local_disease_name']
      ?.toString()
      .trim();
  String? get _canonicalKey =>
      widget.entry.scanMetadata?['offline_local_disease_key']
          ?.toString()
          .trim() ??
      normalizeDiseaseKey(_rawName ?? '');
  String? get _severity =>
      widget.entry.scanMetadata?['offline_local_severity']?.toString().trim();
  double? get _confidence {
    final v = widget.entry.scanMetadata?['offline_local_confidence'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  List<Map<String, dynamic>> get _topScores {
    final raw = widget.entry.scanMetadata?['offline_local_top_scores'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _loadGuidance();
  }

  Future<void> _loadGuidance() async {
    final key = _canonicalKey ?? '';
    if (key.isEmpty || isPendingDiseaseKey(key)) {
      if (mounted) setState(() => _loadingGuidance = false);
      return;
    }
    try {
      final g = await OfflineTreatmentGuidanceService.instance
          .guidanceForDiseaseLabel(key, cropName: key.split('_').first);
      if (mounted)
        setState(() {
          _guidance = g;
          _loadingGuidance = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingGuidance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = widget.lang;
    final screenH = MediaQuery.of(context).size.height;

    final canonicalKey = _canonicalKey ?? '';
    final isHealthy = isHealthyDiseaseKey(canonicalKey);
    final localizedName = localizedDiseaseLabel(lang, canonicalKey);
    final displayName = localizedName.isNotEmpty
        ? localizedName
        : displayDiseaseLabel(canonicalKey).isNotEmpty
        ? displayDiseaseLabel(canonicalKey)
        : (_rawName ?? 'Unknown');

    final imageFile = File(widget.entry.imagePath);
    final hasImage = imageFile.existsSync();
    final confidence = _confidence;
    final severity = _severity ?? '';

    return Container(
      height: screenH * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  //  On-device result badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.offline_bolt_rounded,
                          size: 14,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _dh(lang, 'on_device_ai_result'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  //  Disease name
                  Text(
                    displayName,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isHealthy
                          ? Colors.green.shade800
                          : Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (severity.isNotEmpty)
                        _SeverityChip(severity: severity),
                      if (confidence != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.analytics_outlined,
                                size: 13,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _dh(
                                  lang,
                                  'confidence_percent',
                                  params: {
                                    'value': (confidence * 100).toStringAsFixed(
                                      0,
                                    ),
                                  },
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (_topScores.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Model scores',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._topScores.map((item) {
                      final label = item['label']?.toString() ?? '';
                      final score = item['score'] is num
                          ? (item['score'] as num).toDouble()
                          : double.tryParse(item['score']?.toString() ?? '') ??
                                0.0;
                      return Text(
                        '- ${displayDiseaseLabel(label).isNotEmpty ? displayDiseaseLabel(label) : label}: ${(score * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall,
                      );
                    }),
                  ],
                  const SizedBox(height: 16),

                  //  Provisional notice
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.amber.shade800,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _dh(lang, 'provisional_pending_title'),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _dh(lang, 'provisional_pending_body'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.amber.shade900,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  //  Healthy notice
                  if (isHealthy) ...[
                    _HealthyNotice(lang: lang),
                  ] else ...[
                    //  Offline treatment guidance
                    if (_loadingGuidance)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_guidance != null &&
                        _guidance!.canShowTreatmentDetails) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.medical_services_outlined,
                            color: Colors.green.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _dh(lang, 'offline_treatment_guide'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Text(
                              _dh(lang, 'bundled_guide'),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _TreatmentSection(
                        guidance: _guidance!,
                        isOffline: true,
                        lang: lang,
                      ),
                    ] else if (_guidance != null) ...[
                      // Guidance exists but not treatment-ready  show actions/monitoring
                      if (_guidance!.headline.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Text(
                            _guidance!.headline,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ),
                      if (_guidance!.actions.isNotEmpty)
                        _InlineStepGroup(
                          icon: Icons.checklist_outlined,
                          title: _dh(lang, 'what_to_do_now'),
                          color: Colors.blue,
                          steps: _guidance!.actions,
                        ),
                      if (_guidance!.monitoring.isNotEmpty)
                        _InlineStepGroup(
                          icon: Icons.visibility_outlined,
                          title: _dh(lang, 'what_to_watch_for'),
                          color: Colors.teal,
                          steps: _guidance!.monitoring,
                        ),
                      if (_guidance!.escalateIf.isNotEmpty)
                        _InlineStepGroup(
                          icon: Icons.warning_amber_rounded,
                          title: _dh(lang, 'call_for_help_if_short'),
                          color: Colors.orange,
                          steps: _guidance!.escalateIf,
                        ),
                    ] else
                      _NoticeBox(
                        color: Colors.grey,
                        icon: Icons.medical_services_outlined,
                        title: L.t(lang, 'no_offline_guidance_title'),
                        body: L.t(lang, 'no_offline_guidance_body'),
                      ),
                  ],

                  //  Scan photo
                  if (hasImage) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          size: 18,
                          color: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          L.t(lang, 'captured_photo'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ZoomableLocalFileImage(
                      file: imageFile,
                      width: double.infinity,
                      height: 220,
                      radius: 14,
                      fit: BoxFit.cover,
                      title: L.t(lang, 'captured_photo'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//
// Inline step group  used in offline pending detail sheet
//

class _InlineStepGroup extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<String> steps;
  const _InlineStepGroup({
    required this.icon,
    required this.title,
    required this.color,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
