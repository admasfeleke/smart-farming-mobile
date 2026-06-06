import '../../offline/offline_models.dart';

class SoilHealthInterpretation {
  final bool provisional;
  final String summaryKey;
  final String noticeKey;
  final List<String> issueKeys;
  final List<String> naturalActionKeys;
  final List<String> modernActionKeys;
  final List<String> actionKeys;
  final List<String> watchKeys;

  const SoilHealthInterpretation({
    required this.provisional,
    required this.summaryKey,
    required this.noticeKey,
    required this.issueKeys,
    required this.naturalActionKeys,
    required this.modernActionKeys,
    required this.actionKeys,
    required this.watchKeys,
  });

  factory SoilHealthInterpretation.fromRecord(
    SoilHealthRecord record, {
    required bool isValidated,
  }) {
    final issueKeys = <String>[];
    final naturalActionKeys = <String>[];
    final modernActionKeys = <String>[];
    final watchKeys = <String>[];

    final ph = record.phLevel;
    if (ph != null) {
      if (ph < 5.5) {
        issueKeys.add('soil_local_issue_ph_low');
        naturalActionKeys.add('soil_local_natural_ph_low');
        modernActionKeys.add('soil_local_modern_ph_low');
      } else if (ph > 7.8) {
        issueKeys.add('soil_local_issue_ph_high');
        naturalActionKeys.add('soil_local_natural_ph_high');
        modernActionKeys.add('soil_local_modern_ph_high');
      }
    }

    final moisture = record.moistureLevel;
    if (moisture != null) {
      if (moisture < 20) {
        issueKeys.add('soil_local_issue_moisture_low');
        naturalActionKeys.add('soil_local_natural_moisture_low');
        modernActionKeys.add('soil_local_modern_moisture_low');
      } else if (moisture > 70) {
        issueKeys.add('soil_local_issue_moisture_high');
        naturalActionKeys.add('soil_local_natural_moisture_high');
        modernActionKeys.add('soil_local_modern_moisture_high');
      }
    }

    final organicMatter = record.organicMatter;
    if (organicMatter != null && organicMatter < 2) {
      issueKeys.add('soil_local_issue_organic_low');
      naturalActionKeys.add('soil_local_natural_organic_low');
      modernActionKeys.add('soil_local_modern_organic_low');
    }

    final nitrogen = record.nitrogen;
    if (nitrogen != null && nitrogen < 0.10) {
      issueKeys.add('soil_local_issue_nitrogen_low');
      naturalActionKeys.add('soil_local_natural_nitrogen_low');
      modernActionKeys.add('soil_local_modern_nitrogen_low');
    }

    final phosphorus = record.phosphorus;
    if (phosphorus != null && phosphorus < 0.05) {
      issueKeys.add('soil_local_issue_phosphorus_low');
      naturalActionKeys.add('soil_local_natural_phosphorus_low');
      modernActionKeys.add('soil_local_modern_phosphorus_low');
    }

    final potassium = record.potassium;
    if (potassium != null && potassium < 0.20) {
      issueKeys.add('soil_local_issue_potassium_low');
      naturalActionKeys.add('soil_local_natural_potassium_low');
      modernActionKeys.add('soil_local_modern_potassium_low');
    }

    final soilType = record.soilType?.trim().toLowerCase() ?? '';
    if (soilType.contains('sand')) {
      issueKeys.add('soil_local_issue_sandy_soil');
      naturalActionKeys.add('soil_local_natural_sandy_soil');
      modernActionKeys.add('soil_local_modern_sandy_soil');
    } else if (soilType.contains('clay') || soilType.contains('vertisol')) {
      issueKeys.add('soil_local_issue_clay_soil');
      naturalActionKeys.add('soil_local_natural_clay_soil');
      modernActionKeys.add('soil_local_modern_clay_soil');
    }

    final hasMeasurements = ph != null ||
        moisture != null ||
        organicMatter != null ||
        nitrogen != null ||
        phosphorus != null ||
        potassium != null ||
        soilType.isNotEmpty;

    if (!hasMeasurements) {
      issueKeys.add('soil_local_summary_missing');
      naturalActionKeys.add('soil_local_action_capture_more');
    } else {
      watchKeys.add('soil_local_watch_retest');
      if (!isValidated) {
        watchKeys.add('soil_local_watch_validate');
      }
      if (issueKeys.isEmpty) {
        naturalActionKeys.add('soil_local_natural_maintain');
        modernActionKeys.add('soil_local_modern_maintain');
      }
    }

    final severityCount = issueKeys.length;
    final summaryKey = !hasMeasurements
        ? 'soil_local_summary_missing'
        : severityCount >= 4
        ? 'soil_local_summary_attention'
        : severityCount >= 2
        ? 'soil_local_summary_watch'
        : 'soil_local_summary_stable';
    final actionKeys = <String>[
      ...issueKeys,
      ...naturalActionKeys,
      ...modernActionKeys,
    ];

    return SoilHealthInterpretation(
      provisional: !isValidated,
      summaryKey: summaryKey,
      noticeKey:
          isValidated ? 'soil_local_notice_validated' : 'soil_local_notice_provisional',
      issueKeys: issueKeys.toSet().toList(growable: false),
      naturalActionKeys: naturalActionKeys.toSet().toList(growable: false),
      modernActionKeys: modernActionKeys.toSet().toList(growable: false),
      actionKeys: actionKeys.toSet().toList(growable: false),
      watchKeys: watchKeys.toSet().toList(growable: false),
    );
  }
}
