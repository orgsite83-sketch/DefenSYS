import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  for (final indexed in [false, true]) {
    test(
      'nested ${indexed ? 'indexed' : 'list'} criterion errors identify the section and field',
      () async {
        final errors = {
          'name': ['Use 1000 characters or fewer.'],
        };
        setApiHttpClientForTesting(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'criteria': indexed ? {'2': errors} : [{}, {}, errors],
              }),
              400,
            ),
          ),
        );
        final container = ProviderContainer(overrides: authTestOverrides());
        addTearDown(container.dispose);
        final saved = await container
            .read(rubricEngineProvider.notifier)
            .updateRubric(1, {
              'criteria': [
                {'section': 'Oral', 'name': 'Presentation'},
                {'section': 'Manuscript', 'name': 'Initial pages'},
                {'section': 'Manuscript', 'name': 'Chapter 1'},
              ],
            });
        expect(saved, isFalse);
        final state = container.read(rubricEngineProvider);
        expect(state.criterionErrors, {
          2: {'name': 'Use 1000 characters or fewer.'},
        });
        expect(
          state.error,
          'Section "Manuscript", criterion 2 — name: Use 1000 characters or fewer.',
        );
      },
    );
  }

  test(
    'rubric-wide validation remains readable and has no criterion field errors',
    () async {
      setApiHttpClientForTesting(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'criteria': ['Criterion weights must total 100%.'],
            }),
            400,
          ),
        ),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      expect(
        await container.read(rubricEngineProvider.notifier).addRubric({}),
        isFalse,
      );
      expect(container.read(rubricEngineProvider).criterionErrors, isEmpty);
      expect(
        container.read(rubricEngineProvider).error,
        'criteria: Criterion weights must total 100%.',
      );
    },
  );
}
