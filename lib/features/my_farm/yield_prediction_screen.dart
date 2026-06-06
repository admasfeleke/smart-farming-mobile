import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../auth_session.dart';
import '../../connectivity_status_service.dart';
import '../../language_store.dart';
import '../../localization.dart';
import '../../localized_value.dart';
import '../../offline/local_cache_store.dart';
import '../../offline/offline_models.dart';
import '../../offline/offline_repository.dart';
import '../../widgets/farm_ui.dart';

class YieldPredictionScreen extends StatefulWidget {
  final PlantingRecord planting;
  final PlotRecord plot;
  final String cropLabel;

  const YieldPredictionScreen({
    super.key,
    required this.planting,
    required this.plot,
    required this.cropLabel,
  });

  @override
  State<YieldPredictionScreen> createState() => _YieldPredictionScreenState();
}

class _YieldPredictionScreenState extends State<YieldPredictionScreen> {
  static const String _predictionCachePrefix = 'yield_prediction_cache_v1';

  final _temperatureController = TextEditingController();
  final _humidityController = TextEditingController();
  final _precipitationController = TextEditingController();
  final _soilPhController = TextEditingController();
  final _soilNitrogenController = TextEditingController();
  final _soilPhosphorusController = TextEditingController();
  final _soilPotassiumController = TextEditingController();
  final _soilMoistureController = TextEditingController();

  bool _loading = true;
  bool _predicting = false;
  String? _error;
  Map<String, dynamic> _result = <String, dynamic>{};
  DateTime? _cachedUpdatedAt;

