import '../disease_naming.dart';

class DiseaseReportModel {
  final int id;
  final int plotId;
  final int cropId;
  final int? plantingId;
  final String? clientSubmissionId;
  final String diseaseName;
  final String severity;
  final double? confidenceScore;
  final String? description;
  final String status;
  final DateTime reportedAt;
  final DiseaseTreatmentGuidance? treatmentGuidance;
  final InferenceFailure? inferenceFailure;
  final String canonicalDiseaseName;
  final String? provisionalDiseaseName;
  final String? provisionalCanonicalDiseaseName;
  final String? inferredDiseaseName;
  final String? inferredCanonicalDiseaseName;
  final String? verifiedDiseaseName;
  final String? verifiedCanonicalDiseaseName;
  final String namingStage;
  final String? likelyIssueName;
  final String? likelyIssueCanonicalDiseaseName;
  final String? originalImageUrl;
  final List<DiseaseReportEvidence> evidence;
  final String? decisionReasonCode;
  final String? decisionComment;
  final DateTime? reviewedAt;
  final DateTime? verifiedAt;

  DiseaseReportModel({
    required this.id,
    required this.plotId,
    required this.cropId,
    required this.plantingId,
    required this.clientSubmissionId,
    required this.diseaseName,
    required this.severity,
    required this.confidenceScore,
    required this.description,
    required this.status,
    required this.reportedAt,
    required this.treatmentGuidance,
    required this.inferenceFailure,
    required this.canonicalDiseaseName,
    required this.provisionalDiseaseName,
    required this.provisionalCanonicalDiseaseName,
    required this.inferredDiseaseName,
    required this.inferredCanonicalDiseaseName,
    required this.verifiedDiseaseName,
    required this.verifiedCanonicalDiseaseName,
    required this.namingStage,
    required this.likelyIssueName,
    required this.likelyIssueCanonicalDiseaseName,
    required this.originalImageUrl,
    required this.evidence,
    required this.decisionReasonCode,
    required this.decisionComment,
    required this.reviewedAt,
    required this.verifiedAt,
  });

