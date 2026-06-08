import 'package:flutter/material.dart';
import '../../../offline/offline_models.dart';
import '../../../offline/sync_state.dart';
import '../providers/farm_context_provider.dart';
import 'package:provider/provider.dart';
import '../alerts_mock.dart';
import '../../../language_store.dart';
import '../../../localization.dart';
import '../../../localized_value.dart';

class PlotListWidget extends StatelessWidget {
  final FarmRecord farm;
  final List<PlotRecord> plots;
  final VoidCallback? onAdd;
  final void Function(PlotRecord plot)? onEdit;
  final void Function(PlotRecord plot)? onDelete;

  const PlotListWidget({
    super.key,
    required this.farm,
    required this.plots,
    this.onAdd,
    this.onEdit,
    this.onDelete,
  });

  Widget? _syncIndicator(PlotRecord plot) {
    switch (plot.syncState) {
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: Text(farm.farmName),
              subtitle: Text(L.t(lang, 'my_farm_plot_header_sub')),
              onTap: () => Provider.of<FarmContextProvider>(
                context,
                listen: false,
              ).clearSelection(),
              trailing: onAdd == null
                  ? null
                  : IconButton(
                      onPressed: onAdd,
                      tooltip: L.t(lang, 'my_farm_add_plot'),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
            ),
            Expanded(
              child: plots.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.grid_view_rounded,
                              size: 42,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              L.t(
                                lang,
                                'no_plots_in',
                                params: {'farm': farm.farmName},
                              ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              L.t(lang, 'my_farm_empty_plots_help'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: plots.length,
                      itemBuilder: (context, index) {
                        final plot = plots[index];
                        final hasAlerts = plot.serverId == null
                            ? false
                            : hasAlertsForScope(plotId: plot.serverId!);
                        final syncIndicator = _syncIndicator(plot);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(
                              plot.plotName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${LocalizedValue.fixed(lang, 'soil_label')}: ${LocalizedValue.soilType(lang, plot.soilType.isEmpty ? 'unknown' : plot.soilType)} | '
                              '${plot.areaHectares?.toStringAsFixed(2) ?? '--'} ha',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                                if (onEdit != null || onDelete != null)
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        onEdit?.call(plot);
                                      } else if (value == 'delete') {
                                        onDelete?.call(plot);
                                      }
                                    },
                                    itemBuilder: (context) => [
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
                            ).setPlot(plot),
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
