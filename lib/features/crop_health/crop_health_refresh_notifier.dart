import 'package:flutter/foundation.dart';

final ValueNotifier<int> cropHealthRefreshNotifier = ValueNotifier<int>(0);

void notifyCropHealthUpdated() {
  cropHealthRefreshNotifier.value = cropHealthRefreshNotifier.value + 1;
}

