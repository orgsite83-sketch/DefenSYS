import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/web/admin/team_detail/team_progress_tabs.dart';
import 'package:defensys/services/team_detail_provider.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/shadcn/defensys_breadcrumb.dart';
import 'package:defensys/screens/web/shared/project_archive/components/archive_browser_cards.dart';
import 'package:defensys/screens/web/shared/project_archive/dialogs/archive_file_details_dialog.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';
import '../helpers/mock_http_setup.dart';
import '../helpers/auth_test_overrides.dart';

const _event = <String, dynamic>{
  'id': 2,
  'event_name': 'System Concept Pitching',
  'display_semester': '1st Semester · 2026–2027',
  'year_level': '1st Year',
  'context': {'scheduling_status': 'scheduled'},
  'schedule': {
    'scheduled_date': '2026-11-02',
    'start_time': '13:00:00',
    'room': 'Room 101',
    'status': 'scheduled',
  },
};
const _weekly = <String, dynamic>{
  'id': 'WPR',
  'source': 'weekly_reports',
  'label': 'Weekly Accomplishment Reports',
  'type': 'pre',
  'required': true,
  'weekly_summary': {
    'required': 2,
    'uploaded': 1,
    'accepted': 0,
    'pending': 1,
    'missing': 1,
  },
};

