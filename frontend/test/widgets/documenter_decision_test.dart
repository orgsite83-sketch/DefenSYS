import 'dart:convert';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/screens/web/faculty/documenter/minutes_form_screen.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/grading/panel_deliberation_panel.dart';
import 'package:defensys/widgets/minutes/documenter_decision_fields.dart';
import 'package:defensys/widgets/minutes/documenter_outcome_correction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isRestoring: false,
    user: {
      'id': 7,
      'role': 'faculty',
      'is_documenter': true,
      'e_signature': 'signature.png',
    },
  );
}

Map<String, dynamic> contextData() => {
  'grade_id': 12,
  'draft': <String, dynamic>{},
  'draft_ready': false,
  'outcome_rule': {
    'panel_complete': true,
    'outcome': 'approved',
    'review_token': 'assessment-token',
    'allowed_verdicts': [
      'approved',
      'approved_with_revisions',
      'for_redefense',
    ],
    'per_concept': false,
  },
};

Map<String, dynamic> detail() => {
  'id': 1,
  'team_name': 'Team Inventory',
  'project_title': 'Inventory system',
  'status': 'draft',
  'defense_stage_label': 'Final Defense',
  'defense_date': '2026-11-21',
  'defense_time': '09:00',
  'room': 'Lab 1',
  'documenter_name': 'Assigned Documenter',
  'outcome_required': true,
  'official_outcome': null,
  'decision_context': contextData(),
  'schedule': {
    'id': 10,
    'documenter': 7,
    'team_adviser': 8,
    'status': 'scheduled',
  },
  'panelist_comments': [
    {
      'id': 20,
      'panelist_name_snapshot': 'Assigned Chair',
      'panelist_role_snapshot': 'Chair',
      'comments': 'Revise the manuscript discussion.',
    },
  ],
};

Finder inputPrefix(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key as ValueKey<String>).value.startsWith(prefix),
);

