import 'package:flutter/foundation.dart';

final ValueNotifier<int> diseaseReportRefreshNotifier = ValueNotifier<int>(0);

void notifyDiseaseReportUpdated() {
  diseaseReportRefreshNotifier.value = diseaseReportRefreshNotifier.value + 1;
}