Widget _eventTab({
  List<Map<String, dynamic>> grades = const [],
  String? error,
  VoidCallback? onFiles,
  ValueChanged<Map<String, dynamic>>? onGrade,
}) => DefensysShadcnScope(
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: PitEventProgressTab(
      state: TeamDetailState(
        team: const {'level': '1st Year PIT'},
        events: const [_event],
        grades: grades,
        gradesError: error,
      ),
      eventName: 'System Concept Pitching',
      onViewDeliverables: onFiles ?? () {},
      onViewEvaluation: onGrade ?? (_) {},
      onRetry: () {},
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installDefaultMockHttp();
  });
  tearDown(resetApiHttpClientForTesting);

  testWidgets('an assigned event remains visible before grades exist', (
    tester,
  ) async {
    var opened = false;
    await pumpDefensysWidget(tester, _eventTab(onFiles: () => opened = true));
    expect(find.text('Not evaluated'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.textContaining('Room 101'), findsOneWidget);
    expect(find.text('EVENT RESULTS'), findsOneWidget);
    expect(find.text('ACADEMIC PROGRESS'), findsNothing);
    expect(find.text('Weekly Reports'), findsNothing);
    await tester.tap(find.text('View deliverables'));
    expect(opened, isTrue);
  });

  testWidgets(
    'event results use the event ID and preserve provisional grades',
    (tester) async {
      Map<String, dynamic>? opened;
      await pumpDefensysWidget(
        tester,
        _eventTab(
          grades: const [
            {
              'id': 8,
              'pit_event_config_id': 2,
              'stage_label': 'Earlier event name',
              'final_grade': '86.50',
              'status': 'pending',
              'is_officially_complete': true,
              'panel_evaluators_required': 3,
              'panel_evaluators_submitted': 2,
            },
            {
              'id': 9,
              'pit_event_config_id': 5,
              'stage_label': 'System Concept Pitching',
              'final_grade': '99.00',
              'status': 'published',
            },
          ],
          onGrade: (grade) => opened = grade,
        ),
      );
      expect(find.text('86.50'), findsOneWidget);
      expect(find.text('99.00'), findsNothing);
      expect(find.text('Provisional'), findsOneWidget);
      expect(find.text('Finalized'), findsNothing);
      expect(find.text('Panel evaluations: 2/3'), findsOneWidget);
      await tester.ensureVisible(find.text('View evaluation details'));
      await tester.tap(find.text('View evaluation details'));
      expect(opened?['id'], 8);
    },
  );

  testWidgets('a grade failure is distinct from not evaluated', (tester) async {
    await pumpDefensysWidget(
      tester,
      _eventTab(error: 'Grades could not be loaded.'),
    );
    expect(find.text('Grades could not be loaded.'), findsOneWidget);
    expect(find.text('Not evaluated'), findsNothing);
    expect(find.text('Retry grades'), findsOneWidget);
  });

  testWidgets(
    'Capstone weekly details open inside Deliverables without admin review/upload actions',
    (tester) async {
      Uri? collectionRequest;
      setApiHttpClientForTesting(
        MockClient((request) async {
          collectionRequest = request.url;
          return http.Response(
            jsonEncode({
              ..._weekly,
              'weeks': [
                {
                  'week_number': 1,
                  'required': true,
                  'status': 'missing',
                  'can_upload': true,
                  'can_review': true,
                  'starts_on': '2026-11-01',
                  'ends_on': '2026-11-07',
                  'due_at': '2026-11-07T09:00:00Z',
                },
              ],
            }),
            200,
          );
        }),
      );
      await pumpDefensysWidget(
        tester,
        DefensysShadcnScope(
          child: TeamDeliverablesTab(
            teamId: 1,
            state: const TeamDetailState(
              team: {'level': '3rd Year Capstone'},
              deliverableTeam: {
                'id': 1,
                'semester_id': 4,
                'project_version': 2,
                'stages': [
                  {
                    'stage_label': 'Concept Proposal',
                    'deliverables': [_weekly],
                  },
                ],
              },
            ),
            stageLabel: 'Concept Proposal',
            stageOptions: const ['Concept Proposal'],
            onStageChanged: (_) {},
            onRetry: () {},
            onDownloadDocument: (_) {},
            onViewReport: (_) {},
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('0/1 accepted'), findsNothing);
      await tester.tap(find.text('Weekly Accomplishment Reports').first);
      await tester.pumpAndSettle();
      expect(collectionRequest?.path, contains('/weekly-progress/collection/'));
      expect(collectionRequest?.queryParameters['semester_id'], '4');
      expect(find.text('1 required week'), findsOneWidget);
      expect(find.byType(ArchiveFileCard), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Upload'), findsNothing);
      await tester.tap(
        find
            .descendant(
              of: find.byType(DefensysBreadcrumb),
              matching: find.text('Concept Proposal'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Weekly Accomplishment Reports'), findsOneWidget);
    },
  );

  for (final width in [390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('PIT event progress fits width=$width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts();
        await pumpDefensysWidget(
          tester,
          _eventTab(),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(PitEventProgressTab),
          'team-event-progress-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }

  for (final width in [390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Deliverables retains files and system records at width=$width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadPreviewFonts();
          await pumpDefensysWidget(
            tester,
            DefensysShadcnScope(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: TeamDeliverablesTab(
                  teamId: 1,
                  state: const TeamDetailState(
                    team: {'level': '1st Year PIT'},
                    deliverableTeam: {
                      'id': 1,
                      'stages': [
                        {
                          'stage_label': 'Concept Pitch',
                          'deliverables': [
                            {
                              'id': 'paper',
                              'label': 'Concept paper',
                              'type': 'pre',
                              'required': true,
                              'uploaded': true,
                              'submission': {
                                'file_name': 'Concept_Paper.pdf',
                                'status': 'pending',
                                'file_url': '/paper.pdf',
                                'uploaded_by_name': 'Carlos Reyes',
                              },
                            },
                          ],
                          'system': [
                            {
                              'source': 'defense_minutes',
                              'label': 'Signed minutes',
                              'status_label': 'Awaiting adviser signature',
                              'completed': false,
                            },
                          ],
                        },
                      ],
                    },
                  ),
                  stageLabel: 'Concept Pitch',
                  stageOptions: const ['Concept Pitch'],
                  onStageChanged: (_) {},
                  onRetry: () {},
                  onDownloadDocument: (_) {},
                  onViewReport: (_) {},
                ),
              ),
            ),
            overrides: authTestOverrides(),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          );
          expect(find.text('1/1 submitted'), findsNothing);
          expect(find.byType(ArchiveFolderCard), findsNWidgets(2));
          expect(find.text('0/1 accepted'), findsNothing);
          expect(find.text('Under Review'), findsNothing);
          expect(find.text('System records'), findsOneWidget);
          await tester.tap(find.text('System records'));
          await tester.pumpAndSettle();
          expect(find.text('Awaiting adviser signature'), findsOneWidget);
          await tester.tap(
            find
                .descendant(
                  of: find.byType(DefensysBreadcrumb),
                  matching: find.text('Concept Pitch'),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.text('Weekly Accomplishment Reports'), findsNothing);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(TeamDeliverablesTab),
            'team-deliverables-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.tap(find.text('Concept paper').first);
          await tester.pumpAndSettle();
          expect(find.text('Concept_Paper.pdf'), findsWidgets);
          expect(find.byType(ArchiveFileCard), findsOneWidget);
          await capturePreview(
            tester,
            find.byType(TeamDeliverablesTab),
            'team-deliverables-archive-files-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.tap(find.text('Concept_Paper.pdf').first);
          await tester.pumpAndSettle();
          expect(find.byType(ArchiveFileDetailsDialog), findsOneWidget);
          expect(
            tester
                .widget<ArchiveFileDetailsDialog>(
                  find.byType(ArchiveFileDetailsDialog),
                )
                .archiveContext,
            isFalse,
          );
          expect(
            find.text('Registered in the institutional archive system.'),
            findsNothing,
          );
          await capturePreview(
            tester,
            find.byType(ArchiveFileDetailsDialog),
            'team-deliverables-archive-details-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          expect(
            tester
                .widget<ArchiveFileDetailsDialog>(
                  find.byType(ArchiveFileDetailsDialog),
                )
                .onOverrideStatus,
            isNull,
          );
          expect(find.text('Upload'), findsNothing);
          expect(find.text('Accept'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
