import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/alert_model.dart';
import '../../connectivity_status_service.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../localized_value.dart';
import '../../api_client.dart';
import '../../sync_refresh_notifier.dart';
import '../../widgets/farm_ui.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _loading = false;
  String? _error;
  final List<AlertModel> _alerts = [];
  static const String _alertsCacheKey = 'alerts_cache_v1';

  @override
  void initState() {
    super.initState();
    syncRefreshNotifier.addListener(_handleSyncRefresh);
    _boot();
  }

  @override
  void dispose() {
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    super.dispose();
  }

  void _handleSyncRefresh() {
    if (!mounted) return;
    _loadAlerts();
  }

  Future<void> _boot() async {
    await _loadCachedAlerts();
    if (!mounted) return;
    _loadAlerts();
  }

  Map<String, dynamic> _alertToJson(AlertModel alert) {
    return <String, dynamic>{
      'id': alert.id,
      'disease_report_id': alert.diseaseReportId,
      'farm_id': alert.farmId,
      'plot_id': alert.plotId,
      'planting_id': alert.plantingId,
      'alert_type': alert.alertType,
      'severity': alert.severity,
      'title': alert.title,
      'message': alert.message,
      'status': alert.status,
      'is_preventive': alert.isPreventive,
      'risk_level': alert.riskLevel,
      'farm_name': alert.farmName,
      'plot_name': alert.plotName,
      'triggered_at': alert.triggeredAt.toIso8601String(),
    };
  }

  Future<void> _saveAlertsCache(List<AlertModel> alerts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = alerts.map(_alertToJson).toList(growable: false);
      await prefs.setString(_alertsCacheKey, jsonEncode(payload));
    } catch (_) {
      // Cache failures should not break UI.
    }
  }

  Future<bool> _loadCachedAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_alertsCacheKey)?.trim();
      if (raw == null || raw.isEmpty) {
        return false;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return false;
      }
      final cached = decoded
          .whereType<Map>()
          .map((e) => AlertModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (cached.isEmpty) {
        return false;
      }
      if (!mounted) return true;
      setState(() {
        _alerts
          ..clear()
          ..addAll(cached);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadAlerts() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fetched = <AlertModel>[];
      var page = 1;
      const perPage = 50;
      while (true) {
        final batch = await ApiClient.getAlerts(
          page: page,
          perPage: perPage,
        );
        fetched.addAll(batch);
        if (batch.length < perPage) break;
        page += 1;
      }
      await _saveAlertsCache(fetched);
      if (mounted) {
        setState(() {
          _loading = false;
          _alerts
            ..clear()
            ..addAll(fetched);
        });
      }
    } on ApiUnauthorized {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } on ApiForbidden {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = L.t(LanguageStore.notifier.value, 'alerts_access_denied');
        });
      }
    } on ApiException catch (e) {
      final state = ApiClient.classifyConnectivityMessage(e.message);
      final cached = await _loadCachedAlerts();
      final message = state == ApiConnectivityState.offline
          ? (cached
              ? L.t(LanguageStore.notifier.value, 'alerts_offline_saved')
              : L.t(LanguageStore.notifier.value, 'alerts_offline_none'))
          : state == ApiConnectivityState.internetOnly
              ? (cached
                  ? L.t(LanguageStore.notifier.value, 'alerts_api_unreachable_saved')
                  : L.t(LanguageStore.notifier.value, 'alerts_api_unreachable'))
              : L.t(LanguageStore.notifier.value, 'alerts_load_failed');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = L.t(LanguageStore.notifier.value, 'alerts_load_failed');
        });
      }
    }
  }

  Future<void> _acknowledgeAlert(AlertModel alert) async {
    if (!await _ensureServerActionAvailable()) {
      return;
    }
    try {
      await ApiClient.acknowledgeAlert(alert.id);
      if (!mounted) return;
      await _loadAlerts();
      if (!mounted) return;
      final lang = LanguageStore.notifier.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${L.t(lang, 'alerts_action_acknowledged_success')}\n${L.t(lang, 'action_next_alert_acknowledged')}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } on ApiUnauthorized {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } on ApiForbidden {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t(LanguageStore.notifier.value, 'alerts_ack_forbidden'))),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t(LanguageStore.notifier.value, 'alerts_ack_failed'))),
      );
    }
  }

  Future<bool> _ensureServerActionAvailable() async {
    final connectivity = ConnectivityStatusService.instance.notifier.value;
    if (connectivity.state != ApiConnectivityState.apiOnline) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L.t(LanguageStore.notifier.value, 'alerts_server_required'),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  void _showAlertDetails(AlertModel alert) {
    final lang = LanguageStore.notifier.value;
    final apiOnline =
        ConnectivityStatusService.instance.notifier.value.state == ApiConnectivityState.apiOnline;
    showModalBottomSheet(
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
              FarmPanel(
                color: _severityColor(alert.severity).withValues(alpha: 0.08),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _severityColor(alert.severity).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: _severityColor(alert.severity),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            alert.title,
                            style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1E2A12),
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SeverityBadge(severity: alert.severity, languageCode: lang),
                        _OverviewChip(
                          label: LocalizedValue.status(lang, alert.status),
                          color: _statusColor(alert.status.trim().toLowerCase()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      alert.status.toLowerCase() == 'resolved'
                          ? L.t(lang, 'alerts_next_resolved')
                          : alert.status.toLowerCase() == 'acknowledged'
                              ? L.t(lang, 'alerts_next_acknowledged')
                              : L.t(lang, 'alerts_next_open'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(alert.message),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (!apiOnline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    L.t(lang, 'alerts_server_required'),
                    style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
                  ),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(L.t(lang, 'technical_details')),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${L.t(lang, 'status')}: ${LocalizedValue.status(lang, alert.status)}'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${L.t(lang, 'alerts_severity_label')}: ${LocalizedValue.severity(lang, alert.severity)}',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${L.t(lang, 'alerts_triggered_at_label')}: ${_formatDate(alert.triggeredAt)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (alert.status == 'open')
                    ElevatedButton(
                      onPressed: apiOnline
                          ? () async {
                              Navigator.of(sheetContext).pop();
                              await _acknowledgeAlert(alert);
                            }
                          : null,
                      child: Text(L.t(lang, 'acknowledge')),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(L.t(lang, 'close')),
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        final openAlerts = _sortedAlerts(
          _alerts.where((alert) => alert.status.trim().toLowerCase() == 'open').toList(),
        );
        final acknowledgedAlerts = _sortedAlerts(
          _alerts.where((alert) => alert.status.trim().toLowerCase() == 'acknowledged').toList(),
        );
        final resolvedAlerts = _sortedAlerts(
          _alerts.where((alert) => alert.status.trim().toLowerCase() == 'resolved').toList(),
        );

        if (_loading) {
          return const FarmSurface(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (_error != null && _alerts.isEmpty) {
          return FarmSurface(
            child: Center(
              child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 52, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadAlerts,
                    icon: const Icon(Icons.refresh),
                    label: Text(L.t(lang, 'scan_retry')),
                  ),
                ],
              ),
              ),
            ),
          );
        }

        if (_alerts.isEmpty) {
          return FarmSurface(
            child: Center(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.grey),
                const SizedBox(height: 12),
                Text(L.t(lang, 'no_alerts')),
              ],
              ),
            ),
          );
        }

        return FarmSurface(
          padding: EdgeInsets.zero,
          child: RefreshIndicator(
            onRefresh: _loadAlerts,
            child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AlertsOverviewCard(
                languageCode: lang,
                openCount: openAlerts.length,
                acknowledgedCount: acknowledgedAlerts.length,
                resolvedCount: resolvedAlerts.length,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: const Color(0xFFFFF8E8),
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(_error!),
                    trailing: TextButton(
                      onPressed: _loadAlerts,
                      child: Text(L.t(lang, 'scan_retry')),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _AlertSection(
                languageCode: lang,
                title: L.t(lang, 'alerts_section_open'),
                subtitle: L.t(lang, 'alerts_section_open_subtitle'),
                alerts: openAlerts,
                onOpen: _showAlertDetails,
                onAcknowledge: _acknowledgeAlert,
              ),
              const SizedBox(height: 16),
              _AlertSection(
                languageCode: lang,
                title: L.t(lang, 'alerts_section_acknowledged'),
                subtitle: L.t(lang, 'alerts_section_acknowledged_subtitle'),
                alerts: acknowledgedAlerts,
                onOpen: _showAlertDetails,
                onAcknowledge: _acknowledgeAlert,
              ),
              const SizedBox(height: 16),
              _AlertSection(
                languageCode: lang,
                title: L.t(lang, 'alerts_section_resolved'),
                subtitle: L.t(lang, 'alerts_section_resolved_subtitle'),
                alerts: resolvedAlerts,
                onOpen: _showAlertDetails,
                onAcknowledge: _acknowledgeAlert,
              ),
            ],
            ),
          ),
        );
      },
    );
  }

  List<AlertModel> _sortedAlerts(List<AlertModel> alerts) {
    final sorted = List<AlertModel>.from(alerts);
    sorted.sort((a, b) {
      final severityCompare = _severityRank(b.severity).compareTo(_severityRank(a.severity));
      if (severityCompare != 0) return severityCompare;
      return b.triggeredAt.compareTo(a.triggeredAt);
    });
    return sorted;
  }
}

