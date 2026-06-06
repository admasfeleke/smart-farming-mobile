import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_farm/api_client.dart';
import 'package:smart_farm/auth_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('getSoilHealthPage accepts backend pagination payloads', () async {
    late HttpServer server;
    String? requestMethod;
    Uri? requestUri;
    String? authHeader;

    server = await _startServer((request) async {
      requestMethod = request.method;
      requestUri = request.uri;
      authHeader = request.headers.value(HttpHeaders.authorizationHeader);

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'data': <Map<String, Object?>>[
            <String, Object?>{'id': 1, 'soil_type': 'loam'},
          ],
          'pagination': <String, Object?>{
            'current_page': 1,
            'last_page': 3,
            'per_page': 50,
            'total': 101,
          },
        }),
      );
      await request.response.close();
    });

    try {
      await AuthSession.saveToken('token-12345678901234567890');
      await AuthSession.saveApiBaseUrl('http://127.0.0.1:${server.port}');

      final result = await ApiClient.getSoilHealthPage(page: 1, perPage: 50);

      expect(requestMethod, 'GET');
      expect(requestUri?.path, '/api/v1/soil-health');
      expect(requestUri?.queryParameters['page'], '1');
      expect(requestUri?.queryParameters['per_page'], '50');
      expect(authHeader, 'Bearer token-12345678901234567890');
      expect(result.items, hasLength(1));
      expect(result.items.single['id'], 1);
      expect(result.pagination.currentPage, 1);
      expect(result.pagination.lastPage, 3);
      expect(result.pagination.total, 101);
      expect(result.pagination.hasMore, isTrue);
    } finally {
      await server.close(force: true);
    }
  });

  test('updateSoilHealth uses multipart POST with method override when evidence is attached', () async {
    late HttpServer server;
    String? requestMethod;
    Uri? requestUri;
    String? requestBody;

    final tempDir = await Directory.systemTemp.createTemp('soil-health-api-client');
    final evidence = File('${tempDir.path}\\evidence.jpg');
    await evidence.writeAsString('fake-jpg-body');

    server = await _startServer((request) async {
      requestMethod = request.method;
      requestUri = request.uri;
      requestBody = await utf8.decoder.bind(request).join();

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'id': 99,
          'review_status': 'validated',
        }),
      );
      await request.response.close();
    });

    try {
      await AuthSession.saveToken('token-12345678901234567890');
      await AuthSession.saveApiBaseUrl('http://127.0.0.1:${server.port}');

      final result = await ApiClient.updateSoilHealth(
        soilHealthId: 99,
        phLevel: 6.4,
        reviewStatus: 'validated',
        evidencePath: evidence.path,
      );

      expect(requestMethod, 'POST');
      expect(requestUri?.path, '/api/v1/soil-health/99');
      expect(requestBody, contains('name="_method"'));
      expect(requestBody, contains('\r\nPUT\r\n'));
      expect(requestBody, contains('name="ph_level"'));
      expect(requestBody, contains('name="review_status"'));
      expect(result['id'], 99);
      expect(result['review_status'], 'validated');
    } finally {
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(() async {
    await for (final request in server) {
      await handler(request);
    }
  }());
  return server;
}
