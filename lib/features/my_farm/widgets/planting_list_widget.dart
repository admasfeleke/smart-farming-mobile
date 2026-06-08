import 'package:flutter/material.dart';
import '../../../offline/offline_models.dart';
import '../../../offline/sync_state.dart';
import '../providers/farm_context_provider.dart';
import 'package:provider/provider.dart';
import '../alerts_mock.dart';
import '../../../language_store.dart';
import '../../../localization.dart';
import '../../../localized_value.dart';
import '../../soil_health/soil_health_screen.dart';

class PlantingListWidget extends StatelessWidget {
  final PlotRecord plot;
  final List<PlantingRecord> plantings;
  final String Function(int cropId)? cropNameForId;
  final VoidCallback? onAdd;
  final void Function(PlantingRecord planting)? onEdit;
  final void Function(PlantingRecord planting)? onDelete;
  final void Function(PlantingRecord planting)? onPredictYield;

  const PlantingListWidget({
    super.key,
    required this.plot,
    required this.plantings,
    this.cropNameForId,
    this.onAdd,
    this.onEdit,
    this.onDelete,
    this.onPredictYield,
  });

  Widget? _syncIndicator(PlantingRecord planting) {
    switch (planting.syncState) {
      case SyncState.pending:
        return const Icon(
          Icons.cloud_upload_outlined,
          size: 18,
          color: Colors.orange,
        );
      case SyncState.failed:
        return const Icon(Icons.sync_problem, size: 18, color: Colors.orange);
      case SyncState.conflict:
        return const Icon(
          Icons.error_outline,
          size: 18,
          color: Colors.redAccent,
        );
      case SyncState.synced:
        return null;
    }
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status.trim().toLowerCase()) {
      case 'planned':
        return Colors.blue.shade700;
      case 'active':
        return Colors.green.shade700;
      case 'harvested':
        return Colors.brown.shade700;
      case 'failed':
        return scheme.error;
      default:
        return Colors.grey.shade700;
    }
  }

  String _dateLabel(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        final colorScheme = Theme.of(context).colorScheme;
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: Text(plot.plotName),
              subtitle: Text(L.t(lang, 'my_farm_planting_header_sub')),
              onTap: () => Provider.of<FarmContextProvider>(
                context,
                listen: false,
              ).clearPlotSelection(),
              trailing: onAdd == null
                  ? null
                  : IconButton(
                      onPressed: onAdd,
                      tooltip: L.t(lang, 'my_farm_add_planting'),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SoilHealthScreen(
                        initialPlotId: plot.localId,
                        initialFarmId: plot.farmLocalId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.science),
                label: Text(L.t(lang, 'soilHealthMonitoring')),
              ),
            ),
            Expanded(
              child: plantings.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.spa_outlined,
                              size: 42,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              L.t(lang, 'no_plantings'),
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              L.t(lang, 'my_farm_empty_plantings_help'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: plantings.length,
                      itemBuilder: (context, index) {
                        final planting = plantings[index];
                        final cropLabel =
                            cropNameForId?.call(planting.cropId) ??
                            '${L.t(lang, 'crop_id')}: ${planting.cropId}';
                        final statusColor = _statusColor(
                          planting.status,
                          colorScheme,
                        );
                        final hasAlerts = planting.serverId == null
                            ? false
                            : hasAlertsForScope(plantingId: planting.serverId!);
                        final syncIndicator = _syncIndicator(planting);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(
                              cropLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${L.t(lang, 'planting_date')}: ${_dateLabel(planting.plantingDate)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${L.t(lang, 'status_label')}: ${LocalizedValue.status(lang, planting.status)}',
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (syncIndicator != null) ...[
                                  syncIndicator,
                                  const SizedBox(width: 4),
                                ],
                                if (hasAlerts)
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                if (onPredictYield != null ||
                                    onEdit != null ||
                                    onDelete != null)
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    onSelected: (value) {
                                      if (value == 'yield') {
                                        onPredictYield?.call(planting);
                                      } else if (value == 'edit') {
                                        onEdit?.call(planting);
                                      } else if (value == 'delete') {
                                        onDelete?.call(planting);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (onPredictYield != null)
                                        PopupMenuItem(
                                          value: 'yield',
                                          child: Text(
                                            LocalizedValue.fixed(
                                              lang,
                                              'yield_prediction_short',
                                            ),
                                          ),
                                        ),
                                      if (onEdit != null)
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text(L.t(lang, 'edit')),
                                        ),
                                      if (onDelete != null)
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(L.t(lang, 'delete')),
                                        ),
                                    ],
                                  ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            onTap: () => Provider.of<FarmContextProvider>(
                              context,
                              listen: false,
                            ).setPlanting(planting),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