class _AlertsOverviewCard extends StatelessWidget {
  final String languageCode;
  final int openCount;
  final int acknowledgedCount;
  final int resolvedCount;

  const _AlertsOverviewCard({
    required this.languageCode,
    required this.openCount,
    required this.acknowledgedCount,
    required this.resolvedCount,
  });

  @override
  Widget build(BuildContext context) {
    return FarmPanel(
      color: const Color(0xFFFFFDF5),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.notifications_active_outlined, color: Color(0xFFC62828)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    L.t(languageCode, 'alerts_overview_title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1E2A12),
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              L.t(languageCode, 'alerts_overview_subtitle'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OverviewChip(
                  label: L.t(languageCode, 'alerts_overview_open', params: {'count': '$openCount'}),
                  color: Colors.red.shade700,
                ),
                _OverviewChip(
                  label: L.t(
                    languageCode,
                    'alerts_overview_acknowledged',
                    params: {'count': '$acknowledgedCount'},
                  ),
                  color: Colors.orange.shade700,
                ),
                _OverviewChip(
                  label: L.t(
                    languageCode,
                    'alerts_overview_resolved',
                    params: {'count': '$resolvedCount'},
                  ),
                  color: Colors.green.shade700,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewChip extends StatelessWidget {
  final String label;
  final Color color;

  const _OverviewChip({required this.label, required this.color});

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
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AlertSection extends StatelessWidget {
  final String languageCode;
  final String title;
  final String subtitle;
  final List<AlertModel> alerts;
  final ValueChanged<AlertModel> onOpen;
  final Future<void> Function(AlertModel alert) onAcknowledge;

  const _AlertSection({
    required this.languageCode,
    required this.title,
    required this.subtitle,
    required this.alerts,
    required this.onOpen,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return FarmPanel(
        color: const Color(0xFFF8FBEC),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        for (final alert in alerts)
          _AlertListCard(
            alert: alert,
            languageCode: languageCode,
            onOpen: onOpen,
            onAcknowledge: onAcknowledge,
          ),
      ],
    );
  }
}

class _AlertListCard extends StatelessWidget {
  final AlertModel alert;
  final String languageCode;
  final ValueChanged<AlertModel> onOpen;
  final Future<void> Function(AlertModel alert) onAcknowledge;

  const _AlertListCard({
    required this.alert,
    required this.languageCode,
    required this.onOpen,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final status = alert.status.trim().toLowerCase();
    final apiOnline =
        ConnectivityStatusService.instance.notifier.value.state == ApiConnectivityState.apiOnline;
    final contextLabel = _alertContextLabel(alert);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FarmPanel(
      color: const Color(0xFFFFFDF5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => onOpen(alert),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _severityColor(alert.severity).withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.warning_amber_rounded, color: _severityColor(alert.severity)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1E2A12),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _nextStepText(languageCode, status),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.blueGrey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              alert.message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OverviewChip(
                  label: _alertTypeLabel(languageCode, alert),
                  color: alert.isPreventive ? Colors.blue.shade700 : Colors.purple.shade700,
                ),
                if (contextLabel != null)
                  _OverviewChip(
                    label: contextLabel,
                    color: Colors.teal.shade700,
                  ),
                _SeverityBadge(severity: alert.severity, languageCode: languageCode),
                _OverviewChip(
                  label:
                      '${L.t(languageCode, 'status')}: ${LocalizedValue.status(languageCode, alert.status)}',
                  color: _statusColor(status),
                ),
                if (alert.riskLevel != null)
                  _OverviewChip(
                    label: L.t(
                      languageCode,
                      'alerts_risk_level',
                      params: {'value': '${(alert.riskLevel! * 100).toStringAsFixed(0)}%'},
                    ),
                    color: Colors.indigo.shade700,
                  ),
                _OverviewChip(
                  label: _formatDate(alert.triggeredAt),
                  color: Colors.blueGrey,
                ),
              ],
            ),
            if (status == 'open') ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status == 'open')
                    OutlinedButton(
                      onPressed: apiOnline ? () => onAcknowledge(alert) : null,
                      child: Text(L.t(languageCode, 'acknowledge')),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  final String severity;
  final String? languageCode;

  const _SeverityBadge({required this.severity, this.languageCode});

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        LocalizedValue.severity(languageCode ?? 'en', severity),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

Color _severityColor(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
      return Colors.red;
    case 'high':
      return Colors.deepOrange;
    case 'medium':
      return Colors.orange;
    case 'low':
      return Colors.amber;
    default:
      return Colors.grey;
  }
}

Color _statusColor(String status) {
  switch (status.trim().toLowerCase()) {
    case 'open':
      return Colors.red.shade700;
    case 'acknowledged':
      return Colors.orange.shade700;
    case 'resolved':
      return Colors.green.shade700;
    default:
      return Colors.blueGrey.shade700;
  }
}

int _severityRank(String severity) {
  switch (severity.trim().toLowerCase()) {
    case 'critical':
      return 4;
    case 'high':
      return 3;
    case 'medium':
      return 2;
    case 'low':
      return 1;
    default:
      return 0;
  }
}

String _nextStepText(String languageCode, String status) {
  switch (status) {
    case 'resolved':
      return L.t(languageCode, 'alerts_next_resolved');
    case 'acknowledged':
      return L.t(languageCode, 'alerts_next_acknowledged');
    case 'open':
    default:
      return L.t(languageCode, 'alerts_next_open');
  }
}

String _alertTypeLabel(String languageCode, AlertModel alert) {
  if (alert.isPreventive) {
    return L.t(languageCode, 'alerts_type_preventive');
  }
  return L.t(languageCode, 'alerts_type_confirmed_disease');
}

String? _alertContextLabel(AlertModel alert) {
  final plot = alert.plotName?.trim();
  if (plot != null && plot.isNotEmpty) return plot;
  final farm = alert.farmName?.trim();
  if (farm != null && farm.isNotEmpty) return farm;
  return null;
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}






