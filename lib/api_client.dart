import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'features/my_farm/models/farm_model.dart';
import 'features/my_farm/models/planting_model.dart';
import 'features/my_farm/models/plot_model.dart';
import 'language_store.dart';
import 'models/alert_model.dart';
import 'models/disease_report_model.dart';

enum ApiConnectivityState { offline, internetOnly, apiOnline }

class ApiConnectivityStatus {
  final ApiConnectivityState state;
  final String message;
  final DateTime checkedAt;

  const ApiConnectivityStatus({
    required this.state,
    required this.message,
    required this.checkedAt,
  });
}

class ApiClient {
  static const String _configuredBaseUrl = String.fromEnvironment(
    'SMART_FARM_API_BASE_URL',
    defaultValue: '',
  );
  static const String _defaultDeviceUrl = 'http://10.0.2.2:8000';
  // Legacy constant kept for compatibility with existing references.
  static const String baseUrl = _configuredBaseUrl;

  static Future<String> _resolveBaseUrl() async {
    final stored = await AuthSession.getApiBaseUrl();
    final candidate = (stored != null && stored.trim().isNotEmpty)
        ? stored.trim()
        : (_configuredBaseUrl.trim().isNotEmpty
              ? _configuredBaseUrl
              : _defaultDeviceUrl);
    if (kReleaseMode && candidate == _defaultDeviceUrl) {
      throw const ApiException(
        'Release API base URL is not configured. Set SMART_FARM_API_BASE_URL.',
      );
    }
    return validateAndNormalizeBaseUrl(candidate);
  }

  static Future<String> currentBaseUrlForDisplay() async {
    final stored = await AuthSession.getApiBaseUrl();
    final candidate = (stored != null && stored.trim().isNotEmpty)
        ? stored.trim()
        : (_configuredBaseUrl.trim().isNotEmpty
              ? _configuredBaseUrl
              : _defaultDeviceUrl);
    try {
      return validateAndNormalizeBaseUrl(candidate);
    } on ApiException {
      return candidate.trim();
    }
  }

  static String validateAndNormalizeBaseUrl(
    String rawUrl, {
    bool allowInsecureHttpInDebug = true,
  }) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw const ApiException('API server address is required.');
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      throw const ApiException(
        'API server address is invalid. Use full URL like https://api.example.com',
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const ApiException(
        'API server address must start with http:// or https://.',
      );
    }

    if (scheme == 'https' && _isDevelopmentHost(uri.host)) {
      throw const ApiException(
        'Local API host should use HTTP. Set API URL like http://<your-pc-ip>:8000',
      );
    }

    final insecureHttpAllowed =
        _isDevelopmentHost(uri.host) ||
        (allowInsecureHttpInDebug && !kReleaseMode);

    if (scheme != 'https' && !insecureHttpAllowed) {
      throw const ApiException(
        'Insecure public API URL blocked. Use HTTPS, or use a local/private URL like http://<your-pc-ip>:8000.',
      );
    }

    final normalized = uri.toString();
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  static bool _isDevelopmentHost(String host) {
    final h = host.trim().toLowerCase();
    if (h == 'localhost' || h == '127.0.0.1' || h == '10.0.2.2') {
      return true;
    }
    if (h.startsWith('192.168.')) {
      return true;
    }
    if (h.startsWith('10.')) {
      return true;
    }
    final match = RegExp(r'^172\.(\d+)\.').firstMatch(h);
    if (match != null) {
      final octet = int.tryParse(match.group(1)!);
      if (octet != null && octet >= 16 && octet <= 31) {
        return true;
      }
    }
    return false;
  }

  static String normalizePhoneForLogin(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D+'), '');
    if (digits.isEmpty) return '';
    if (digits.length == 9 && digits.startsWith('9')) {
      return '0$digits';
    }
    if (digits.length == 12 && digits.startsWith('2519')) {
      return '0${digits.substring(3)}';
    }
    if (digits.length == 10 && digits.startsWith('09')) {
      return digits;
    }
    return digits;
  }

