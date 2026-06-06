import 'package:flutter_test/flutter_test.dart';
import 'package:smart_farm/models/disease_report_model.dart';

void main() {
  test('treatment stays locked until expert verification', () {
    final guidance = DiseaseTreatmentGuidance.fromJson({
      'mode': 'treat',
      'treatment_ready': true,
      'review_status': 'draft',
      'expert_verified': false,
      'verification_note': 'Expert review required.',
      'headline': 'Draft guidance',
      'next_step': 'Wait for expert review.',
    });

    expect(guidance.treatmentReady, isTrue);
    expect(guidance.expertVerified, isFalse);
    expect(guidance.canShowTreatmentDetails, isFalse);
  });

  test('treatment unlocks only when ready and expert verified', () {
    final guidance = DiseaseTreatmentGuidance.fromJson({
      'mode': 'treat',
      'treatment_ready': true,
      'review_status': 'verified',
      'expert_verified': true,
      'verification_note': 'Approved for field use.',
      'headline': 'Verified guidance',
      'next_step': 'Follow approved treatment.',
    });

    expect(guidance.canShowTreatmentDetails, isTrue);
  });

  test('treatment guidance parses boolean-like strings correctly', () {
    final guidance = DiseaseTreatmentGuidance.fromJson({
      'mode': 'treat',
      'treatment_ready': 'true',
      'review_status': 'verified',
      'expert_verified': 'true',
      'verification_note': 'Approved for field use.',
      'headline': 'Verified guidance',
      'next_step': 'Follow approved treatment.',
    });

    expect(guidance.treatmentReady, isTrue);
    expect(guidance.expertVerified, isTrue);
    expect(guidance.canShowTreatmentDetails, isTrue);
  });
}
