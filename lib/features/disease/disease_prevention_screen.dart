import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../auth_session.dart';
import '../../connectivity_status_service.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../offline/local_cache_store.dart';
import '../../offline/offline_models.dart';
import '../../offline/offline_repository.dart';
import '../../reference/reference_data.dart';
import '../../sync_refresh_notifier.dart';
import '../../widgets/farm_ui.dart';

class DiseasePreventionScreen extends StatefulWidget {
  final int? initialFarmId;
  final int? initialPlotId;
  final int? initialCropId;

  const DiseasePreventionScreen({
    super.key,
    this.initialFarmId,
    this.initialPlotId,
    this.initialCropId,
  });

  @override
  State<DiseasePreventionScreen> createState() => _DiseasePreventionScreenState();
}

class _DiseasePreventionScreenState extends State<DiseasePreventionScreen> {
  static const String _cropCacheKey = 'disease_prevention_crops_cache_v1';

  final _temperatureController = TextEditingController();
  final _humidityController = TextEditingController();
  final _precipitationController = TextEditingController();
  final _soilMoistureController = TextEditingController();

  bool _loading = true;
  bool _loadingPlots = false;
  bool _requesting = false;
  String? _error;

  List<FarmRecord> _farms = <FarmRecord>[];
  List<PlotRecord> _plots = <PlotRecord>[];
  List<Map<String, dynamic>> _crops = <Map<String, dynamic>>[];
  int? _selectedFarmId;
  int? _selectedPlotId;
  int? _selectedCropId;
  Map<String, dynamic> _recommendations = <String, dynamic>{};
  DateTime? _recommendationsCachedAt;

  String _dpText(String lang, String key) {
    const values = <String, Map<String, String>>{
      'en': {
        'headline': 'Prevention summary',
        'risk_drivers': 'Why the risk changed',
        'watch_items': 'What to watch',
        'actions': 'What to do now',
      },
      'am': {
        'headline': 'የመከላከያ ማጠቃለያ',
        'risk_drivers': 'አደጋው ለምን ተለወጠ',
        'watch_items': 'የሚታዩ ነገሮች',
        'actions': 'አሁን የሚወሰዱ እርምጃዎች',
      },
      'om': {
        'headline': 'Cuunfaa ittisaa',
        'risk_drivers': 'Balaan maaliif jijjiirame',
        'watch_items': 'Maal ilaalu',
        'actions': 'Amma maal gochuu',
      },
      'ti': {
        'headline': 'ሓፈሻዊ መከላኸሊ',
        'risk_drivers': 'ሓደጋ ስለምንታይ ተቐይሩ',
        'watch_items': 'እንታይ ክትከታተሉ',
        'actions': 'ሕጂ እንታይ ክትገብሩ',
      },
    };
    return values[lang]?[key] ?? values['en']![key]!;
  }

  @override
  void initState() {
    super.initState();
    _selectedFarmId = widget.initialFarmId;
    _selectedPlotId = widget.initialPlotId;
    _selectedCropId = widget.initialCropId;
    syncRefreshNotifier.addListener(_handleSyncRefresh);
    _load();
  }

