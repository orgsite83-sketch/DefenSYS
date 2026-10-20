import 'dart:convert';

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
