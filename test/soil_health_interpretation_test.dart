import 'package:flutter_test/flutter_test.dart';
import 'package:smart_farm/features/soil_health/soil_health_interpretation.dart';
import 'package:smart_farm/offline/offline_models.dart';
import 'package:smart_farm/offline/sync_state.dart';

SoilHealthRecord _record({
  double? ph,
  double? nitrogen,
  double? phosphorus,
  double? potassium,
  double? organicMatter,
  double? moisture,
  String? reviewStatus,
}) {
  return SoilHealthRecord(
    localId: 1,
    serverId: 1,
    plotLocalId: 1,
    plotServerId: 1,
    phLevel: ph,
    nitrogen: nitrogen,
    phosphorus: phosphorus,
    potassium: potassium,
    organicMatter: organicMatter,
    moistureLevel: moisture,
    soilType: 'clay',
    testDate: DateTime(2026, 3, 29),
    testMethod: 'manual',
    dataSource: 'manual',
    sensorDeviceId: null,
    sensorReadingId: null,
    sensorPayload: null,
    fieldContext: null,
    confidenceScore: null,
    reviewStatus: reviewStatus,
    reviewReasonCode: null,
    reviewComment: null,
    reviewedBy: null,
    reviewedAt: null,
    evidencePath: null,
    evidenceUrl: null,
    localUpdatedAt: DateTime(2026, 3, 29),
    serverCreatedAt: DateTime(2026, 3, 29),
    serverUpdatedAt: DateTime(2026, 3, 29),
    baseServerUpdatedAt: null,
    syncState: SyncState.synced,
    deleted: false,
    conflictReason: null,
    syncAttempts: 0,
    nextRetryAt: null,
    syncError: null,
  );
}

void main() {
  test('flags attention when multiple soil risks are present', () {
    final interpretation = SoilHealthInterpretation.fromRecord(
      _record(
        ph: 5.0,
        nitrogen: 0.05,
        phosphorus: 0.03,
        potassium: 0.10,
        organicMatter: 1.1,
        moisture: 12,
      ),
      isValidated: false,
    );

    expect(interpretation.provisional, isTrue);
    expect(interpretation.summaryKey, 'soil_local_summary_attention');
    expect(interpretation.actionKeys, contains('soil_local_issue_ph_low'));
    expect(interpretation.actionKeys, contains('soil_local_issue_nitrogen_low'));
    expect(interpretation.watchKeys, contains('soil_local_watch_validate'));
  });

  test('returns stable summary for validated balanced record', () {
    final interpretation = SoilHealthInterpretation.fromRecord(
      _record(
        ph: 6.4,
        nitrogen: 0.18,
        phosphorus: 0.12,
        potassium: 0.35,
        organicMatter: 3.2,
        moisture: 42,
        reviewStatus: 'validated',
      ),
      isValidated: true,
    );

    expect(interpretation.provisional, isFalse);
    expect(interpretation.summaryKey, 'soil_local_summary_stable');
    expect(interpretation.noticeKey, 'soil_local_notice_validated');
    expect(interpretation.actionKeys, contains('soil_local_issue_clay_soil'));
    expect(interpretation.actionKeys, contains('soil_local_natural_clay_soil'));
    expect(interpretation.actionKeys, contains('soil_local_modern_clay_soil'));
  });
}
