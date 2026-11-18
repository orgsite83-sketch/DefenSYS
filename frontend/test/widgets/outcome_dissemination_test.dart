import 'dart:async';

import 'package:defensys/screens/web/admin/grade_center/grade_masterlist.dart';
import 'package:defensys/screens/web/admin/grade_center/outcome_dissemination_dialog.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/grading/grade_masterlist_provider.dart';
import 'package:defensys/services/grading/outcome_dissemination_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Admin extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isRestoring: false, user: {'id': 1, 'role': 'admin'});
}

class _Api implements OutcomeDisseminationApi {
  final batches = <String>[];
  int previewCalls = 0, holdCalls = 0;
  bool timeoutOnce = false;
  List<int>? selected;

  @override
  AuthenticatedHttpClient get client =>
      throw StateError('This test uses the API boundary.');
  @override
  Future<Map<String, dynamic>> preview(
    Map<String, String> filters,
    List<int>? gradeIds,
  ) async {
    previewCalls++;
    selected = gradeIds;
    return {
      'review_token': 'fixed-reviewed-team-attempt',
      'team_count': 1,
      'student_count': 3,
      'excluded_count': 4,
      'selection_mode': gradeIds == null ? 'matching_ready' : 'selected',
      'context': {'assessment_label': 'Proposal defense'},
      'entries': [
        {
          'grade_id': 51,
          'metadata': {'version': 'v1', 'schedule_id': 12},
          'snapshot': {
            'team_id': 10,
            'team_name': 'Team Atlas',
            'attempt': 1,
            'schedule_id': 12,
            'verdict': 'approved',
            'approved_title': 'Campus platform',
            'verdict_remarks': 'Clarify the project scope.',
          },
        },
      ],
      'excluded': [],
    };
  }

  @override
  Future<Map<String, dynamic>> confirm(String token, String batchId) async {
    batches.add(batchId);
    if (timeoutOnce && batches.length == 1) {
      throw TimeoutException('Connection timed out; retry confirmation.');
    }
    return {'team_count': 1};
  }

  @override
  Future<Map<String, dynamic>> hold(
    int gradeId,
    Map<String, dynamic> metadata,
    bool held,
    String reason,
  ) async {
    holdCalls++;
    return {'status': held ? 'held' : 'ready'};
  }

  @override
  Future<Map<String, dynamic>> history(Map<String, String> filters) async => {
    'batches': [],
  };
}

Map<String, dynamic> _masterlist(String query) {
  final teams = Uri.splitQueryString(query)['entity'] == 'teams';
  return {
    'context': {
      'scope': 'capstone',
      'coverage': 'assessment',
      'assessment_id': 4,
      'semester_id': 7,
      'academic_period': '2026–2027 First semester',
      'assessment_label': 'Proposal defense',
    },
    'dissemination': {'can_manage': true, 'ready': 1, 'released': 0},
    'page': 1,
    'page_size': 25,
    'total': teams ? 1 : 2,
    'options': {
      'sections': [],
      'statuses': [],
      'sessions': [],
      'dissemination_statuses': [
        {'value': 'ready', 'label': 'Ready for release'},
      ],
    },
    'rows': List.generate(
      teams ? 1 : 2,
      (index) => {
        'id': teams ? 10 : index + 1,
        'student_id': teams ? null : index + 1,
        'name': teams ? 'Team Atlas' : 'Student ${index + 1}',
        'student_number': '2026-00${index + 1}',
        'section': 'BSIT 4A',
        'team_name': 'Team Atlas',
        'assessments': [
          {
            'grade_id': 51,
            'assessment_id': 4,
            'team': {
              'id': 10,
              'name': 'Team Atlas',
              'project_title': 'Campus platform',
            },
            'components': {},
            'final_grade': null,
            'evaluators': [],
            'status': 'pending',
            'status_label': 'Pending publication',
            'outcome': 'Approved',
            'missing_components': [],
            'dissemination': {
              'status': 'ready',
              'label': 'Ready for release',
              'can_release': true,
              'schedule_id': 12,
              'version': 'v1',
            },
          },
        ],
      },
    ),
  };
}