  factory DiseaseReportModel.fromJson(Map<String, dynamic> json) {
    final rawDiseaseName = json['disease_name']?.toString() ?? '';
    final displayName = json['display_disease_name']?.toString().trim();
    final canonicalName = json['canonical_disease_name']?.toString().trim();
    return DiseaseReportModel(
      id: _toInt(json['id']),
      plotId: _toInt(json['plot_id']),
      cropId: _toInt(json['crop_id']),
      plantingId: json['planting_id'] == null
          ? null
          : _toInt(json['planting_id']),
      clientSubmissionId: _firstNonEmptyString(json, const [
        'client_submission_id',
        'clientSubmissionId',
        'submission_id',
      ]),
      diseaseName: displayName != null && displayName.isNotEmpty
          ? displayName
          : rawDiseaseName,
      severity: json['severity']?.toString() ?? '',
      confidenceScore: _toDouble(json['confidence_score']),
      description: json['description'] as String?,
      status: json['status']?.toString() ?? '',
      reportedAt:
          _parseDate(json['reported_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      treatmentGuidance: DiseaseTreatmentGuidance.fromJson(
        json['treatment_guidance'] is Map<String, dynamic>
            ? json['treatment_guidance'] as Map<String, dynamic>
            : null,
      ),
      inferenceFailure: InferenceFailure.fromJson(
        json['inference_failure'] is Map<String, dynamic>
            ? json['inference_failure'] as Map<String, dynamic>
            : null,
      ),
      canonicalDiseaseName: canonicalName != null && canonicalName.isNotEmpty
          ? canonicalName
          : normalizeDiseaseKey(rawDiseaseName),
      provisionalDiseaseName: _firstNonEmptyString(json, const [
        'provisional_disease_name',
      ]),
      provisionalCanonicalDiseaseName: _firstNonEmptyString(json, const [
        'provisional_canonical_disease_name',
      ]),
      inferredDiseaseName: _firstNonEmptyString(json, const [
        'inferred_disease_name',
      ]),
      inferredCanonicalDiseaseName: _firstNonEmptyString(json, const [
        'inferred_canonical_disease_name',
      ]),
      verifiedDiseaseName: _firstNonEmptyString(json, const [
        'verified_disease_name',
      ]),
      verifiedCanonicalDiseaseName: _firstNonEmptyString(json, const [
        'verified_canonical_disease_name',
      ]),
      namingStage:
          _firstNonEmptyString(json, const ['naming_stage']) ?? 'pending',
      likelyIssueName: _firstNonEmptyString(json, const ['likely_issue_name']),
      likelyIssueCanonicalDiseaseName: _firstNonEmptyString(json, const [
        'likely_issue_canonical_disease_name',
      ]),
      originalImageUrl: _firstNonEmptyString(json, const [
        'original_image_url',
        'image_url',
        'imageUrl',
      ]),
      evidence: _toEvidenceList(json['evidence']),
      decisionReasonCode: _firstNonEmptyString(json, const [
        'decision_reason_code',
        'decisionReasonCode',
      ]),
      decisionComment: _firstNonEmptyString(json, const [
        'decision_comment',
        'decisionComment',
      ]),
      reviewedAt: _parseDate(json['reviewed_at']),
      verifiedAt: _parseDate(json['verified_at']),
    );
  }

  DiseaseFindingResolution get finding {
    final verifiedName = _meaningfulName(verifiedDiseaseName);
    final verifiedKey = _meaningfulCanonicalKey(
      verifiedCanonicalDiseaseName,
      verifiedDiseaseName,
    );
    if (verifiedName != null) {
      return DiseaseFindingResolution(
        stage: DiseaseFindingStage.verified,
        name: verifiedName,
        canonicalKey: verifiedKey,
      );
    }

    final resolvedDisplayName = _meaningfulName(diseaseName);
    final inferredName =
        _meaningfulName(inferredDiseaseName) ??
        ((namingStage == 'inferred' || namingStage == 'verified')
            ? resolvedDisplayName
            : null);
    final inferredKey = _meaningfulCanonicalKey(
      inferredCanonicalDiseaseName ?? canonicalDiseaseName,
      inferredName ?? diseaseName,
    );
    if (inferredName != null && !isPendingDiseaseKey(inferredKey)) {
      return DiseaseFindingResolution(
        stage: DiseaseFindingStage.inferred,
        name: inferredName,
        canonicalKey: inferredKey,
      );
    }

    final provisionalName =
        _meaningfulName(provisionalDiseaseName) ??
        (namingStage == 'provisional' ? resolvedDisplayName : null);
    final provisionalKey = _meaningfulCanonicalKey(
      provisionalCanonicalDiseaseName ?? canonicalDiseaseName,
      provisionalName ?? provisionalDiseaseName,
    );
    if (provisionalName != null) {
      return DiseaseFindingResolution(
        stage: DiseaseFindingStage.provisional,
        name: provisionalName,
        canonicalKey: provisionalKey,
      );
    }

    final likelyIssue = _meaningfulName(likelyIssueName);
    final likelyIssueKey = _meaningfulCanonicalKey(
      likelyIssueCanonicalDiseaseName,
      likelyIssueName,
    );
    if (likelyIssue != null) {
      return DiseaseFindingResolution(
        stage: DiseaseFindingStage.likelyIssue,
        name: likelyIssue,
        canonicalKey: likelyIssueKey,
      );
    }

    final fallbackReason = _meaningfulName(decisionReasonCode);
    if (isConfirmedWorkflowState && fallbackReason != null) {
      return DiseaseFindingResolution(
        stage: DiseaseFindingStage.verified,
        name: fallbackReason,
        canonicalKey: normalizeDiseaseKey(fallbackReason),
      );
    }

    return const DiseaseFindingResolution.pending();
  }

  String get resolvedDiseaseName => finding.name ?? '';
  String get resolvedCanonicalDiseaseName => finding.canonicalKey;
  String get resolvedFindingStage => finding.stage.name;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'plot_id': plotId,
      'crop_id': cropId,
      'planting_id': plantingId,
      'client_submission_id': clientSubmissionId,
      'disease_name': diseaseName,
      'display_disease_name': diseaseName,
      'severity': severity,
      'confidence_score': confidenceScore,
      'description': description,
      'status': status,
      'reported_at': reportedAt.toIso8601String(),
      'treatment_guidance': treatmentGuidance?.toJson(),
      'inference_failure': inferenceFailure?.toJson(),
      'canonical_disease_name': canonicalDiseaseName,
      'provisional_disease_name': provisionalDiseaseName,
      'provisional_canonical_disease_name': provisionalCanonicalDiseaseName,
      'inferred_disease_name': inferredDiseaseName,
      'inferred_canonical_disease_name': inferredCanonicalDiseaseName,
      'verified_disease_name': verifiedDiseaseName,
      'verified_canonical_disease_name': verifiedCanonicalDiseaseName,
      'naming_stage': namingStage,
      'likely_issue_name': likelyIssueName,
      'likely_issue_canonical_disease_name': likelyIssueCanonicalDiseaseName,
      'original_image_url': originalImageUrl,
      'evidence': evidence.map((item) => item.toJson()).toList(growable: false),
      'decision_reason_code': decisionReasonCode,
      'decision_comment': decisionComment,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'verified_at': verifiedAt?.toIso8601String(),
    };
  }

  bool get isConfirmedWorkflowState {
    final s = status.toLowerCase();
    return s == 'confirmed' ||
        s == 'verified' ||
        s == 'done' ||
        s == 'completed' ||
        s == 'resolved' ||
        verifiedAt != null;
  }

  static String? _meaningfulName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final normalized = normalizeDiseaseKey(trimmed);
    if (isPendingDiseaseKey(normalized)) return null;
    return trimmed;
  }

  static String _meaningfulCanonicalKey(
    String? preferredKey,
    String? fallbackName,
  ) {
    final normalizedKey = normalizeDiseaseKey(preferredKey ?? '');
    if (!isPendingDiseaseKey(normalizedKey) && normalizedKey.isNotEmpty) {
      return normalizedKey;
    }
    final fallbackKey = normalizeDiseaseKey(fallbackName ?? '');
    if (!isPendingDiseaseKey(fallbackKey) && fallbackKey.isNotEmpty) {
      return fallbackKey;
    }
    return normalizedKey.isNotEmpty ? normalizedKey : fallbackKey;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static String? _firstNonEmptyString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static List<DiseaseReportEvidence> _toEvidenceList(dynamic value) {
    if (value is! List) return const <DiseaseReportEvidence>[];
    return value
        .whereType<Map>()
        .map(
          (item) => DiseaseReportEvidence.fromJson(
            item.map((key, val) => MapEntry(key.toString(), val)),
          ),
        )
        .where((item) => item.isUsable)
        .toList(growable: false);
  }
}

