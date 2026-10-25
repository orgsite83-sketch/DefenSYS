import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/widgets/repository/team_concept_title_editor.dart';
import 'package:defensys/theme/app_theme.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Leader extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 10, 'role': 'student'},
  );
}

Map<String, dynamic> workflow({int count = 3, bool shared = false}) => {
  'enabled': true,
  'can_edit_titles': true,
  'module_review_token': 'current-version',
  if (shared) 'section_project_id': 7,
  'concepts': [
    for (var i = 1; i <= count; i++)
      {
        'key': 'c$i',
        'title': i == 1 ? 'Imported soil sensor concept' : '',
        if (shared) 'system_title': 'Shared alternative $i',
        'faculty_confirmed': shared && i == 1,
      },
  ],
};

Finder field(String key) => find.descendant(
  of: find.byKey(ValueKey('concept-title-$key')),
  matching: find.byType(EditableText),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  for (final width in [390.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'title editor saves partial drafts at $width ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadPreviewFonts();
          Map? saved;
          Map<String, dynamic>? result;
          final current = workflow(count: 4);
          setApiHttpClientForTesting(
            MockClient((request) async {
              expect(request.url.path, endsWith('/deliverables/concepts/'));
              expect(request.url.queryParameters['team_id'], '5');
              if (request.method == 'POST') {
                saved = jsonDecode(request.body) as Map;
                return http.Response(
                  jsonEncode({
                    'concept_workflow': {
                      ...current,
                      'concepts': saved!['concepts'],
                    },
                  }),
                  200,
                );
              }
              return http.Response(
                jsonEncode({'concept_workflow': current}),
                200,
              );
            }),
          );
          await pumpDefensysWidget(
            tester,
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await editTeamConceptTitles(
                    context,
                    teamId: 5,
                    stageLabel: 'Concept Proposal',
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
            overrides: [authProvider.overrideWith(_Leader.new)],
          );
          await tester.tap(find.text('Open editor'));
          await tester.pumpAndSettle();
          final dialog = tester.widget<Dialog>(find.byType(Dialog));
          expect(
            dialog.insetPadding,
            width < 600 ? EdgeInsets.zero : const EdgeInsets.all(24),
          );
          expect(find.text('1 of 4 titles completed'), findsOneWidget);
          expect(
            tester.widget<EditableText>(field('c1')).controller.text,
            'Imported soil sensor concept',
          );
          await tester.enterText(field('c2'), 'Additional draft concept');
          await tester.pumpAndSettle();
          await capturePreview(
            tester,
            find.byType(TeamConceptTitleEditor),
            'team-concept-editor-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          await tester.tap(find.text('Save concept titles'));
          await tester.pumpAndSettle();
          expect(saved!['action'], 'save_draft_titles');
          expect(saved!['review_token'], 'current-version');
          expect((saved!['concepts'] as List)[2]['title'], '');
          expect(
            (result!['concepts'] as List)[1]['title'],
            'Additional draft concept',
          );
          expect(find.byType(TeamConceptTitleEditor), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'save failure retains edits and cancel protects unsaved changes',
    (tester) async {
      setApiHttpClientForTesting(
        MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.method == 'POST'
                  ? {'detail': 'The concepts changed. Refresh before saving.'}
                  : {'concept_workflow': workflow()},
            ),
            request.method == 'POST' ? 409 : 200,
          ),
        ),
      );
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => editTeamConceptTitles(
              context,
              teamId: 5,
              stageLabel: 'Concept Proposal',
            ),
            child: const Text('Open editor'),
          ),
        ),
        overrides: [authProvider.overrideWith(_Leader.new)],
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(field('c2'), 'Keep my draft');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save concept titles'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(field('c2')).controller.text,
        'Keep my draft',
      );
      expect(find.textContaining('concepts changed'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved titles?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(field('c2')).controller.text,
        'Keep my draft',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.byType(TeamConceptTitleEditor), findsNothing);
    },
  );

  testWidgets(
    'confirmed shared names stay locked while remaining modules are editable',
    (tester) async {
      setApiHttpClientForTesting(
        MockClient(
          (request) async => http.Response(
            jsonEncode({'concept_workflow': workflow(shared: true)}),
            200,
          ),
        ),
      );
      await pumpDefensysWidget(
        tester,
        const TeamConceptTitleEditor(teamId: 5, stageLabel: 'Concept Proposal'),
        overrides: [authProvider.overrideWith(_Leader.new)],
      );
      expect(find.text('Edit module titles'), findsOneWidget);
      expect(find.text('Shared alternative 2'), findsOneWidget);
      expect(
        tester
            .widget<ShadInput>(find.byKey(const ValueKey('concept-title-c1')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ShadInput>(find.byKey(const ValueKey('concept-title-c2')))
            .enabled,
        isTrue,
      );
    },
  );

  testWidgets(
    'small phone keeps save actions above the keyboard and scrolls all configured titles',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      setApiHttpClientForTesting(
        MockClient(
          (request) async => http.Response(
            jsonEncode({'concept_workflow': workflow(count: 10)}),
            200,
          ),
        ),
      );
      await pumpDefensysWidget(
        tester,
        const TeamConceptTitleEditor(teamId: 5, stageLabel: 'Concept Proposal'),
        overrides: [authProvider.overrideWith(_Leader.new)],
      );
      await tester.enterText(field('c2'), 'Keyboard draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('c10'));
      await tester.pumpAndSettle();
      expect(find.text('Concept 10'), findsOneWidget);
      final saveButton = find.widgetWithText(ShadButton, 'Save concept titles');
      expect(tester.getRect(saveButton).bottom, lessThanOrEqualTo(460));
      expect(tester.widget<ShadButton>(saveButton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}
