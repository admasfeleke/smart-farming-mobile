import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_farm/features/my_farm/my_farm_screen.dart';
import 'package:smart_farm/features/my_farm/providers/farm_context_provider.dart';
import 'package:smart_farm/features/my_farm/widgets/farm_list_widget.dart';
import 'package:smart_farm/features/my_farm/widgets/planting_list_widget.dart';
import 'package:smart_farm/features/my_farm/widgets/plot_list_widget.dart';
import 'package:smart_farm/language_store.dart';
import 'package:smart_farm/offline/offline_models.dart';
import 'package:smart_farm/offline/sync_state.dart';

FarmRecord _farmRecord({required int localId, required String name}) {
  return FarmRecord(
    localId: localId,
    serverId: localId,
    regionId: 1,
    farmName: name,
    latitude: 9.0,
    longitude: 38.0,
    areaHectares: 10.5,
    farmType: 'crop',
    isActive: true,
    localUpdatedAt: DateTime(2026, 1, 1),
    serverCreatedAt: DateTime(2026, 1, 1),
    serverUpdatedAt: DateTime(2026, 1, 1),
    baseServerUpdatedAt: DateTime(2026, 1, 1),
    syncState: SyncState.synced,
    deleted: false,
    conflictReason: null,
    syncAttempts: 0,
    nextRetryAt: null,
    syncError: null,
  );
}

PlotRecord _plotRecord({required int localId, required int farmLocalId, required String name}) {
  return PlotRecord(
    localId: localId,
    serverId: localId,
    farmLocalId: farmLocalId,
    farmServerId: farmLocalId,
    plotName: name,
    areaHectares: 2.5,
    soilType: 'loam',
    isActive: true,
    localUpdatedAt: DateTime(2026, 1, 1),
    serverCreatedAt: DateTime(2026, 1, 1),
    serverUpdatedAt: DateTime(2026, 1, 1),
    baseServerUpdatedAt: DateTime(2026, 1, 1),
    syncState: SyncState.synced,
    deleted: false,
    conflictReason: null,
    syncAttempts: 0,
    nextRetryAt: null,
    syncError: null,
  );
}

PlantingRecord _plantingRecord({required int localId, required int plotLocalId}) {
  return PlantingRecord(
    localId: localId,
    serverId: localId,
    plotLocalId: plotLocalId,
    plotServerId: plotLocalId,
    cropId: 1,
    plantingDate: DateTime(2026, 2, 1),
    expectedHarvestDate: DateTime(2026, 6, 1),
    status: 'active',
    isActive: true,
    localUpdatedAt: DateTime(2026, 2, 1),
    serverCreatedAt: DateTime(2026, 2, 1),
    serverUpdatedAt: DateTime(2026, 2, 1),
    baseServerUpdatedAt: DateTime(2026, 2, 1),
    syncState: SyncState.synced,
    deleted: false,
    conflictReason: null,
    syncAttempts: 0,
    nextRetryAt: null,
    syncError: null,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'language': 'en',
    });
    await LanguageStore.setLanguage('en');
  });

  test('FarmContextProvider selection transitions are correct', () {
    final provider = FarmContextProvider();
    final farm = _farmRecord(localId: 1, name: 'Main Farm');
    final plot = _plotRecord(localId: 11, farmLocalId: 1, name: 'North Plot');
    final planting = _plantingRecord(localId: 101, plotLocalId: 11);

    provider.setFarm(farm);
    expect(provider.selectedFarm?.id, 1);
    expect(provider.selectedPlot, isNull);
    expect(provider.selectedPlanting, isNull);

    provider.setPlot(plot);
    expect(provider.selectedPlot?.id, 11);
    expect(provider.selectedPlanting, isNull);

    provider.setPlanting(planting);
    expect(provider.selectedPlanting?.id, 101);

    provider.clearPlotSelection();
    expect(provider.selectedFarm?.id, 1);
    expect(provider.selectedPlot, isNull);
    expect(provider.selectedPlanting, isNull);

    provider.clearSelection();
    expect(provider.selectedFarm, isNull);
    expect(provider.selectedPlot, isNull);
    expect(provider.selectedPlanting, isNull);
  });

  testWidgets('FarmListWidget tap sets selected farm', (tester) async {
    final provider = FarmContextProvider();
    final farm = _farmRecord(localId: 1, name: 'Alpha Farm');

    await tester.pumpWidget(
      ChangeNotifierProvider<FarmContextProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: FarmListWidget(
              farms: [farm],
              plotCounts: const {1: 2},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Alpha Farm'));
    await tester.pump();

    expect(provider.selectedFarm?.id, 1);
  });

  testWidgets('PlotListWidget back clears farm selection and tap sets plot', (tester) async {
    final provider = FarmContextProvider();
    final farm = _farmRecord(localId: 1, name: 'Alpha Farm');
    final plot = _plotRecord(localId: 11, farmLocalId: 1, name: 'North Plot');
    provider.setFarm(farm);

    await tester.pumpWidget(
      ChangeNotifierProvider<FarmContextProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: PlotListWidget(
              farm: farm,
              plots: [plot],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('North Plot'));
    await tester.pump();
    expect(provider.selectedPlot?.id, 11);

    await tester.tap(find.text('Alpha Farm'));
    await tester.pump();
    expect(provider.selectedFarm, isNull);
    expect(provider.selectedPlot, isNull);
  });

  testWidgets('PlantingListWidget back clears plot selection and tap sets planting', (
    tester,
  ) async {
    final provider = FarmContextProvider();
    final farm = _farmRecord(localId: 1, name: 'Alpha Farm');
    final plot = _plotRecord(localId: 11, farmLocalId: 1, name: 'North Plot');
    final planting = _plantingRecord(localId: 101, plotLocalId: 11);
    provider.setFarm(farm);
    provider.setPlot(plot);

    await tester.pumpWidget(
      ChangeNotifierProvider<FarmContextProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: PlantingListWidget(
              plot: plot,
              plantings: [planting],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Crop ID: 1'));
    await tester.pump();
    expect(provider.selectedPlanting?.id, 101);

    await tester.tap(find.text('North Plot'));
    await tester.pump();
    expect(provider.selectedFarm?.id, 1);
    expect(provider.selectedPlot, isNull);
    expect(provider.selectedPlanting, isNull);
  });

  testWidgets('MyFarmScreen redirects to login when token is missing', (tester) async {
    SharedPreferences.setMockInitialValues({
      'language': 'en',
    });
    await LanguageStore.setLanguage('en');

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FarmContextProvider(),
        child: MaterialApp(
          routes: {
            '/login': (_) => const Scaffold(body: SizedBox(key: Key('login-screen'))),
          },
          home: const Scaffold(body: MyFarmScreen()),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-screen')), findsOneWidget);
  });
}