enum DiseaseFindingStage {
  pending,
  likelyIssue,
  provisional,
  inferred,
  verified,
}

class DiseaseFindingResolution {
  final DiseaseFindingStage stage;
  final String? name;
  final String canonicalKey;

  const DiseaseFindingResolution({
    required this.stage,
    required this.name,
    required this.canonicalKey,
  });

  const DiseaseFindingResolution.pending()
    : stage = DiseaseFindingStage.pending,
      name = null,
      canonicalKey = 'pending_analysis';

  bool get hasMeaningfulName => name != null && name!.trim().isNotEmpty;
  bool get isPending => stage == DiseaseFindingStage.pending;
  bool get isVerified => stage == DiseaseFindingStage.verified;
  bool get isInferred => stage == DiseaseFindingStage.inferred;
  bool get isProvisional => stage == DiseaseFindingStage.provisional;
}

class DiseaseReportEvidence {
  final int? id;
  final String kind;
  final String? url;
  final String? mimeType;
  final String? caption;
  final DateTime? uploadedAt;
  final String? uploadedByName;

  const DiseaseReportEvidence({
    required this.id,
    required this.kind,
    required this.url,
    required this.mimeType,
    required this.caption,
    required this.uploadedAt,
    required this.uploadedByName,
  });

  factory DiseaseReportEvidence.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DiseaseReportEvidence(
        id: null,
        kind: '',
        url: null,
        mimeType: null,
        caption: null,
        uploadedAt: null,
        uploadedByName: null,
      );
    }
    return DiseaseReportEvidence(
      id: _toIntOrNull(json['id']),
      kind: json['kind']?.toString().trim() ?? '',
      url: _firstNonEmptyString(json, const [
        'url',
        'file_url',
        'fileUrl',
        'public_url',
        'publicUrl',
      ]),
      mimeType: _firstNonEmptyString(json, const ['mime_type', 'mimeType']),
      caption: _firstNonEmptyString(json, const ['caption', 'note']),
      uploadedAt: _parseDate(json['uploaded_at'] ?? json['created_at']),
      uploadedByName: _firstNonEmptyString(json, const [
        'uploaded_by_name',
        'uploadedByName',
        'reviewer_name',
      ]),
    );
  }

  bool get isImage {
    final mime = (mimeType ?? '').toLowerCase();
    return mime.startsWith('image/');
  }

  bool get isUsable => (url ?? '').trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'kind': kind,
      'url': url,
      'mime_type': mimeType,
      'caption': caption,
      'uploaded_at': uploadedAt?.toIso8601String(),
      'uploaded_by_name': uploadedByName,
    };
  }

  static int? _toIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static String? _firstNonEmptyString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}