void main() {
  setUpAll(() => registerFallbackValue(Uri()));
  testWidgets(
    'documenter records levels and demonstrations without duplicate correction boxes',
    (tester) async {
      Map<String, dynamic>? draft;
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DocumenterDecisionFields(
              value: const {},
              contextData: contextData(),
              onChanged: (value) => draft = value,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Select announced verdict'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approved with revisions').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add revision area'));
      await tester.pumpAndSettle();
      await tester.enterText(inputPrefix('documenter-area-'), 'Manuscript');
      await tester.tap(find.text('Choose Minor or Major'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Major revision').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Re-demo required'));
      await tester.tap(find.text('Re-demo required'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) => widget is ShadInput && widget.maxLength == 1000,
        ),
        'Demonstrate corrected report exports.',
      );
      expect(draft?['verdict'], 'approved_with_revisions');
      expect(
        (draft?['revision_entries'] as List).single,
        containsPair('severity', 'major'),
      );
      expect(
        (draft?['revision_entries'] as List).single,
        isNot(contains('instructions')),
      );
      expect(draft?['demo_requirements'], [
        {'text': 'Demonstrate corrected report exports.'},
      ]);
      expect(find.text('Confirm panel decision'), findsNothing);
      await tester.ensureVisible(find.text('Approved with revisions'));
      await tester.tap(find.text('Approved with revisions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approved').last);
      await tester.pumpAndSettle();
      expect(draft?['revision_entries'], isEmpty);
      expect(draft?['demo_requirements'], isEmpty);
      expect(draft?['re_demo_required'], false);
      expect(find.text('Add revision area'), findsNothing);
    },
  );

  testWidgets('minutes autosave carries the decision draft with its comments', (
    tester,
  ) async {
    final client = _Client();
    Map? saved;
    final data = detail();
    when(
      () => client.get(any()),
    ).thenAnswer((_) async => http.Response(jsonEncode(data), 200));
    when(
      () => client.patch(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((call) async {
      saved = jsonDecode(call.namedArguments[#body] as String) as Map;
      (data['decision_context'] as Map)['draft'] = saved?['decision_draft'];
      return http.Response(jsonEncode(data), 200);
    });
    await pumpDefensysWidget(
      tester,
      MinutesFormScreen(scheduleId: 10, onBack: () {}),
      overrides: [
        authProvider.overrideWith(_Auth.new),
        authenticatedHttpClientProvider.overrideWithValue(client),
      ],
    );
    await tester.ensureVisible(find.text('Select announced verdict'));
    await tester.tap(find.text('Select announced verdict'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approved').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect((saved?['decision_draft'] as Map)['verdict'], 'approved');
    expect(
      (saved?['decision_draft'] as Map)['review_token'],
      'assessment-token',
    );
    expect(
      (saved?['comments'] as List).single,
      containsPair('comments', 'Revise the manuscript discussion.'),
    );
    expect(find.text('Confirm panel decision'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('chair has read-only outcome with no extra confirmation', (
    tester,
  ) async {
    final data = {
      'id': 12,
      'schedule_id': 10,
      'workflow': {
        'deliberation': {
          'enabled': true,
          'revision_mode': 'documenter',
          'can_confirm': false,
          'decision': null,
        },
        'outcome_rule': (contextData()['outcome_rule'] as Map),
      },
    };
    await pumpDefensysWidget(
      tester,
      PanelDeliberationPanel(grade: data, isChair: true),
    );
    expect(
      find.text('Awaiting the documenter’s recorded panel outcome.'),
      findsOneWidget,
    );
    expect(find.byType(ShadSelect<String>), findsNothing);
    expect(find.text('Confirm panel decision'), findsNothing);
  });

  testWidgets(
    'documenter correction goes to the minutes review queue without a chair action',
    (tester) async {
      final client = _Client();
      Map? sent;
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((call) async {
        expect(
          (call.positionalArguments.single as Uri).path,
          endsWith('/10/decision-correction/'),
        );
        sent = jsonDecode(call.namedArguments[#body] as String) as Map;
        return http.Response(jsonEncode({'status': 'pending'}), 200);
      });
      final data = contextData()..['grade_updated_at'] = '2026-11-21T14:00:00Z';
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => DocumenterOutcomeCorrection(
                scheduleId: 10,
                contextData: data,
                decision: {
                  'revision': 4,
                  'verdict': 'approved_with_revisions',
                  'revision_entries': [
                    {
                      'area_id': 'system',
                      'label': 'System',
                      'severity': 'minor',
                    },
                  ],
                  'demo_requirements': [],
                  're_demo_required': false,
                },
              ),
            ),
            child: const Text('Correct outcome'),
          ),
        ),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await tester.tap(find.text('Correct outcome'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) => widget is ShadInput && widget.maxLength == 2000,
        ),
        'Correct the recorded revision level.',
      );
      await tester.tap(find.text('Request correction'));
      await tester.pumpAndSettle();
      expect(sent?['reason'], 'Correct the recorded revision level.');
      final correction = (sent?['changes'] as Map)['panel_decision'] as Map;
      expect(correction['source_revision'], 4);
      expect(correction['review_token'], 'assessment-token');
      expect(correction.containsKey('request_id'), false);
      expect(find.text('Correct outcome'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  final sample = {
    'request_id': 'draft-identity',
    'verdict': 'approved_with_revisions',
    'revision_entries': [
      {'area_id': 'manuscript', 'label': 'Manuscript', 'severity': 'major'},
      {'area_id': 'system', 'label': 'System', 'severity': 'minor'},
    ],
    're_demo_required': true,
    'demo_requirements': [
      {'text': 'Demonstrate corrected report exports.'},
      {'text': 'Demonstrate access restrictions.'},
    ],
  };
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('documenter outcome fits $width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DocumenterDecisionFields(
                value: sample,
                contextData: contextData(),
                onChanged: (_) {},
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'documenter-outcome-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }
}
