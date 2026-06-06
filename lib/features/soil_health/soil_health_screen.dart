import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:smart_farm/api_client.dart';
import 'package:smart_farm/features/my_farm/providers/farm_context_provider.dart';
import 'package:smart_farm/language_store.dart';
import 'package:smart_farm/localization.dart';
import 'package:smart_farm/localized_value.dart';
import 'package:smart_farm/offline/offline_models.dart';
import 'package:smart_farm/offline/offline_repository.dart';
import 'package:smart_farm/offline/offline_sync_service.dart';
import 'package:smart_farm/offline/sync_state.dart';
import 'package:smart_farm/sync_refresh_notifier.dart';
import 'package:smart_farm/widgets/app_header.dart';
import 'package:smart_farm/widgets/error_banner.dart';
import 'package:smart_farm/widgets/farm_ui.dart';
import 'soil_health_interpretation.dart';

class SoilHealthScreen extends StatefulWidget {
  final int? initialPlotId;
  final int? initialFarmId;

  const SoilHealthScreen({super.key, this.initialPlotId, this.initialFarmId});

  @override
  State<SoilHealthScreen> createState() => _SoilHealthScreenState();
}

class _SoilHealthScreenState extends State<SoilHealthScreen> {
  late Future<List<SoilHealthRecord>> _soilHealthFuture;
  List<SoilHealthRecord> _soilHealthData = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    syncRefreshNotifier.addListener(_handleSyncRefresh);
    _soilHealthFuture = _fetchSoilHealthData();
  }

  @override
  void dispose() {
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    super.dispose();
  }

  void _handleSyncRefresh() {
    unawaited(_reloadFromRepositoryOnly());
  }

  Future<List<SoilHealthRecord>> _fetchSoilHealthData() async {
    final repo = OfflineRepository.instance;
    try {
      final response = await repo.listSoilHealth(plotLocalId: widget.initialPlotId);
      if (!mounted) return response;
      setState(() {
        _soilHealthData = response;
        _isLoading = false;
      });

      unawaited(() async {
        try {
          await OfflineSyncService.instance.syncNow().timeout(const Duration(seconds: 12));
          final refreshed = await repo.listSoilHealth(plotLocalId: widget.initialPlotId);
          if (!mounted) return;
          setState(() {
            _soilHealthData = refreshed;
          });
        } catch (_) {
          // Keep the initial local result visible instead of blocking on sync.
        }
      }());
      return response;
    } catch (e) {
      if (!mounted) return [];
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      return [];
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _soilHealthFuture = _fetchSoilHealthData();
    await _soilHealthFuture;
  }

  Future<void> _reloadFromRepositoryOnly() async {
    try {
      final refreshed = await OfflineRepository.instance.listSoilHealth(
        plotLocalId: widget.initialPlotId,
      );
      if (!mounted) return;
      setState(() {
        _soilHealthData = refreshed;
        _error = null;
        _isLoading = false;
      });
    } catch (_) {
      // Keep the last visible local list when a lightweight refresh fails.
    }
  }

  void _showActionMessage(String message, String nextStep) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('$message\n$nextStep'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM dd, yyyy HH:mm').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  String _normalizeSoilMethod(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (value.contains('lab')) return 'lab';
    if (value.contains('sensor')) return 'sensor';
    if (value.contains('officer') || value.contains('support')) return 'officer';
    if (value.contains('manual')) return 'manual';
    return value;
  }

  Color _soilMethodColor(String method) {
    switch (method) {
      case 'lab':
        return Colors.purple.shade700;
      case 'sensor':
        return Colors.teal.shade700;
      case 'officer':
        return Colors.green.shade700;
      case 'manual':
        return Colors.blueGrey.shade700;
      default:
        return Colors.blueGrey.shade700;
    }
  }

  String _soilMethodLabel(String method, String lang) {
    switch (method) {
      case 'lab':
        return L.t(lang, 'soil_method_lab');
      case 'sensor':
        return L.t(lang, 'soil_method_sensor');
      case 'officer':
        return L.t(lang, 'soil_method_officer');
      case 'manual':
        return L.t(lang, 'soil_method_manual');
      default:
        return method;
    }
  }

  String _normalizeReviewStatus(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (value.contains('valid') || value.contains('approve')) return 'validated';
    if (value.contains('reject')) return 'rejected';
    if (value.contains('pend')) return 'pending';
    return value;
  }

  bool _isValidatedStatus(String status) => status == 'validated';

  Color _soilStatusColor(String status) {
    switch (status) {
      case 'validated':
        return Colors.green.shade700;
      case 'rejected':
        return Colors.red.shade700;
      case 'pending':
      default:
        return Colors.orange.shade800;
    }
  }

  String _soilStatusLabel(String status, String lang) {
    switch (status) {
      case 'validated':
        return L.t(lang, 'soil_status_validated');
      case 'rejected':
        return L.t(lang, 'soil_status_rejected');
      case 'pending':
      default:
        return L.t(lang, 'soil_status_pending');
    }
  }

  static String _soilUiText(String lang, String key) {
    const values = <String, Map<String, String>>{
      'am': {
        'reviewer_note': 'የገምጋሚ ማስታወሻ',
        'reason_prefix': 'ምክንያት',
        'soil_status_title': 'የአፈር ሁኔታ',
        'live_unavailable': 'የቀጥታ የአፈር ትንተና አልተገኘም። የአካባቢ መመሪያ እየታየ ነው።',
        'trend_organic_up': 'ኦርጋኒክ ንጥረ ነገር ከቀድሞው ሙከራ ተሻሽሏል።',
        'trend_organic_down': 'ኦርጋኒክ ንጥረ ነገር ከቀድሞው ሙከራ ቀንሷል።',
        'trend_moisture_up': 'የአፈር እርጥበት ከመጨረሻው ሙከራ በግልጽ ጨምሯል።',
        'trend_moisture_down': 'የአፈር እርጥበት ከመጨረሻው ሙከራ በግልጽ ቀንሷል።',
        'trend_ph_shift': 'የአፈር pH ተቀይሯል፤ ቅርብ ክትትል ያስፈልጋል።',
      },
      'om': {
        'reviewer_note': 'Yaada gamaaggamaa',
        'reason_prefix': 'Sababa',
        'soil_status_title': 'Haala biyyee',
        'live_unavailable': 'Xiinxalli biyyee kallattiin hin argamne. Qajeelfamni naannoo agarsiifamaa jira.',
        'trend_organic_up': 'Qabiyyeen orgaanikii qorannoo duraanii irraa fooyyaʼeera.',
        'trend_organic_down': 'Qabiyyeen orgaanikii qorannoo duraanii irraa hirʼateera.',
        'trend_moisture_up': 'Jiidhinni biyyee qorannoo dhumaa irraa ifatti dabaleera.',
        'trend_moisture_down': 'Jiidhinni biyyee qorannoo dhumaa irraa ifatti hirʼateera.',
        'trend_ph_shift': 'pH biyyee jijjiirameera; hordoffii dhihoo barbaada.',
      },
      'ti': {
        'reviewer_note': 'መዘኻኸሪ ገምጋሚ',
        'reason_prefix': 'ምኽንያት',
        'soil_status_title': 'ኩነታት መሬት',
        'live_unavailable': 'ቀጥታዊ ትንተና መሬት ኣይተረኽበን። ናይ ከባቢ መምርሒ ይረአ ኣሎ።',
        'trend_organic_up': 'ኦርጋኒክ ንጥረ ነገር ካብ ቀዳማይ ፈተነ ተመሓይሹ።',
        'trend_organic_down': 'ኦርጋኒክ ንጥረ ነገር ካብ ቀዳማይ ፈተነ ቀኒሱ።',
        'trend_moisture_up': 'ርጥበት መሬት ካብ መወዳእታ ፈተነ ብግልጺ ወሲኹ።',
        'trend_moisture_down': 'ርጥበት መሬት ካብ መወዳእታ ፈተነ ብግልጺ ቀኒሱ።',
        'trend_ph_shift': 'pH መሬት ተቐይሩ፤ ቀረባ ክትትል የድሊ።',
      },
      'en': {
        'reviewer_note': 'Reviewer note',
        'reason_prefix': 'Reason',
        'soil_status_title': 'Soil Status',
        'live_unavailable': 'Live soil analysis unavailable. Showing local guidance.',
        'trend_organic_up': 'Organic matter improved from the previous test.',
        'trend_organic_down': 'Organic matter dropped from the previous test.',
        'trend_moisture_up': 'Soil moisture increased noticeably since the last test.',
        'trend_moisture_down': 'Soil moisture decreased noticeably since the last test.',
        'trend_ph_shift': 'Soil pH shifted enough to justify close monitoring.',
      },
    };
    return values[lang]?[key] ?? values['en']?[key] ?? key;
  }

  String _soilReviewReasonLabel(String reason, String lang) {
    final prefix = _soilUiText(lang, 'reason_prefix');
    switch (reason) {
      case 'evidence_consistent':
        return '$prefix: ${L.t(lang, 'evidence')}';
      case 'field_measurement_verified':
        return '$prefix: ${LocalizedValue.status(lang, 'verified')}';
      case 'supporter_confirmed':
        return '$prefix: ${LocalizedValue.status(lang, 'confirmed')}';
      case 'expert_confirmed':
        return '$prefix: ${LocalizedValue.status(lang, 'confirmed')}';
      case 'insufficient_evidence':
        return '$prefix: ${L.t(lang, 'soil_evidence_unavailable')}';
      case 'measurement_outlier':
        return '$prefix: ${L.t(lang, 'soil_local_summary_watch')}';
      case 'wrong_plot_context':
        return '$prefix: ${L.t(lang, 'guidance_no_plot_selected')}';
      case 'needs_retest':
        return '$prefix: ${L.t(lang, 'soil_local_watch_retest')}';
      default:
        return '$prefix: ${reason.replaceAll('_', ' ')}';
    }
  }

  Color _soilSummaryColor(SoilHealthInterpretation interpretation) {
    switch (interpretation.summaryKey) {
      case 'soil_local_summary_attention':
        return Colors.red.shade700;
      case 'soil_local_summary_watch':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
  }

  String? _localTrendMessage(String lang, SoilHealthRecord current, SoilHealthRecord? previous) {
    if (previous == null) {
      return null;
    }

    final messages = <String>[];
    final organicDelta = _delta(current.organicMatter, previous.organicMatter);
    if (organicDelta != null) {
      if (organicDelta >= 0.4) {
        messages.add(_soilUiText(lang, 'trend_organic_up'));
      } else if (organicDelta <= -0.4) {
        messages.add(_soilUiText(lang, 'trend_organic_down'));
      }
    }

    final moistureDelta = _delta(current.moistureLevel, previous.moistureLevel);
    if (moistureDelta != null) {
      if (moistureDelta >= 8) {
        messages.add(_soilUiText(lang, 'trend_moisture_up'));
      } else if (moistureDelta <= -8) {
        messages.add(_soilUiText(lang, 'trend_moisture_down'));
      }
    }

    final phDelta = _delta(current.phLevel, previous.phLevel);
    if (phDelta != null && phDelta.abs() >= 0.4) {
      messages.add(_soilUiText(lang, 'trend_ph_shift'));
    }

    if (messages.isEmpty) {
      return null;
    }
    return messages.first;
  }

  double? _delta(double? current, double? previous) {
    if (current == null || previous == null) {
      return null;
    }
    return current - previous;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openAddSoilHealth,
            icon: const Icon(Icons.add),
            label: Text(L.t(lang, 'addSoilHealthData')),
          ),
          body: FarmSurface(
            padding: EdgeInsets.zero,
            child: Column(
            children: [
              AppHeader(
                titleKey: 'soilHealthMonitoring',
                subtitle: L.t(lang, 'soilHealthMonitoringSubtitle'),
                onRefreshTap: _refreshData,
              ),
              if (_error != null) ErrorBanner(message: _error!, onRetry: _refreshData),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _soilHealthData.isEmpty
                    ? _SoilHealthEmptyState(
                        languageCode: lang,
                        onAdd: _openAddSoilHealth,
                      )
                    : RefreshIndicator(
                        onRefresh: _refreshData,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          itemCount: _soilHealthData.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final data = _soilHealthData[index];
                            final previous = index + 1 < _soilHealthData.length
                                ? _soilHealthData[index + 1]
                                : null;
                            return _buildSoilHealthCard(
                              data,
                              lang,
                              previous,
                            );
                          },
                        ),
                      ),
              ),
            ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddSoilHealth() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => AddSoilHealthScreen(
          initialFarmId: widget.initialFarmId,
          initialPlotId: widget.initialPlotId,
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _refreshData();
    if (!mounted) return;
    final lang = LanguageStore.notifier.value;
    _showActionMessage(
      L.t(lang, 'soil_action_added_success'),
      L.t(lang, 'action_next_soil_added'),
    );
  }

  Future<void> _openEditSoilHealth(SoilHealthRecord record) async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => AddSoilHealthScreen(
          initialFarmId: widget.initialFarmId,
          initialPlotId: record.plotLocalId ?? widget.initialPlotId,
          existingRecord: record,
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _refreshData();
    if (!mounted) return;
    final lang = LanguageStore.notifier.value;
    _showActionMessage(
      L.t(lang, 'soil_action_updated_success'),
      L.t(lang, 'action_next_soil_updated'),
    );
  }

  Future<void> _confirmDeleteSoilHealth(SoilHealthRecord record, String lang) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.t(lang, 'soil_delete_title')),
        content: Text(L.t(lang, 'soil_delete_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(L.t(lang, 'cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(L.t(lang, 'delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await OfflineRepository.instance.deleteSoilHealthLocal(record.localId);
      unawaited(OfflineSyncService.instance.syncNow().catchError((_) {}));
      if (!mounted) return;
      await _refreshData();
      if (!mounted) return;
      _showActionMessage(
        L.t(lang, 'soil_action_deleted_success'),
        L.t(lang, 'action_next_soil_deleted'),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${L.t(lang, 'soil_delete_failed')}: $e')),
      );
    }
  }

  Widget _buildSoilHealthCard(
    SoilHealthRecord data,
    String lang,
    SoilHealthRecord? previous,
  ) {
    final theme = Theme.of(context);
    final testMethodRaw = (data.testMethod ?? '').trim();
    final reviewStatusRaw = (data.reviewStatus ?? '').trim();
    final testMethod = _normalizeSoilMethod(testMethodRaw);
    final reviewStatus = _normalizeReviewStatus(reviewStatusRaw);
    final soilType = (data.soilType ?? '').trim();
    final isProvisional = reviewStatus.isEmpty || !_isValidatedStatus(reviewStatus);
    final interpretation = SoilHealthInterpretation.fromRecord(
      data,
      isValidated: _isValidatedStatus(reviewStatus),
    );
    final testDate = data.testDate ?? data.serverCreatedAt ?? data.localUpdatedAt;
    final evidenceUrl = (data.evidenceUrl ?? '').trim();
    final evidencePath = (data.evidencePath ?? '').trim();
    final hasPendingSync = data.syncState != SyncState.synced;
    final hasEvidence = evidenceUrl.isNotEmpty || evidencePath.isNotEmpty;
    final localTrend = _localTrendMessage(lang, data, previous);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatDateTime(testDate.toString()),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                ),
                if (hasPendingSync)
                  Icon(
                    data.syncState == SyncState.conflict
                        ? Icons.error_outline
                        : Icons.cloud_upload_outlined,
                    size: 18,
                    color: data.syncState == SyncState.conflict
                        ? Colors.redAccent
                        : Colors.orange.shade700,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (testMethod.isNotEmpty)
                  _SoilChip(
                    label: _soilMethodLabel(testMethod, lang),
                    backgroundColor: _soilMethodColor(testMethod).withValues(alpha: 0.12),
                    textColor: _soilMethodColor(testMethod),
                  ),
                if (reviewStatus.isNotEmpty)
                  _SoilChip(
                    label: _soilStatusLabel(reviewStatus, lang),
                    backgroundColor: _soilStatusColor(reviewStatus).withValues(alpha: 0.12),
                    textColor: _soilStatusColor(reviewStatus),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _soilSummaryColor(interpretation).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _soilSummaryColor(interpretation).withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L.t(lang, interpretation.summaryKey),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _soilSummaryColor(interpretation),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    L.t(lang, interpretation.noticeKey),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _SoilDashboardMetrics(
              record: data,
              lang: lang,
              soilType: soilType,
            ),
            const SizedBox(height: 8),
            if (isProvisional)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  L.t(lang, 'soil_recommendations_pending'),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
                ),
              ),
            if ((data.reviewReasonCode ?? '').trim().isNotEmpty ||
                (data.reviewComment ?? '').trim().isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _soilStatusColor(reviewStatus).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _soilStatusColor(reviewStatus).withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _soilUiText(lang, 'reviewer_note'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _soilStatusColor(reviewStatus),
                      ),
                    ),
                    if ((data.reviewReasonCode ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _soilReviewReasonLabel(data.reviewReasonCode!.trim(), lang),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if ((data.reviewComment ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          data.reviewComment!.trim(),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            if (localTrend != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  localTrend,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.blueGrey.shade700),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openRecommendationsDialog(data, interpretation, lang),
                icon: const Icon(Icons.tips_and_updates_outlined),
                label: Text(L.t(lang, 'recommendations')),
              ),
            ),
            if (hasEvidence) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _showEvidenceDialog(context, evidenceUrl, evidencePath, lang),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(L.t(lang, 'soil_view_evidence')),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openEditSoilHealth(data),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(L.t(lang, 'edit')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _confirmDeleteSoilHealth(data, lang),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(L.t(lang, 'delete')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openRecommendationsDialog(
    SoilHealthRecord record,
    SoilHealthInterpretation interpretation,
    String lang,
  ) {
    showDialog(
      context: context,
      builder: (context) => _SoilInsightDialog(
        record: record,
        interpretation: interpretation,
        languageCode: lang,
      ),
    );
  }

  void _showEvidenceDialog(
    BuildContext context,
    String url,
    String localPath,
    String lang,
  ) {
    final lower = url.toLowerCase();
    final isImage = lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
    final hasLocal = localPath.isNotEmpty && File(localPath).existsSync();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.t(lang, 'soil_evidence_title')),
        content: isImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Text(L.t(lang, 'soil_evidence_unavailable')),
                ),
              )
            : hasLocal
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(localPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Text(L.t(lang, 'soil_evidence_unavailable')),
                    ),
                  )
                : Text(L.t(lang, 'soil_evidence_unavailable')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(L.t(lang, 'close'))),
        ],
      ),
    );
  }

}