class InferenceFailure {
  final String code;
  final int? gate;
  final String? selected;
  final String? detected;
  final String? message;
  final double? confidenceScore;
  final DateTime? occurredAt;

  const InferenceFailure({
    required this.code,
    required this.gate,
    required this.selected,
    required this.detected,
    required this.message,
    required this.confidenceScore,
    required this.occurredAt,
  });

  factory InferenceFailure.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const InferenceFailure(
        code: '',
        gate: null,
        selected: null,
        detected: null,
        message: null,
        confidenceScore: null,
        occurredAt: null,
      );
    }

    return InferenceFailure(
      code: json['code']?.toString().trim().toUpperCase() ?? '',
      gate: _toIntOrNull(json['gate']),
      selected: json['selected']?.toString(),
      detected: json['detected']?.toString(),
      message: json['message']?.toString(),
      confidenceScore: _toDouble(json['confidence_score']),
      occurredAt: _parseDate(json['occurred_at']),
    );
  }

  bool get hasFailure => code.isNotEmpty;
  bool get isNotAPlant => code == 'NOT_A_PLANT';
  bool get isCropMismatch => code == 'CROP_MISMATCH';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'code': code,
      'gate': gate,
      'selected': selected,
      'detected': detected,
      'message': message,
      'confidence_score': confidenceScore,
      'occurred_at': occurredAt?.toIso8601String(),
    };
  }

  static int? _toIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}

class DiseaseTreatmentGuidance {
  final String mode;
  final bool treatmentReady;
  final bool advisoryTreatmentAvailable;
  final String reviewStatus;
  final bool expertVerified;
  final String source;
  final String? verificationNote;
  final String reliability;
  final String riskLevel;
  final double? confidenceScore;
  final String? cropFamily;
  final String headline;
  final String nextStep;
  final String? activeIngredient;
  final String? dosage;
  final String? ppe;
  final String? preHarvestInterval;
  final String? reEntryInterval;
  final List<String> actions;
  final List<String> monitoring;
  final List<String> prevention;
  final List<String> escalateIf;
  final List<DiseaseTreatmentOption> treatmentOptions;
  final List<String> notes;

  const DiseaseTreatmentGuidance({
    required this.mode,
    required this.treatmentReady,
    required this.advisoryTreatmentAvailable,
    required this.reviewStatus,
    required this.expertVerified,
    required this.source,
    required this.verificationNote,
    required this.reliability,
    required this.riskLevel,
    required this.confidenceScore,
    required this.cropFamily,
    required this.headline,
    required this.nextStep,
    required this.activeIngredient,
    required this.dosage,
    required this.ppe,
    required this.preHarvestInterval,
    required this.reEntryInterval,
    required this.actions,
    required this.monitoring,
    required this.prevention,
    required this.escalateIf,
    required this.treatmentOptions,
    required this.notes,
  });