  bool get _canRequestPrediction => widget.planting.serverId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _humidityController.dispose();
    _precipitationController.dispose();
    _soilPhController.dispose();
    _soilNitrogenController.dispose();
    _soilPhosphorusController.dispose();
    _soilPotassiumController.dispose();
    _soilMoistureController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _prefillFromLatestSoilHealth();
      await _prefillFromLatestWeather();
      final cachedEntry = await LocalCacheStore.instance.read(_cacheKey());
      if (cachedEntry?.payload is Map<String, dynamic> && mounted) {
        setState(() {
          _result = cachedEntry!.payload as Map<String, dynamic>;
          _cachedUpdatedAt = cachedEntry.updatedAt;
        });
      }
      if (_canRequestPrediction) {
        final response = await ApiClient.getYieldPredictionForPlanting(widget.planting.serverId!);
        await LocalCacheStore.instance.write(_cacheKey(), response);
        if (!mounted) return;
        setState(() {
          _result = response;
          _cachedUpdatedAt = DateTime.now();
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _loading = false;
        });
      }
    } on ApiUnauthorized {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _result.isNotEmpty
            ? L.t(
                LanguageStore.notifier.value,
                'yield_prediction_server_required_cached',
              )
            : e.toString();
      });
    }
  }

  Future<void> _prefillFromLatestSoilHealth() async {
    final plotLocalId = widget.plot.localId;
    final soilItems = await OfflineRepository.instance.listSoilHealth(plotLocalId: plotLocalId);
    if (soilItems.isEmpty) return;

    final latest = soilItems.first;
    _soilPhController.text = _formatNullable(latest.phLevel);
    _soilNitrogenController.text = _formatNullable(latest.nitrogen);
    _soilPhosphorusController.text = _formatNullable(latest.phosphorus);
    _soilPotassiumController.text = _formatNullable(latest.potassium);
    _soilMoistureController.text = _formatNullable(latest.moistureLevel);
  }

  Future<void> _prefillFromLatestWeather() async {
    final records = await LocalCacheStore.instance.readList('weather_records_cache_v1');
    final items = (records ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    if (items.isEmpty) return;
    final latest = items.first;
    _setIfEmpty(_temperatureController, latest['temperature']);
    _setIfEmpty(_humidityController, latest['humidity']);
    _setIfEmpty(_precipitationController, latest['precipitation']);
    _setIfEmpty(_soilMoistureController, latest['soil_moisture']);
  }

  void _setIfEmpty(TextEditingController controller, dynamic value) {
    if (controller.text.trim().isNotEmpty) return;
    final number = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (number == null) return;
    controller.text = _formatNullable(number);
  }

  String _formatNullable(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  double? _parseOptional(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _predict() async {
    if (!_canRequestPrediction) return;
    if (!await _ensureServerPredictionAvailable()) {
      return;
    }

    setState(() {
      _predicting = true;
      _error = null;
    });

    try {
      final response = await ApiClient.predictYield(
        plantingId: widget.planting.serverId!,
        temperature: _parseOptional(_temperatureController),
        humidity: _parseOptional(_humidityController),
        precipitation: _parseOptional(_precipitationController),
        soilPh: _parseOptional(_soilPhController),
        soilNitrogen: _parseOptional(_soilNitrogenController),
        soilPhosphorus: _parseOptional(_soilPhosphorusController),
        soilPotassium: _parseOptional(_soilPotassiumController),
        soilMoisture: _parseOptional(_soilMoistureController),
      );
      await LocalCacheStore.instance.write(_cacheKey(), response);
      if (!mounted) return;
      setState(() {
        _result = response;
        _cachedUpdatedAt = DateTime.now();
        _predicting = false;
      });
    } on ApiUnauthorized {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _predicting = false;
        _error = _result.isNotEmpty
            ? L.t(
                LanguageStore.notifier.value,
                'yield_prediction_server_required_cached',
              )
            : e.toString();
      });
    }
  }

  String _cacheKey() =>
      '${_predictionCachePrefix}_${widget.planting.serverId ?? widget.planting.localId}';

  Future<bool> _ensureServerPredictionAvailable() async {
    final offlineMode = await AuthSession.isOfflineModeActive();
    final connectivity = ConnectivityStatusService.instance.notifier.value;
    if (offlineMode || connectivity.state != ApiConnectivityState.apiOnline) {
      if (!mounted) return false;
      setState(() {
        _error = _result.isNotEmpty
            ? L.t(
                LanguageStore.notifier.value,
                'yield_prediction_server_required_cached',
              )
            : L.t(
                LanguageStore.notifier.value,
                'yield_prediction_server_required',
              );
      });
      return false;
    }
    return true;
  }

  Map<String, dynamic> get _prediction {
    final prediction = _result['prediction'];
    return prediction is Map<String, dynamic> ? prediction : <String, dynamic>{};
  }

  Map<String, dynamic> _provisionalPrediction(String lang) {
    final baseline = _baselineYieldForCrop(widget.cropLabel);
    final moisture = _parseOptional(_soilMoistureController);
    final ph = _parseOptional(_soilPhController);
    final nitrogen = _parseOptional(_soilNitrogenController);
    final phosphorus = _parseOptional(_soilPhosphorusController);
    final potassium = _parseOptional(_soilPotassiumController);
    final temperature = _parseOptional(_temperatureController);
    final precipitation = _parseOptional(_precipitationController);
    var multiplier = 1.0;
    final riskFlags = <String, bool>{
      'water_stress': false,
      'heat_stress': false,
      'ph_stress': false,
      'nutrient_gap': false,
      'late_cycle': false,
    };

    if (moisture != null) {
      if (moisture < 35) {
        multiplier -= 0.14;
        riskFlags['water_stress'] = true;
      } else if (moisture > 82) {
        multiplier -= 0.08;
      } else if (moisture >= 45 && moisture <= 70) {
        multiplier += 0.06;
      }
    }
    if (ph != null) {
      if (ph < 5.5 || ph > 8.0) {
        multiplier -= 0.12;
        riskFlags['ph_stress'] = true;
      } else if (ph >= 6.0 && ph <= 7.2) {
        multiplier += 0.05;
      }
    }
    final lowNutrients = [nitrogen, phosphorus, potassium]
        .where((value) => value != null)
        .where((value) => value! < 30)
        .length;
    if (lowNutrients > 0) {
      multiplier -= 0.07 * lowNutrients;
      riskFlags['nutrient_gap'] = true;
    }
    if (temperature != null && temperature > 34) {
      multiplier -= 0.10;
      riskFlags['heat_stress'] = true;
    }
    if (precipitation != null && precipitation < 2 && moisture != null && moisture < 45) {
      multiplier -= 0.06;
      riskFlags['water_stress'] = true;
    }

    final now = DateTime.now();
    final daysSincePlanting = now.difference(widget.planting.plantingDate).inDays.clamp(0, 400);
    final expectedDays = widget.planting.expectedHarvestDate == null
        ? 120
        : widget.planting.expectedHarvestDate!.difference(widget.planting.plantingDate).inDays.clamp(1, 400);
    final progress = (daysSincePlanting / expectedDays * 100).clamp(0, 100);
    if (progress > 88) {
      riskFlags['late_cycle'] = true;
    }

    final predicted = (baseline * multiplier).clamp(baseline * 0.45, baseline * 1.25);
    final deltaPercent = ((predicted - baseline) / baseline) * 100;
    final confidence = _provisionalConfidence([moisture, ph, nitrogen, phosphorus, potassium, temperature, precipitation]);
    final lower = predicted * 0.82;
    final upper = predicted * 1.18;

    return <String, dynamic>{
      'headline': _yieldPhrase(lang, 'offline_headline'),
      'predicted_yield': predicted,
      'confidence_level': confidence,
      'baseline_yield': baseline,
      'confidence_interval': <String, dynamic>{'lower': lower, 'upper': upper},
      'yield_band': <String, dynamic>{
        'label': deltaPercent >= 8
            ? _yieldPhrase(lang, 'above_baseline')
            : deltaPercent <= -8
                ? _yieldPhrase(lang, 'below_baseline')
                : _yieldPhrase(lang, 'near_baseline'),
        'delta_percent': deltaPercent,
      },
      'growth_context': <String, dynamic>{
        'stage_label': _growthStageLabel(lang, progress),
        'progress_percent': progress,
        'days_since_planting': daysSincePlanting,
        'expected_harvest_date': widget.planting.expectedHarvestDate?.toIso8601String().split('T').first ?? '--',
      },
      'risk_flags': riskFlags,
      'recommendations': _provisionalRecommendations(lang, riskFlags),
      'factors': <String, dynamic>{
        'source': _yieldPhrase(lang, 'offline_source'),
        'soil_moisture': moisture,
        'soil_ph': ph,
        'temperature': temperature,
      },
    };
  }

  double _baselineYieldForCrop(String cropLabel) {
    final label = cropLabel.toLowerCase();
    if (label.contains('maize') || label.contains('corn')) return 4200;
    if (label.contains('potato')) return 18000;
    if (label.contains('tomato')) return 24000;
    if (label.contains('pepper')) return 9000;
    return 5000;
  }

  double _provisionalConfidence(List<double?> values) {
    final filled = values.whereType<double>().length;
    return (38 + filled * 6).clamp(38, 72).toDouble();
  }

  String _growthStageLabel(String lang, num progress) {
    if (progress < 25) return _yieldPhrase(lang, 'stage_establishment');
    if (progress < 55) return _yieldPhrase(lang, 'stage_vegetative');
    if (progress < 82) return _yieldPhrase(lang, 'stage_yield_formation');
    return _yieldPhrase(lang, 'stage_maturity');
  }

  List<String> _provisionalRecommendations(String lang, Map<String, bool> riskFlags) {
    final items = <String>[];
    if (riskFlags['water_stress'] == true) {
      items.add(_yieldPhrase(lang, 'rec_water'));
    }
    if (riskFlags['nutrient_gap'] == true) {
      items.add(_yieldPhrase(lang, 'rec_nutrient'));
    }
    if (riskFlags['ph_stress'] == true) {
      items.add(_yieldPhrase(lang, 'rec_ph'));
    }
    if (riskFlags['heat_stress'] == true) {
      items.add(_yieldPhrase(lang, 'rec_heat'));
    }
    if (items.isEmpty) {
      items.add(_yieldPhrase(lang, 'rec_maintain'));
    }
    return items;
  }

  String _yieldPhrase(String lang, String key) {
    const values = <String, Map<String, String>>{
      'am': {
        'offline_headline': 'በተቀመጠ የአፈር፣ የአየር እና የተክል መረጃ ላይ የተመሰረተ የኦፍላይን ግምት ነው። ለተረጋገጠ የሰርቨር ትንበያ ያስመስሉ።',
        'above_baseline': 'ከመሠረታዊው በላይ',
        'below_baseline': 'ከመሠረታዊው በታች',
        'near_baseline': 'ከመሠረታዊው ጋር ቅርብ',
        'offline_source': 'የኦፍላይን ጊዜያዊ ግምት',
        'stage_establishment': 'የመቋቋም ደረጃ',
        'stage_vegetative': 'የቅጠል እድገት',
        'stage_yield_formation': 'የምርት መፈጠር',
        'stage_maturity': 'የመብሰል/መከር ጊዜ',
        'rec_water': 'የማሳ እርጥበትን ያረጋግጡ፤ ሰብሉ ከሚያዝል በጠዋት ያጠጡ።',
        'rec_nutrient': 'የአፈር ንጥረ ነገርን ይመርምሩ፤ ለሰብሉ የሚስማማ ኮምፖስት ወይም ማዳበሪያ ይጠቀሙ።',
        'rec_ph': 'ኬሚካል ማስተካከያ በፊት pH ያረጋግጡ፤ የአፈር ጭንቀትን ለመቀነስ ኦርጋኒክ ነገር ይጨምሩ።',
        'rec_heat': 'በከፍተኛ ሙቀት ሰዓት መርጨትን ወይም ከባድ የማሳ ስራን ያስወግዱ።',
        'rec_maintain': 'የአሁኑን የማሳ አሰራር ይቀጥሉ፤ ለተሻለ ትንበያ መዝገቦችን ያዘምኑ።',
      },
      'om': {
        'offline_headline': 'Tilmaama offline odeeffannoo biyyee, haala qilleensaa fi dhaabbii kuufame irratti hundaaʼe. Raaga server mirkanaaʼeef sync godhi.',
        'above_baseline': 'Buʼuura ol',
        'below_baseline': 'Buʼuura gadi',
        'near_baseline': 'Buʼuuraatti dhihoo',
        'offline_source': 'Tilmaama offline yeroo gabaabaa',
        'stage_establishment': 'Sadarkaa hundeeffama',
        'stage_vegetative': 'Guddina baalaa',
        'stage_yield_formation': 'Uumama omishaa',
        'stage_maturity': 'Bilchina/yeroo haamaa',
        'rec_water': 'Jiidhina dirree ilaali; midhaan yoo gogaa jiru ganama obaasii.',
        'rec_nutrient': 'Haala nyaata biyyee ilaali; kompostii ykn xaaʼoo midhaan kanaaf malu fayyadami.',
        'rec_ph': 'Sirreeffama keemikaalaa dura pH biyyee mirkaneessi; dhiphina biyyee hirʼisuuf orgaanikii dabali.',
        'rec_heat': 'Yeroo hoʼi cimaa taʼu biifuu ykn hojii dirree ulfaataa hin hojjetin.',
        'rec_maintain': 'Hojmaata dirree ammaa itti fufi; raaga fooyyaʼaa argachuuf galmee haaromsi.',
      },
      'ti': {
        'offline_headline': 'ኣብ ዝተቐመጠ መረዳእታ መሬት፣ ኣየርን ተኽልን ዝተመርኮሰ ኦፍላይን ግምት እዩ። ንዝተረጋገጸ ትንበያ ሰርቨር sync ግበር።',
        'above_baseline': 'ካብ መሰረት ንላዕሊ',
        'below_baseline': 'ካብ መሰረት ንታሕቲ',
        'near_baseline': 'ናብ መሰረት ዝቐረበ',
        'offline_source': 'ጊዜያዊ ኦፍላይን ግምት',
        'stage_establishment': 'ደረጃ ምትካል',
        'stage_vegetative': 'ዕብየት ቆጽሊ',
        'stage_yield_formation': 'ምፍጣር ፍርያት',
        'stage_maturity': 'ብስለት/ግዜ መከር',
        'rec_water': 'ርጥበት ማሳ ኣረጋግጽ፤ ተኽሊ እንተደኺሙ ንግሆ ኣጠጥዖ።',
        'rec_nutrient': 'ኩነታት ንጥረ መሬት ገምግም፤ ንሰብሉ ዝሰማማዕ ኮምፖስት ወይ ማዳበሪያ ተጠቐም።',
        'rec_ph': 'ቅድሚ ኬሚካላዊ ምስትኽኻል pH መሬት ኣረጋግጽ፤ ጭንቀት መሬት ንምቕናስ ኦርጋኒክ ነገር ወስኽ።',
        'rec_heat': 'ኣብ ሰዓታት ከቢድ ሙቐት ምርጫው ወይ ከቢድ ስራሕ ማሳ ኣወግድ።',
        'rec_maintain': 'ናይ ሕጂ ኣሰራርሓ ማሳ ቀጽል፤ ንዝበለጸ ትንበያ መዝገብ ኣሐድስ።',
      },
      'en': {
        'offline_headline': 'Provisional offline estimate based on saved soil, weather, and planting context. Sync for verified server prediction.',
        'above_baseline': 'Above baseline',
        'below_baseline': 'Below baseline',
        'near_baseline': 'Near baseline',
        'offline_source': 'offline provisional',
        'stage_establishment': 'Establishment',
        'stage_vegetative': 'Vegetative growth',
        'stage_yield_formation': 'Yield formation',
        'stage_maturity': 'Maturity / harvest window',
        'rec_water': 'Check field moisture and irrigate early morning if the crop is wilting.',
        'rec_nutrient': 'Review soil nutrient status and apply crop-appropriate compost or fertilizer.',
        'rec_ph': 'Confirm soil pH before chemical correction; use organic matter to buffer soil stress.',
        'rec_heat': 'Avoid spraying or heavy field work during peak heat hours.',
        'rec_maintain': 'Maintain current field practice and keep records updated for better prediction.',
      },
    };
    return values[lang]?[key] ?? values['en']?[key] ?? key;
  }

  String _formatDate(DateTime value) => DateFormat('MMM dd, yyyy').format(value);

  String _metric(dynamic value, {String suffix = '', int decimals = 1}) {
    if (value == null) return '--';
    if (value is num) {
      final normalized = decimals == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(decimals);
      return '$normalized$suffix';
    }
    final text = value.toString().trim();
    return text.isEmpty ? '--' : '$text$suffix';
  }

  String _yieldText(String lang, String key) {
    const values = <String, Map<String, String>>{
      'en': {
        'headline': 'Forecast summary',
        'baseline': 'Baseline yield',
        'yield_band': 'Yield band',
        'yield_delta': 'Change from baseline',
        'growth_stage': 'Growth stage',
        'days_since_planting': 'Days since planting',
        'expected_harvest': 'Expected harvest',
        'risk_flags': 'Current risks',
        'no_risks': 'No major risk flagged',
        'field_progress': 'Field progress',
      },
      'am': {
        'headline': 'የትንበያ ማጠቃለያ',
        'baseline': 'መሠረታዊ ምርት',
        'yield_band': 'የምርት ደረጃ',
        'yield_delta': 'ከመሠረታዊ ጋር ልዩነት',
        'growth_stage': 'የእድገት ደረጃ',
        'days_since_planting': 'ከተከለ በኋላ ቀናት',
        'expected_harvest': 'የሚጠበቀው መከር',
        'risk_flags': 'አሁን ያሉ አደጋዎች',
        'no_risks': 'ዋና አደጋ አልተገኘም',
        'field_progress': 'የማሳ እድገት',
      },
      'om': {
        'headline': 'Cuunfaa tilmaamaa',
        'baseline': 'Omisha bu’uuraa',
        'yield_band': 'Sadarkaa omishaa',
        'yield_delta': 'Garaagarummaa bu’uuraa irraa',
        'growth_stage': 'Sadarkaa guddinaa',
        'days_since_planting': 'Guyyoota dhaabbii irraa',
        'expected_harvest': 'Haamuu eegamu',
        'risk_flags': 'Balaa yeroo ammaa',
        'no_risks': 'Balaan guddaan hin mul’anne',
        'field_progress': 'Adeemsa dirree',
      },
      'ti': {
        'headline': 'ሓፈሻዊ ትንበያ',
        'baseline': 'መሰረታዊ ምርት',
        'yield_band': 'ደረጃ ምርት',
        'yield_delta': 'ካብ መሰረት ዝለዓለ ወይ ዝወረደ',
        'growth_stage': 'ደረጃ ዕብየት',
        'days_since_planting': 'ካብ ተኽሊ ጀሚሩ ዝሓለፈ መዓልታት',
        'expected_harvest': 'ዝጽበ መከር',
        'risk_flags': 'ህልው ሓደጋታት',
        'no_risks': 'ዓቢ ሓደጋ አይተረኽበን',
        'field_progress': 'ምዕባለ ማሳ',
      },
    };
    return values[lang]?[key] ?? values['en']![key]!;
  }

  String _riskLabel(String lang, String key) {
    const values = <String, Map<String, String>>{
      'en': {
        'water_stress': 'Water stress',
        'heat_stress': 'Heat stress',
        'ph_stress': 'Soil pH stress',
        'nutrient_gap': 'Nutrient gap',
        'late_cycle': 'Late crop cycle',
      },
      'am': {
        'water_stress': 'የውሃ ጭንቀት',
        'heat_stress': 'የሙቀት ጭንቀት',
        'ph_stress': 'የአፈር pH ችግኝ',
        'nutrient_gap': 'የንጥረ ነገር እጥረት',
        'late_cycle': 'የመጨረሻ የእድገት ዘመን',
      },
      'om': {
        'water_stress': 'Ciniinsuu bishaanii',
        'heat_stress': 'Ciniinsuu ho’aa',
        'ph_stress': 'Rakkoo pH lafa',
        'nutrient_gap': 'Hanqina nafa',
        'late_cycle': 'Marsaa dhuma qonnaa',
      },
      'ti': {
        'water_stress': 'ጭንቀት ማይ',
        'heat_stress': 'ጭንቀት ሙቐት',
        'ph_stress': 'ጸገም pH መሬት',
        'nutrient_gap': 'ክፍተት ንጥረ ነገር',
        'late_cycle': 'ደንጉዩ ዑደት እትዮ',
      },
    };
    return values[lang]?[key] ?? values['en']?[key] ?? key.replaceAll('_', ' ');
  }

  List<String> _activeRiskLabels(String lang) {
    final riskFlags = _prediction['risk_flags'];
    if (riskFlags is! Map<String, dynamic>) {
      return const <String>[];
    }

    final labels = <String>[];
    riskFlags.forEach((key, value) {
      if (value == true) {
        labels.add(_riskLabel(lang, key));
      }
    });
    return labels;
  }

  Widget _sectionTitle(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }

  List<Widget> _factorWidgets(BuildContext context) {
    final factors = _prediction['factors'];
    if (factors is! Map<String, dynamic> || factors.isEmpty) {
      return const <Widget>[];
    }

    final widgets = <Widget>[];
    factors.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        value.forEach((nestedKey, nestedValue) {
          widgets.add(
            _PredictionChip(
              label: '${nestedKey.replaceAll('_', ' ')}: ${_metric(nestedValue)}',
            ),
          );
        });
        return;
      }

      widgets.add(
        _PredictionChip(
          label: '${key.replaceAll('_', ' ')}: ${_metric(value)}',
        ),
      );
    });
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final lang = LanguageStore.notifier.value;
    final serverPrediction = _prediction;
    final prediction = serverPrediction.isNotEmpty ? serverPrediction : _provisionalPrediction(lang);
    final isProvisionalPrediction = serverPrediction.isEmpty && prediction.isNotEmpty;
    final confidenceInterval = prediction['confidence_interval'];
    final lower = confidenceInterval is Map<String, dynamic> ? confidenceInterval['lower'] : null;
    final upper = confidenceInterval is Map<String, dynamic> ? confidenceInterval['upper'] : null;
    final recommendations = prediction['recommendations'] is List
        ? (prediction['recommendations'] as List<dynamic>).map((e) => e.toString()).toList()
        : const <String>[];
    final growthContext = prediction['growth_context'] is Map<String, dynamic>
        ? prediction['growth_context'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final yieldBand = prediction['yield_band'] is Map<String, dynamic>
        ? prediction['yield_band'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final serverAvailable =
        ConnectivityStatusService.instance.notifier.value.state == ApiConnectivityState.apiOnline;
    final activeRisks = _activeRiskLabels(lang);

    return Scaffold(
      appBar: AppBar(
        title: Text(L.t(lang, 'yield_prediction_title')),
      ),
      body: FarmSurface(
        padding: EdgeInsets.zero,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
          children: [
            FarmHeroCard(
              imageAsset: 'assets/images/home/quick_farm.jpg',
              eyebrow: L.t(lang, 'yield_outlook'),
              title: widget.cropLabel,
              body: '${L.t(lang, 'yield_prediction_plot', params: {'name': widget.plot.plotName})}\n${L.t(lang, 'yield_prediction_planting_date', params: {'date': _formatDate(widget.planting.plantingDate)})}',
              trailing: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.auto_graph_rounded, color: Color(0xFF41670F), size: 32),
              ),
            ),
            const SizedBox(height: 16),
            if (!_canRequestPrediction)
              FarmPanel(
                color: const Color(0xFFFFEFE9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.sync_problem_rounded, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        L.t(lang, 'yield_prediction_sync_first'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                        L.t(lang, 'yield_prediction_error', params: {'error': _error!}),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_cachedUpdatedAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  L.t(
                    lang,
                    'yield_prediction_saved_at',
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
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _InputBox(controller: _temperatureController, label: LocalizedValue.fixed(lang, 'temperature_celsius_short')),
                        _InputBox(controller: _humidityController, label: '${L.t(lang, 'humidity')} %'),
                        _InputBox(controller: _precipitationController, label: '${L.t(lang, 'precipitation')} mm'),
                        _InputBox(controller: _soilPhController, label: L.t(lang, 'phLevel')),
                        _InputBox(controller: _soilNitrogenController, label: L.t(lang, 'nitrogenLevel')),
                        _InputBox(controller: _soilPhosphorusController, label: L.t(lang, 'phosphorusLevel')),
                        _InputBox(controller: _soilPotassiumController, label: L.t(lang, 'potassiumLevel')),
                        _InputBox(controller: _soilMoistureController, label: '${L.t(lang, 'soilMoisture')} %'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _predicting || !_canRequestPrediction || !serverAvailable ? null : _predict,
                icon: _predicting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_graph_outlined),
                label: Text(
                  _predicting
                      ? L.t(lang, 'yield_prediction_updating')
                      : L.t(lang, 'yield_prediction_action'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                L.t(lang, 'yield_prediction_server_required_banner'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              if (prediction.isNotEmpty) ...[
                if (isProvisionalPrediction)
                  FarmPanel(
                    color: const Color(0xFFFFF5D7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.offline_bolt_rounded, color: Color(0xFF8A6500)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _yieldPhrase(lang, 'offline_headline'),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF57430A),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isProvisionalPrediction) const SizedBox(height: 12),
                Text(
                  L.t(lang, 'yield_prediction_result'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if ((prediction['headline']?.toString().trim().isNotEmpty ?? false))
                  FarmPanel(
                    color: const Color(0xFFF8FBEC),
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(context, _yieldText(lang, 'headline')),
                          const SizedBox(height: 8),
                          Text(
                            prediction['headline'].toString(),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if ((prediction['headline']?.toString().trim().isNotEmpty ?? false))
                  const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _PredictionMetricCard(
                      label: L.t(lang, 'yield_prediction_predicted_yield'),
                      value: _metric(prediction['predicted_yield'], suffix: ' kg/ha'),
                    ),
                    _PredictionMetricCard(
                      label: L.t(lang, 'yield_prediction_confidence'),
                      value: _metric(prediction['confidence_level'], suffix: '%'),
                    ),
                    _PredictionMetricCard(
                      label: _yieldText(lang, 'baseline'),
                      value: _metric(prediction['baseline_yield'], suffix: ' kg/ha'),
                    ),
                    _PredictionMetricCard(
                      label: L.t(lang, 'yield_prediction_lower_bound'),
                      value: _metric(lower, suffix: ' kg/ha'),
                    ),
                    _PredictionMetricCard(
                      label: L.t(lang, 'yield_prediction_upper_bound'),
                      value: _metric(upper, suffix: ' kg/ha'),
                    ),
                    if (yieldBand.isNotEmpty)
                      _PredictionMetricCard(
                        label: _yieldText(lang, 'yield_delta'),
                        value: _metric(yieldBand['delta_percent'], suffix: '%'),
                      ),
                  ],
                ),
                if (growthContext.isNotEmpty || yieldBand.isNotEmpty || activeRisks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  FarmPanel(
                    color: const Color(0xFFFFFDF5),
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (growthContext.isNotEmpty) ...[
                            _sectionTitle(context, _yieldText(lang, 'growth_stage')),
                            const SizedBox(height: 8),
                            Text(growthContext['stage_label']?.toString() ?? '--'),
                            const SizedBox(height: 6),
                            Text(
                              '${_yieldText(lang, 'field_progress')}: ${_metric(growthContext['progress_percent'], suffix: '%')}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_yieldText(lang, 'days_since_planting')}: ${_metric(growthContext['days_since_planting'], decimals: 0)}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_yieldText(lang, 'expected_harvest')}: ${growthContext['expected_harvest_date']?.toString() ?? '--'}',
                            ),
                          ],
                          if (yieldBand.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _sectionTitle(context, _yieldText(lang, 'yield_band')),
                            const SizedBox(height: 8),
                            Text(yieldBand['label']?.toString() ?? '--'),
                          ],
                          const SizedBox(height: 14),
                          _sectionTitle(context, _yieldText(lang, 'risk_flags')),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: activeRisks.isEmpty
                                ? [
                                    _PredictionChip(
                                      label: _yieldText(lang, 'no_risks'),
                                    ),
                                  ]
                                : activeRisks
                                    .map((risk) => _PredictionChip(label: risk))
                                    .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_factorWidgets(context).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionTitle(context, L.t(lang, 'yield_prediction_factors_used')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _factorWidgets(context),
                  ),
                ],
                if (recommendations.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionTitle(context, L.t(lang, 'recommendations')),
                  const SizedBox(height: 8),
                  ...recommendations.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
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
              ] else
                FarmPanel(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDEF9D),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.insights_outlined, color: Color(0xFF41670F)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              LocalizedValue.fixed(lang, 'no_prediction_available_yet'),
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(LocalizedValue.fixed(lang, 'yield_prediction_empty_help')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

class _InputBox extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _InputBox({
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

class _PredictionMetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _PredictionMetricCard({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: FarmPanel(
        padding: const EdgeInsets.all(14),
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PredictionChip extends StatelessWidget {
  final String label;

  const _PredictionChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}
