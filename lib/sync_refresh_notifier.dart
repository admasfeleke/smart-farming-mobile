import 'package:flutter/foundation.dart';

final ValueNotifier<int> syncRefreshNotifier = ValueNotifier<int>(0);

void notifySyncRefresh() {
  syncRefreshNotifier.value += 1;
}
