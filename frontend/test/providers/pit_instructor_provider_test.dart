import 'dart:async';
import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/pit_instructor_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  for (final restore in [false, true]) {
    for (final refreshStatus in [200, 503]) {
      test(
        '${restore ? 'restoring' : 'assigning'} an instructor releases actions after a $refreshStatus refresh',
        () async {
          final refresh = Completer<http.Response>();
          final requests = <http.Request>[];
          setApiHttpClientForTesting(
            MockClient((request) async {
              requests.add(request);
              if (request.method == 'GET') return refresh.future;
              return http.Response('{}', restore ? 200 : 201);
            }),
          );
          final container = ProviderContainer(overrides: authTestOverrides());
          addTearDown(container.dispose);
          final notifier = container.read(pitInstructorProvider.notifier);
          final save = restore
              ? notifier.setAssignmentActive(7, true)
              : notifier.assignInstructor(facultyId: 10, section: 'BSIT-1A');

          await Future<void>.delayed(Duration.zero);
          expect(container.read(pitInstructorProvider).isSaving, isTrue);
          expect(requests.map((request) => request.method), [
            restore ? 'PATCH' : 'POST',
            'GET',
          ]);
          expect(
            jsonDecode(requests.first.body),
            restore
                ? {'is_active': true}
                : {'faculty_id': 10, 'section': 'BSIT-1A'},
          );

          refresh.complete(
            http.Response(
              refreshStatus == 200
                  ? '{"assignments":[{"id":7,"is_active":true}]}'
                  : '{"detail":"Assignments temporarily unavailable"}',
              refreshStatus,
            ),
          );
          expect(await save, isTrue);
          final state = container.read(pitInstructorProvider);
          expect(state.isSaving, isFalse);
          expect(state.isLoading, isFalse);
          expect(
            state.message,
            restore ? 'Instructor restored.' : 'Instructor assigned.',
          );
          if (refreshStatus == 200) {
            expect(state.assignments.single['is_active'], isTrue);
          } else {
            expect(state.error, 'Assignments temporarily unavailable');
          }

          // A second operation must also finish with the actions enabled.
          expect(
            await notifier.assignInstructor(facultyId: 11, section: 'BSIT-1B'),
            isTrue,
          );
          expect(container.read(pitInstructorProvider).isSaving, isFalse);
        },
      );
    }
  }

  test(
    'a rejected restore releases actions and exposes the API error',
    () async {
      setApiHttpClientForTesting(
        MockClient(
          (_) async => http.Response(
            '{"detail":"This assignment is outside your PIT scope."}',
            403,
          ),
        ),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      expect(
        await container
            .read(pitInstructorProvider.notifier)
            .setAssignmentActive(7, true),
        isFalse,
      );
      expect(container.read(pitInstructorProvider).isSaving, isFalse);
      expect(
        container.read(pitInstructorProvider).error,
        'This assignment is outside your PIT scope.',
      );
    },
  );
}
