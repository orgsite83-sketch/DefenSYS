import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/api_http.dart';
import 'package:user/services/authenticated_client.dart';
import 'package:user/services/session_expired.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    resetApiHttpClientForTesting();
  });

  test('401 after failed refresh throws SessionExpiredException', () async {
    SharedPreferences.setMockInitialValues({});
    var refreshCalls = 0;

    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('token/refresh/')) {
          refreshCalls++;
          return http.Response('{"detail":"invalid"}', 401);
        }
        if (request.url.path.endsWith('login/')) {
          return http.Response(
            '{"access":"a","refresh":"r","user":{"id":1,"role":"admin"}}',
            200,
          );
        }
        return http.Response('', 401);
      }),
    );

    final container = ProviderContainer(
      overrides: authTestOverrides(),
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(authenticatedHttpClientProvider).get(
            Uri.parse('http://example.com/api/dashboards/admin/'),
          ),
      throwsA(isA<SessionExpiredException>()),
    );
  });
}
