import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/api_http.dart';
import 'package:user/services/capstone_deliverables_provider.dart';

import '../helpers/mock_http_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'jwt_token': 'test-token'});
    installDefaultMockHttp();
  });

  tearDown(() {
    resetApiHttpClientForTesting();
  });

  test('fetchDeliverables loads teams and stages', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();

    final state = container.read(capstoneDeliverablesProvider);
    expect(state.isLoading, isFalse);
    expect(state.teams, hasLength(1));
    expect(state.stageOptions, contains('Concept Proposal'));
  });
}
