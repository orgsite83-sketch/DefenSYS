import 'package:defensys/widgets/defense/defense_stages_map.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/app/student/section_integration_tab.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _PM extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 1, 'role': 'student'},
  );
}

class _Teams extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState();
  @override
  Future<void> fetchTeams({
    String? historyIntake,
    String? historyPhase,
    String? historyStage,
    String? workspace,
    String? search,
    String? level,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? eventName,
    bool clearEventName = false,
    bool clearYearLevel = false,
    String? successMessage,
  }) async {}
}

class _Picker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(
      name: 'system-a.pdf',
      size: 18,
      bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 system a')),
    ),
  ]);
}

Map<String, dynamic> _preview() => {
  'id': null,
  'imported': true,
  'team_id': 5,
  'section': 'BSIT-3A',
  'stage_label': 'Concept Proposal',
  'round': 1,
  'review_token': 'import-version',
  'project_manager_id': 1,
  'project_manager_name': 'Gabriel Navarro',
  'reviewer_name': 'Eduardo Padilla, Grace Hopper',
  'can_edit_names': true,
  'selected_key': '',
  'systems': [
    for (var i = 1; i <= 3; i++)
      {
        'key': 'c$i',
        'title': i == 1
            ? 'Smart Agro-Industrial IoT & Sustainable Supply Platform'
            : '',
        'confirmed': false,
        'can_upload': i == 1,
        'papers': [],
      },
  ],
  'teams': [
    {
      'id': 5,
      'name': 'Team AgriPulse',
      'leader_id': 1,
      'leader_name': 'Gabriel Navarro',
      'members': [
        {'id': 1, 'name': 'Gabriel Navarro', 'is_leader': true},
        {'id': 2, 'name': 'Maya Santos', 'is_leader': false},
        {'id': 3, 'name': 'Rafael Lim', 'is_leader': false},
      ],
      'concepts': [
        for (var i = 1; i <= 3; i++)
          {'key': 'c$i', 'title': i == 1 ? 'Imported soil sensor module' : ''},
      ],
    },
    {
      'id': 6,
      'name': 'Team ClimateNode',
      'leader_id': 4,
      'leader_name': 'Joaquin Panganiban',
      'members': [
        {'id': 4, 'name': 'Joaquin Panganiban', 'is_leader': true},
        {'id': 5, 'name': 'Sofia Ramos', 'is_leader': false},
      ],
      'concepts': [
        {'key': 'c1', 'title': 'Greenhouse climate telemetry module'},
      ],
    },
  ],
};

