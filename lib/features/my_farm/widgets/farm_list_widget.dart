import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../offline/offline_models.dart';
import '../../../offline/sync_state.dart';
import '../providers/farm_context_provider.dart';
import '../alerts_mock.dart';
import '../../../language_store.dart';
import '../../../localization.dart';

class FarmListWidget extends StatelessWidget {
  final List<FarmRecord> farms;
  final Map<int, int> plotCounts;
  final VoidCallback? onAdd;
  final void Function(FarmRecord farm)? onEdit;
  final void Function(FarmRecord farm)? onDelete;

  const FarmListWidget({
    super.key,
    required this.farms,
    this.plotCounts = const {},
    this.onAdd,
    this.onEdit,
    this.onDelete,
  });

  Widget? _syncIndicator(FarmRecord farm) {
    switch (farm.syncState) {
      case SyncState.pending:
        return const Icon(Icons.cloud_upload_outlined, size: 18, color: Colors.orange);
      case SyncState.failed:
        return const Icon(Icons.sync_problem, size: 18, color: Colors.orange);
      case SyncState.conflict:
        return const Icon(Icons.error_outline, size: 18, color: Colors.redAccent);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L.t(lang, 'my_farm'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L.t(lang, 'my_farm_context_hint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (onAdd != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: onAdd,
                          icon: const Icon(Icons.add),
                          label: Text(L.t(lang, 'my_farm_add_farm')),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: farms.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.agriculture, size: 42, color: Colors.grey.shade600),
                            const SizedBox(height: 10),
                            Text(
                              L.t(lang, 'no_farms'),
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              L.t(lang, 'my_farm_empty_farms_help'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: farms.length,
                      itemBuilder: (context, index) {
                        final farm = farms[index];
                        final plotCount = plotCounts[farm.id] ?? 0;
                        final hasAlerts = farm.serverId == null
                            ? false
                            : hasAlertsForScope(farmId: farm.serverId!);
                        final syncIndicator = _syncIndicator(farm);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(farm.farmName),
                            subtitle: Text(
                              '$plotCount ${L.t(lang, 'plots')} | '
                              '${farm.areaHectares?.toStringAsFixed(2) ?? '--'} ha',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (syncIndicator != null) ...[
                                  syncIndicator,
                                  const SizedBox(width: 6),
                                ],
                                if (hasAlerts)
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                if (onEdit != null)
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => onEdit?.call(farm),
                                  ),
                                if (onDelete != null)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    onPressed: () => onDelete?.call(farm),
                                  ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            onTap: () => Provider.of<FarmContextProvider>(context, listen: false)
                                .setFarm(farm),
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