class _SoilInsightDialog extends StatefulWidget {
  final SoilHealthRecord record;
  final SoilHealthInterpretation interpretation;
  final String languageCode;

  const _SoilInsightDialog({
    required this.record,
    required this.interpretation,
    required this.languageCode,
  });

  @override
  State<_SoilInsightDialog> createState() => _SoilInsightDialogState();
}

class _SoilInsightDialogState extends State<_SoilInsightDialog> {
  Map<String, dynamic>? _serverPayload;
  bool _loading = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _loadServerAnalysis();
  }

  Future<void> _loadServerAnalysis() async {
    if (!widget.record.isSynced || widget.record.serverId == null) {
      return;
    }
    setState(() {
      _loading = true;
      _serverError = null;
    });
    try {
      final payload = await ApiClient.getSoilHealthRecommendations(
        widget.record.serverId!,
      );
      if (!mounted) return;
      setState(() {
        _serverPayload = payload;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = e.toString();
        _loading = false;
      });
    }
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList();
    }
    return const <String>[];
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is List) {
      return value.whereType<Map>().map((item) {
        return item.map((key, val) => MapEntry(key.toString(), val));
      }).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'urgent':
        return Colors.red.shade700;
      case 'attention':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
  }

  Widget _buildLocalFallback(String lang) {
    final interpretation = widget.interpretation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          L.t(lang, interpretation.noticeKey),
          style: TextStyle(
            color: interpretation.provisional ? Colors.orange.shade800 : Colors.green.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (interpretation.issueKeys.isNotEmpty) ...[
          Text(L.t(lang, 'soil_local_priority_issues'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...interpretation.issueKeys.map((key) => Text('- ${L.t(lang, key)}')),
        ],
        if (interpretation.naturalActionKeys.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(L.t(lang, 'soil_local_natural_treatment'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...interpretation.naturalActionKeys.map((key) => Text('- ${L.t(lang, key)}')),
        ],
        if (interpretation.modernActionKeys.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(L.t(lang, 'soil_local_modern_treatment'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...interpretation.modernActionKeys.map((key) => Text('- ${L.t(lang, key)}')),
        ],
        if (interpretation.watchKeys.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(L.t(lang, 'monitoring'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...interpretation.watchKeys.map((key) => Text('- ${L.t(lang, key)}')),
        ],
      ],
    );
  }

  Widget _buildServerAnalysis(String lang) {
    final payload = _serverPayload ?? const <String, dynamic>{};
    final analysis = payload['analysis'] is Map<String, dynamic>
        ? payload['analysis'] as Map<String, dynamic>
        : (payload['analysis'] is Map
            ? (payload['analysis'] as Map).map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{});
    if (analysis.isEmpty) {
      return _buildLocalFallback(lang);
    }

    final overall = analysis['overall_status']?.toString().trim() ?? 'stable';
    final headline = analysis['headline']?.toString().trim() ?? '';
    final cropContext = analysis['crop_context'] is Map<String, dynamic>
        ? analysis['crop_context'] as Map<String, dynamic>
        : (analysis['crop_context'] is Map
            ? (analysis['crop_context'] as Map).map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{});
    final issues = _mapList(analysis['issues']);
    final actions = _stringList(analysis['actions']);
    final watch = _stringList(analysis['watch_items']);
    final trends = _mapList(analysis['trends']);
    final nextSteps = _stringList(analysis['next_steps']);
    final provisional = payload['provisional'] == true;
    final notice = payload['notice']?.toString().trim();
    final activeCrop = cropContext['active_crop']?.toString().trim();
    final soilType = cropContext['soil_type']?.toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _statusColor(overall).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _statusColor(overall).withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline.isEmpty ? L.t(lang, 'soil_analysis') : headline,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _statusColor(overall),
                ),
              ),
              if ((activeCrop ?? '').isNotEmpty || (soilType ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if ((activeCrop ?? '').isNotEmpty)
                      L.t(lang, 'active_crop_value', params: {'value': activeCrop!}),
                    if ((soilType ?? '').isNotEmpty)
                      L.t(lang, 'soil_type_value', params: {'value': LocalizedValue.soilType(lang, soilType!)}),
                  ].join('  •  '),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (provisional && (notice ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            notice!,
            style: TextStyle(
              color: Colors.orange.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(L.t(lang, 'priority_issues'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...issues.take(4).map((issue) {
            final metric = issue['metric']?.toString().trim() ?? 'Issue';
            final message = issue['message']?.toString().trim() ?? '';
            final severity = issue['severity']?.toString().trim() ?? 'watch';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _statusColor(severity == 'critical' ? 'urgent' : 'attention'),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('$metric: $message')),
                ],
              ),
            );
          }),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(L.t(lang, 'recommendations'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...actions.map((item) => Text('- $item')),
        ],
        if (watch.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(L.t(lang, 'monitoring'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...watch.map((item) => Text('- $item')),
        ],
        if (trends.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(L.t(lang, 'trend_since_last_test'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...trends.map((item) => Text('- ${item['message']?.toString().trim() ?? ''}')),
        ],
        if (nextSteps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(L.t(lang, 'next_steps'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...nextSteps.map((item) => Text('- $item')),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.languageCode;
    return AlertDialog(
      title: Text(widget.record.isSynced ? L.t(lang, 'soil_analysis') : L.t(lang, 'soil_local_guidance_title')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_serverError != null && widget.record.isSynced) ...[
                Text(
                  _SoilHealthScreenState._soilUiText(lang, 'live_unavailable'),
                  style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
              ],
              _serverPayload != null ? _buildServerAnalysis(lang) : _buildLocalFallback(lang),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L.t(lang, 'close')),
        ),
      ],
    );
  }
}

class _SoilHealthEmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  final String languageCode;

  const _SoilHealthEmptyState({required this.onAdd, required this.languageCode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.science, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              L.t(languageCode, 'noSoilHealthData'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              L.t(languageCode, 'soilHealthSummary'),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(L.t(languageCode, 'addSoilHealthData')),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoilChip extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;

  const _SoilChip({
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

class _SoilDashboardMetrics extends StatelessWidget {
  final SoilHealthRecord record;
  final String lang;
  final String soilType;

  const _SoilDashboardMetrics({
    required this.record,
    required this.lang,
    required this.soilType,
  });

  @override
  Widget build(BuildContext context) {
    final moisture = record.moistureLevel;
    final ph = record.phLevel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE9B7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _MoistureRing(value: moisture),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L.t(lang, 'soilMoisture'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _moistureLabel(moisture),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (soilType.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _SoilChip(
                        label:
                            '${L.t(lang, 'soilTexture')}: ${LocalizedValue.soilType(lang, soilType)}',
                        backgroundColor: const Color(0xFFEAF3CF),
                        textColor: const Color(0xFF41670F),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _SoilHealthScreenState._soilUiText(lang, 'soil_status_title'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NutrientStatusTile(
                  label: L.t(lang, 'nitrogenLevel'),
                  value: record.nitrogen,
                  accent: const Color(0xFF4F7D12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NutrientStatusTile(
                  label: L.t(lang, 'phosphorusLevel'),
                  value: record.phosphorus,
                  accent: const Color(0xFFB88718),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NutrientStatusTile(
                  label: L.t(lang, 'potassiumLevel'),
                  value: record.potassium,
                  accent: const Color(0xFFC8482A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PhScale(value: ph, lang: lang),
          if (record.organicMatter != null) ...[
            const SizedBox(height: 10),
            _SoilChip(
              label: '${L.t(lang, 'organicMatter')}: ${record.organicMatter}%',
              backgroundColor: const Color(0xFFF0E4C6),
              textColor: const Color(0xFF7A4F21),
            ),
          ],
        ],
      ),
    );
  }

  String _moistureLabel(double? value) {
    if (value == null) return 'No moisture reading';
    if (value < 20) return 'Low moisture - irrigation may be needed';
    if (value > 75) return 'High moisture - check drainage';
    return 'Optimal range';
  }
}

class _MoistureRing extends StatelessWidget {
  final double? value;

  const _MoistureRing({required this.value});

  @override
  Widget build(BuildContext context) {
    final normalized = ((value ?? 0).clamp(0, 100) / 100).toDouble();
    final color = value == null
        ? Colors.grey
        : value! < 20
            ? Colors.orange
            : value! > 75
                ? Colors.blue
                : const Color(0xFF7FE36D);

    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: normalized,
            strokeWidth: 9,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeCap: StrokeCap.round,
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value == null ? '--' : '${value!.round()}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text(
                  'Moisture',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey.shade600,
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

class _NutrientStatusTile extends StatelessWidget {
  final String label;
  final double? value;
  final Color accent;

  const _NutrientStatusTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final status = _status(value);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.grey.shade700,
                ),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: ((value ?? 0).clamp(0, 1)).toDouble(),
              backgroundColor: Colors.white.withValues(alpha: 0.8),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            status,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
          ),
        ],
      ),
    );
  }

  String _status(double? value) {
    if (value == null) return 'N/A';
    if (value < 0.08) return 'Low';
    if (value > 0.30) return 'High';
    return 'Good';
  }
}

class _PhScale extends StatelessWidget {
  final double? value;
  final String lang;

  const _PhScale({required this.value, required this.lang});

  @override
  Widget build(BuildContext context) {
    final ph = value;
    final normalized = ph == null ? 0.0 : ((ph.clamp(3.5, 9.5) - 3.5) / 6.0).toDouble();
    final label = ph == null
        ? 'No pH reading'
        : ph < 5.8
            ? 'Acidic'
            : ph > 7.5
                ? 'Alkaline'
                : 'Neutral';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              L.t(lang, 'phLevel'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const Spacer(),
            Text(
              ph == null ? '--' : '${ph.toStringAsFixed(1)} $label',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF41670F),
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final markerLeft = (constraints.maxWidth * normalized).clamp(0.0, constraints.maxWidth - 10);
            return SizedBox(
              height: 22,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        height: 8,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFFD95A3C),
                              Color(0xFF7FE36D),
                              Color(0xFF4D8CEB),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: markerLeft,
                    top: 2,
                    child: Container(
                      width: 14,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF1E2A12), width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SoilFormSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SoilFormSection({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return FarmPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E2A12),
                ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SoilMethodOption {
  final String value;
  final IconData icon;
  final String labelKey;

  const _SoilMethodOption({
    required this.value,
    required this.icon,
    required this.labelKey,
  });
}

const List<_SoilMethodOption> _soilMethodOptions = [
  _SoilMethodOption(
    value: 'manual',
    icon: Icons.edit,
    labelKey: 'soil_method_manual',
  ),
  _SoilMethodOption(
    value: 'lab',
    icon: Icons.science,
    labelKey: 'soil_method_lab',
  ),
  _SoilMethodOption(
    value: 'sensor',
    icon: Icons.memory,
    labelKey: 'soil_method_sensor',
  ),
  _SoilMethodOption(
    value: 'officer',
    icon: Icons.support_agent,
    labelKey: 'soil_method_officer',
  ),
];

class AddSoilHealthScreen extends StatefulWidget {
  final int? initialFarmId;
  final int? initialPlotId;
  final SoilHealthRecord? existingRecord;

  const AddSoilHealthScreen({
    super.key,
    this.initialFarmId,
    this.initialPlotId,
    this.existingRecord,
  });

  @override
  State<AddSoilHealthScreen> createState() => _AddSoilHealthScreenState();
}

class _AddSoilHealthScreenState extends State<AddSoilHealthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phController = TextEditingController();
  final _nitrogenController = TextEditingController();
  final _phosphorusController = TextEditingController();
  final _potassiumController = TextEditingController();
  final _organicMatterController = TextEditingController();
  final _moistureController = TextEditingController();
  final _soilTypeController = TextEditingController();
  bool _isSubmitting = false;
  String _selectedMethod = 'manual';
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _evidenceFile;
  bool _pickingEvidence = false;

  List<FarmRecord> _farms = [];
  List<PlotRecord> _plots = [];
  int? _selectedFarmId;
  int? _selectedPlotId;
  bool _isLoadingFarms = false;
  bool _isLoadingPlots = false;
  String? _farmsError;
  String? _plotsError;

  bool get _isEditing => widget.existingRecord != null;

  InputDecoration _compactInput(String label, {String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }

  @override
  void initState() {
    super.initState();

    final farmContext = Provider.of<FarmContextProvider>(context, listen: false);
    final selectedFarm = farmContext.selectedFarm;
    final selectedPlot = farmContext.selectedPlot;

    final existing = widget.existingRecord;
    _selectedFarmId = widget.initialFarmId ?? selectedFarm?.id ?? selectedPlot?.farmLocalId;
    _selectedPlotId = widget.initialPlotId ?? selectedPlot?.id ?? existing?.plotLocalId;
    _selectedMethod = (existing?.testMethod ?? '').trim().isEmpty
        ? 'manual'
        : existing!.testMethod!.trim().toLowerCase();
    _phController.text = _formatMeasurement(existing?.phLevel);
    _nitrogenController.text = _formatMeasurement(existing?.nitrogen);
    _phosphorusController.text = _formatMeasurement(existing?.phosphorus);
    _potassiumController.text = _formatMeasurement(existing?.potassium);
    _organicMatterController.text = _formatMeasurement(existing?.organicMatter);
    _moistureController.text = _formatMeasurement(existing?.moistureLevel);
    _soilTypeController.text = (existing?.soilType ?? '').trim();

    unawaited(_bootstrapSelection());
  }

  String _formatMeasurement(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  Future<void> _bootstrapSelection() async {
    if (_selectedFarmId == null && _selectedPlotId != null) {
      final plot = await OfflineRepository.instance.getPlotByLocalId(_selectedPlotId!);
      if (!mounted) return;
      _selectedFarmId = plot?.farmLocalId;
    }
    await _loadFarms();
  }

  Future<void> _loadFarms() async {
    setState(() {
      _isLoadingFarms = true;
      _farmsError = null;
    });

    try {
      final repo = OfflineRepository.instance;
      final farms = await repo.listFarms();
      if (!mounted) return;

      var farmId = _selectedFarmId;
      if (farmId != null && !farms.any((f) => f.id == farmId)) {
        farmId = null;
      }

      if (farmId == null && farms.length == 1) {
        farmId = farms.first.id;
      }

      setState(() {
        _farms = farms;
        _isLoadingFarms = false;
        _selectedFarmId = farmId;
      });

      if (farmId != null) {
        await _loadPlots(farmId);
      }

      unawaited(() async {
        try {
          await OfflineSyncService.instance.syncNow().timeout(const Duration(seconds: 12));
          final refreshed = await repo.listFarms();
          if (!mounted) return;
          setState(() {
            _farms = refreshed;
          });
        } catch (_) {
          // Do not block this form on background sync.
        }
      }());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingFarms = false;
        _farmsError = e.toString();
      });
    }
  }

  Future<void> _loadPlots(int farmId) async {
    setState(() {
      _isLoadingPlots = true;
      _plotsError = null;
      _plots = [];
    });

    try {
      final repo = OfflineRepository.instance;
      final plots = await repo.listPlotsByFarmLocalId(farmId);
      if (!mounted) return;

      var plotId = _selectedPlotId;
      if (plotId != null && !plots.any((p) => p.id == plotId)) {
        plotId = null;
      }

      if (plotId == null && plots.length == 1) {
        plotId = plots.first.id;
      }

      setState(() {
        _plots = plots;
        _isLoadingPlots = false;
        _selectedPlotId = plotId;
      });

      unawaited(() async {
        try {
          await OfflineSyncService.instance.syncNow().timeout(const Duration(seconds: 12));
          final refreshed = await repo.listPlotsByFarmLocalId(farmId);
          if (!mounted) return;
          setState(() {
            _plots = refreshed;
          });
        } catch (_) {
          // Keep current plot choices visible if sync is slow.
        }
      }());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPlots = false;
        _plotsError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _phController.dispose();
    _nitrogenController.dispose();
    _phosphorusController.dispose();
    _potassiumController.dispose();
    _organicMatterController.dispose();
    _moistureController.dispose();
    _soilTypeController.dispose();
    super.dispose();
  }

  double? _doubleOrNull(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  Future<void> _pickEvidence(ImageSource source) async {
    if (_pickingEvidence) return;
    setState(() => _pickingEvidence = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (!mounted) return;
      if (picked != null) {
        setState(() => _evidenceFile = picked);
      }
    } finally {
      if (mounted) {
        setState(() => _pickingEvidence = false);
      }
    }
  }

  void _clearEvidence() {
    setState(() => _evidenceFile = null);
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final lang = LanguageStore.notifier.value;

    try {
      final plotId = _selectedPlotId;
      if (plotId == null) {
        throw Exception('plot_id is required');
      }

      final hasAnyMeasurement = [
        _phController,
        _nitrogenController,
        _phosphorusController,
        _potassiumController,
        _organicMatterController,
        _moistureController,
      ].any((c) => c.text.trim().isNotEmpty);
      if (!hasAnyMeasurement) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t(lang, 'soil_min_one_measurement'))),
        );
        return;
      }

      if (_isEditing) {
        await OfflineRepository.instance.updateSoilHealthLocal(
          localId: widget.existingRecord!.localId,
          phLevel: _doubleOrNull(_phController.text),
          nitrogen: _doubleOrNull(_nitrogenController.text),
          phosphorus: _doubleOrNull(_phosphorusController.text),
          potassium: _doubleOrNull(_potassiumController.text),
          organicMatter: _doubleOrNull(_organicMatterController.text),
          moistureLevel: _doubleOrNull(_moistureController.text),
          soilType: _soilTypeController.text.isNotEmpty ? _soilTypeController.text : null,
          testMethod: _selectedMethod,
          testDate: widget.existingRecord?.testDate ?? DateTime.now(),
          evidencePath: _evidenceFile?.path,
        );
      } else {
        await OfflineRepository.instance.createSoilHealthLocal(
          plotLocalId: plotId,
          phLevel: _doubleOrNull(_phController.text),
          nitrogen: _doubleOrNull(_nitrogenController.text),
          phosphorus: _doubleOrNull(_phosphorusController.text),
          potassium: _doubleOrNull(_potassiumController.text),
          organicMatter: _doubleOrNull(_organicMatterController.text),
          moistureLevel: _doubleOrNull(_moistureController.text),
          soilType: _soilTypeController.text.isNotEmpty ? _soilTypeController.text : null,
          testMethod: _selectedMethod,
          testDate: DateTime.now(),
          evidencePath: _evidenceFile?.path,
        );
      }
      unawaited(OfflineSyncService.instance.syncNow().catchError((_) {}));
      if (!mounted) return;
      Navigator.of(context).pop(
        <String, String>{
          'action': _isEditing ? 'updated' : 'added',
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            '${L.t(lang, _isEditing ? 'soil_save_failed_update' : 'soil_save_failed_add')}: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        final existingEvidenceUrl = (widget.existingRecord?.evidenceUrl ?? '').trim();
        final existingEvidencePath = (widget.existingRecord?.evidencePath ?? '').trim();
        final hasExistingEvidence = existingEvidenceUrl.isNotEmpty || existingEvidencePath.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: Text(_isEditing ? L.t(lang, 'editSoilHealthData') : L.t(lang, 'addSoilHealthData')),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          body: FarmSurface(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  _SoilFormSection(
                    title: _isEditing ? L.t(lang, 'soil_update_record') : L.t(lang, 'soil_add_record'),
                    subtitle: L.t(lang, 'soil_form_intro'),
                    child: Column(
                      children: [
                  if (_farmsError != null)
                    ErrorBanner(
                      message: '${L.t(lang, 'soil_load_farms_failed')}: $_farmsError',
                      onRetry: _loadFarms,
                    ),
                  DropdownButtonFormField<int>(
                    key: ValueKey<String>(
                      'soil-farm-${_selectedFarmId ?? 'none'}-${_farms.length}-${_isLoadingFarms ? 'loading' : 'ready'}',
                    ),
                    initialValue: _farms.any((f) => f.id == _selectedFarmId) ? _selectedFarmId : null,
                    decoration: InputDecoration(
                      labelText: L.t(lang, 'farm_name'),
                      hintText: _isLoadingFarms
                          ? L.t(lang, 'soil_loading_farms')
                          : L.t(lang, 'soil_select_farm'),
                    ),
                    items: _farms
                        .map(
                          (farm) => DropdownMenuItem<int>(
                            value: farm.id,
                            child: Text(farm.farmName),
                          ),
                        )
                        .toList(),
                    onChanged: _isEditing || _isLoadingFarms
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedFarmId = value;
                              _selectedPlotId = null;
                              _plots = [];
                              _plotsError = null;
                            });
                            _loadPlots(value);
                          },
                    validator: (value) => value == null ? L.t(lang, 'fieldRequired') : null,
                  ),
                  const SizedBox(height: 12),
                  if (_plotsError != null)
                    ErrorBanner(
                      message: '${L.t(lang, 'soil_load_plots_failed')}: $_plotsError',
                      onRetry: () {
                        final farmId = _selectedFarmId;
                        if (farmId != null) {
                          _loadPlots(farmId);
                        }
                      },
                    ),
                  DropdownButtonFormField<int>(
                    key: ValueKey<String>(
                      'soil-plot-${_selectedFarmId ?? 'none'}-${_selectedPlotId ?? 'none'}-${_plots.length}-${_isLoadingPlots ? 'loading' : 'ready'}',
                    ),
                    initialValue: _plots.any((p) => p.id == _selectedPlotId) ? _selectedPlotId : null,
                    decoration: InputDecoration(
                      labelText: L.t(lang, 'plot_name'),
                      hintText: _selectedFarmId == null
                          ? L.t(lang, 'soil_select_farm_first')
                          : (_isLoadingPlots
                              ? L.t(lang, 'soil_loading_plots')
                              : L.t(lang, 'soil_select_plot')),
                    ),
                    items: _plots
                        .map(
                          (plot) => DropdownMenuItem<int>(
                            value: plot.id,
                            child: Text(plot.plotName),
                          ),
                        )
                        .toList(),
                    onChanged: (_isEditing || _selectedFarmId == null || _isLoadingPlots)
                        ? null
                        : (value) => setState(() => _selectedPlotId = value),
                    validator: (value) => value == null ? L.t(lang, 'fieldRequired') : null,
                  ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SoilFormSection(
                    title: L.t(lang, 'soil_test_method'),
                    subtitle: L.t(lang, 'soil_method_hint'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _soilMethodOptions.map((option) {
                      final selected = _selectedMethod == option.value;
                      final color = selected ? Theme.of(context).colorScheme.primary : Colors.blueGrey;
                      return ChoiceChip(
                        selected: selected,
                        onSelected: (value) {
                          if (!value) return;
                          setState(() => _selectedMethod = option.value);
                        },
                        selectedColor: Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              option.icon,
                              size: 16,
                              color: selected ? Colors.white : color,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              L.t(lang, option.labelKey),
                              style: TextStyle(
                                color: selected ? Colors.white : color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SoilFormSection(
                    title: L.t(lang, 'soil_evidence_optional'),
                    subtitle: L.t(lang, 'soil_evidence_hint'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickingEvidence ? null : () => _pickEvidence(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(L.t(lang, 'soil_take_photo')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickingEvidence ? null : () => _pickEvidence(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(L.t(lang, 'soil_pick_photo')),
                      ),
                    ],
                  ),
                  if (_evidenceFile != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(_evidenceFile!.path),
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _clearEvidence,
                        icon: const Icon(Icons.close),
                        label: Text(L.t(lang, 'soil_remove_photo')),
                      ),
                    ),
                  ] else if (_isEditing && hasExistingEvidence) ...[
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attachment_outlined),
                      title: Text(L.t(lang, 'soil_existing_evidence_kept')),
                      subtitle: Text(
                        existingEvidenceUrl.isNotEmpty ? existingEvidenceUrl : existingEvidencePath,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SoilFormSection(
                    title: L.t(lang, 'soil_values_title'),
                    subtitle: L.t(lang, 'soil_values_subtitle'),
                    child: Column(
                      children: [
                  TextFormField(
                    controller: _phController,
                    decoration: _compactInput(
                      L.t(lang, 'phLevel'),
                      hintText: L.t(lang, 'soil_hint_ph'),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final ph = double.tryParse(value.trim());
                      if (ph == null || ph < 0 || ph > 14) return L.t(lang, 'soil_error_valid_ph');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nitrogenController,
                    decoration: _compactInput(L.t(lang, 'nitrogenLevel')),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final n = double.tryParse(value.trim());
                      if (n == null || n < 0) return L.t(lang, 'soil_error_valid_percentage');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phosphorusController,
                    decoration: _compactInput(L.t(lang, 'phosphorusLevel')),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final p = double.tryParse(value.trim());
                      if (p == null || p < 0) return L.t(lang, 'soil_error_valid_percentage');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _potassiumController,
                    decoration: _compactInput(L.t(lang, 'potassiumLevel')),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final k = double.tryParse(value.trim());
                      if (k == null || k < 0) return L.t(lang, 'soil_error_valid_percentage');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _organicMatterController,
                    decoration: _compactInput(L.t(lang, 'organicMatter')),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final om = double.tryParse(value.trim());
                      if (om == null || om < 0) return L.t(lang, 'soil_error_valid_percentage');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _moistureController,
                    decoration: _compactInput(L.t(lang, 'soilMoisture')),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final m = double.tryParse(value.trim());
                      if (m == null || m < 0) return L.t(lang, 'soil_error_valid_percentage');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _soilTypeController,
                    decoration: _compactInput(
                      L.t(lang, 'soilTexture'),
                      hintText: L.t(lang, 'soil_hint_texture'),
                    ),
                  ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(L.t(lang, 'save')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}