  factory DiseaseTreatmentGuidance.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const DiseaseTreatmentGuidance(
        mode: '',
        treatmentReady: false,
        advisoryTreatmentAvailable: false,
        reviewStatus: 'draft',
        expertVerified: false,
        source: 'fallback_config',
        verificationNote: null,
        reliability: '',
        riskLevel: '',
        confidenceScore: null,
        cropFamily: null,
        headline: '',
        nextStep: '',
        activeIngredient: null,
        dosage: null,
        ppe: null,
        preHarvestInterval: null,
        reEntryInterval: null,
        actions: <String>[],
        monitoring: <String>[],
        prevention: <String>[],
        escalateIf: <String>[],
        treatmentOptions: <DiseaseTreatmentOption>[],
        notes: <String>[],
      );
    }

    return DiseaseTreatmentGuidance(
      mode: json['mode']?.toString() ?? '',
      treatmentReady: _toBool(json['treatment_ready']),
      advisoryTreatmentAvailable: _toBool(json['advisory_treatment_available']),
      reviewStatus:
          json['review_status']?.toString().trim().toLowerCase() ?? 'draft',
      expertVerified: _toBool(json['expert_verified']),
      source: json['source']?.toString().trim() ?? 'fallback_config',
      verificationNote: _firstNonEmptyString(json, const [
        'verification_note',
        'verificationNote',
      ]),
      reliability: json['reliability']?.toString() ?? '',
      riskLevel: json['risk_level']?.toString() ?? '',
      confidenceScore: _toDouble(json['confidence_score']),
      cropFamily: json['crop_family']?.toString(),
      headline: json['headline']?.toString() ?? '',
      nextStep: json['next_step']?.toString() ?? '',
      activeIngredient: _firstNonEmptyString(json, const [
        'active_ingredient',
        'activeIngredient',
      ]),
      dosage: _firstNonEmptyString(json, const ['dosage', 'dose']),
      ppe: _firstNonEmptyString(json, const ['ppe', 'safety_gear']),
      preHarvestInterval: _firstNonEmptyString(json, const [
        'pre_harvest_interval',
        'pre_harvest_interval_days',
        'phi',
      ]),
      reEntryInterval: _firstNonEmptyString(json, const [
        're_entry_interval',
        'rei',
      ]),
      actions: _toStringList(json['actions']),
      monitoring: _toStringList(json['monitoring']),
      prevention: _toStringList(json['prevention']),
      escalateIf: _toStringList(json['escalate_if']),
      treatmentOptions: _toTreatmentOptions(json['treatment_options']),
      notes: _toStringList(json['notes']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mode': mode,
      'treatment_ready': treatmentReady,
      'review_status': reviewStatus,
      'expert_verified': expertVerified,
      'source': source,
      'verification_note': verificationNote,
      'reliability': reliability,
      'risk_level': riskLevel,
      'confidence_score': confidenceScore,
      'crop_family': cropFamily,
      'headline': headline,
      'next_step': nextStep,
      'active_ingredient': activeIngredient,
      'dosage': dosage,
      'ppe': ppe,
      'pre_harvest_interval': preHarvestInterval,
      're_entry_interval': reEntryInterval,
      'actions': actions,
      'monitoring': monitoring,
      'prevention': prevention,
      'escalate_if': escalateIf,
      'treatment_options': treatmentOptions
          .map((option) => option.toJson())
          .toList(),
      'notes': notes,
    };
  }

  // True when the server has confirmed the diagnosis and treatment data is
  // available — either fully verified by an expert, or advisory-level
  // (confirmed diagnosis but template not yet expert-signed).
  bool get canShowTreatmentDetails =>
      mode == 'treat' ||
      advisoryTreatmentAvailable ||
      treatmentOptions.isNotEmpty ||
      (treatmentReady && expertVerified);

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes' || text == 'y')
      return true;
    return false;
  }

  static List<String> _toStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<DiseaseTreatmentOption> _toTreatmentOptions(dynamic value) {
    if (value is! List) return const <DiseaseTreatmentOption>[];
    return value
        .whereType<Map<String, dynamic>>()
        .map(DiseaseTreatmentOption.fromJson)
        .toList();
  }

  static String? _firstNonEmptyString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}

