import 'package:flutter_test/flutter_test.dart';
import 'package:smart_farm/features/scan/offline_treatment_guidance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline treatment guide asset path is stable', () {
    expect(
      OfflineTreatmentGuidanceService.assetPathForTest,
      'assets/inference/offline_treatment_guide.json',
    );
  });

  testWidgets('offline treatment guide loads and returns fallback', (tester) async {
    final service = OfflineTreatmentGuidanceService.instance;
    service.clearMemoryCache();

    final guidance = await service.guidanceForDiseaseLabel('Unknown Disease Label');
    expect(guidance, isNotNull);
    expect(guidance!.headline.isNotEmpty, isTrue);
    expect(guidance.ppe, isNotNull);
  });
}

