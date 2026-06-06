import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_farm/offline/local_cache_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('write and read map payload', () async {
    await LocalCacheStore.instance.write(
      'profile_cache_v1',
      <String, Object?>{'name': 'Admas', 'role_name': 'farmer'},
    );

    final entry = await LocalCacheStore.instance.read('profile_cache_v1');
    final map = await LocalCacheStore.instance.readMap('profile_cache_v1');
    final updatedAt = await LocalCacheStore.instance.readUpdatedAt('profile_cache_v1');

    expect(entry, isNotNull);
    expect(map?['name'], 'Admas');
    expect(map?['role_name'], 'farmer');
    expect(updatedAt, isNotNull);
  });

  test('write and read list payload', () async {
    await LocalCacheStore.instance.write(
      'weather_records_cache_v1',
      <Map<String, Object?>>[
        <String, Object?>{'temperature': 24.5},
        <String, Object?>{'temperature': 25.0},
      ],
    );

    final list = await LocalCacheStore.instance.readList('weather_records_cache_v1');

    expect(list, isNotNull);
    expect(list, hasLength(2));
    expect((list!.first as Map)['temperature'], 24.5);
  });

  test('invalid cache envelope returns null instead of throwing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'broken_cache': 'not-json',
    });

    final entry = await LocalCacheStore.instance.read('broken_cache');
    final map = await LocalCacheStore.instance.readMap('broken_cache');
    final list = await LocalCacheStore.instance.readList('broken_cache');

    expect(entry, isNull);
    expect(map, isNull);
    expect(list, isNull);
  });
}
