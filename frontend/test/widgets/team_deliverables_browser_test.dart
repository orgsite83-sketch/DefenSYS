import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/team_detail/team_progress_tabs.dart';
import 'package:defensys/screens/web/shared/project_archive/components/archive_browser_cards.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/team_detail_provider.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import '../helpers/pump_app.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/mock_http_setup.dart';

Widget _browser({
  required List<Map<String, dynamic>> items,
  bool pit = false,
  List<Map<String, dynamic>> system = const [],
  List<Map<String, dynamic>> documents = const [],
  List<Map<String, dynamic>> reports = const [],
  ValueChanged<int>? onDownload,
}) => DefensysShadcnScope(
  child: TeamDeliverablesTab(
    teamId: 7,
    state: TeamDetailState(
      team: {'level': pit ? '1st Year PIT' : '3rd Year Capstone'},
      documents: documents,
      weeklyReports: reports,
      deliverableTeam: {
        'id': 7,
        'semester_id': 4,
        'project_version': 2,
        'stages': [
          {'stage_label': 'Concept', 'deliverables': items, 'system': system},
        ],
      },
    ),
    stageLabel: 'Concept',
    stageOptions: const ['Concept'],
    onStageChanged: (_) {},
    onRetry: () {},
    onDownloadDocument: onDownload ?? (_) {},
    onViewReport: (_) {},
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installDefaultMockHttp();
  });
  tearDown(resetApiHttpClientForTesting);

  testWidgets(
    'weekly files and history stay read-only even when the server allows reviews',
    (tester) async {
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/versions/')) {
            return http.Response(
              jsonEncode({
                'versions': [
                  {
                    'id': 10,
                    'revision': 1,
                    'file_name': 'Week_1_original.pdf',
                    'file_url': '/weekly/10.pdf',
                    'status': 'rejected',
                  },
                  {
                    'id': 11,
                    'revision': 2,
                    'file_name': 'Week_1_signed.pdf',
                    'file_url': '/weekly/11.pdf',
                    'status': 'pending',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'weeks': [
                {
                  'week_number': 1,
                  'required': true,
                  'status': 'pending',
                  'can_review': true,
                  'can_upload': true,
                  'history_url': '/api/teams/weekly-progress/77/versions/',
                  'file': {
                    'id': 11,
                    'file_name': 'Week_1_signed.pdf',
                    'file_url': '/weekly/11.pdf',
                    'status': 'pending',
                  },
                },
                {
                  'week_number': 2,
                  'required': true,
                  'status': 'missing',
                  'timing': 'upcoming',
                  'file': null,
                },
              ],
            }),
            200,
          );
        }),
      );
      await pumpDefensysWidget(
        tester,
        _browser(
          items: const [
            {
              'id': 'weekly',
              'source': 'weekly_reports',
              'label': 'Weekly reports',
              'required': true,
              'weekly_summary': {'uploaded': 1, 'required': 2, 'missing': 1},
            },
          ],
        ),
        overrides: authTestOverrides(),
      );
      await tester.tap(find.text('Weekly reports').first);
      await tester.pumpAndSettle();
      expect(requests.first.url.queryParameters, {
        'team_id': '7',
        'stage_label': 'Concept',
        'semester_id': '4',
        'project_version': '2',
      });
      expect(find.byType(ArchiveFileCard), findsNWidgets(2));
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Request correction'), findsNothing);
      expect(find.text('Upload'), findsNothing);
      final submittedCard = find.ancestor(
        of: find.text('Week_1_signed.pdf'),
        matching: find.byType(ArchiveFileCard),
      );
      await tester.tap(
        find.descendant(
          of: submittedCard,
          matching: find.bySemanticsLabel('File actions'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Version history'));
      await tester.pumpAndSettle();
      expect(find.text('Week_1_original.pdf'), findsOneWidget);
      expect(find.text('Week_1_signed.pdf'), findsOneWidget);
      expect(requests.last.url.hasScheme, isTrue);
      expect(requests.last.url.path, '/api/teams/weekly-progress/77/versions/');
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'grouped submissions retain configured missing slots and earlier versions',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        _browser(
          items: const [
            {
              'id': 'papers',
              'label': 'Concept papers',
              'required': true,
              'type': 'pre',
              'file_policy': {'mode': 'named'},
              'document_slots': [
                {'key': 'a', 'label': 'Concept A'},
                {'key': 'b', 'label': 'Concept B'},
              ],
              'submission': {
                'files': [
                  {
                    'id': 1,
                    'slot_key': 'a',
                    'file_name': 'Concept_A.pdf',
                    'file_url': '/a.pdf',
                    'status': 'pending',
                  },
                ],
                'file_history': [
                  {
                    'id': 9,
                    'is_current': false,
                    'revision': 1,
                    'file_name': 'Concept_A_old.pdf',
                    'file_url': '/old.pdf',
                  },
                ],
              },
            },
          ],
        ),
        overrides: authTestOverrides(),
      );
      await tester.tap(find.text('Concept papers'));
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveFileCard), findsNWidgets(2));
      expect(find.text('Concept B'), findsOneWidget);
      expect(find.text('Not uploaded'), findsWidgets);
      await tester.tap(find.text('Previous versions'));
      await tester.pumpAndSettle();
      expect(find.text('Concept_A_old.pdf'), findsOneWidget);
      expect(find.text('Concept_A.pdf'), findsNothing);
      expect(find.text('Accept'), findsNothing);
    },
  );

  testWidgets(
    'PIT folders exclude weekly reports, deduplicate system records, and download legacy files',
    (tester) async {
      int? downloaded;
      await pumpDefensysWidget(
        tester,
        _browser(
          pit: true,
          items: const [
            {
              'id': 'weekly',
              'source': 'weekly_reports',
              'label': 'Weekly reports',
            },
            {'id': 'paper', 'label': 'Project paper', 'required': true},
            {
              'id': 'minutes',
              'source': 'defense_minutes',
              'label': 'Signed minutes',
            },
          ],
          system: const [
            {
              'id': 'minutes',
              'source': 'defense_minutes',
              'label': 'Signed minutes',
              'status_label': 'Awaiting documenter',
            },
          ],
          documents: const [
            {
              'id': 88,
              'file_name': 'Earlier_document.pdf',
              'uploaded_by_name': 'Carlos Reyes',
            },
          ],
          onDownload: (id) => downloaded = id,
        ),
        overrides: authTestOverrides(),
      );
      expect(find.byType(ArchiveFolderCard), findsNWidgets(3));
      expect(find.text('Weekly reports'), findsNothing);
      await tester.enterText(find.byType(EditableText), 'project');
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveFolderCard), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '');
      await tester.tap(find.bySemanticsLabel('List view'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ArchiveFolderCard>(find.byType(ArchiveFolderCard))
            .every((card) => card.list),
        isTrue,
      );
      await tester.tap(find.text('Legacy documents'));
      await tester.pumpAndSettle();
      expect(find.text('Earlier_document.pdf'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('File actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(downloaded, 88);
    },
  );

  testWidgets('structured legacy reports remain accessible without a PDF', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      _browser(
        items: const [],
        reports: const [
          {
            'id': 19,
            'week_number': 5,
            'student_name': 'Carlos Reyes',
            'report_date': '2026-11-02',
            'accomplishments': ['Built a working prototype'],
            'issues': ['Testing the offline flow'],
          },
        ],
      ),
      overrides: authTestOverrides(),
    );
    await tester.tap(find.text('Legacy reports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week 5 report'));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsOneWidget);
    expect(find.textContaining('Built a working prototype'), findsOneWidget);
    expect(find.textContaining('Testing the offline flow'), findsOneWidget);
  });
}