void main() {
  const filters = {
    'scope': 'capstone',
    'defense_stage_id': '4',
    'semester_id': '7',
  };

  testWidgets(
    'review retains the batch identity after a confirmation timeout',
    (tester) async {
      final api = _Api()..timeoutOnce = true;
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showOutcomeDisseminationDialog(context, filters: filters),
            child: const Text('Open review'),
          ),
        ),
        overrides: [outcomeDisseminationApiProvider.overrideWithValue(api)],
      );
      await tester.tap(find.text('Open review'));
      await tester.pumpAndSettle();
      expect(find.text('Disseminate 1 outcome?'), findsOneWidget);
      expect(
        find.textContaining('Later completions remain private'),
        findsOneWidget,
      );
      expect(api.batches, isEmpty);
      await tester.tap(find.text('Disseminate 1 outcome'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Connection timed out'), findsOneWidget);
      await tester.tap(find.text('Disseminate 1 outcome'));
      await tester.pumpAndSettle();
      expect(api.batches.length, 2);
      expect(api.batches[0], api.batches[1]);
      expect(api.previewCalls, 1);
      expect(find.text('Disseminate 1 outcome?'), findsNothing);
    },
  );

  testWidgets(
    'existing masterlist views retain grades and team selection scopes dissemination',
    (tester) async {
      final api = _Api();
      await pumpDefensysWidget(
        tester,
        const SingleChildScrollView(
          child: GradeMasterlist(
            groupKey: 'capstone|Proposal defense',
            scope: 'capstone',
            stageLabel: 'Proposal defense',
            initialSemesterId: 7,
            initialAssessmentId: 4,
          ),
        ),
        overrides: [
          authProvider.overrideWith(_Admin.new),
          outcomeDisseminationApiProvider.overrideWithValue(api),
          gradeMasterlistDataProvider.overrideWith(
            (ref, query) async => _masterlist(query),
          ),
        ],
      );
      expect(find.text('Student Grades'), findsOneWidget);
      expect(find.text('Team Grades'), findsOneWidget);
      expect(find.text('Individual final'), findsOneWidget);
      expect(find.text('Disseminate outcomes (1)'), findsOneWidget);
      await tester.tap(find.text('Team Grades'));
      await tester.pumpAndSettle();
      expect(find.text('Team final'), findsOneWidget);
      final checkbox = find.byType(ShadCheckbox).last;
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('Disseminate selected (1)'), findsOneWidget);
      await tester.tap(find.text('Disseminate selected (1)'));
      await tester.pumpAndSettle();
      expect(api.selected, [51]);
      expect(find.text('Selected teams only.'), findsOneWidget);
    },
  );

  testWidgets('removing a hold never confirms a release', (tester) async {
    final api = _Api();
    await pumpDefensysWidget(
      tester,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showOutcomeDisseminationDialog(
            context,
            filters: filters,
            statusCell: const {
              'grade_id': 51,
              'dissemination': {
                'status': 'held',
                'label': 'On hold',
                'version': 'v1',
                'schedule_id': 12,
                'reason': 'Awaiting administrative review',
              },
            },
          ),
          child: const Text('Review hold'),
        ),
      ),
      overrides: [outcomeDisseminationApiProvider.overrideWithValue(api)],
    );
    await tester.tap(find.text('Review hold'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove hold'));
    await tester.pumpAndSettle();
    expect(api.holdCalls, 1);
    expect(api.batches, isEmpty);
  });

  for (final width in [320.0, 390.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets('release review fits $width pixels dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts();
        await pumpDefensysWidget(
          tester,
          const OutcomeDisseminationDialog(filters: filters),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [
            outcomeDisseminationApiProvider.overrideWithValue(_Api()),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Disseminate 1 outcome'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(OutcomeDisseminationDialog),
          'outcome-dissemination/review-${width.toInt()}-$dark',
          viewport: true,
        );
      });
    }
  }
}
