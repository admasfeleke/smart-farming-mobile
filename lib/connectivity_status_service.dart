import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

class ConnectivityStatusService {
  ConnectivityStatusService._();

  static final ConnectivityStatusService instance = ConnectivityStatusService._();

  static const Duration _interval = Duration(seconds: 30);
  Timer? _timer;

  final ValueNotifier<ApiConnectivityStatus> notifier =
      ValueNotifier<ApiConnectivityStatus>(
    ApiConnectivityStatus(
      state: ApiConnectivityState.internetOnly,
      message: 'Connectivity not checked yet.',
      checkedAt: DateTime.now(),
    ),
  );

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    unawaited(refreshNow());
    _timer = Timer.periodic(_interval, (_) {
      unawaited(refreshNow());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<ApiConnectivityStatus> refreshNow() async {
    final status = await ApiClient.probeConnectivity();
    notifier.value = status;
    return status;
  }
}