class DiseaseTreatmentOption {
  final int? id;
  final String type;
  final String title;
  final String? crop;
  final String? diseaseKey;
  final String? diseaseKeyword;
  final String? summary;
  final String? naturalTreatment;
  final String? modernTreatment;
  final String? productName;
  final String? activeIngredient;
  final String? formulation;
  final String? registrationStatus;
  final String? dosage;
  final String? applicationTiming;
  final int? preHarvestIntervalDays;
  final int? reEntryIntervalHours;
  final int? maxApplications;
  final String? ppe;
  final String? restrictions;
  final List<String> monitoringSteps;
  final List<String> preventionSteps;

  const DiseaseTreatmentOption({
    required this.id,
    required this.type,
    required this.title,
    required this.crop,
    required this.diseaseKey,
    required this.diseaseKeyword,
    required this.summary,
    required this.naturalTreatment,
    required this.modernTreatment,
    required this.productName,
    required this.activeIngredient,
    required this.formulation,
    required this.registrationStatus,
    required this.dosage,
    required this.applicationTiming,
    required this.preHarvestIntervalDays,
    required this.reEntryIntervalHours,
    required this.maxApplications,
    required this.ppe,
    required this.restrictions,
    required this.monitoringSteps,
    required this.preventionSteps,
  });

  factory DiseaseTreatmentOption.fromJson(Map<String, dynamic> json) {
    return DiseaseTreatmentOption(
      id: _toOptionIntOrNull(json['id']),
      type: json['type']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      crop: _optionFirstNonEmptyString(json, const ['crop']),
      diseaseKey: _optionFirstNonEmptyString(json, const ['disease_key']),
      diseaseKeyword: _optionFirstNonEmptyString(json, const [
        'disease_keyword',
      ]),
      summary: _optionFirstNonEmptyString(json, const ['summary']),
      naturalTreatment: _optionFirstNonEmptyString(json, const [
        'natural_treatment',
      ]),
      modernTreatment: _optionFirstNonEmptyString(json, const [
        'modern_treatment',
      ]),
      productName: _optionFirstNonEmptyString(json, const ['product_name']),
      activeIngredient: _optionFirstNonEmptyString(json, const [
        'active_ingredient',
      ]),
      formulation: _optionFirstNonEmptyString(json, const ['formulation']),
      registrationStatus: _optionFirstNonEmptyString(json, const [
        'registration_status',
      ]),
      dosage: _optionFirstNonEmptyString(json, const ['dosage']),
      applicationTiming: _optionFirstNonEmptyString(json, const [
        'application_timing',
      ]),
      preHarvestIntervalDays: _toOptionIntOrNull(
        json['pre_harvest_interval_days'],
      ),
      reEntryIntervalHours: _toOptionIntOrNull(json['re_entry_interval_hours']),
      maxApplications: _toOptionIntOrNull(json['max_applications']),
      ppe: _optionFirstNonEmptyString(json, const ['ppe']),
      restrictions: _optionFirstNonEmptyString(json, const ['restrictions']),
      monitoringSteps: _optionStringList(json['monitoring_steps']),
      preventionSteps: _optionStringList(json['prevention_steps']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'title': title,
      'crop': crop,
      'disease_key': diseaseKey,
      'disease_keyword': diseaseKeyword,
      'summary': summary,
      'natural_treatment': naturalTreatment,
      'modern_treatment': modernTreatment,
      'product_name': productName,
      'active_ingredient': activeIngredient,
      'formulation': formulation,
      'registration_status': registrationStatus,
      'dosage': dosage,
      'application_timing': applicationTiming,
      'pre_harvest_interval_days': preHarvestIntervalDays,
      're_entry_interval_hours': reEntryIntervalHours,
      'max_applications': maxApplications,
      'ppe': ppe,
      'restrictions': restrictions,
      'monitoring_steps': monitoringSteps,
      'prevention_steps': preventionSteps,
    };
  }

  static int? _toOptionIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String? _optionFirstNonEmptyString(
    Map<String, dynamic> json,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static List<String> _optionStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
