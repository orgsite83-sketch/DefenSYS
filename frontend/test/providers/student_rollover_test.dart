import 'dart:convert';
import 'dart:async';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/student_academic_records_provider.dart';
import 'package:defensys/utils/import/student_rollover_action.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  test(
    'enrollment defaults to the current term and history is explicit',
    () async {
      final contexts = <String?>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          contexts.add(request.url.queryParameters['term_context']);
          return http.Response(
            '{"records":[],"active_semester":{"id":2},'
            '"counts":{"enrollment":{"semester_id":2,"enrolled":0}}}',
            200,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(studentAcademicRecordsProvider.notifier);
      await notifier.fetchRecords();
      await notifier.selectTermContext('history');
      expect(contexts, ['current', 'history']);
      expect(
        (container.read(studentAcademicRecordsProvider).counts['enrollment']
            as Map)['enrolled'],
        0,
      );
    },
  );

  test(
    'a late current-term response cannot replace the selected history',
    () async {
      final firstResponse = Completer<http.Response>();
      final firstStarted = Completer<void>();
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.queryParameters['term_context'] == 'current') {
            firstStarted.complete();
            return firstResponse.future;
          }
          return http.Response(
            '{"records":[{"id":99}],"active_semester":{"id":2}}',
            200,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(studentAcademicRecordsProvider.notifier);
      final stale = notifier.fetchRecords();
      await firstStarted.future;
      await notifier.selectTermContext('history');
      firstResponse.complete(
        http.Response('{"records":[{"id":1}],"active_semester":{"id":1}}', 200),
      );
      await stale;
      final state = container.read(studentAcademicRecordsProvider);
      expect(state.termContext, 'history');
      expect(state.records.single['id'], 99);
      expect(state.activeSemester?['id'], 2);
    },
  );

  const row = <String, dynamic>{
    'record': {
      'id': 11,
      'student_username': '2026-001',
      'year_level': '1st Year',
      'section': 'BSIT-1A',
    },
    'promote_result': {
      'year_level': '2nd Year',
      'section': 'BSIT-2B',
      'target_semester_id': 22,
    },
    'retain_result': {
      'year_level': '1st Year',
      'section': 'BSIT-1A',
      'target_semester_id': 22,
    },
  };

  for (final action in ['retain', 'promote']) {
    test(
      '$action submits its reviewed standing and semester after the active term changes',
      () async {
        Map<String, dynamic>? submitted;
        setApiHttpClientForTesting(
          MockClient((request) async {
            if (request.url.path.endsWith('/rollover-preview/')) {
              return http.Response(
                jsonEncode({
                  'active_semester': {'id': 21},
                  'rows': [row],
                }),
                200,
              );
            }
            if (request.url.path.endsWith('/rollover/')) {
              submitted = Map<String, dynamic>.from(jsonDecode(request.body));
              return http.Response(
                '{"created_count":1,"skipped_count":0}',
                201,
              );
            }
            // A refresh may expose a different active semester; the reviewed target
            // belongs to the action and must survive that change.
            return http.Response(
              '{"records":[],"active_semester":{"id":23}}',
              200,
            );
          }),
        );
        final container = ProviderContainer(overrides: authTestOverrides());
        addTearDown(container.dispose);
        final notifier = container.read(
          studentAcademicRecordsProvider.notifier,
        );
        expect(await notifier.fetchRolloverPreview(), isTrue);
        final reviewed = container
            .read(studentAcademicRecordsProvider)
            .rolloverRows
            .single;
        await notifier.fetchRecords();
        expect(
          container.read(studentAcademicRecordsProvider).activeSemester?['id'],
          23,
        );
        expect(
          await notifier.confirmRollover([
            buildStudentRolloverAction(reviewed, action),
          ]),
          isTrue,
        );
        final saved = (submitted!['actions'] as List).single as Map;
        expect(saved['target_semester_id'], 22);
        expect(saved['action'], action);
        expect(
          saved['year_level'],
          action == 'retain' ? '1st Year' : '2nd Year',
        );
        expect(saved['section'], action == 'retain' ? 'BSIT-1A' : 'BSIT-2B');
      },
    );
  }

  test(
    'replayed rollover with existing enrollments completes successfully',
    () async {
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.path.endsWith('/rollover/')) {
            return http.Response(
              '{"created_count":0,"skipped_count":1,"skipped":[{"reason":"duplicate"}]}',
              200,
            );
          }
          return http.Response('{"records":[]}', 200);
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(studentAcademicRecordsProvider.notifier);
      expect(
        await notifier.confirmRollover([
          buildStudentRolloverAction(row, 'promote'),
        ]),
        isTrue,
      );
      expect(container.read(studentAcademicRecordsProvider).error, isNull);
      expect(
        container.read(studentAcademicRecordsProvider).message,
        contains('0 created, 1 skipped'),
      );
    },
  );

  test(
    'rejected rollover preserves the reviewed rows for correction',
    () async {
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.path.endsWith('/rollover-preview/')) {
            return http.Response(
              jsonEncode({
                'rows': [row],
              }),
              200,
            );
          }
          return http.Response(
            '{"detail":"Target semester is not configured."}',
            400,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(studentAcademicRecordsProvider.notifier);
      await notifier.fetchRolloverPreview();
      expect(
        await notifier.confirmRollover([
          buildStudentRolloverAction(row, 'promote'),
        ]),
        isFalse,
      );
      final state = container.read(studentAcademicRecordsProvider);
      expect(state.rolloverRows, hasLength(1));
      expect(state.error, 'Target semester is not configured.');
    },
  );
}
