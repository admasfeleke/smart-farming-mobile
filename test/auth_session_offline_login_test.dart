import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_farm/auth_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('online login bootstrap caches proof and offline unlock succeeds', () async {
    await AuthSession.saveToken('token-12345678901234567890');
    await AuthSession.saveOfflineLoginProof(
      phone: '0911000001',
      password: 'password123',
      ttl: const Duration(hours: 1),
    );

    expect(await AuthSession.hasValidOfflineLoginProof(), isTrue);

    final unlocked = await AuthSession.tryOfflineUnlock(
      phone: '+251 911 000 001',
      password: 'password123',
    );

    expect(unlocked, isTrue);
    expect(await AuthSession.isOfflineModeActive(), isTrue);
  });

  test('offline unlock fails with wrong password', () async {
    await AuthSession.saveToken('token-12345678901234567890');
    await AuthSession.saveOfflineLoginProof(
      phone: '0911000002',
      password: 'password123',
      ttl: const Duration(hours: 1),
    );

    final unlocked = await AuthSession.tryOfflineUnlock(
      phone: '0911000002',
      password: 'wrong-password',
    );

    expect(unlocked, isFalse);
    expect(await AuthSession.isOfflineModeActive(), isFalse);
  });

  test('offline unlock lockout activates after repeated failures', () async {
    await AuthSession.saveToken('token-12345678901234567890');
    await AuthSession.saveOfflineLoginProof(
      phone: '0911000005',
      password: 'password123',
      ttl: const Duration(hours: 1),
    );

    for (var i = 0; i < 5; i++) {
      final unlocked = await AuthSession.tryOfflineUnlock(
        phone: '0911000005',
        password: 'wrong-password',
      );
      expect(unlocked, isFalse);
    }

    expect(await AuthSession.offlineUnlockBlockedUntil(), isNotNull);
    expect(
      await AuthSession.tryOfflineUnlock(
        phone: '0911000005',
        password: 'password123',
      ),
      isFalse,
    );
  });

  test('offline proof expires by ttl', () async {
    await AuthSession.saveToken('token-12345678901234567890');
    await AuthSession.saveOfflineLoginProof(
      phone: '0911000003',
      password: 'password123',
      ttl: const Duration(milliseconds: 5),
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(await AuthSession.hasValidOfflineLoginProof(), isFalse);
    expect(
      await AuthSession.tryOfflineUnlock(
        phone: '0911000003',
        password: 'password123',
      ),
      isFalse,
    );
  });

  test('clearAuthAndOffline clears token and cached verifier', () async {
    await AuthSession.saveToken('token-12345678901234567890');
    await AuthSession.saveOfflineLoginProof(
      phone: '0911000004',
      password: 'password123',
      ttl: const Duration(hours: 1),
    );

    await AuthSession.clearAuthAndOffline();

    expect(await AuthSession.getToken(), isNull);
    expect(await AuthSession.hasValidOfflineLoginProof(), isFalse);
    expect(
      await AuthSession.tryOfflineUnlock(
        phone: '0911000004',
        password: 'password123',
      ),
      isFalse,
    );
  });
}
