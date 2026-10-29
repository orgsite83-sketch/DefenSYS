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

Future<void> _pump(WidgetTester tester, {bool dark = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  await pumpDefensysWidget(
    tester,
    const SectionIntegrationTab(
      studentData: {
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = _Picker();
  });
  tearDown(resetApiHttpClientForTesting);

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
            tester.widget<ShadTabs<String>>(navigation).value,
            'Project Proposal',
          );
          expect(find.text('Current'), findsOneWidget);
          expect(find.text('Complete'), findsOneWidget);
          expect(find.text('Upcoming'), findsOneWidget);
          expect(find.text('Suggested archive filename'), findsOneWidget);
          expect(find.text(suggested), findsOneWidget);
          expect(find.byTooltip('Copy archive filename'), findsOneWidget);
          await capturePreview(
            tester,
            find.byType(SectionIntegrationTab),
            'shared-stage-tabs-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.tap(find.text('Concept Proposal'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<ShadTabs<String>>(navigation).value,
            'Concept Proposal',
          );
          expect(
            find.text('Current'),
            findsOneWidget,
          ); // Browsing does not change workflow state.
          await tester.tap(find.text('Project Proposal'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.widgetWithText(OutlinedButton, 'Upload').first,
          );
          await tester.tap(find.widgetWithText(OutlinedButton, 'Upload').first);
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
        expect(find.text('PM: Gabriel Navarro'), findsOneWidget);
        expect(
          find.text('Reviewers: Eduardo Padilla, Grace Hopper'),
          findsOneWidget,
        );
        expect(find.text('1 of 3 titles provided'), findsOneWidget);
        expect(find.textContaining('Smart Agro-Industrial'), findsOneWidget);
        expect(find.text('★ Selected System'), findsNothing);
        expect(find.text('Upload Concept Paper (PDF)'), findsOneWidget);
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
    await tester.ensureVisible(find.text('Upload Concept Paper (PDF)'));
    await tester.tap(find.text('Upload Concept Paper (PDF)'));
    await tester.pumpAndSettle();
    expect(uploaded, isTrue);
    expect(find.text('system-a.pdf'), findsOneWidget);
    expect(find.text('1 of 3 titles provided'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