  static String _formatApiDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<Map<String, String>> _authHeaders() async {
    var token = await AuthSession.getToken();
    if (token == null || token.isEmpty) {
      final refreshed = await _tryRefreshAccessToken();
      if (refreshed) {
        token = await AuthSession.getToken();
      }
    }
    if (token == null || token.isEmpty) {
      final offlineMode = await AuthSession.isOfflineModeActive();
      if (offlineMode) {
        throw const ApiException(
          'Offline mode is active. Connect to the internet to refresh your server session.',
        );
      }
      throw const ApiUnauthorized('Missing auth token.');
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ..._languageHeaders(),
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, String> _authHeadersForToken(String token) {
    return <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ..._languageHeaders(),
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, String> _jsonHeaders() {
    return <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ..._languageHeaders(),
    };
  }

  static Future<Map<String, String>> _authHeadersWithoutContentType() async {
    var token = await AuthSession.getToken();
    if (token == null || token.isEmpty) {
      final refreshed = await _tryRefreshAccessToken();
      if (refreshed) {
        token = await AuthSession.getToken();
      }
    }
    if (token == null || token.isEmpty) {
      final offlineMode = await AuthSession.isOfflineModeActive();
      if (offlineMode) {
        throw const ApiException(
          'Offline mode is active. Connect to the internet to refresh your server session.',
        );
      }
      throw const ApiUnauthorized('Missing auth token.');
    }
    return {
      'Accept': 'application/json',
      ..._languageHeaders(),
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, String> _languageHeaders() {
    final language = LanguageStore.notifier.value.trim().toLowerCase();
    final normalized = language.isEmpty ? 'am' : language;
    return <String, String>{
      'Accept-Language': normalized,
      'X-App-Language': normalized,
    };
  }

  static Future<Map<String, String>> mediaHeaders() async {
    final headers = await _authHeadersWithoutContentType();
    return <String, String>{
      ...headers,
      'Accept': 'image/*,application/octet-stream;q=0.9,*/*;q=0.5',
    };
  }

  static Future<bool> hasServerSessionCapability() async {
    final token = await AuthSession.getToken();
    if (token != null && token.trim().isNotEmpty) {
      return true;
    }
    return AuthSession.hasRefreshToken();
  }

  static Future<bool> _tryRefreshAccessToken() async {
    final inflight = _refreshInFlight;
    if (inflight != null) {
      return inflight;
    }

    final future = _refreshAccessTokenInternal();
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  static Future<bool> _refreshAccessTokenInternal() async {
    final refreshToken = await AuthSession.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/auth/refresh');
      await _validateTlsPinIfConfigured(uri);
      final response = await http
          .post(
            uri,
            headers: _jsonHeaders(),
            body: jsonEncode(<String, dynamic>{'refresh_token': refreshToken}),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final token = data['token']?.toString().trim();
        final nextRefreshToken = data['refresh_token']?.toString().trim();
        if ((token ?? '').isEmpty || (nextRefreshToken ?? '').isEmpty) {
          throw const ApiException(
            'Session refresh succeeded but tokens were missing.',
          );
        }
        await AuthSession.saveToken(token!);
        await AuthSession.saveRefreshToken(nextRefreshToken!);
        await AuthSession.setOfflineModeActive(false);
        final user = data['user'];
        if (user is Map<String, dynamic>) {
          final userName = user['name']?.toString().trim();
          final roleName = user['role_name']?.toString().trim();
          if ((userName ?? '').isNotEmpty) {
            await AuthSession.saveUserName(userName!);
          }
          if ((roleName ?? '').isNotEmpty) {
            await AuthSession.saveUserRole(roleName!);
          }
        }
        return true;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        await AuthSession.clearSession();
        return false;
      }
    } on ApiException {
      return false;
    } on TimeoutException {
      return false;
    }

    return false;
  }

  static List<dynamic> _extractList(dynamic body) {
    if (body is List) return body;
    if (body is Map<String, dynamic> && body['data'] is List) {
      return body['data'] as List;
    }
    return const [];
  }

  static int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static PaginationMeta _extractPaginationMeta(
    dynamic body, {
    required int requestedPage,
    required int requestedPerPage,
    required int itemCount,
  }) {
    if (body is Map<String, dynamic>) {
      final meta = body['meta'] ?? body['pagination'];
      if (meta is Map<String, dynamic>) {
        final currentPage = _asInt(meta['current_page'], requestedPage);
        final perPage = _asInt(meta['per_page'], requestedPerPage);
        final total = _asInt(meta['total'], itemCount);
        final lastPage = _asInt(meta['last_page'], currentPage);
        return PaginationMeta(
          currentPage: currentPage,
          perPage: perPage,
          total: total,
          lastPage: lastPage,
        );
      }
    }

    return PaginationMeta(
      currentPage: requestedPage,
      perPage: requestedPerPage,
      total: itemCount,
      lastPage: requestedPage,
    );
  }

  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _connectivityProbeTimeout = Duration(seconds: 8);
  static const Duration _loginRequestTimeout = Duration(seconds: 15);
  static const int _scanSubmitTimeoutSeconds = int.fromEnvironment(
    'SMART_FARM_SCAN_SUBMIT_TIMEOUT_SECONDS',
    defaultValue: 18,
  );
  static const Duration _scanSubmitTimeout = Duration(
    seconds: _scanSubmitTimeoutSeconds,
  );
  static const int _scanSubmitRetryAttempts = int.fromEnvironment(
    'SMART_FARM_SCAN_SUBMIT_RETRIES',
    defaultValue: 0,
  );
  static const int _maxRetryAttempts = 2;
  static const int _loginRetryAttempts = 1;
  static bool _unauthorizedHandled = false;
  static Future<bool>? _refreshInFlight;
  static const Map<String, Set<String>> _pinnedCertSha256ByHost =
      <String, Set<String>>{
        // Example:
        // 'api.smartfarm.et': {'replace_with_sha256_hex_of_server_cert_der'},
      };
  static const String _configuredTlsPinsRaw = String.fromEnvironment(
    'SMART_FARM_TLS_PINS',
    defaultValue: '',
  );
  static const Duration _pinValidationCacheTtl = Duration(minutes: 10);
  static final Map<String, DateTime> _pinValidationCache = <String, DateTime>{};
  static Map<String, Set<String>>? _runtimePinsCache;

  static const int _maxTelemetryEvents = 400;
  static final List<ApiTelemetryEvent> _telemetryEvents = <ApiTelemetryEvent>[];

  static List<ApiTelemetryEvent> telemetrySnapshot() =>
      List<ApiTelemetryEvent>.unmodifiable(_telemetryEvents);

  static void clearTelemetry() {
    _telemetryEvents.clear();
  }

  static void _logScanEvent(String event, Map<String, Object?> payload) {
    if (!kDebugMode) return;
    developer.log(
      jsonEncode(<String, Object?>{'event': event, ...payload}),
      name: 'smart_farm.scan',
    );
  }

  static void _recordTelemetry({
    required String method,
    required Uri uri,
    required int attempt,
    required Duration duration,
    int? statusCode,
    String? error,
  }) {
    final event = ApiTelemetryEvent(
      timestamp: DateTime.now(),
      method: method,
      uri: uri.toString(),
      attempt: attempt,
      latencyMs: duration.inMilliseconds,
      statusCode: statusCode,
      error: error,
    );
    _telemetryEvents.add(event);
    if (_telemetryEvents.length > _maxTelemetryEvents) {
      _telemetryEvents.removeRange(
        0,
        _telemetryEvents.length - _maxTelemetryEvents,
      );
    }
    if (kDebugMode) {
      debugPrint(
        '[API] $event.method $event.uri '
        'status=${event.statusCode ?? '-'} '
        'attempt=$event.attempt '
        'latency=${event.latencyMs}ms '
        '${event.error == null ? '' : 'error=${event.error}'}',
      );
    }
  }

  static Future<void> _validateTlsPinIfConfigured(Uri uri) async {
    if (uri.scheme.toLowerCase() != 'https') return;

    final host = uri.host.trim().toLowerCase();
    final pins = _pinsForHost(host);
    if (pins == null || pins.isEmpty) {
      if (kReleaseMode) {
        throw ApiException(
          'TLS pin is not configured for API host: $host. '
          'Set SMART_FARM_TLS_PINS or _pinnedCertSha256ByHost.',
        );
      }
      return;
    }

    final lastValidated = _pinValidationCache[host];
    if (lastValidated != null &&
        DateTime.now().difference(lastValidated) < _pinValidationCacheTtl) {
      return;
    }

    SecureSocket? socket;
    try {
      final port = uri.hasPort ? uri.port : 443;
      socket = await SecureSocket.connect(host, port, timeout: _requestTimeout);
      final cert = socket.peerCertificate;
      if (cert == null) {
        throw const ApiException('TLS certificate was not provided by server.');
      }
      final certSha256 = sha256.convert(cert.der).toString();
      if (!pins.contains(certSha256)) {
        throw const ApiException('TLS certificate pin mismatch.');
      }
      _pinValidationCache[host] = DateTime.now();
    } on HandshakeException {
      throw const ApiException(
        'TLS handshake failed. Check certificate validity.',
      );
    } on SocketException {
      throw const ApiException(
        'TLS pin validation failed to connect to API host.',
      );
    } on TimeoutException {
      throw const ApiException('TLS certificate validation timed out.');
    } finally {
      socket?.destroy();
    }
  }

  static ApiConnectivityState classifyConnectivityMessage(String message) {
    final m = message.toLowerCase();
    if (m.contains('socket') ||
        m.contains('no internet') ||
        m.contains('network is unreachable') ||
        m.contains('failed host lookup') ||
        m.contains('api base url is not configured') ||
        m.contains('api server address is required') ||
        m.contains('insecure public api url blocked')) {
      return ApiConnectivityState.offline;
    }
    if (m.contains('timeout') ||
        m.contains('tls') ||
        m.contains('handshake') ||
        m.contains('server') ||
        m.contains('503') ||
        m.contains('unavailable') ||
        m.contains('connection refused')) {
      return ApiConnectivityState.internetOnly;
    }
    return ApiConnectivityState.apiOnline;
  }

  static bool isConnectivityIssueMessage(String message) {
    final state = classifyConnectivityMessage(message);
    return state != ApiConnectivityState.apiOnline;
  }

  static String _connectivityHintForBase(String base) {
    final uri = Uri.tryParse(base);
    final host = uri?.host.trim().toLowerCase() ?? '';
    if (host == '10.0.2.2') {
      return ' Current API URL is $base. That host only works from an Android emulator. '
          'If you are testing on a real phone, set API URL to http://<your-pc-ip>:8000.';
    }
    if (host == 'localhost' || host == '127.0.0.1') {
      return ' Current API URL is $base. localhost only works on the same device as the server. '
          'If you are testing on another device, set API URL to http://<your-pc-ip>:8000.';
    }
    return ' Current API URL is $base.';
  }

  static Future<ApiConnectivityStatus> probeConnectivity() async {
    final checkedAt = DateTime.now();
    String? base;
    try {
      base = await _resolveBaseUrl();
      // Probe Laravel's public health route so we do not trigger auth/login throttling.
      final uri = Uri.parse('$base/up');
      await _validateTlsPinIfConfigured(uri);

      final response = await http
          .get(uri, headers: {'Accept': 'application/json', ..._languageHeaders()})
          .timeout(_connectivityProbeTimeout);

      // Any non-5xx response from the API server confirms API reachability.
      if (response.statusCode < 500) {
        return ApiConnectivityStatus(
          state: ApiConnectivityState.apiOnline,
          message: 'API reachable.',
          checkedAt: checkedAt,
        );
      }

      return ApiConnectivityStatus(
        state: ApiConnectivityState.internetOnly,
        message:
            'Internet available, but API returned server errors.${_connectivityHintForBase(base)}',
        checkedAt: checkedAt,
      );
    } on SocketException {
      return ApiConnectivityStatus(
        state: ApiConnectivityState.offline,
        message: 'No internet connection.',
        checkedAt: checkedAt,
      );
    } on TimeoutException {
      return ApiConnectivityStatus(
        state: ApiConnectivityState.internetOnly,
        message:
            'API request timed out. Server may be slow or unreachable.'
            '${base == null ? '' : _connectivityHintForBase(base)}',
        checkedAt: checkedAt,
      );
    } on HandshakeException {
      return ApiConnectivityStatus(
        state: ApiConnectivityState.internetOnly,
        message:
            'TLS/SSL handshake failed.${base == null ? '' : _connectivityHintForBase(base)}',
        checkedAt: checkedAt,
      );
    } on ApiException catch (e) {
      final state = classifyConnectivityMessage(e.message);
      final message = base == null
          ? e.message
          : '${e.message}${_connectivityHintForBase(base)}';
      return ApiConnectivityStatus(
        state: state == ApiConnectivityState.apiOnline
            ? ApiConnectivityState.internetOnly
            : state,
        message: message,
        checkedAt: checkedAt,
      );
    } catch (_) {
      return ApiConnectivityStatus(
        state: ApiConnectivityState.internetOnly,
        message:
            'Internet available, but API probe failed.'
            '${base == null ? '' : _connectivityHintForBase(base)}',
        checkedAt: checkedAt,
      );
    }
  }

  static Set<String>? _pinsForHost(String host) {
    final staticPins = _pinnedCertSha256ByHost[host];
    final dynamicPins = _runtimePins()[host];
    if (staticPins == null && dynamicPins == null) {
      return null;
    }
    return <String>{...?staticPins, ...?dynamicPins};
  }

  static Map<String, Set<String>> _runtimePins() {
    final cached = _runtimePinsCache;
    if (cached != null) return cached;
    final parsed = <String, Set<String>>{};
    final raw = _configuredTlsPinsRaw.trim();
    if (raw.isNotEmpty) {
      final hostDefs = raw.split(';');
      for (final hostDef in hostDefs) {
        final trimmed = hostDef.trim();
        if (trimmed.isEmpty) continue;
        final split = trimmed.split('=');
        if (split.length != 2) continue;
        final host = split[0].trim().toLowerCase();
        if (host.isEmpty) continue;
        final pinSet = split[1]
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .where((e) => RegExp(r'^[a-f0-9]{64}$').hasMatch(e))
            .toSet();
        if (pinSet.isEmpty) continue;
        parsed[host] = pinSet;
      }
    }
    _runtimePinsCache = parsed;
    return parsed;
  }

  static bool _isRetriableStatus(int statusCode) {
    return statusCode == 429 || statusCode >= 500;
  }

  static Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() request, {
    required String method,
    required Uri uri,
    Duration? timeout,
    int? maxRetryAttempts,
  }) async {
    final requestTimeout = timeout ?? _requestTimeout;
    final retries = maxRetryAttempts ?? _maxRetryAttempts;
    var attempt = 0;
    var backoff = const Duration(milliseconds: 350);
    var refreshedAfterUnauthorized = false;

    while (true) {
      attempt += 1;
      final sw = Stopwatch()..start();
      try {
        await _validateTlsPinIfConfigured(uri);
        final response = await request().timeout(requestTimeout);
        sw.stop();
        _recordTelemetry(
          method: method,
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          statusCode: response.statusCode,
        );
        if (response.statusCode == 401) {
          final refreshed =
              !refreshedAfterUnauthorized && await _tryRefreshAccessToken();
          if (refreshed) {
            refreshedAfterUnauthorized = true;
            continue;
          }
          await _handleUnauthorizedResponse();
          throw const ApiUnauthorized('Unauthorized');
        }
        if (_isRetriableStatus(response.statusCode) && attempt <= retries) {
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        }
        return response;
      } on TimeoutException {
        sw.stop();
        _recordTelemetry(
          method: method,
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          error: 'timeout',
        );
        if (attempt <= retries) {
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        }
        throw const ApiException('Network timeout. Please try again.');
      } on SocketException {
        sw.stop();
        _recordTelemetry(
          method: method,
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          error: 'socket_exception',
        );
        if (attempt <= retries) {
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        }
        _logScanEvent('submit.socket_exception', <String, Object?>{
          'attempt': attempt,
          'duration_ms': sw.elapsedMilliseconds,
        });
        throw const ApiException(
          'No internet connection. Please check network and retry.',
        );
      } on HandshakeException {
        sw.stop();
        _recordTelemetry(
          method: method,
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          error: 'tls_handshake',
        );
        _logScanEvent('submit.tls_handshake', <String, Object?>{
          'attempt': attempt,
          'duration_ms': sw.elapsedMilliseconds,
        });
        throw const ApiException(
          'SSL/TLS handshake failed. If this is a local server, use http://<your-pc-ip>:8000',
        );
      } on ApiException catch (e) {
        sw.stop();
        _recordTelemetry(
          method: method,
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          error: 'api_exception:${e.message}',
        );
        rethrow;
      }
    }
  }

  static Future<void> _handleUnauthorizedResponse() async {
    if (_unauthorizedHandled) {
      return;
    }

    // During offline-unlocked sessions, avoid forcing a logout cascade.
    final offlineMode = await AuthSession.isOfflineModeActive();
    if (offlineMode) {
      return;
    }

    _unauthorizedHandled = true;
    try {
      // Do not wipe offline login proof on token expiry/401.
      // Keep proof for offline unlock; explicit logout handles full clear policy.
      await AuthSession.clearSession();
    } finally {
      _unauthorizedHandled = false;
    }
  }

  static ApiException _validationException(http.Response response) {
    try {
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      if (body is Map<String, dynamic>) {
        final errors = body['errors'];
        if (errors is Map<String, dynamic>) {
          final messages = <String>[];
          for (final value in errors.values) {
            if (value is List && value.isNotEmpty) {
              messages.add(value.first.toString());
            } else if (value is String && value.isNotEmpty) {
              messages.add(value);
            }
          }
          if (messages.isNotEmpty) {
            return ApiException(messages.join('\n'));
          }
        }

        final message = body['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return ApiException(message);
        }
      }
    } catch (_) {
      // Use fallback below.
    }
    return const ApiException('Validation failed.');
  }

  static String? _extractServerMessage(String body) {
    try {
      final decoded = jsonDecode(_sanitizeJsonBody(body));
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message']?.toString().trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      // Ignore invalid JSON.
    }
    return null;
  }

  static String _sanitizeJsonBody(String body) {
    var sanitized = body.trim();
    if (sanitized.startsWith('\uFEFF')) {
      sanitized = sanitized.substring(1);
    }
    return sanitized;
  }

  static Map<String, dynamic> _decodeJsonMapOrThrow(
    String body, {
    required String fallbackMessage,
  }) {
    try {
      final decoded = jsonDecode(_sanitizeJsonBody(body));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const FormatException('Expected JSON object.');
    } on FormatException {
      final snippet = _sanitizeJsonBody(body);
      final preview = snippet.isEmpty
          ? 'empty response'
          : (snippet.length > 160
                ? '${snippet.substring(0, 160)}...'
                : snippet);
      throw ApiException('$fallbackMessage Server returned: $preview');
    }
  }

  static Future<List<FarmModel>> getFarms({
    int page = 1,
    int perPage = 50,
  }) async {
    final result = await getFarmsWithCounts(page: page, perPage: perPage);
    return result.farms;
  }

  static Future<FarmsResponse> getFarmsWithCounts({
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/farms',
      ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException('Failed to load farms (${response.statusCode}).');
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final farms = <FarmModel>[];
      final plotCounts = <int, int>{};
      for (final item in list.whereType<Map<String, dynamic>>()) {
        final farm = FarmModel.fromJson(item);
        farms.add(farm);
        final count = item['plots_count'];
        if (count is int) {
          plotCounts[farm.id] = count;
        } else if (count is num) {
          plotCounts[farm.id] = count.toInt();
        } else if (count is String) {
          plotCounts[farm.id] = int.tryParse(count) ?? 0;
        }
      }
      final pagination = _extractPaginationMeta(
        body,
        requestedPage: page,
        requestedPerPage: perPage,
        itemCount: farms.length,
      );
      return FarmsResponse(
        farms: farms,
        plotCounts: plotCounts,
        pagination: pagination,
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<List<PlotModel>> getPlots(
    int farmId, {
    int page = 1,
    int perPage = 50,
  }) async {
    final result = await getPlotsPage(farmId, page: page, perPage: perPage);
    return result.items;
  }

  static Future<PaginatedResponse<PlotModel>> getPlotsPage(
    int farmId, {
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/farms/$farmId/plots',
      ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException('Failed to load plots (${response.statusCode}).');
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => PlotModel.fromJson(e))
          .toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<PlotModel> createPlot({
    required int farmId,
    required String plotName,
    double? areaHectares,
    String? soilType,
    bool? isActive,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/farms/$farmId/plots');
      final isActiveValue = isActive == null ? null : (isActive ? 1 : 0);
      final body = <String, dynamic>{
        'plot_name': plotName,
        'area_hectares': ?areaHectares,
        if (soilType != null && soilType.trim().isNotEmpty)
          'soil_type': soilType.trim(),
        'is_active': ?isActiveValue,
      };
      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'POST',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final plotJson = data['data'] is Map<String, dynamic>
            ? data['data']
            : data;
        return PlotModel.fromJson(plotJson as Map<String, dynamic>);
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException('Failed to create plot (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<PlotModel> updatePlot({
    required int plotId,
    String? plotName,
    double? areaHectares,
    String? soilType,
    bool? isActive,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/plots/$plotId');
      final isActiveValue = isActive == null ? null : (isActive ? 1 : 0);
      final body = <String, dynamic>{
        if (plotName != null && plotName.trim().isNotEmpty)
          'plot_name': plotName.trim(),
        'area_hectares': ?areaHectares,
        if (soilType != null && soilType.trim().isNotEmpty)
          'soil_type': soilType.trim(),
        'is_active': ?isActiveValue,
      };
      final response = await _sendWithRetry(
        () async => http.put(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'PUT',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final plotJson = data['data'] is Map<String, dynamic>
            ? data['data']
            : data;
        return PlotModel.fromJson(plotJson as Map<String, dynamic>);
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException('Failed to update plot (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<void> deletePlot(int plotId) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/plots/$plotId');
      final response = await _sendWithRetry(
        () async => http.delete(uri, headers: await _authHeaders()),
        method: 'DELETE',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 204) return;
      throw ApiException('Failed to delete plot (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<FarmModel> createFarm({
    required int regionId,
    required String farmName,
    double? latitude,
    double? longitude,
    double? areaHectares,
    String? farmType,
    bool? isActive,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/farms');
      final isActiveValue = isActive == null ? null : (isActive ? 1 : 0);
      final body = <String, dynamic>{
        'region_id': regionId,
        'farm_name': farmName,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'area_hectares': ?areaHectares,
        if (farmType != null && farmType.trim().isNotEmpty)
          'farm_type': farmType.trim(),
        'is_active': ?isActiveValue,
      };
      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'POST',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final farmJson = data['data'] is Map<String, dynamic>
            ? data['data']
            : data;
        return FarmModel.fromJson(farmJson as Map<String, dynamic>);
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException('Failed to create farm (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<FarmModel> updateFarm({
    required int farmId,
    int? regionId,
    String? farmName,
    double? latitude,
    double? longitude,
    double? areaHectares,
    String? farmType,
    bool? isActive,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/farms/$farmId');
      final isActiveValue = isActive == null ? null : (isActive ? 1 : 0);
      final body = <String, dynamic>{
        'region_id': ?regionId,
        if (farmName != null && farmName.trim().isNotEmpty)
          'farm_name': farmName.trim(),
        'latitude': ?latitude,
        'longitude': ?longitude,
        'area_hectares': ?areaHectares,
        if (farmType != null && farmType.trim().isNotEmpty)
          'farm_type': farmType.trim(),
        'is_active': ?isActiveValue,
      };
      final response = await _sendWithRetry(
        () async => http.put(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'PUT',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final farmJson = data['data'] is Map<String, dynamic>
            ? data['data']
            : data;
        return FarmModel.fromJson(farmJson as Map<String, dynamic>);
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException('Failed to update farm (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<void> deleteFarm(int farmId) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/farms/$farmId');
      final response = await _sendWithRetry(
        () async => http.delete(uri, headers: await _authHeaders()),
        method: 'DELETE',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 204) {
        return;
      }
      throw ApiException('Failed to delete farm (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<List<PlantingModel>> getPlantings(
    int plotId, {
    int page = 1,
    int perPage = 50,
  }) async {
    final result = await getPlantingsPage(plotId, page: page, perPage: perPage);
    return result.items;
  }

  static Future<PaginatedResponse<PlantingModel>> getPlantingsPage(
    int plotId, {
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/plots/$plotId/plantings',
      ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load plantings (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => PlantingModel.fromJson(e))
          .toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<PlantingModel> createPlanting({
    required int plotId,
    required int cropId,
    required DateTime plantingDate,
    DateTime? expectedHarvestDate,
    String? status,
    bool? isActive,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/plots/$plotId/plantings');
      final isActiveValue = isActive == null ? null : (isActive ? 1 : 0);
      final body = <String, dynamic>{
        'crop_id': cropId,
        'planting_date': _formatApiDate(plantingDate),
      };
      if (expectedHarvestDate != null) {
        body['expected_harvest_date'] = _formatApiDate(expectedHarvestDate);
      }
      if (status != null && status.trim().isNotEmpty) {
        body['status'] = status.trim();
      }
      if (isActiveValue != null) {
        body['is_active'] = isActiveValue;
      }
      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'POST',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final plantingJson = data['data'] is Map<String, dynamic>
            ? data['data']
            : data;
        return PlantingModel.fromJson(plantingJson as Map<String, dynamic>);
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException('Failed to create planting (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<PlantingModel> updatePlanting({
    required int plantingId,
    int? cropId,
    DateTime? plantingDate,
    DateTime? expectedHarvestDate,
    String? status,
    bool? isActive,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/plantings/$plantingId');
      final isActiveValue = isActive == null ? null : (isActive ? 1 : 0);
      final body = <String, dynamic>{};
      if (cropId != null) {
        body['crop_id'] = cropId;
      }
      if (plantingDate != null) {
        body['planting_date'] = _formatApiDate(plantingDate);
      }
      if (expectedHarvestDate != null) {
        body['expected_harvest_date'] = _formatApiDate(expectedHarvestDate);
      }
      if (status != null && status.trim().isNotEmpty) {
        body['status'] = status.trim();
      }
      if (isActiveValue != null) {
        body['is_active'] = isActiveValue;
      }
      final response = await _sendWithRetry(
        () async => http.put(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'PUT',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final plantingJson = data['data'] is Map<String, dynamic>
            ? data['data']
            : data;
        return PlantingModel.fromJson(plantingJson as Map<String, dynamic>);
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException('Failed to update planting (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<void> deletePlanting(int plantingId) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/plantings/$plantingId');
      final response = await _sendWithRetry(
        () async => http.delete(uri, headers: await _authHeaders()),
        method: 'DELETE',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 204) return;
      throw ApiException('Failed to delete planting (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<List<AlertModel>> getAlerts({
    int page = 1,
    int perPage = 50,
    String? roleName,
  }) async {
    final result = await getAlertsPage(
      page: page,
      perPage: perPage,
      roleName: roleName,
    );
    return result.items;
  }

  static Future<PaginatedResponse<AlertModel>> getAlertsPage({
    int page = 1,
    int perPage = 50,
    String? roleName,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/alerts').replace(
        queryParameters: {
          'page': '$page',
          'per_page': '$perPage',
          if (roleName != null && roleName.trim().isNotEmpty)
            'role_name': roleName.trim(),
        },
      );
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException('Failed to load alerts (${response.statusCode}).');
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => AlertModel.fromJson(e))
          .toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<AlertModel> acknowledgeAlert(int alertId) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/alerts/$alertId/acknowledge');
      final response = await _sendWithRetry(
        () async => http.put(uri, headers: await _authHeaders()),
        method: 'PUT',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode == 200) {
        final body = jsonDecode(_sanitizeJsonBody(response.body));
        final data =
            body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
            ? body['data'] as Map<String, dynamic>
            : body as Map<String, dynamic>;
        return AlertModel.fromJson(data);
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException(
        'Failed to acknowledge alert (${response.statusCode}).',
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<AlertModel> resolveAlert(int alertId) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/alerts/$alertId/resolve');
      final response = await _sendWithRetry(
        () async => http.put(uri, headers: await _authHeaders()),
        method: 'PUT',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode == 200) {
        final body = jsonDecode(_sanitizeJsonBody(response.body));
        final data =
            body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
            ? body['data'] as Map<String, dynamic>
            : body as Map<String, dynamic>;
        return AlertModel.fromJson(data);
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException('Failed to resolve alert (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<List<Map<String, dynamic>>> getCrops({
    int page = 1,
    int perPage = 200,
  }) async {
    final result = await getCropsPage(page: page, perPage: perPage);
    return result.items;
  }

  static Future<PaginatedResponse<Map<String, dynamic>>> getCropsPage({
    int page = 1,
    int perPage = 200,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/crops',
      ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException('Failed to load crops (${response.statusCode}).');
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list.whereType<Map<String, dynamic>>().toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<List<Map<String, dynamic>>> getRegions({
    int page = 1,
    int perPage = 200,
  }) async {
    final result = await getRegionsPage(page: page, perPage: perPage);
    return result.items;
  }

  static Future<PaginatedResponse<Map<String, dynamic>>> getRegionsPage({
    int page = 1,
    int perPage = 200,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/regions',
      ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException('Failed to load regions (${response.statusCode}).');
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list.whereType<Map<String, dynamic>>().toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> getWeatherSummary() async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/weather-data/summary');
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load weather summary (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      return body is Map<String, dynamic> ? body : {};
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<void> deleteSoilHealth(int soilHealthId) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/soil-health/$soilHealthId');
      final response = await _sendWithRetry(
        () async => http.delete(uri, headers: await _authHeaders()),
        method: 'DELETE',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 204 || response.statusCode == 200) return;
      throw ApiException(
        'Failed to delete soil health (${response.statusCode}).',
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<List<Map<String, dynamic>>> getSoilHealth({
    int page = 1,
    int perPage = 50,
    int? plotId,
  }) async {
    final result = await getSoilHealthPage(
      page: page,
      perPage: perPage,
      plotId: plotId,
    );
    return result.items;
  }

  static Future<PaginatedResponse<Map<String, dynamic>>> getSoilHealthPage({
    int page = 1,
    int perPage = 50,
    int? plotId,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/soil-health').replace(
        queryParameters: {
          'page': '$page',
          'per_page': '$perPage',
          if (plotId != null) 'plot_id': '$plotId',
        },
      );
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load soil health data (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list.whereType<Map<String, dynamic>>().toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> getSoilHealthRecommendations(
    int soilHealthId,
  ) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/soil-health/$soilHealthId/recommendations',
      );
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load soil health recommendations (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      return body is Map<String, dynamic> ? body : {};
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> createSoilHealth({
    required int plotId,
    double? phLevel,
    double? nitrogen,
    double? phosphorus,
    double? potassium,
    double? organicMatter,
    double? moisture,
    String? soilType,
    String? testMethod,
    DateTime? testedAt,
    String? evidencePath,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/soil-health');
      final resolvedTestMethod = (testMethod ?? '').trim();
      final evidenceFilePath = evidencePath?.trim();

      http.Response response;
      if (evidenceFilePath != null && evidenceFilePath.isNotEmpty) {
        final headers = await _authHeadersWithoutContentType();
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll(headers);
        request.fields['plot_id'] = '$plotId';
        if (phLevel != null) request.fields['ph_level'] = '$phLevel';
        if (nitrogen != null) request.fields['nitrogen'] = '$nitrogen';
        if (phosphorus != null) request.fields['phosphorus'] = '$phosphorus';
        if (potassium != null) request.fields['potassium'] = '$potassium';
        if (organicMatter != null) {
          request.fields['organic_matter'] = '$organicMatter';
        }
        if (moisture != null) request.fields['moisture_level'] = '$moisture';
        if (soilType != null && soilType.trim().isNotEmpty) {
          request.fields['soil_type'] = soilType.trim();
        }
        request.fields['test_date'] = (testedAt ?? DateTime.now())
            .toIso8601String();
        request.fields['test_method'] = resolvedTestMethod.isNotEmpty
            ? resolvedTestMethod
            : 'manual';
        request.files.add(
          await http.MultipartFile.fromPath('evidence', evidenceFilePath),
        );

        final streamed = await request.send().timeout(_requestTimeout);
        response = await http.Response.fromStream(
          streamed,
        ).timeout(_requestTimeout);
      } else {
        final normalizedSoilType = soilType?.trim();
        final body = <String, dynamic>{
          'plot_id': plotId,
          'test_date': (testedAt ?? DateTime.now()).toIso8601String(),
          'test_method': resolvedTestMethod.isNotEmpty
              ? resolvedTestMethod
              : 'manual',
        };
        if (phLevel != null) body['ph_level'] = phLevel;
        if (nitrogen != null) body['nitrogen'] = nitrogen;
        if (phosphorus != null) body['phosphorus'] = phosphorus;
        if (potassium != null) body['potassium'] = potassium;
        if (organicMatter != null) body['organic_matter'] = organicMatter;
        if (moisture != null) body['moisture_level'] = moisture;
        if ((normalizedSoilType ?? '').isNotEmpty) {
          body['soil_type'] = normalizedSoilType;
        }
        response = await _sendWithRetry(
          () async => http.post(
            uri,
            headers: await _authHeaders(),
            body: jsonEncode(body),
          ),
          method: 'POST',
          uri: uri,
        );
      }
      if (response.statusCode == 401) {
        await _handleUnauthorizedResponse();
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        return data['data'] is Map<String, dynamic> ? data['data'] : data;
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException(
        'Failed to create soil health data (${response.statusCode}).',
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> updateSoilHealth({
    required int soilHealthId,
    double? phLevel,
    double? nitrogen,
    double? phosphorus,
    double? potassium,
    double? organicMatter,
    double? moisture,
    String? soilType,
    String? testMethod,
    DateTime? testedAt,
    String? reviewStatus,
    String? evidencePath,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/soil-health/$soilHealthId');
      final resolvedTestMethod = (testMethod ?? '').trim();
      final evidenceFilePath = evidencePath?.trim();

      http.Response response;
      if (evidenceFilePath != null && evidenceFilePath.isNotEmpty) {
        final headers = await _authHeadersWithoutContentType();
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll(headers);
        request.fields['_method'] = 'PUT';
        if (phLevel != null) request.fields['ph_level'] = '$phLevel';
        if (nitrogen != null) request.fields['nitrogen'] = '$nitrogen';
        if (phosphorus != null) request.fields['phosphorus'] = '$phosphorus';
        if (potassium != null) request.fields['potassium'] = '$potassium';
        if (organicMatter != null) {
          request.fields['organic_matter'] = '$organicMatter';
        }
        if (moisture != null) request.fields['moisture_level'] = '$moisture';
        if (soilType != null && soilType.trim().isNotEmpty) {
          request.fields['soil_type'] = soilType.trim();
        }
        if (testedAt != null) {
          request.fields['test_date'] = testedAt.toIso8601String();
        }
        if (resolvedTestMethod.isNotEmpty) {
          request.fields['test_method'] = resolvedTestMethod;
        }
        if (reviewStatus != null && reviewStatus.trim().isNotEmpty) {
          request.fields['review_status'] = reviewStatus.trim();
        }
        request.files.add(
          await http.MultipartFile.fromPath('evidence', evidenceFilePath),
        );

        final streamed = await request.send().timeout(_requestTimeout);
        response = await http.Response.fromStream(
          streamed,
        ).timeout(_requestTimeout);
      } else {
        final normalizedSoilType = soilType?.trim();
        final normalizedReviewStatus = reviewStatus?.trim();
        final body = <String, dynamic>{
          if (testedAt != null) 'test_date': testedAt.toIso8601String(),
          if (resolvedTestMethod.isNotEmpty) 'test_method': resolvedTestMethod,
        };
        if (phLevel != null) body['ph_level'] = phLevel;
        if (nitrogen != null) body['nitrogen'] = nitrogen;
        if (phosphorus != null) body['phosphorus'] = phosphorus;
        if (potassium != null) body['potassium'] = potassium;
        if (organicMatter != null) body['organic_matter'] = organicMatter;
        if (moisture != null) body['moisture_level'] = moisture;
        if ((normalizedSoilType ?? '').isNotEmpty) {
          body['soil_type'] = normalizedSoilType;
        }
        if ((normalizedReviewStatus ?? '').isNotEmpty) {
          body['review_status'] = normalizedReviewStatus;
        }
        response = await _sendWithRetry(
          () async => http.put(
            uri,
            headers: await _authHeaders(),
            body: jsonEncode(body),
          ),
          method: 'PUT',
          uri: uri,
        );
      }

      if (response.statusCode == 401) {
        await _handleUnauthorizedResponse();
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        return data['data'] is Map<String, dynamic> ? data['data'] : data;
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException(
        'Failed to update soil health data (${response.statusCode}).',
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<List<DiseaseReportModel>> getDiseaseReports({
    int page = 1,
    int perPage = 50,
  }) async {
    final result = await getDiseaseReportsPage(page: page, perPage: perPage);
    return result.items;
  }

  static Future<PaginatedResponse<DiseaseReportModel>> getDiseaseReportsPage({
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/disease-reports',
      ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load disease reports (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => DiseaseReportModel.fromJson(e))
          .toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<DiseaseReportModel> getDiseaseReportById(int reportId) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/disease-reports/$reportId');
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load disease report (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final data =
          body is Map<String, dynamic> && body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : body as Map<String, dynamic>;
      return DiseaseReportModel.fromJson(data);
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<String> getDiseaseReportStatus(int reportId) async {
    final report = await getDiseaseReportById(reportId);
    return report.status;
  }

  static bool shouldPollDiseaseReportStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'new' ||
        normalized == 'processing' ||
        normalized == 'queued' ||
        normalized == 'analyzing' ||
        normalized == 'pending' ||
        normalized == 'reviewing';
  }

  static bool isDiseaseReportFinalStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'completed' ||
        normalized == 'done' ||
        normalized == 'ready' ||
        normalized == 'resolved' ||
        normalized == 'analyzed' ||
        normalized == 'confirmed' ||
        normalized == 'verified' ||
        normalized == 'rejected';
  }

  static Future<DiseaseReportModel> pollForScanCompletion({
    required int reportId,
    DiseaseReportModel? initialReport,
    int maxAttempts = 8,
    Duration pollInterval = const Duration(seconds: 2),
    void Function(int attempt, int maxAttempts, String status)? onProgress,
  }) async {
    var latest = initialReport ?? await getDiseaseReportById(reportId);
    onProgress?.call(0, maxAttempts, latest.status);
    if (isDiseaseReportFinalStatus(latest.status)) {
      return latest;
    }

    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(pollInterval);
      try {
        latest = await getDiseaseReportById(reportId);
      } on ApiUnauthorized {
        rethrow;
      } catch (_) {
        onProgress?.call(i + 1, maxAttempts, latest.status);
        continue;
      }
      onProgress?.call(i + 1, maxAttempts, latest.status);
      if (isDiseaseReportFinalStatus(latest.status)) {
        return latest;
      }
    }

    return latest;
  }

  static Future<DiseaseReportModel> verifyDiseaseReport({
    required int reportId,
    required String diseaseName,
    required String severity,
    required String status,
    String? description,
    double? confidenceScore,
    String? decisionReasonCode,
    String? decisionComment,
    String? evidencePath,
    String? evidenceCaption,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/disease-reports/$reportId/verify');
      final normalizedDescription = description?.trim();
      final normalizedDecisionReason = decisionReasonCode?.trim();
      final normalizedDecisionComment = decisionComment?.trim();
      final normalizedEvidenceCaption = evidenceCaption?.trim();
      final normalizedEvidencePath = evidencePath?.trim();

      http.Response response;
      if (normalizedEvidencePath != null && normalizedEvidencePath.isNotEmpty) {
        final headers = await _authHeadersWithoutContentType();
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll(headers);
        request.fields['_method'] = 'PUT';
        request.fields['disease_name'] = diseaseName.trim();
        request.fields['severity'] = severity.trim();
        request.fields['status'] = status.trim();
        if (normalizedDescription != null && normalizedDescription.isNotEmpty) {
          request.fields['description'] = normalizedDescription;
        }
        if (confidenceScore != null) {
          request.fields['confidence_score'] = '$confidenceScore';
        }
        if (normalizedDecisionReason != null &&
            normalizedDecisionReason.isNotEmpty) {
          request.fields['decision_reason_code'] = normalizedDecisionReason;
        }
        if (normalizedDecisionComment != null &&
            normalizedDecisionComment.isNotEmpty) {
          request.fields['decision_comment'] = normalizedDecisionComment;
        }
        if (normalizedEvidenceCaption != null &&
            normalizedEvidenceCaption.isNotEmpty) {
          request.fields['evidence_caption'] = normalizedEvidenceCaption;
        }
        request.files.add(
          await http.MultipartFile.fromPath('evidence', normalizedEvidencePath),
        );
        final streamed = await request.send().timeout(_requestTimeout);
        response = await http.Response.fromStream(
          streamed,
        ).timeout(_requestTimeout);
      } else {
        final body = <String, dynamic>{
          'disease_name': diseaseName.trim(),
          'severity': severity.trim(),
          'status': status.trim(),
          if (normalizedDescription != null && normalizedDescription.isNotEmpty)
            'description': normalizedDescription,
          'confidence_score': ?confidenceScore,
          if (normalizedDecisionReason != null &&
              normalizedDecisionReason.isNotEmpty)
            'decision_reason_code': normalizedDecisionReason,
          if (normalizedDecisionComment != null &&
              normalizedDecisionComment.isNotEmpty)
            'decision_comment': normalizedDecisionComment,
          if (normalizedEvidenceCaption != null &&
              normalizedEvidenceCaption.isNotEmpty)
            'evidence_caption': normalizedEvidenceCaption,
        };
        response = await _sendWithRetry(
          () async => http.put(
            uri,
            headers: await _authHeaders(),
            body: jsonEncode(body),
          ),
          method: 'PUT',
          uri: uri,
        );
      }

      if (response.statusCode == 401) {
        await _handleUnauthorizedResponse();
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) {
        throw const ApiForbidden('Forbidden');
      }
      if (response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final reportJson = data['data'] is Map<String, dynamic>
            ? data['data']
            : data;
        return DiseaseReportModel.fromJson(reportJson as Map<String, dynamic>);
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException(
        'Failed to verify disease report (${response.statusCode}).',
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<DiseaseReportModel> createDiseaseReport({
    required int plotId,
    required int cropId,
    int? plantingId,
    required String imagePath,
    DateTime? capturedAt,
    String? submissionId,
    String? growthStage,
    int? symptomDays,
    bool? recentRain,
    String? fieldNotes,
    int? captureShots,
    String? captureProtocol,
    String? provisionalDiseaseName,
    String? provisionalCanonicalDiseaseName,
    String? provisionalSeverity,
    double? provisionalConfidence,
    String? provisionalInferenceMessage,
    String? provisionalInferenceUnavailable,
  }) async {
    _logScanEvent('submit.start', <String, Object?>{
      'plot_id': plotId,
      'crop_id': cropId,
      'planting_id': plantingId,
      'has_submission_id':
          submissionId != null && submissionId.trim().isNotEmpty,
      'has_captured_at': capturedAt != null,
    });
    final base = await _resolveBaseUrl();
    final uri = Uri.parse('$base/api/v1/disease-reports/scan');
    final headers = await _authHeadersWithoutContentType();
    var attempt = 0;
    var backoff = const Duration(milliseconds: 350);

    while (true) {
      attempt += 1;
      final sw = Stopwatch()..start();
      try {
        await _validateTlsPinIfConfigured(uri);
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll(headers);
        if (submissionId != null && submissionId.trim().isNotEmpty) {
          request.headers['Idempotency-Key'] = submissionId.trim();
        }
        request.fields['plot_id'] = '$plotId';
        request.fields['crop_id'] = '$cropId';
        if (submissionId != null && submissionId.trim().isNotEmpty) {
          request.fields['client_submission_id'] = submissionId.trim();
        }
        if (plantingId != null) {
          request.fields['planting_id'] = '$plantingId';
        }
        if (capturedAt != null) {
          request.fields['captured_at'] = capturedAt.toIso8601String();
        }

        if (growthStage != null && growthStage.trim().isNotEmpty) {
          request.fields['scan_metadata[growth_stage]'] = growthStage.trim();
        }
        if (symptomDays != null) {
          request.fields['scan_metadata[symptom_days]'] = '$symptomDays';
        }
        if (recentRain != null) {
          request.fields['scan_metadata[recent_rain]'] = recentRain ? '1' : '0';
        }
        if (fieldNotes != null && fieldNotes.trim().isNotEmpty) {
          request.fields['scan_metadata[field_notes]'] = fieldNotes.trim();
        }
        if (captureShots != null) {
          request.fields['scan_metadata[capture_shots]'] = '$captureShots';
        }
        if (captureProtocol != null && captureProtocol.trim().isNotEmpty) {
          request.fields['scan_metadata[capture_protocol]'] = captureProtocol
              .trim();
        }
        if (provisionalDiseaseName != null &&
            provisionalDiseaseName.trim().isNotEmpty) {
          request.fields['scan_metadata[offline_local_disease_name]'] =
              provisionalDiseaseName.trim();
        }
        if (provisionalCanonicalDiseaseName != null &&
            provisionalCanonicalDiseaseName.trim().isNotEmpty) {
          request.fields['scan_metadata[offline_local_disease_key]'] =
              provisionalCanonicalDiseaseName.trim();
        }
        if (provisionalSeverity != null &&
            provisionalSeverity.trim().isNotEmpty) {
          request.fields['scan_metadata[offline_local_severity]'] =
              provisionalSeverity.trim();
        }
        if (provisionalConfidence != null) {
          request.fields['scan_metadata[offline_local_confidence]'] =
              provisionalConfidence.toString();
        }
        if (provisionalInferenceMessage != null &&
            provisionalInferenceMessage.trim().isNotEmpty) {
          request.fields['scan_metadata[offline_local_inference]'] =
              provisionalInferenceMessage.trim();
        }
        if (provisionalInferenceUnavailable != null &&
            provisionalInferenceUnavailable.trim().isNotEmpty) {
          request.fields['scan_metadata[offline_local_inference_unavailable]'] =
              provisionalInferenceUnavailable.trim();
        }

        request.files.add(
          await http.MultipartFile.fromPath('image', imagePath),
        );

        final streamed = await request.send().timeout(_scanSubmitTimeout);
        final response = await http.Response.fromStream(
          streamed,
        ).timeout(_scanSubmitTimeout);
        sw.stop();
        _recordTelemetry(
          method: 'POST',
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          statusCode: response.statusCode,
        );

        if (response.statusCode == 401) {
          await _handleUnauthorizedResponse();
          throw const ApiUnauthorized('Unauthorized');
        }
        if (response.statusCode == 201 || response.statusCode == 200) {
          final data =
              jsonDecode(_sanitizeJsonBody(response.body))
                  as Map<String, dynamic>;
          final reportJson = data['data'] is Map<String, dynamic>
              ? data['data']
              : data;
          _logScanEvent('submit.success', <String, Object?>{
            'status': response.statusCode,
            'attempt': attempt,
            'duration_ms': sw.elapsedMilliseconds,
          });
          return DiseaseReportModel.fromJson(
            reportJson as Map<String, dynamic>,
          );
        }
        if (response.statusCode == 422) {
          throw _validationException(response);
        }
        if (_isRetriableStatus(response.statusCode) &&
            attempt <= _scanSubmitRetryAttempts) {
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        }
        if (response.statusCode == 503) {
          final message = _extractServerMessage(response.body);
          _logScanEvent('submit.backend_unavailable', <String, Object?>{
            'status': response.statusCode,
            'attempt': attempt,
            'duration_ms': sw.elapsedMilliseconds,
          });
          throw ApiException(
            message ??
                'Scan service is temporarily unavailable (503). Please retry in a moment.',
          );
        }
        if (response.statusCode >= 500) {
          _logScanEvent('submit.server_error', <String, Object?>{
            'status': response.statusCode,
            'attempt': attempt,
            'duration_ms': sw.elapsedMilliseconds,
          });
          throw const ApiException(
            'Server error while submitting disease report. Please retry shortly.',
          );
        }
        throw ApiException(
          'Failed to submit disease report (${response.statusCode}).',
        );
      } on TimeoutException {
        sw.stop();
        _recordTelemetry(
          method: 'POST',
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          error: 'timeout',
        );
        if (attempt <= _scanSubmitRetryAttempts) {
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        }
        _logScanEvent('submit.timeout', <String, Object?>{
          'attempt': attempt,
          'duration_ms': sw.elapsedMilliseconds,
        });
        throw const ApiException(
          'Scan timed out. Check connection quality and inference server, then retry.',
        );
      } on SocketException {
        sw.stop();
        _recordTelemetry(
          method: 'POST',
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          error: 'socket_exception',
        );
        if (attempt <= _scanSubmitRetryAttempts) {
          await Future.delayed(backoff);
          backoff *= 2;
          continue;
        }
        _logScanEvent('submit.socket_exception', <String, Object?>{
          'attempt': attempt,
          'duration_ms': sw.elapsedMilliseconds,
        });
        throw const ApiException(
          'No internet connection. Please check network and retry.',
        );
      } on HandshakeException {
        sw.stop();
        _recordTelemetry(
          method: 'POST',
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          error: 'tls_handshake',
        );
        _logScanEvent('submit.tls_handshake', <String, Object?>{
          'attempt': attempt,
          'duration_ms': sw.elapsedMilliseconds,
        });
        throw const ApiException(
          'SSL/TLS handshake failed. If this is a local server, use http://<your-pc-ip>:8000',
        );
      } on FileSystemException {
        sw.stop();
        _recordTelemetry(
          method: 'POST',
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          error: 'file_missing',
        );
        throw const ApiException(
          'Captured image file is unavailable. Please retake and submit again.',
        );
      } on ApiException catch (e) {
        sw.stop();
        _recordTelemetry(
          method: 'POST',
          uri: uri,
          attempt: attempt,
          duration: sw.elapsed,
          error: 'api_exception:${e.message}',
        );
        rethrow;
      }
    }
  }

  static Future<List<Map<String, dynamic>>> getCropHealthRecords({
    int page = 1,
    int perPage = 50,
  }) async {
    final result = await getCropHealthRecordsPage(page: page, perPage: perPage);
    return result.items;
  }

  static Future<PaginatedResponse<Map<String, dynamic>>>
  getCropHealthRecordsPage({int page = 1, int perPage = 50}) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/crop-health',
      ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load crop health (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list.whereType<Map<String, dynamic>>().toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<LoginResult> login({
    required String phone,
    required String password,
  }) async {
    final base = await _resolveBaseUrl();
    final normalizedPhone = normalizePhoneForLogin(phone);
    try {
      final uri = Uri.parse('$base/api/v1/auth/login');
      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: _jsonHeaders(),
          body: jsonEncode(<String, dynamic>{
            'phone': normalizedPhone.isEmpty ? phone.trim() : normalizedPhone,
            'password': password,
          }),
        ),
        method: 'POST',
        uri: uri,
        timeout: _loginRequestTimeout,
        maxRetryAttempts: _loginRetryAttempts,
      );

      if (response.statusCode == 200) {
        final data = _decodeJsonMapOrThrow(
          response.body,
          fallbackMessage: 'Login response was not valid JSON.',
        );
        final token = data['token'] as String?;
        final refreshToken = data['refresh_token'] as String?;
        if (token == null || token.isEmpty) {
          throw const ApiException('Login succeeded but token missing.');
        }
        if (refreshToken == null || refreshToken.isEmpty) {
          throw const ApiException(
            'Login succeeded but refresh token missing.',
          );
        }
        final user = data['user'];
        final userName = user is Map<String, dynamic>
            ? user['name']?.toString()
            : null;
        final roleName = user is Map<String, dynamic>
            ? user['role_name']?.toString()
            : null;
        return LoginResult(
          token: token,
          refreshToken: refreshToken,
          userName: userName,
          roleName: roleName,
        );
      }

      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 422) {
        throw ApiException(
          _extractServerMessage(response.body) ??
              (response.statusCode == 422
                  ? 'Please check your phone and password.'
                  : 'Invalid phone or password.'),
        );
      }

      throw ApiException(
        _extractServerMessage(response.body) ??
            'Login failed (${response.statusCode}).',
      );
    } on ApiUnauthorized {
      throw const ApiException('Invalid phone or password.');
    } on ApiException catch (e) {
      if (isConnectivityIssueMessage(e.message)) {
        throw ApiException('${e.message}${_connectivityHintForBase(base)}');
      }
      rethrow;
    } on TimeoutException {
      throw ApiException('Request timed out.${_connectivityHintForBase(base)}');
    }
  }

  static Future<LoginResult> registerFarmer({
    required String name,
    required String phone,
    required String password,
    String? email,
    int? regionId,
  }) async {
    final base = await _resolveBaseUrl();
    final normalizedPhone = normalizePhoneForLogin(phone);
    try {
      final uri = Uri.parse('$base/api/v1/auth/register');
      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: _jsonHeaders(),
          body: jsonEncode(<String, dynamic>{
            'name': name.trim(),
            'phone': normalizedPhone.isEmpty ? phone.trim() : normalizedPhone,
            'password': password,
            if ((email ?? '').trim().isNotEmpty) 'email': email!.trim(),
            if (regionId != null && regionId > 0) 'region_id': regionId,
          }),
        ),
        method: 'POST',
        uri: uri,
        timeout: _loginRequestTimeout,
        maxRetryAttempts: _loginRetryAttempts,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = _decodeJsonMapOrThrow(
          response.body,
          fallbackMessage: 'Registration response was not valid JSON.',
        );
        final token = data['token'] as String?;
        final refreshToken = data['refresh_token'] as String?;
        if (token == null || token.isEmpty) {
          throw const ApiException('Registration succeeded but token missing.');
        }
        if (refreshToken == null || refreshToken.isEmpty) {
          throw const ApiException(
            'Registration succeeded but refresh token missing.',
          );
        }
        final user = data['user'];
        final userName = user is Map<String, dynamic>
            ? user['name']?.toString()
            : null;
        final roleName = user is Map<String, dynamic>
            ? user['role_name']?.toString()
            : null;
        return LoginResult(
          token: token,
          refreshToken: refreshToken,
          userName: userName,
          roleName: roleName,
        );
      }

      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 422) {
        throw ApiException(
          _extractServerMessage(response.body) ??
              (response.statusCode == 422
                  ? 'Please check the account details.'
                  : 'Account registration failed.'),
        );
      }

      throw ApiException(
        _extractServerMessage(response.body) ??
            'Registration failed (${response.statusCode}).',
      );
    } on ApiException catch (e) {
      if (isConnectivityIssueMessage(e.message)) {
        throw ApiException('${e.message}${_connectivityHintForBase(base)}');
      }
      rethrow;
    } on TimeoutException {
      throw ApiException(
        'Registration timed out. Please try again.${_connectivityHintForBase(base)}',
      );
    }
  }

  static Future<void> logout({
    String? tokenOverride,
    String? refreshTokenOverride,
    String? baseUrlOverride,
  }) async {
    try {
      final base = baseUrlOverride ?? await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/auth/logout');
      final headers = tokenOverride != null && tokenOverride.trim().isNotEmpty
          ? _authHeadersForToken(tokenOverride.trim())
          : await _authHeaders();
      final refreshToken =
          refreshTokenOverride ?? await AuthSession.getRefreshToken();
      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            if (refreshToken != null && refreshToken.isNotEmpty)
              'refresh_token': refreshToken,
          }),
        ),
        method: 'POST',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException('Logout failed (${response.statusCode}).');
      }
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Uint8List> fetchProtectedBytes(String url) async {
    try {
      final uri = await _resolveMediaUri(url);
      final response = await _sendWithRetry(
        () async => http.get(
          uri,
          headers: <String, String>{
            ...(await _authHeadersWithoutContentType()),
            'Accept': 'image/*,application/octet-stream;q=0.9,*/*;q=0.5',
          },
        ),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) {
        throw const ApiForbidden('Forbidden');
      }
      if (response.statusCode != 200) {
        throw ApiException('Failed to load media (${response.statusCode}).');
      }
      final contentType = response.headers['content-type']
          ?.toLowerCase()
          .trim();
      final bytes = response.bodyBytes;
      if (!_isSupportedImageResponse(contentType, bytes)) {
        throw ApiException(
          'Invalid image response'
          '${contentType == null || contentType.isEmpty ? '' : ' ($contentType)'}',
        );
      }
      return bytes;
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Uri> _resolveMediaUri(String rawUrl) async {
    final trimmed = rawUrl.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return _normalizeMediaUriHost(parsed);
    }
    final base = await _resolveBaseUrl();
    final baseUri = Uri.parse(base);
    final relative = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    return baseUri.resolve(relative);
  }

  static Future<Uri> _normalizeMediaUriHost(Uri uri) async {
    final host = uri.host.toLowerCase().trim();
    if (host.isEmpty) {
      return uri;
    }
    const loopbackHosts = <String>{'127.0.0.1', 'localhost', '0.0.0.0', '::1'};
    if (!loopbackHosts.contains(host)) {
      return uri;
    }

    final base = await _resolveBaseUrl();
    final baseUri = Uri.parse(base);
    return uri.replace(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : uri.port,
    );
  }

  static bool _isSupportedImageResponse(String? contentType, Uint8List bytes) {
    if (bytes.isEmpty) {
      return false;
    }
    if (contentType != null && contentType.isNotEmpty) {
      if (contentType.startsWith('image/')) {
        return true;
      }
      if (contentType.contains('application/json') ||
          contentType.contains('text/html') ||
          contentType.contains('text/plain')) {
        return false;
      }
    }
    return _hasSupportedImageSignature(bytes);
  }

  static bool _hasSupportedImageSignature(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true; // JPEG
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true; // PNG
    }
    if (bytes.length >= 6) {
      final header = String.fromCharCodes(bytes.take(6));
      if (header == 'GIF87a' || header == 'GIF89a') {
        return true;
      }
    }
    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.take(4));
      final webp = String.fromCharCodes(bytes.skip(8).take(4));
      if (riff == 'RIFF' && webp == 'WEBP') {
        return true;
      }
      final boxType = String.fromCharCodes(bytes.skip(4).take(4));
      final brand = String.fromCharCodes(bytes.skip(8).take(4));
      const isoBrands = <String>{
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
        'avif',
        'avis',
      };
      if (boxType == 'ftyp' && isoBrands.contains(brand)) {
        return true;
      }
    }
    return false;
  }

  static Future<Map<String, dynamic>> getCurrentUserProfile() async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/auth/me');
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) {
        throw const ApiForbidden('Forbidden');
      }
      if (response.statusCode != 200) {
        throw ApiException('Failed to load profile (${response.statusCode}).');
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      if (body is Map<String, dynamic>) {
        return body['data'] is Map<String, dynamic> ? body['data'] : body;
      }
      return <String, dynamic>{};
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<void> healthCheck() async {
    final base = await _resolveBaseUrl();
    final uri = Uri.parse('$base/api/v1/health');
    final response = await _sendWithRetry(
      () async => http.get(uri, headers: await _authHeaders()),
      method: 'GET',
      uri: uri,
    );
    if (response.statusCode == 403) {
      throw const ApiForbidden('Forbidden');
    }
    if (response.statusCode != 200) {
      throw ApiException('Health check failed (${response.statusCode}).');
    }
  }

  static Future<List<Map<String, dynamic>>> getWeatherData({
    int page = 1,
    int perPage = 50,
  }) async {
    final result = await getWeatherDataPage(page: page, perPage: perPage);
    return result.items;
  }

  static Future<PaginatedResponse<Map<String, dynamic>>> getWeatherDataPage({
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/weather-data',
      ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load weather data (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list.whereType<Map<String, dynamic>>().toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> createWeatherData({
    required double temperature,
    required double humidity,
    required double precipitation,
    required double windSpeed,
    required double soilMoisture,
    required String dataSource,
    required DateTime recordedAt,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/weather-data');
      final body = <String, dynamic>{
        'temperature': temperature,
        'humidity': humidity,
        'precipitation': precipitation,
        'wind_speed': windSpeed,
        'soil_moisture': soilMoisture,
        'data_source': dataSource,
        'recorded_at': recordedAt.toIso8601String(),
      };
      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'POST',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final weatherJson = data['data'] is Map<String, dynamic>
            ? data['data']
            : data;
        return weatherJson as Map<String, dynamic>;
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException(
        'Failed to create weather data (${response.statusCode}).',
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> getWeatherDataSummary() async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/weather-data/summary');
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load weather summary (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      return body is Map<String, dynamic> ? body : {};
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<List<Map<String, dynamic>>> getSoilHealthData({
    int page = 1,
    int perPage = 50,
  }) async {
    final result = await getSoilHealthDataPage(page: page, perPage: perPage);
    return result.items;
  }

  static Future<PaginatedResponse<Map<String, dynamic>>> getSoilHealthDataPage({
    int page = 1,
    int perPage = 50,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse(
        '$base/api/v1/soil-health',
      ).replace(queryParameters: {'page': '$page', 'per_page': '$perPage'});
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) throw const ApiForbidden('Forbidden');
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load soil health data (${response.statusCode}).',
        );
      }
      final body = jsonDecode(_sanitizeJsonBody(response.body));
      final list = _extractList(body);
      final items = list.whereType<Map<String, dynamic>>().toList();
      return PaginatedResponse(
        items: items,
        pagination: _extractPaginationMeta(
          body,
          requestedPage: page,
          requestedPerPage: perPage,
          itemCount: items.length,
        ),
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> createSoilHealthData({
    required int plotId,
    required double phLevel,
    required double nitrogen,
    required double phosphorus,
    required double potassium,
    required double organicMatter,
    required String soilType,
    required double moistureLevel,
    required DateTime testDate,
    required String testMethod,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/soil-health');
      final body = <String, dynamic>{
        'plot_id': plotId,
        'ph_level': phLevel,
        'nitrogen': nitrogen,
        'phosphorus': phosphorus,
        'potassium': potassium,
        'organic_matter': organicMatter,
        'soil_type': soilType,
        'moisture_level': moistureLevel,
        'test_date': testDate.toIso8601String(),
        'test_method': testMethod,
      };
      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'POST',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        final soilJson = data['data'] is Map<String, dynamic>
            ? data['data']
            : data;
        return soilJson as Map<String, dynamic>;
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException(
        'Failed to create soil health data (${response.statusCode}).',
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> predictYield({
    required int plantingId,
    double? temperature,
    double? humidity,
    double? precipitation,
    double? soilPh,
    double? soilNitrogen,
    double? soilPhosphorus,
    double? soilPotassium,
    double? soilMoisture,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/yield-prediction');
      final body = <String, dynamic>{
        'planting_id': plantingId,
        'temperature': ?temperature,
        'humidity': ?humidity,
        'precipitation': ?precipitation,
        'soil_ph': ?soilPh,
        'soil_nitrogen': ?soilNitrogen,
        'soil_phosphorus': ?soilPhosphorus,
        'soil_potassium': ?soilPotassium,
        'soil_moisture': ?soilMoisture,
      };
      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'POST',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        return data;
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException('Failed to predict yield (${response.statusCode}).');
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> getYieldPredictionForPlanting(
    int plantingId,
  ) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/yield-prediction/$plantingId');
      final response = await _sendWithRetry(
        () async => http.get(uri, headers: await _authHeaders()),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 403) {
        throw const ApiForbidden('Forbidden');
      }
      if (response.statusCode != 200) {
        throw ApiException(
          'Failed to load yield prediction (${response.statusCode}).',
        );
      }
      final data = jsonDecode(_sanitizeJsonBody(response.body));
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> getDiseasePreventionRecommendations({
    required int cropId,
    double? temperature,
    double? humidity,
    double? precipitation,
    double? soilMoisture,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/disease-prevention/recommendations');
      final queryParams = <String, String>{};
      queryParams['crop_id'] = '$cropId';
      if (temperature != null) queryParams['temperature'] = '$temperature';
      if (humidity != null) queryParams['humidity'] = '$humidity';
      if (precipitation != null) {
        queryParams['precipitation'] = '$precipitation';
      }
      if (soilMoisture != null) queryParams['soil_moisture'] = '$soilMoisture';

      final response = await _sendWithRetry(
        () async => http.get(
          uri.replace(queryParameters: queryParams),
          headers: await _authHeaders(),
        ),
        method: 'GET',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 200) {
        final data =
            jsonDecode(_sanitizeJsonBody(response.body))
                as Map<String, dynamic>;
        return data;
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException(
        'Failed to get disease prevention recommendations (${response.statusCode}).',
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }

  static Future<Map<String, dynamic>> runDiseasePreventionAnalysis({
    int? farmId,
    int? plotId,
    int? cropId,
    double? temperature,
    double? humidity,
    double? precipitation,
    double? soilMoisture,
  }) async {
    try {
      final base = await _resolveBaseUrl();
      final uri = Uri.parse('$base/api/v1/disease-prevention/analyze');
      final body = <String, dynamic>{};
      if (farmId != null) body['farm_id'] = farmId;
      if (plotId != null) body['plot_id'] = plotId;
      if (cropId != null) body['crop_id'] = cropId;
      if (temperature != null) body['temperature'] = temperature;
      if (humidity != null) body['humidity'] = humidity;
      if (precipitation != null) body['precipitation'] = precipitation;
      if (soilMoisture != null) body['soil_moisture'] = soilMoisture;

      final response = await _sendWithRetry(
        () async => http.post(
          uri,
          headers: await _authHeaders(),
          body: jsonEncode(body),
        ),
        method: 'POST',
        uri: uri,
      );
      if (response.statusCode == 401) {
        throw const ApiUnauthorized('Unauthorized');
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(_sanitizeJsonBody(response.body));
        return data is Map<String, dynamic> ? data : <String, dynamic>{};
      }
      if (response.statusCode == 422) {
        throw _validationException(response);
      }
      throw ApiException(
        'Failed to run disease prevention analysis (${response.statusCode}).',
      );
    } on TimeoutException {
      throw const ApiException('Request timed out.');
    }
  }
}

class FarmsResponse {
  final List<FarmModel> farms;
  final Map<int, int> plotCounts;
  final PaginationMeta? pagination;
  const FarmsResponse({
    required this.farms,
    required this.plotCounts,
    this.pagination,
  });
}

class PaginatedResponse<T> {
  final List<T> items;
  final PaginationMeta pagination;
  const PaginatedResponse({required this.items, required this.pagination});
}

class PaginationMeta {
  final int currentPage;
  final int perPage;
  final int total;
  final int lastPage;

  const PaginationMeta({
    required this.currentPage,
    required this.perPage,
    required this.total,
    required this.lastPage,
  });

  bool get hasMore => currentPage < lastPage;
}

class LoginResult {
  final String token;
  final String refreshToken;
  final String? userName;
  final String? roleName;
  const LoginResult({
    required this.token,
    required this.refreshToken,
    required this.userName,
    required this.roleName,
  });
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class ApiUnauthorized extends ApiException {
  const ApiUnauthorized(super.message);
}

class ApiForbidden extends ApiException {
  const ApiForbidden(super.message);
}

class ApiTelemetryEvent {
  final DateTime timestamp;
  final String method;
  final String uri;
  final int attempt;
  final int latencyMs;
  final int? statusCode;
  final String? error;

  const ApiTelemetryEvent({
    required this.timestamp,
    required this.method,
    required this.uri,
    required this.attempt,
    required this.latencyMs,
    required this.statusCode,
    required this.error,
  });

  @override
  String toString() {
    return 'ApiTelemetryEvent(method: $method, uri: $uri, status: ${statusCode ?? '-'}, attempt: $attempt, latency: ${latencyMs}ms, error: $error)';
  }
}