Future<void> _pump(
  WidgetTester tester, {
  bool dark = false,
  Map<String, dynamic>? studentData,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  await pumpDefensysWidget(
    tester,
    SectionIntegrationTab(
      studentData:
          studentData ??
          const {
            // The project response establishes the role, even when this cached flag is missing.
            'student': {'id': 1, 'is_project_manager': false},
            'team': {'id': 5, 'section': 'BSIT-3A'},
          },
    ),
    overrides: [
      authProvider.overrideWith(_PM.new),
      studentTeamsProvider.overrideWith(_Teams.new),
    ],
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
  );
}

Map<String, dynamic> _selectedProject() {
  final project = _preview();
  final systems = [
    for (var i = 1; i <= 3; i++)
      {
        'key': 'c$i',
        'title': i == 1
            ? 'HABI: Artisan Heritage & Craft Exchange Platform'
            : 'Earlier system proposal $i',
        'title_review': {
          'state': 'accepted',
          'status_label': 'Title accepted',
          'blocker':
              'This scheduled, decided or historical proposal is read-only.',
        },
      },
  ];
  final group = {
    'team_id': 5,
    'scope': 'capstone',
    'context_id': 7,
    'identity': 'section-7-concept-proposal',
    'section': 'BSIT-3A',
    'stage_label': 'Concept Proposal',
    'selected_key': 'c1',
    'systems': systems,
    'requirements': [
      {
        'deliverable_id': 'PAPERS',
        'label': 'Concept Papers',
        'file_format': 'pdf',
        'deliverable_type': 'pre',
        'required': true,
        'status': 'accepted',
        'file_policy': {'mode': 'concepts'},
        'unavailable_reason':
            "['These proposals are attached to a hearing. Use the next revision round for changes.']",
        'documents': [
          for (var i = 1; i <= 3; i++)
            {
              'key': 'c$i:paper',
              'system_key': 'c$i',
              'label': 'Concept paper',
              'required': true,
              'can_upload': false,
              'can_review': false,
              'file': {
                'id': i,
                'file_name': 'system-$i.pdf',
                'revision': 1,
                'status': 'accepted',
              },
            },
        ],
      },
      {
        'deliverable_id': 'FINAL',
        'label': 'Final shared paper',
        'file_format': 'pdf',
        'deliverable_type': 'post',
        'required': true,
        'status': 'missing',
        'file_policy': {'mode': 'single'},
        'documents': [
          {
            'key': 'primary',
            'label': 'Final shared paper',
            'required': true,
            'can_upload': true,
            'file_format': 'pdf',
          },
        ],
      },
    ],
  };
  return {
    ...project,
    'id': 7,
    'imported': false,
    'selected_key': 'c1',
    'verdict': 'approved',
    'title_workflow_version': 2,
    'systems': systems,
    'shared_contexts': [group],
  };
}

Future<void> _openStageHistory(WidgetTester tester) async {
  final menu = find.byTooltip('More history actions').first;
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.text('View stage history'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'system summary advances one status and keeps history in the footer menu',
    (tester) async {
      final steps = [
        ('Title submitted', {'review': 'submitted'}),
        ('Title accepted', {'review': 'accepted'}),
        (
          'Hearing scheduled',
          {
            'review': 'accepted',
            'hearing_progress': 'scheduled',
            'hearing_schedule_ids': [10],
          },
        ),
        (
          'Hearing in progress',
          {
            'review': 'accepted',
            'hearing_progress': 'scheduled',
            'presentation_started_at': '2026-11-03T08:00:00Z',
          },
        ),
        (
          'Awaiting decision',
          {
            'review': 'accepted',
            'hearing_progress': 'awaiting_concept_selection',
            'presentation_started_at': '2026-11-03T08:00:00Z',
          },
        ),
        ('Approved', {'review': 'accepted', 'verdict': 'approved'}),
        (
          'Approved with revisions',
          {'review': 'accepted', 'verdict': 'approved_with_revisions'},
        ),
        (
          'Re-defense required',
          {'review': 'accepted', 'verdict': 'for_redefense'},
        ),
      ];
      for (final step in steps) {
        await tester.pumpWidget(const SizedBox());
        final project = _selectedProject()..['verdict'] = '';
        final values = Map<String, dynamic>.from(step.$2);
        final state = values.remove('review');
        project.addAll(values);
        ((project['systems'] as List).first as Map)['title_review'] = {
          'state': state,
        };
        setApiHttpClientForTesting(
          MockClient(
            (request) async => http.Response(jsonEncode(project), 200),
          ),
        );
        await _pump(
          tester,
          studentData: const {
            'student': {'id': 1},
            'team': {'id': 5, 'section': 'BSIT-3A', 'section_project_id': 7},
          },
        );
        final header = find.byKey(const ValueKey('student-selected-system'));
        expect(
          find.descendant(of: header, matching: find.text(step.$1)),
          findsOneWidget,
        );
        expect(find.text('Selected system'), findsNothing);
        expect(find.textContaining('System outcome:'), findsNothing);
        expect(find.text('More'), findsNothing);
        expect(
          find.byKey(const ValueKey('shared-stage-history')),
          findsNothing,
        );
        final menu = find.byTooltip('More history actions');
        expect(menu, findsOneWidget);
        expect(
          tester.getBottomRight(menu).dx,
          closeTo(tester.getBottomRight(header).dx, 1),
        );
        expect(
          tester.getBottomRight(menu).dy,
          closeTo(tester.getBottomRight(header).dy, 1),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = _Picker();
  });
  tearDown(resetApiHttpClientForTesting);

  for (final dark in [false, true]) {
    testWidgets(
      'stage map opens each configured stage history without changing the system $dark',
      (tester) async {
        final project = _selectedProject()..['history_available'] = true;
        ((project['shared_contexts'] as List).first as Map)['stage_status'] =
            'complete';
        final timeline = {
          'stages': [
            {
              'id': 21,
              'label': 'Concept Proposal',
              'order': 1,
              'records': [
                {
                  'id': 'hearing-1',
                  'kind': 'hearing',
                  'attempt': 1,
                  'outcome': 'approved',
                  'selected_key': 'c1',
                  'team_count': 8,
                  'roster_basis': 'Recorded roster',
                  'teams': [
                    for (var i = 1; i <= 8; i++)
                      {'id': i, 'name': 'Recorded team $i'},
                  ],
                  'systems': [
                    {'key': 'c1', 'title': 'Original section system'},
                  ],
                },
              ],
            },
            {
              'id': 22,
              'label': 'Project Proposal',
              'order': 2,
              'stage_status': 'current',
              'records': [
                {
                  'id': 'shared-2',
                  'kind': 'shared_submission',
                  'team_count': 6,
                  'joined_count': 0,
                  'left_count': 2,
                  'teams': [
                    for (var i = 1; i <= 6; i++)
                      {'id': i, 'name': 'Recorded team $i'},
                  ],
                  'systems': [
                    {'key': 'c1', 'title': 'Proposal-stage system record'},
                  ],
                },
              ],
            },
            {
              'id': 23,
              'label': 'Configured release review',
              'order': 3,
              'records': [],
            },
          ],
        };
        setApiHttpClientForTesting(
          MockClient(
            (request) async => http.Response(
              jsonEncode(
                request.url.path.endsWith('/history/') ? timeline : project,
              ),
              200,
            ),
          ),
        );
        await _pump(
          tester,
          dark: dark,
          studentData: const {
            'student': {'id': 1},
            'team': {'id': 5, 'section': 'BSIT-3A', 'section_project_id': 7},
          },
        );
        expect(find.text('Earlier proposals (2)'), findsNothing);
        expect(find.text('8 teams'), findsNothing);
        await _openStageHistory(tester);
        expect(find.text('8 teams'), findsOneWidget);
        await tester.ensureVisible(find.text('Shared hearing · Attempt 1'));
        await tester.tap(find.text('Shared hearing · Attempt 1'));
        await tester.pumpAndSettle();
        expect(find.text('Original section system'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(SectionIntegrationTab),
          'integration-concept-history-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        final map = find.byKey(const ValueKey('shared-stage-navigation'));
        final proposal = find.descendant(
          of: map,
          matching: find.text('Project Proposal'),
        );
        await tester.ensureVisible(proposal);
        await tester.tap(proposal);
        await tester.pumpAndSettle();
        expect(find.text('8 teams'), findsNothing);
        expect(find.text('6 teams'), findsNothing);
        await _openStageHistory(tester);
        expect(find.text('6 teams'), findsOneWidget);
        await tester.ensureVisible(find.text('Shared submission'));
        await tester.tap(find.text('Shared submission'));
        await tester.pumpAndSettle();
        expect(find.text('Proposal-stage system record'), findsOneWidget);
        expect(
          find.text('Roster change: 0 added, 2 no longer listed'),
          findsOneWidget,
        );
        await capturePreview(
          tester,
          find.byType(SectionIntegrationTab),
          'integration-proposal-history-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        final release = find.descendant(
          of: map,
          matching: find.text('Configured release review'),
        );
        await tester.ensureVisible(release);
        await tester.tap(release);
        await tester.pumpAndSettle();
        await _openStageHistory(tester);
        expect(
          find.text('No activity recorded for this stage yet.'),
          findsOneWidget,
        );
        expect(find.text('6 teams'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('system selection does not invent faculty title acceptance', (
    tester,
  ) async {
    final project = _selectedProject();
    (project['systems'] as List).first['title_review'] = {
      'state': 'submitted',
      'status_label': 'Awaiting title review',
    };
    setApiHttpClientForTesting(
      MockClient((request) async => http.Response(jsonEncode(project), 200)),
    );
    await _pump(
      tester,
      studentData: const {
        'student': {'id': 1},
        'team': {'id': 5, 'section': 'BSIT-3A', 'section_project_id': 7},
      },
    );
    expect(find.text('Selected system'), findsNothing);
    expect(find.text('Title accepted'), findsNothing);
    expect(find.text('Approved'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'selected system is clear once, with documents and proposal history $dark',
      (tester) async {
        setApiHttpClientForTesting(
          MockClient(
            (request) async =>
                http.Response(jsonEncode(_selectedProject()), 200),
          ),
        );
        await _pump(
          tester,
          dark: dark,
          studentData: const {
            'student': {'id': 1},
            'team': {'id': 5, 'section': 'BSIT-3A', 'section_project_id': 7},
          },
        );
        expect(find.text('Your section system'), findsOneWidget);
        expect(find.text('Selected system'), findsNothing);
        expect(find.text('Title accepted'), findsNothing);
        expect(
          find.text('HABI: Artisan Heritage & Craft Exchange Platform'),
          findsOneWidget,
        );
        expect(find.text('System proposals'), findsNothing);
        expect(find.textContaining('titles provided'), findsNothing);
        expect(find.textContaining('Each team follows'), findsNothing);
        expect(find.textContaining('Only the selected system'), findsNothing);
        expect(find.textContaining('This scheduled, decided'), findsNothing);
        expect(find.text('Approved'), findsOneWidget);
        expect(find.text('Final shared paper'), findsNothing);
        expect(find.text('Concept Papers'), findsNothing);
        expect(find.text('Team AgriPulse'), findsOneWidget);
        expect(find.text('Earlier system proposal 2'), findsNothing);
        await capturePreview(
          tester,
          find.byType(SectionIntegrationTab),
          'integration-selected-${dark ? 'dark' : 'light'}',
          viewport: true,
        );

        for (final width in [320.0, 1100.0, 390.0]) {
          tester.view.physicalSize = Size(width, 1000);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(SectionIntegrationTab),
            'integration-details-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
        }
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view.physicalSize = const Size(320, 1000);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.physicalSize = const Size(390, 1000);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Deliverables'));
        await tester.pumpAndSettle();
        expect(find.text('Pre-defense'), findsOneWidget);
        expect(find.text('Post-defense'), findsOneWidget);
        expect(find.text('PDF · 1 required file'), findsNWidgets(2));
        expect(find.text('Title accepted'), findsNothing);
        expect(find.text('Team AgriPulse'), findsNothing);
        expect(find.text('Final shared paper'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(SectionIntegrationTab),
          'integration-deliverables-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.tap(find.text('Concept Papers'));
        await tester.pumpAndSettle();
        expect(find.text('system-1.pdf'), findsOneWidget);
        expect(
          find.textContaining('These proposals are attached'),
          findsNothing,
        );
        expect(find.text('Mandatory for oral defense'), findsNothing);
        await capturePreview(
          tester,
          find.byType(SectionIntegrationTab),
          'integration-file-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();

        expect(find.text('Earlier proposals (2)'), findsNothing);
        await tester.tap(find.text('System details'));
        await tester.pumpAndSettle();
        await _openStageHistory(tester);
        await tester.ensureVisible(find.text('Shared hearing · Attempt 1'));
        await tester.tap(find.text('Shared hearing · Attempt 1'));
        await tester.pumpAndSettle();
        expect(find.text('Earlier system proposal 2'), findsOneWidget);
        expect(find.text('Selected system'), findsWidgets);
        expect(find.text('Concept Papers'), findsNothing);
        expect(find.text('Team roster not recorded'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Deliverables'));
        await tester.tap(find.text('Deliverables'));
        await tester.pumpAndSettle();
        expect(find.text('Final shared paper'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'earlier attempts retain their recorded titles and outcomes in details',
    (tester) async {
      final project = _selectedProject()..['round'] = 2;
      project['history'] = [
        {
          'round': 1,
          'verdict': 'for_redefense',
          'selected_key': '',
          'remarks': 'Refine the section proposals.',
          'snapshot': {
            'systems': [
              {'key': 'c2', 'title': 'Original hearing proposal'},
            ],
          },
        },
      ];
      setApiHttpClientForTesting(
        MockClient((request) async => http.Response(jsonEncode(project), 200)),
      );
      await _pump(
        tester,
        studentData: const {
          'student': {'id': 1},
          'team': {'id': 5, 'section': 'BSIT-3A', 'section_project_id': 7},
        },
      );
      expect(find.text('Original hearing proposal'), findsNothing);
      await _openStageHistory(tester);
      await tester.tap(find.text('Shared hearing · Attempt 1'));
      await tester.pumpAndSettle();
      expect(find.text('Original hearing proposal'), findsOneWidget);
      expect(find.text('For Re-defense'), findsOneWidget);
      expect(find.text('Refine the section proposals.'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deliverables'));
      await tester.pumpAndSettle();
      expect(find.text('Original hearing proposal'), findsNothing);
      expect(find.text('Final shared paper'), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [500.0, 390.0]) {
      testWidgets(
        'stage tabs retain workflow labels and shared upload uses archive suggestion ($width, $dark)',
        (tester) async {
          const suggested =
              'SmartAgroIndustrialIoTSustainableSupplyPlatform_ApprovedConceptPaper.pdf';
          Map<String, dynamic> group(String stage, String status, int id) => {
            'team_id': 5,
            'section': 'BSIT-3A',
            'stage_label': stage,
            'stage_status': status,
            'scope': 'capstone',
            'context_id': id,
            'review_token': 'shared-version',
            'concept_selection_enabled': false,
            'project_manager_name': 'Gabriel Navarro',
            'reviewer_name': 'Eduardo Padilla',
            'systems': [
              {
                'key': 'c1',
                'title':
                    'Smart Agro-Industrial IoT & Sustainable Supply Platform',
              },
            ],
            'selected_key': 'c1',
            'requirements': [
              if (status == 'current')
                {
                  'deliverable_id': 'FINAL',
                  'label': 'Approved concept paper',
                  'required': true,
                  'deliverable_type': 'post',
                  'file_format': 'pdf',
                  'status': 'missing',
                  'file_policy': {'mode': 'single'},
                  'documents': [
                    {
                      'key': 'primary',
                      'label': 'Approved concept paper',
                      'file_format': 'pdf',
                      'can_upload': true,
                      'can_review': false,
                      'suggested_file_name': suggested,
                    },
                  ],
                },
            ],
          };
          final groups = [
            group('Concept Proposal', 'complete', 1),
            group('Project Proposal', 'current', 2),
            group('Final Defense', 'upcoming', 3),
          ];
          final project = {
            ..._preview(),
            'id': 7,
            'imported': false,
            'round_id': 20,
            'shared_contexts': groups,
          };
          var uploaded = false;
          setApiHttpClientForTesting(
            MockClient((request) async {
              if (request.method == 'POST' &&
                  request.url.path.endsWith('/shared-deliverables/')) {
                expect(request.body, contains(suggested));
                expect(
                  request.body,
                  isNot(contains('filename="system-a.pdf"')),
                );
                uploaded = true;
                return http.Response(
                  jsonEncode({'shared_deliverables': groups[1]}),
                  200,
                );
              }
              if (request.url.path.endsWith('/section-concepts/')) {
                return http.Response(
                  jsonEncode({
                    'projects': [project],
                    'shared_contexts': groups,
                    'tasks': [],
                  }),
                  200,
                );
              }
              return http.Response(jsonEncode(project), 200);
            }),
          );
          await _pump(tester, dark: dark);
          tester.view.physicalSize = Size(width, 1000);
          await tester.pumpAndSettle();
          final navigation = find.byKey(
            const ValueKey('shared-stage-navigation'),
          );
          expect(find.byType(DropdownButtonFormField<String>), findsNothing);
          expect(
            tester.widget<DefenseStagesMap>(navigation).selectedStageName,
            'Project Proposal',
          );
          expect(find.text('Current'), findsOneWidget);
          expect(find.text('Passed'), findsOneWidget);
          expect(find.text('Upcoming'), findsOneWidget);
          await capturePreview(
            tester,
            find.byType(SectionIntegrationTab),
            'shared-stage-tabs-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.tap(find.text('Concept Proposal'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<DefenseStagesMap>(navigation).selectedStageName,
            'Concept Proposal',
          );
          expect(
            find.text('Current'),
            findsOneWidget,
          ); // Browsing does not change workflow state.
          await tester.tap(find.text('Project Proposal'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Deliverables'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Approved concept paper'));
          await tester.pumpAndSettle();
          expect(find.text('Suggested archive filename'), findsOneWidget);
          expect(find.text(suggested), findsOneWidget);
          expect(find.byTooltip('Copy archive filename'), findsOneWidget);
          await tester.ensureVisible(
            find.widgetWithText(ShadButton, 'Upload').first,
          );
          await tester.tap(find.widgetWithText(ShadButton, 'Upload').first);
          await tester.pumpAndSettle();
          expect(uploaded, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final dark in [false, true]) {
    testWidgets(
      'imported rosters show own and other teams without a student list $dark',
      (tester) async {
        setApiHttpClientForTesting(
          MockClient(
            (request) async => http.Response(
              jsonEncode(
                request.url.path.endsWith('/section-concepts/')
                    ? {'projects': [], 'tasks': []}
                    : _preview(),
              ),
              200,
            ),
          ),
        );
        await _pump(tester, dark: dark);
        await tester.ensureVisible(find.text('Team AgriPulse'));
        await tester.tap(find.text('Team AgriPulse'));
        await tester.pumpAndSettle();
        expect(find.text('Team Roster (3)'), findsOneWidget);
        expect(find.text('Gabriel Navarro'), findsOneWidget);
        expect(find.text('Maya Santos'), findsOneWidget);
        expect(find.text('Rafael Lim'), findsOneWidget);
        await tester.ensureVisible(find.text('Team Roster (3)'));
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(SectionIntegrationTab),
          'shared-import-roster-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        await tester.ensureVisible(find.text('Team ClimateNode'));
        await tester.tap(find.text('Team ClimateNode'));
        await tester.pumpAndSettle();
        expect(find.text('Team Roster (2)'), findsOneWidget);
        expect(find.text('Joaquin Panganiban'), findsOneWidget);
        expect(find.text('Sofia Ramos'), findsOneWidget);
        expect(find.text('Team Roster (0)'), findsNothing);
        expect(
          find.text('No members assigned to this team yet.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'imported System A and real PM/reviewers appear; PM saves the remaining systems $dark',
      (tester) async {
        Map<String, dynamic> project = _preview();
        Map? saved;
        setApiHttpClientForTesting(
          MockClient((request) async {
            if (request.url.path.endsWith('/section-concepts/')) {
              return http.Response(
                jsonEncode({'projects': [], 'tasks': []}),
                200,
              );
            }
            if (request.method == 'POST') {
              saved = jsonDecode(request.body) as Map;
              project = {
                ...project,
                'id': 7,
                'imported': false,
                'round_id': 20,
                'review_token': 'saved-version',
                'systems': [
                  for (final row in saved!['concepts'] as List)
                    {
                      ...row as Map,
                      'confirmed': false,
                      'papers': [],
                      'can_upload': true,
                    },
                ],
              };
              return http.Response(jsonEncode(project), 201);
            }
            return http.Response(jsonEncode(project), 200);
          }),
        );
        await _pump(tester, dark: dark);
        expect(find.text('Project manager: Gabriel Navarro'), findsOneWidget);
        expect(
          find.text('System reviewer: Eduardo Padilla, Grace Hopper'),
          findsOneWidget,
        );
        expect(find.text('1 of 3 titles provided'), findsOneWidget);
        expect(find.textContaining('Smart Agro-Industrial'), findsOneWidget);
        expect(find.text('★ Selected System'), findsNothing);
        expect(find.text('Upload Concept Paper (PDF)'), findsNothing);
        await capturePreview(
          tester,
          find.byType(SectionIntegrationTab),
          'shared-import-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
        for (final width in [320.0, 1100.0]) {
          tester.view.physicalSize = Size(width, 1000);
          await tester.pumpAndSettle();
          await capturePreview(
            tester,
            find.byType(SectionIntegrationTab),
            'shared-import-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          expect(tester.takeException(), isNull);
        }
        tester.view.physicalSize = const Size(390, 1000);
        await tester.pumpAndSettle();
        await tester.tap(find.text('System B'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Smart Agro-Industrial'), findsNothing);
        await tester.tap(find.text('Edit titles'));
        await tester.pumpAndSettle();
        for (final entry in {
          'c2': 'Shared irrigation alternative',
          'c3': 'Shared supply alternative',
        }.entries) {
          final field = find.descendant(
            of: find.byKey(ValueKey('concept-title-${entry.key}')),
            matching: find.byType(EditableText),
          );
          await tester.ensureVisible(field);
          await tester.enterText(field, entry.value);
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save system titles'));
        await tester.pumpAndSettle();
        expect(saved!['review_token'], 'import-version');
        expect(
          (saved!['concepts'] as List).first['title'],
          contains('Smart Agro-Industrial'),
        );
        expect(find.text('3 of 3 titles provided'), findsOneWidget);
        expect(find.text('Shared irrigation alternative'), findsOneWidget);
        await tester.tap(find.text('System C'));
        await tester.pumpAndSettle();
        expect(find.text('Shared supply alternative'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('PM uploads imported System A while B/C are still blank', (
    tester,
  ) async {
    final picker = FilePicker.platform;
    FilePicker.platform = _Picker();
    addTearDown(() => FilePicker.platform = picker);
    var initialized = false, uploaded = false;
    final project = {..._preview(), 'id': 7, 'imported': false, 'round_id': 20};
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/section-concepts/')) {
          return http.Response(jsonEncode({'projects': [], 'tasks': []}), 200);
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/imported/')) {
          final body = jsonDecode(request.body) as Map;
          expect(body.containsKey('concepts'), isFalse);
          expect(body['review_token'], 'import-version');
          initialized = true;
          return http.Response(jsonEncode(project), 201);
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/7/upload/')) {
          expect(initialized, isTrue);
          expect(
            request.headers['content-type'],
            contains('multipart/form-data'),
          );
          expect(request.body, contains('system-a.pdf'));
          uploaded = true;
          ((project['systems'] as List).first as Map)['papers'] = [
            {
              'id': 9,
              'file_name': 'system-a.pdf',
              'revision': 1,
              'status': 'pending',
              'is_current': true,
            },
          ];
          return http.Response(jsonEncode(project), 201);
        }
        return http.Response(jsonEncode(_preview()), 200);
      }),
    );
    await _pump(tester);
    await tester.tap(find.text('Deliverables'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Upload Concept Paper (PDF)'));
    await tester.tap(find.widgetWithText(ShadButton, 'Upload'));
    await tester.pumpAndSettle();
    expect(uploaded, isTrue);
    expect(find.text('system-a.pdf'), findsOneWidget);
    await tester.tap(find.text('System details'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 titles provided'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'continued system opens the current stage with its own team context',
    (tester) async {
      final requests = <Uri>[];
      final project = {
        ..._preview(),
        'id': 7,
        'imported': false,
        'historical': true,
        'editable': false,
        'selected_key': 'c1',
        'can_edit_names': false,
        'shared_contexts': [
          {
            'team_id': 5,
            'source_project_id': 7,
            'section': 'BSIT-4A',
            'stage_label': 'Final Defense',
            'stage_status': 'current',
            'scope': 'capstone',
            'continued': true,
            'historical': false,
            'project_manager_id': 1,
            'project_manager_name': 'Gabriel Navarro',
            'reviewer_name': 'Eduardo Padilla',
            'selected_key': 'c1',
            'systems': [(_preview()['systems'] as List).first],
            'requirements': [],
          },
        ],
      };
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          return http.Response(jsonEncode(project), 200);
        }),
      );
      await _pump(
        tester,
        studentData: const {
          'student': {'id': 1, 'is_project_manager': false},
          'team': {
            'id': 5,
            'section': 'BSIT-4A',
            'section_project_id': 7,
            'current_defense_stage': 'Final Defense',
          },
        },
      );
      expect(requests.single.queryParameters['team_id'], '5');
      expect(find.textContaining('Smart Agro-Industrial'), findsWidgets);
      expect(find.text('Upload Concept Paper (PDF)'), findsNothing);
      expect(find.text('Edit titles'), findsNothing);
      expect(find.text('System B'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
