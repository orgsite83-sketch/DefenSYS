import 'dart:convert';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  Future<ProviderContainer> setup({
    required List<Map<String, dynamic>> patches,
    bool admin = true,
    bool denied = false,
  }) async {
    var eligible = false;
    Map<String, dynamic> person() => {
      'id': 11,
      'name': 'Lina Santos',
      'username': 'FAC-11',
      'is_panelist': eligible,
      'is_documenter': true,
    };
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.method == 'PATCH') {
          expect(request.url.path, '/api/users/11/');
          patches.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          if (denied) {
            return http.Response('{"detail":"Permission denied."}', 403);
          }
          eligible = patches.last['is_panelist'] as bool;
          return http.Response(jsonEncode({'user': person()}), 200);
        }
        if (request.url.path.endsWith('/generate-plan/')) {
          return http.Response(
            jsonEncode({
              'slots': [
                {'team_id': 99},
              ],
              'faculty': [person()],
              'panelists': [if (eligible) person()],
              'can_approve_panelists': admin,
            }),
            200,
          );
        }
        if (request.url.path.contains('/defense/schedules')) {
          return http.Response(
            jsonEncode({
              'faculty': [person()],
              'panelists': [if (eligible) person()],
              'can_approve_panelists': admin,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/users')) {
          return http.Response(
            jsonEncode({
              'users': [person()],
              'counts': {'panelists': eligible ? 1 : 0},
            }),
            200,
          );
        }
        throw StateError('Unexpected ${request.method} ${request.url}');
      }),
    );
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(defenseSchedulerProvider.notifier);
    await notifier.fetchSchedules();
    expect(container.read(defenseSchedulerProvider).error, isNull);
    expect(container.read(defenseSchedulerProvider).canApprovePanelists, admin);
    await notifier.generatePlan({});
    return container;
  }

  test(
    'grant and revoke patch only the panelist duty and refresh RBAC without clearing a draft',
    () async {
      final patches = <Map<String, dynamic>>[];
      final container = await setup(patches: patches);
      final notifier = container.read(defenseSchedulerProvider.notifier);
      expect(await notifier.setPanelistEligibility(11, eligible: true), isTrue);
      expect(patches.single, {'is_panelist': true});
      expect(
        container.read(defenseSchedulerProvider).isEligiblePanelist(11),
        isTrue,
      );
      expect(container.read(userManagementProvider).counts['panelists'], 1);
      expect(
        await notifier.setPanelistEligibility(11, eligible: false),
        isTrue,
      );
      expect(patches.last, {'is_panelist': false});
      expect(
        container.read(defenseSchedulerProvider).isEligiblePanelist(11),
        isFalse,
      );
      expect(container.read(userManagementProvider).counts['panelists'], 0);
      expect(container.read(defenseSchedulerProvider).generatedSlots, [
        {'team_id': 99},
      ]);
    },
  );

  test('PIT leads cannot send a direct eligibility patch', () async {
    final patches = <Map<String, dynamic>>[];
    final container = await setup(patches: patches, admin: false);
    expect(
      await container
          .read(defenseSchedulerProvider.notifier)
          .setPanelistEligibility(11, eligible: true),
      isFalse,
    );
    expect(patches, isEmpty);
  });

  test('a rejected role change retains eligibility and the draft', () async {
    final patches = <Map<String, dynamic>>[];
    final container = await setup(patches: patches, denied: true);
    expect(
      await container
          .read(defenseSchedulerProvider.notifier)
          .setPanelistEligibility(11, eligible: true),
      isFalse,
    );
    expect(
      container.read(defenseSchedulerProvider).error,
      'Permission denied.',
    );
    expect(
      container.read(defenseSchedulerProvider).isEligiblePanelist(11),
      isFalse,
    );
    expect(container.read(defenseSchedulerProvider).generatedSlots, [
      {'team_id': 99},
    ]);
  });
}