  @override
  void dispose() {
    syncRefreshNotifier.removeListener(_handleSyncRefresh);
    _temperatureController.dispose();
    _humidityController.dispose();
    _precipitationController.dispose();
    _soilMoistureController.dispose();
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

    final farms = await OfflineRepository.instance.listFarms();
    final cachedCrops = await LocalCacheStore.instance.readList(_cropCacheKey);
    final cachedCropItems = (cachedCrops ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    final fallbackCrops = ReferenceData.mergeByIdThenName(
      cachedCropItems,
      ReferenceData.crops,
    );
    if (mounted) {
      setState(() {
        _farms = farms;
        _crops = fallbackCrops;
      });
    }

    try {
      final crops = <Map<String, dynamic>>[];
      var page = 1;
      const perPage = 200;

      while (true) {
        final batch = await ApiClient.getCrops(page: page, perPage: perPage);
        crops.addAll(
          batch.where(
            (item) => item['is_active'] == null || item['is_active'] == 1 || item['is_active'] == true,
          ),
        );
        if (batch.length < perPage) break;
        page += 1;
      }
      final mergedCrops = ReferenceData.mergeByIdThenName(
        crops,
        ReferenceData.crops,
      );
      await LocalCacheStore.instance.write(_cropCacheKey, mergedCrops);

      if (!mounted) return;
      final selectedCropId = mergedCrops.any((crop) => _intValue(crop['id']) == _selectedCropId)
          ? _selectedCropId
          : null;
      setState(() {
        _farms = farms;
        _crops = mergedCrops;
        _selectedCropId = selectedCropId;
        _loading = false;
      });

      final farmId = _selectedFarmId;
      if (farmId != null) {
        await _loadPlots(farmId);
      }
      await _prefillFromLatestWeather();
    } on ApiUnauthorized {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = fallbackCrops.isNotEmpty
            ? L.t(
                LanguageStore.notifier.value,
                'disease_prevention_saved_crop_list',
                params: {'error': e.toString()},
              )
            : e.toString();
      });
    }
  }

  Future<void> _loadPlots(int farmId) async {
    setState(() {
      _loadingPlots = true;
      _plots = <PlotRecord>[];
    });

    try {
      final plots = await OfflineRepository.instance.listPlotsByFarmLocalId(farmId);
      var plotId = _selectedPlotId;
      if (plotId != null && !plots.any((plot) => plot.id == plotId)) {
        plotId = null;
      }
      if (plotId == null && plots.length == 1) {
        plotId = plots.first.id;
      }

      if (!mounted) return;
      setState(() {
        _plots = plots;
        _selectedPlotId = plotId;
        _loadingPlots = false;
      });

      if (plotId != null) {
        await _maybeAutofillCrop(plotId);
        await _prefillFromLatestSoilHealth(plotId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPlots = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _maybeAutofillCrop(int plotId) async {
    final plantings = await OfflineRepository.instance.listPlantingsByPlotLocalId(plotId);
    PlantingRecord? candidate;
    for (final planting in plantings) {
      if (planting.status.trim().toLowerCase() == 'active') {
        candidate = planting;
        break;
      }
    }
    candidate ??= plantings.isNotEmpty ? plantings.first : null;
    if (candidate == null) return;

    final cropId = candidate.cropId;
    if (!_crops.any((crop) => _intValue(crop['id']) == cropId)) return;

    if (!mounted) return;
    setState(() {
      _selectedCropId = cropId;
    });
  }

  Future<void> _prefillFromLatestSoilHealth(int plotId) async {
    final records = await OfflineRepository.instance.listSoilHealth(plotLocalId: plotId);
    if (records.isEmpty || !mounted) return;
    final latest = records.first;
    final changed = _setIfEmpty(_soilMoistureController, latest.moistureLevel);
    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<void> _prefillFromLatestWeather() async {
    final records = await LocalCacheStore.instance.readList('weather_records_cache_v1');
    final items = (records ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    if (items.isEmpty || !mounted) return;
    final latest = items.first;
    var changed = false;
    changed = _setIfEmpty(_temperatureController, latest['temperature']) || changed;
    changed = _setIfEmpty(_humidityController, latest['humidity']) || changed;
    changed = _setIfEmpty(_precipitationController, latest['precipitation']) || changed;
    changed = _setIfEmpty(_soilMoistureController, latest['soil_moisture']) || changed;
    if (changed && mounted) {
      setState(() {});
    }
  }

  bool _setIfEmpty(TextEditingController controller, dynamic value) {
    if (controller.text.trim().isNotEmpty) return false;
    final number = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (number == null) return false;
    controller.text = _formatNumber(number);
    return true;
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  double? _parse(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _isKnownCropId(int? cropId) {
    if (cropId == null) return false;
    return _crops.any((crop) => _intValue(crop['id']) == cropId);
  }

  String _cropLabel(int? cropId) {
    if (cropId == null) return L.t(LanguageStore.notifier.value, 'select_crop');
    for (final crop in _crops) {
      if (_intValue(crop['id']) == cropId) {
        final name = crop['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) return name;
      }
    }
    return '${L.t(LanguageStore.notifier.value, 'crop')} #$cropId';
  }

  Future<void> _loadRecommendations() async {
    final selectedCropId = _selectedCropId;
    if (!_isKnownCropId(selectedCropId)) {
      setState(() {
        _selectedCropId = null;
        _error = L.t(LanguageStore.notifier.value, 'disease_prevention_choose_crop_first');
      });
      return;
    }
    final cropId = selectedCropId!;

    setState(() {
      _requesting = true;
      _error = null;
    });

    try {
      final response = await ApiClient.getDiseasePreventionRecommendations(
        cropId: cropId,
        temperature: _parse(_temperatureController),
        humidity: _parse(_humidityController),
        precipitation: _parse(_precipitationController),
        soilMoisture: _parse(_soilMoistureController),
      );
      await LocalCacheStore.instance.write(
        _recommendationsCacheKey(cropId, _selectedFarmId, _selectedPlotId),
        response,
      );
      if (!mounted) return;
      setState(() {
        _recommendations = response;
        _recommendationsCachedAt = DateTime.now();
        _requesting = false;
      });
    } on ApiUnauthorized {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      final cachedEntry = await LocalCacheStore.instance.read(
        _recommendationsCacheKey(cropId, _selectedFarmId, _selectedPlotId),
      );
      final payload = cachedEntry?.payload;
      if (!mounted) return;
      setState(() {
        _requesting = false;
        if (payload is Map<String, dynamic>) {
          _recommendations = payload;
          _recommendationsCachedAt = cachedEntry?.updatedAt;
          _error = L.t(
            LanguageStore.notifier.value,
            'disease_prevention_saved_guidance',
            params: {'error': e.toString()},
          );
        } else {
          _error = e.toString();
        }
      });
    }
  }

  Future<void> _runAnalysis() async {
    if (!await _ensureServerActionAvailable()) {
      return;
    }
    setState(() {
      _requesting = true;
      _error = null;
    });

    try {
      final response = await ApiClient.runDiseasePreventionAnalysis(
        farmId: _selectedFarmId,
        plotId: _selectedPlotId,
        cropId: _selectedCropId,
        temperature: _parse(_temperatureController),
        humidity: _parse(_humidityController),
        precipitation: _parse(_precipitationController),
        soilMoisture: _parse(_soilMoistureController),
      );
      if (!mounted) return;
      setState(() {
        _requesting = false;
      });
      final result = response['result'] is Map<String, dynamic>
          ? response['result'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final alertsCreated = result['alerts_created']?.toString() ?? '0';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L.t(
              LanguageStore.notifier.value,
              'disease_prevention_analysis_completed',
              params: {'count': alertsCreated},
            ),
          ),
        ),
      );
    } on ApiUnauthorized {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _requesting = false;
        _error = L.t(
          LanguageStore.notifier.value,
          'disease_prevention_analysis_failed',
          params: {'error': e.toString()},
        );
      });
    }
  }

  String _recommendationsCacheKey(int cropId, int? farmId, int? plotId) {
    return 'disease_prevention_recommendations_${cropId}_${farmId ?? 0}_${plotId ?? 0}';
  }

  Future<bool> _ensureServerActionAvailable() async {
    final offlineMode = await AuthSession.isOfflineModeActive();
    final connectivity = ConnectivityStatusService.instance.notifier.value;
    if (offlineMode || connectivity.state != ApiConnectivityState.apiOnline) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L.t(
              LanguageStore.notifier.value,
              'disease_prevention_analysis_server_required',
            ),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageStore.notifier,
      builder: (context, lang, _) {
        final serverAvailable =
            ConnectivityStatusService.instance.notifier.value.state == ApiConnectivityState.apiOnline;
        final analysis = _recommendations['analysis'] is Map<String, dynamic>
            ? _recommendations['analysis'] as Map<String, dynamic>
            : const <String, dynamic>{};
        final recommendations = _recommendations['recommendations'] is List
            ? (_recommendations['recommendations'] as List<dynamic>).map((e) => e.toString()).toList()
            : const <String>[];

        return Scaffold(
          appBar: AppBar(
            title: Text(L.t(lang, 'disease_prevention')),
          ),
          body: FarmSurface(
            padding: EdgeInsets.zero,
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
              children: [
                FarmHeroCard(
                  imageAsset: 'assets/images/home/field_prevention.jpg',
                  eyebrow: L.t(lang, 'disease_prevention'),
                  title: _cropLabel(_selectedCropId),
                  body: L.t(lang, 'disease_prevention_intro'),
                  trailing: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.shield_outlined, color: Color(0xFF41670F), size: 30),
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  FarmPanel(
                    color: const Color(0xFFFFEFE9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_recommendationsCachedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      L.t(
                        lang,
                        'disease_prevention_saved_guidance_at',
                        params: {'time': DateFormat('MMM dd, HH:mm').format(_recommendationsCachedAt!.toLocal())},
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
                                color: const Color(0xFFDDEF9D),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.tune_rounded, color: Color(0xFF41670F)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                L.t(lang, 'yield_prediction_current_conditions'),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1E2A12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          key: ValueKey<String>('prevent-farm-${_selectedFarmId ?? 'none'}-${_farms.length}'),
                          initialValue: _farms.any((farm) => farm.id == _selectedFarmId) ? _selectedFarmId : null,
                          decoration: InputDecoration(labelText: L.t(lang, 'farm_name'), border: const OutlineInputBorder()),
                          items: _farms.map((farm) => DropdownMenuItem<int>(value: farm.id, child: Text(farm.farmName))).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedFarmId = value;
                              _selectedPlotId = null;
                              _plots = <PlotRecord>[];
                            });
                            if (value != null) _loadPlots(value);
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          key: ValueKey<String>('prevent-plot-${_selectedFarmId ?? 'none'}-${_selectedPlotId ?? 'none'}-${_plots.length}'),
                          initialValue: _plots.any((plot) => plot.id == _selectedPlotId) ? _selectedPlotId : null,
                          decoration: InputDecoration(
                            labelText: L.t(lang, 'plot_name'),
                            border: const OutlineInputBorder(),
                            hintText: _selectedFarmId == null
                                ? L.t(lang, 'scan_select_farm_first')
                                : (_loadingPlots ? L.t(lang, 'disease_prevention_loading_plots') : L.t(lang, 'disease_prevention_select_plot')),
                          ),
                          items: _plots.map((plot) => DropdownMenuItem<int>(value: plot.id, child: Text(plot.plotName))).toList(),
                          onChanged: _selectedFarmId == null || _loadingPlots
                              ? null
                              : (value) {
                                  setState(() => _selectedPlotId = value);
                                  if (value != null) {
                                    _maybeAutofillCrop(value);
                                    _prefillFromLatestSoilHealth(value);
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          key: ValueKey<String>('prevent-crop-${_selectedCropId ?? 'none'}-${_crops.length}'),
                          initialValue: _crops.any((crop) => _intValue(crop['id']) == _selectedCropId) ? _selectedCropId : null,
                          decoration: InputDecoration(labelText: L.t(lang, 'crop'), border: const OutlineInputBorder()),
                          items: _crops.map((crop) => DropdownMenuItem<int>(value: _intValue(crop['id']), child: Text(crop['name']?.toString() ?? L.t(lang, 'crop')))).toList(),
                          onChanged: (value) => setState(() => _selectedCropId = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _NumberField(controller: _temperatureController, label: '${L.t(lang, 'temperature')} (C)'),
                      _NumberField(controller: _humidityController, label: '${L.t(lang, 'humidity')} (%)'),
                      _NumberField(controller: _precipitationController, label: '${L.t(lang, 'precipitation')} (mm)'),
                      _NumberField(controller: _soilMoistureController, label: '${L.t(lang, 'weather_soil_moisture')} (%)'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: _requesting || !_isKnownCropId(_selectedCropId)
                        ? null
                        : _loadRecommendations,
                    icon: const Icon(Icons.tips_and_updates_outlined),
                    label: Text(
                      _requesting
                          ? L.t(lang, 'disease_prevention_loading')
                          : L.t(lang, 'disease_prevention_get_recommendations'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _requesting || !serverAvailable ? null : _runAnalysis,
                    icon: const Icon(Icons.shield_outlined),
                    label: Text(L.t(lang, 'disease_prevention_analyze_field_risk')),
                  ),
                  if (!serverAvailable) ...[
                    const SizedBox(height: 8),
                    Text(
                      L.t(lang, 'disease_prevention_analysis_server_required'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (recommendations.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    FarmPanel(
                      color: const Color(0xFFF8FBEC),
                      child: Padding(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _cropLabel(_selectedCropId),
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if ((analysis['headline']?.toString().trim().isNotEmpty ?? false)) ...[
                              const SizedBox(height: 10),
                              Text(
                                _dpText(lang, 'headline'),
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(analysis['headline'].toString()),
                            ],
                            if (analysis['risk_drivers'] is List &&
                                (analysis['risk_drivers'] as List).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                _dpText(lang, 'risk_drivers'),
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...((analysis['risk_drivers'] as List<dynamic>).map((item) {
                                final text = item is Map<String, dynamic>
                                    ? item['label']?.toString() ?? ''
                                    : item.toString();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('- '),
                                      Expanded(child: Text(text)),
                                    ],
                                  ),
                                );
                              })),
                            ],
                            if (analysis['watch_items'] is List &&
                                (analysis['watch_items'] as List).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                _dpText(lang, 'watch_items'),
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...((analysis['watch_items'] as List<dynamic>).map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('- '),
                                      Expanded(child: Text(item.toString())),
                                    ],
                                  ),
                                ),
                              )),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              _dpText(lang, 'actions'),
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...recommendations.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('- '),
                                    Expanded(child: Text(item)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _NumberField({
    required this.controller,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
