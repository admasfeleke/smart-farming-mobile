import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class AuthSession {
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'auth_refresh_token';
  static const String _apiBaseUrlKey = 'api_base_url';
  static const String _userNameKey = 'auth_user_name';
  static const String _userRoleKey = 'auth_user_role';
  static const String _activeFarmerPhoneKey = 'auth_active_farmer_phone';
  static const String _offlineLoginPhoneKey = 'offline_login_phone';
  static const String _offlineLoginVerifierKey = 'offline_login_verifier';
  static const String _offlineLoginSaltKey = 'offline_login_salt';
  static const String _offlineSessionExpiryMsKey = 'offline_session_expiry_ms';
  static const String _offlineSessionActiveKey = 'offline_session_active';
  static const String _offlineUnlockFailedAttemptsKey =
      'offline_unlock_failed_attempts';
  static const String _offlineUnlockBlockedUntilMsKey =
      'offline_unlock_blocked_until_ms';
  static const String _pendingLocalRegistrationNameKey =
      'pending_local_registration_name';
  static const String _pendingLocalRegistrationPhoneKey =
      'pending_local_registration_phone';
  static const String _pendingLocalRegistrationPasswordKey =
      'pending_local_registration_password';
  static const String _pendingLocalRegistrationEmailKey =
      'pending_local_registration_email';
  static const String _pendingLocalRegistrationRegionIdKey =
      'pending_local_registration_region_id';
  static const String _pendingLocalRegistrationCreatedAtMsKey =
      'pending_local_registration_created_at_ms';
  static const Duration _defaultOfflineSessionTtl = Duration(hours: 72);
  static const int _maxOfflineUnlockAttempts = 5;
  static const Duration _offlineUnlockLockout = Duration(minutes: 15);
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static bool _isLikelySafeToken(String token) {
    final trimmed = token.trim();
    if (trimmed.length < 20 || trimmed.length > 4096) return false;
    if (RegExp(r'\s').hasMatch(trimmed)) return false;
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(trimmed)) return false;
    return true;
  }

  static Future<void> _writeSecureWithPrefsFallback(
    String key,
    String value,
  ) async {
    final prefs = await _prefs();
    try {
      await _secureStorage.write(key: key, value: value);
      await prefs.remove(key);
    } catch (_) {
      await prefs.setString(key, value);
    }
  }

  static Future<String?> _readSecureWithPrefsFallback(String key) async {
    try {
      final secureValue = await _secureStorage.read(key: key);
      if (secureValue != null && secureValue.trim().isNotEmpty) {
        return secureValue.trim();
      }
    } catch (_) {
      // Fall back to SharedPreferences below.
    }

    final prefs = await _prefs();
    final plainValue = prefs.getString(key)?.trim();
    return (plainValue == null || plainValue.isEmpty) ? null : plainValue;
  }

  static Future<void> saveToken(String token) async {
    await _writeSecureWithPrefsFallback(_tokenKey, token);
  }

  static Future<void> saveRefreshToken(String token) async {
    await _writeSecureWithPrefsFallback(_refreshTokenKey, token);
  }

  static Future<String?> getToken() async {
    String? secureToken;
    try {
      secureToken = await _secureStorage.read(key: _tokenKey);
    } catch (_) {
      secureToken = null;
    }
    if (secureToken != null && secureToken.isNotEmpty) {
      return secureToken;
    }

    // Legacy migration from plaintext SharedPreferences.
    final prefs = await _prefs();
    final legacyToken = prefs.getString(_tokenKey)?.trim();
    if (legacyToken != null && legacyToken.isNotEmpty) {
      await prefs.remove(_tokenKey);
      if (_isLikelySafeToken(legacyToken)) {
        await _secureStorage.write(key: _tokenKey, value: legacyToken);
        return legacyToken;
      }
    }
    return null;
  }

  static Future<void> clearToken() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (_) {
      // SharedPreferences fallback cleared below.
    }
    final prefs = await _prefs();
    await prefs.remove(_tokenKey);
  }

  static Future<String?> getRefreshToken() async {
    final token = await _readSecureWithPrefsFallback(_refreshTokenKey);
    if (token != null && token.trim().isNotEmpty) {
      return token.trim();
    }
    return null;
  }

  static Future<bool> hasRefreshToken() async {
    final token = await getRefreshToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clearRefreshToken() async {
    try {
      await _secureStorage.delete(key: _refreshTokenKey);
    } catch (_) {
      // SharedPreferences fallback cleared below.
    }
    final prefs = await _prefs();
    await prefs.remove(_refreshTokenKey);
  }

  static String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D+'), '');
    if (digits.isEmpty) return '';

    // Canonicalize common Ethiopia phone formats:
    // 9XXXXXXXX  -> 09XXXXXXXX
    // 2519XXXXXXX -> 09XXXXXXXX
    if (digits.length == 9 && digits.startsWith('9')) {
      return '0$digits';
    }
    if (digits.length == 12 && digits.startsWith('2519')) {
      return '0${digits.substring(3)}';
    }
    if (digits.length == 10 && digits.startsWith('09')) {
      return digits;
    }

    // Fallback for other valid local variants (keeps deterministic comparison).
    return digits;
  }

  static String normalizeFarmerPhone(String phone) => _normalizePhone(phone);

  static Future<String?> getActiveFarmerPhone() async {
    final prefs = await _prefs();
    final value = prefs.getString(_activeFarmerPhoneKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> saveActiveFarmerPhone(String phone) async {
    final normalizedPhone = _normalizePhone(phone);
    if (normalizedPhone.isEmpty) return;
    final prefs = await _prefs();
    await prefs.setString(_activeFarmerPhoneKey, normalizedPhone);
  }

  static Future<void> markActiveFarmerUnknown() async {
    final prefs = await _prefs();
    await prefs.setString(_activeFarmerPhoneKey, 'unknown_server_session');
  }

  static Future<bool> isDifferentActiveFarmer(String phone) async {
    final normalizedPhone = _normalizePhone(phone);
    if (normalizedPhone.isEmpty) return false;
    final activePhone = await getActiveFarmerPhone();
    return activePhone != normalizedPhone;
  }

  static String _saltForOfflineProof(String phone, String password) {
    final seed = '$phone|$password|${DateTime.now().millisecondsSinceEpoch}';
    return sha256.convert(utf8.encode(seed)).toString().substring(0, 24);
  }

  static String _offlineProof({
    required String salt,
    required String phone,
    required String password,
  }) {
    final normalizedPhone = _normalizePhone(phone);
    final payload = '$salt|$normalizedPhone|$password';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  static Future<void> saveOfflineLoginProof({
    required String phone,
    required String password,
    Duration ttl = _defaultOfflineSessionTtl,
  }) async {
    final normalizedPhone = _normalizePhone(phone);
    if (normalizedPhone.isEmpty || password.isEmpty) return;

    final salt = _saltForOfflineProof(normalizedPhone, password);
    final verifier = _offlineProof(
      salt: salt,
      phone: normalizedPhone,
      password: password,
    );
    final expiryMs = DateTime.now().add(ttl).millisecondsSinceEpoch;

    await _secureStorage.write(
      key: _offlineLoginPhoneKey,
      value: normalizedPhone,
    );
    await _secureStorage.write(key: _offlineLoginSaltKey, value: salt);
    await _secureStorage.write(key: _offlineLoginVerifierKey, value: verifier);
    final prefs = await _prefs();
    await prefs.setInt(_offlineSessionExpiryMsKey, expiryMs);
    await _clearOfflineUnlockThrottle();
  }

  static Future<bool> hasValidOfflineLoginProof() async {
    final phone = await _secureStorage.read(key: _offlineLoginPhoneKey);
    final salt = await _secureStorage.read(key: _offlineLoginSaltKey);
    final verifier = await _secureStorage.read(key: _offlineLoginVerifierKey);
    final prefs = await _prefs();
    final expiryMs = prefs.getInt(_offlineSessionExpiryMsKey) ?? 0;
    if ((phone ?? '').isEmpty ||
        (salt ?? '').isEmpty ||
        (verifier ?? '').isEmpty) {
      return false;
    }
    if (expiryMs <= DateTime.now().millisecondsSinceEpoch) {
      return false;
    }
    return true;
  }

  static Future<bool> tryOfflineUnlock({
    required String phone,
    required String password,
  }) async {
    if (password.isEmpty) return false;
    final blockedUntil = await offlineUnlockBlockedUntil();
    if (blockedUntil != null) {
      return false;
    }
    final storedPhone = await _secureStorage.read(key: _offlineLoginPhoneKey);
    final salt = await _secureStorage.read(key: _offlineLoginSaltKey);
    final verifier = await _secureStorage.read(key: _offlineLoginVerifierKey);
    final prefs = await _prefs();
    final expiryMs = prefs.getInt(_offlineSessionExpiryMsKey) ?? 0;
    if ((storedPhone ?? '').isEmpty ||
        (salt ?? '').isEmpty ||
        (verifier ?? '').isEmpty) {
      return false;
    }
    if (expiryMs <= DateTime.now().millisecondsSinceEpoch) {
      return false;
    }
    final normalizedPhone = _normalizePhone(phone);
    if (normalizedPhone != storedPhone) {
      return false;
    }
    final inputVerifier = _offlineProof(
      salt: salt!,
      phone: normalizedPhone,
      password: password,
    );
    if (inputVerifier != verifier) {
      await _registerOfflineUnlockFailure();
      return false;
    }
    await _clearOfflineUnlockThrottle();
    await setOfflineModeActive(true);
    return true;
  }

  static Future<DateTime?> offlineUnlockBlockedUntil() async {
    final prefs = await _prefs();
    final blockedUntilMs = prefs.getInt(_offlineUnlockBlockedUntilMsKey) ?? 0;
    if (blockedUntilMs <= DateTime.now().millisecondsSinceEpoch) {
      if (blockedUntilMs != 0) {
        await prefs.remove(_offlineUnlockBlockedUntilMsKey);
        await prefs.remove(_offlineUnlockFailedAttemptsKey);
      }
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(blockedUntilMs);
  }

  static Future<void> _registerOfflineUnlockFailure() async {
    final prefs = await _prefs();
    final failedAttempts =
        (prefs.getInt(_offlineUnlockFailedAttemptsKey) ?? 0) + 1;
    await prefs.setInt(_offlineUnlockFailedAttemptsKey, failedAttempts);
    if (failedAttempts >= _maxOfflineUnlockAttempts) {
      final blockedUntil = DateTime.now()
          .add(_offlineUnlockLockout)
          .millisecondsSinceEpoch;
      await prefs.setInt(_offlineUnlockBlockedUntilMsKey, blockedUntil);
      await prefs.remove(_offlineUnlockFailedAttemptsKey);
    }
  }

  static Future<void> _clearOfflineUnlockThrottle() async {
    final prefs = await _prefs();
    await prefs.remove(_offlineUnlockFailedAttemptsKey);
    await prefs.remove(_offlineUnlockBlockedUntilMsKey);
  }

  static Future<void> setOfflineModeActive(bool active) async {
    final prefs = await _prefs();
    await prefs.setBool(_offlineSessionActiveKey, active);
  }

  static Future<bool> isOfflineModeActive() async {
    final prefs = await _prefs();
    return prefs.getBool(_offlineSessionActiveKey) ?? false;
  }

  static Future<void> clearOfflineLoginProof() async {
    await _secureStorage.delete(key: _offlineLoginPhoneKey);
    await _secureStorage.delete(key: _offlineLoginSaltKey);
    await _secureStorage.delete(key: _offlineLoginVerifierKey);
    final prefs = await _prefs();
    await prefs.remove(_offlineSessionExpiryMsKey);
    await prefs.remove(_offlineSessionActiveKey);
    await prefs.remove(_offlineUnlockFailedAttemptsKey);
    await prefs.remove(_offlineUnlockBlockedUntilMsKey);
  }

  static Future<void> savePendingLocalRegistration({
    required String name,
    required String phone,
    required String password,
    String? email,
    int? regionId,
  }) async {
    final normalizedPhone = _normalizePhone(phone);
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || normalizedPhone.isEmpty || password.isEmpty) {
      return;
    }

    await _secureStorage.write(
      key: _pendingLocalRegistrationNameKey,
      value: trimmedName,
    );
    await _secureStorage.write(
      key: _pendingLocalRegistrationPhoneKey,
      value: normalizedPhone,
    );
    await _secureStorage.write(
      key: _pendingLocalRegistrationPasswordKey,
      value: password,
    );
    final trimmedEmail = email?.trim();
    if (trimmedEmail != null && trimmedEmail.isNotEmpty) {
      await _secureStorage.write(
        key: _pendingLocalRegistrationEmailKey,
        value: trimmedEmail,
      );
    } else {
      await _secureStorage.delete(key: _pendingLocalRegistrationEmailKey);
    }

    if (regionId != null && regionId > 0) {
      await _secureStorage.write(
        key: _pendingLocalRegistrationRegionIdKey,
        value: regionId.toString(),
      );
    } else {
      await _secureStorage.delete(key: _pendingLocalRegistrationRegionIdKey);
    }

    final prefs = await _prefs();
    await prefs.setInt(
      _pendingLocalRegistrationCreatedAtMsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<PendingLocalRegistration?> getPendingLocalRegistration() async {
    final name = await _secureStorage.read(
      key: _pendingLocalRegistrationNameKey,
    );
    final phone = await _secureStorage.read(
      key: _pendingLocalRegistrationPhoneKey,
    );
    final password = await _secureStorage.read(
      key: _pendingLocalRegistrationPasswordKey,
    );
    if ((name ?? '').trim().isEmpty ||
        (phone ?? '').trim().isEmpty ||
        (password ?? '').isEmpty) {
      return null;
    }

    final prefs = await _prefs();
    final createdAtMs = prefs.getInt(_pendingLocalRegistrationCreatedAtMsKey);
    final regionIdText = await _secureStorage.read(
      key: _pendingLocalRegistrationRegionIdKey,
    );
    return PendingLocalRegistration(
      name: name!.trim(),
      phone: phone!.trim(),
      password: password!,
      email: (await _secureStorage.read(
        key: _pendingLocalRegistrationEmailKey,
      ))?.trim(),
      regionId: int.tryParse((regionIdText ?? '').trim()),
      createdAt: createdAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    );
  }

  static Future<bool> hasPendingLocalRegistration() async {
    return await getPendingLocalRegistration() != null;
  }

  static Future<void> clearPendingLocalRegistration() async {
    await _secureStorage.delete(key: _pendingLocalRegistrationNameKey);
    await _secureStorage.delete(key: _pendingLocalRegistrationPhoneKey);
    await _secureStorage.delete(key: _pendingLocalRegistrationPasswordKey);
    await _secureStorage.delete(key: _pendingLocalRegistrationEmailKey);
    await _secureStorage.delete(key: _pendingLocalRegistrationRegionIdKey);
    final prefs = await _prefs();
    await prefs.remove(_pendingLocalRegistrationCreatedAtMsKey);
  }

  static Future<void> saveUserName(String name) async {
    final prefs = await _prefs();
    await prefs.setString(_userNameKey, name);
  }

  static Future<String?> getUserName() async {
    final prefs = await _prefs();
    return prefs.getString(_userNameKey);
  }

  static Future<void> clearUserName() async {
    final prefs = await _prefs();
    await prefs.remove(_userNameKey);
  }

  static Future<void> saveUserRole(String roleName) async {
    final prefs = await _prefs();
    await prefs.setString(_userRoleKey, roleName);
  }

  static Future<String?> getUserRole() async {
    final prefs = await _prefs();
    return prefs.getString(_userRoleKey);
  }

  static Future<void> clearUserRole() async {
    final prefs = await _prefs();
    await prefs.remove(_userRoleKey);
  }

  static Future<void> saveApiBaseUrl(String baseUrl) async {
    final prefs = await _prefs();
    await prefs.setString(_apiBaseUrlKey, baseUrl);
  }

  static Future<String?> getApiBaseUrl() async {
    final prefs = await _prefs();
    return prefs.getString(_apiBaseUrlKey);
  }

  static Future<void> clearSession() async {
    final prefs = await _prefs();
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (_) {}
    try {
      await _secureStorage.delete(key: _refreshTokenKey);
    } catch (_) {}
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userRoleKey);
    await prefs.remove(_offlineSessionActiveKey);
  }

  static Future<void> clearActiveSessionPreservingOfflineProof() async {
    await clearSession();
  }

  static Future<void> clearAuthAndOffline() async {
    await clearSession();
    await clearOfflineLoginProof();
    await clearPendingLocalRegistration();
  }
}

class PendingLocalRegistration {
  final String name;
  final String phone;
  final String password;
  final String? email;
  final int? regionId;
  final DateTime? createdAt;

  const PendingLocalRegistration({
    required this.name,
    required this.phone,
    required this.password,
    required this.email,
    required this.regionId,
    required this.createdAt,
  });
}
