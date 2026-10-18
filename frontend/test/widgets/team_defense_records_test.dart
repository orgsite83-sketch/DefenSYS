import 'package:defensys/screens/app/student/student_events_tab.dart';
import 'package:defensys/screens/web/faculty/adviser/adviser_defense_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/defense/team_defense_records.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Defenses extends TeamDefenseNotifier {
  _Defenses(this.records, {this.error});
  final List<Map<String, dynamic>> records;
  final String? error;
  int refreshes = 0;
  @override
  TeamDefenseState build() =>
      TeamDefenseState(schedules: records, error: error);
  @override
  Future<void> fetch({String? workspace}) async {
    refreshes++;
  }
}

class _Deliverables extends CapstoneDeliverablesNotifier {
  _Deliverables({this.teams = const []});
  final List<Map<String, dynamic>> teams;
  @override
  CapstoneDeliverablesState build() => CapstoneDeliverablesState(
    teams: teams,
    selectedStage: 'Project Proposal',
    stageOptions: ['Concept Proposal', 'Project Proposal'],
  );
  @override
  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

Map<String, dynamic> _record(
  int id, {
  String status = 'scheduled',
  String? minutes,
  String verdict = '',
  String? progress,
}) => {
  'id': id,
  'team_id': 7,
  'team_name': 'Team AgriSense',
  'scope': 'capstone',
  'stage_label': 'Project Proposal',
  'project_version': 1,
  'semester_id': 3,
  'project_title': 'Smart Agriculture Crop & Soil Monitoring',
  'scheduled_date': '2099-10-20',
  'start_time': '08:00:00',
  'slot_duration': 60,
  'room': 'Room 301',
  'status': status,
  'display_status': progress ?? status,
  'adviser_name': 'Ricardo Fontanilla',
  'documenter_name': 'Cecilia Magbanua',
  'minutes_required': true,
  'minutes_status': minutes,
  'panelists': [
    {'name': 'Florencia Dela Torre', 'is_chair': true},
    {'name': 'Teresita Buenaventura'},
  ],
  'external_evaluators': [
    {'name': 'Dr. Lina Santos', 'is_active': false},
  ],
  'assessment': {
    'verdict': verdict,
    'attempt_count': id == 18 ? 1 : 2,
    'is_completed': progress == 'completed',
  },
};

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> records, {
  bool adviser = false,
  bool dark = false,
  List<Map<String, dynamic>> grades = const [],
  String? error,
}) => pumpDefensysWidget(
  tester,
  SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: TeamDefenseRecordsView(
        teamId: 7,
        selectedStage: 'Project Proposal',
        grades: grades,
        allowAdviserReview: adviser,
      ),
    ),
  ),
  theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
  overrides: [
    teamDefenseProvider.overrideWith(() => _Defenses(records, error: error)),
  ],
);

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  testWidgets('upcoming records show the full roster before minutes exist', (
    tester,
  ) async {
    await _pump(tester, [_record(18)]);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Room 301'), findsOneWidget);
    expect(find.textContaining('Florencia Dela Torre · Chair'), findsOneWidget);
    expect(
      find.textContaining('Dr. Lina Santos · External panelist'),
      findsOneWidget,
    );
    expect(find.text('Cecilia Magbanua'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Awaiting verdict'), findsOneWidget);
    expect(find.text('View final minutes'), findsNothing);
  });

  testWidgets(
    'recorded verdict is visible before grades and minutes are finalized',
    (tester) async {
      await _pump(
        tester,
        [
          _record(
            18,
            status: 'done',
            verdict: 'approved_with_revisions',
            progress: 'revisions_pending',
          ),
        ],
        grades: [
          {
            'schedule_id': 18,
            'status': 'draft',
            'revision_deadline': '2099-10-25',
            'final_grade': 77.07,
          },
        ],
      );
      expect(
        find.text('Defense verdict: Approved with Revisions'),
        findsOneWidget,
      );
      expect(find.textContaining('Revision deadline:'), findsOneWidget);
      expect(find.text('Grade publication: Pending'), findsOneWidget);
      expect(find.textContaining('77.07'), findsNothing);
      expect(find.text('Not started'), findsOneWidget);
    },
  );

  testWidgets(
    'completed records keep schedule details and students only get the final PDF action',
    (tester) async {
      await _pump(
        tester,
        [
          _record(
            18,
            status: 'done',
            verdict: 'approved',
            progress: 'completed',
            minutes: 'completed',
          ),
        ],
        grades: [
          {
            'schedule_id': 18,
            'status': 'published',
            'result': 'passed',
            'final_grade': 77.07,
          },
        ],
      );
      expect(find.text('Room 301'), findsOneWidget);
      expect(find.text('Stage completion: Completed'), findsOneWidget);
      expect(find.text('Team average: 77.07 · Published'), findsOneWidget);
      expect(find.text('View final minutes'), findsOneWidget);
      expect(find.text('Review and sign minutes'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, [_record(18, minutes: 'submitted')]);
      expect(find.text('Awaiting adviser signature'), findsOneWidget);
      expect(find.text('Review and sign minutes'), findsNothing);
      expect(find.text('View signed minutes'), findsNothing);
    },
  );

  testWidgets(
    'history preserves cancelled and earlier attempts without leaking their verdict',
    (tester) async {
      await _pump(tester, [
        _record(18, status: 'done', verdict: 'for_redefense'),
        _record(19),
        _record(20, status: 'cancelled'),
        {..._record(21), 'team_id': 99, 'room': 'Private room'},
        {
          ..._record(22),
          'stage_label': 'Concept Proposal',
          'room': 'Concept room',
        },
      ]);
      expect(find.byKey(const ValueKey('defense-record-19')), findsOneWidget);
      expect(find.text('Defense verdict: For Re-defense'), findsNothing);
      await tester.ensureVisible(find.text('Previous defenses (2)'));
      await tester.tap(find.text('Previous defenses (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Defense verdict: For Re-defense'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Private room'), findsNothing);
      expect(find.text('Concept room'), findsNothing);
    },
  );

  testWidgets('empty and refresh errors are explicit', (tester) async {
    await _pump(tester, []);
    expect(find.text('No defense scheduled yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, [
      _record(18),
    ], error: 'Unable to refresh defense records.');
    expect(find.text('Unable to refresh defense records.'), findsOneWidget);
    expect(find.text('Room 301'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    'student roadmap uses the Defense tab and loads schedules before minutes',
    (tester) async {
      final defenses = _Defenses([
        _record(18),
        {..._record(19), 'team_id': 99, 'room': 'Private room'},
        {
          ..._record(20, status: 'done'),
          'stage_label': 'Concept Proposal',
          'room': 'Concept room',
        },
        {
          ..._record(21, status: 'cancelled'),
          'stage_label': 'Concept Proposal',
          'room': 'Cancelled concept room',
        },
      ]);
      await pumpDefensysWidget(
        tester,
        const StudentEventsTab(
          isCapstone: true,
          initialStage: 'Project Proposal',
          studentData: {
            'team': {
              'id': 7,
              'project_version': 1,
              'semester_id': 3,
              'adviserName': 'Ricardo Fontanilla',
            },
            'stage_options': ['Concept Proposal', 'Project Proposal'],
            'current_stage': 'Project Proposal',
            'stages': [],
          },
        ),
        overrides: [
          teamDefenseProvider.overrideWith(() => defenses),
          capstoneDeliverablesProvider.overrideWith(
            () => _Deliverables(
              teams: [
                {
                  'id': 99,
                  'project_version': 1,
                  'semester_id': 3,
                  'stages': [],
                },
              ],
            ),
          ),
        ],
      );
      expect(defenses.refreshes, 1);
      expect(find.text('Defense'), findsOneWidget);
      expect(find.text('Schedule'), findsNothing);
      expect(find.text('Room 301'), findsOneWidget);
      expect(find.text('Not started'), findsOneWidget);
      expect(find.text('Private room'), findsNothing);
      expect(find.text('Concept room'), findsNothing);
      expect(find.textContaining('Previous defenses ('), findsNothing);
      await tester.ensureVisible(find.text('Concept Proposal'));
      await tester.tap(find.text('Concept Proposal'));
      await tester.pumpAndSettle();
      expect(find.text('Concept room'), findsOneWidget);
      expect(find.text('Room 301'), findsNothing);
      await tester.ensureVisible(find.text('Previous defenses (1)'));
      await tester.tap(find.text('Previous defenses (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled concept room'), findsOneWidget);
      expect(find.text('Room 301'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'adviser stage switching filters the current record and history',
    (tester) async {
      var selectedStage = 'Project Proposal';
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => selectedStage = 'Concept Proposal'),
                  child: const Text('View Concept Proposal'),
                ),
                AdviserDefenseTab(teamId: 7, selectedStage: selectedStage),
              ],
            ),
          ),
        ),
        overrides: [
          teamDefenseProvider.overrideWith(
            () => _Defenses([
              _record(18),
              {
                ..._record(19, status: 'done'),
                'stage_label': 'Concept Proposal',
                'room': 'Concept room',
              },
              {
                ..._record(20, status: 'cancelled'),
                'stage_label': 'Concept Proposal',
                'room': 'Cancelled concept room',
              },
            ]),
          ),
        ],
      );
      expect(find.text('Room 301'), findsOneWidget);
      expect(find.textContaining('Previous defenses ('), findsNothing);
      await tester.tap(find.text('View Concept Proposal'));
      await tester.pumpAndSettle();
      expect(find.text('Concept room'), findsOneWidget);
      expect(find.text('Room 301'), findsNothing);
      await tester.ensureVisible(find.text('Previous defenses (1)'));
      await tester.tap(find.text('Previous defenses (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled concept room'), findsOneWidget);
      expect(find.text('Room 301'), findsNothing);
    },
  );

  for (final variant in ['desktop', 'phone', 'dark']) {
    testWidgets('$variant defense record fits and renders in its theme', (
      tester,
    ) async {
      tester.view.physicalSize = variant == 'phone'
          ? const Size(390, 1050)
          : const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        RepaintBoundary(
          key: const ValueKey('preview'),
          child: ColoredBox(
            color: variant == 'dark'
                ? const Color(0xFF131720)
                : const Color(0xFFF8FAFC),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: TeamDefenseRecordsView(
                  teamId: 7,
                  selectedStage: 'Project Proposal',
                  allowAdviserReview: variant != 'phone',
                  grades: const [
                    {
                      'schedule_id': 19,
                      'status': 'draft',
                      'revision_deadline': '2099-10-25',
                    },
                  ],
                ),
              ),
            ),
          ),
        ),
        theme: variant == 'dark' ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        overrides: [
          teamDefenseProvider.overrideWith(
            () => _Defenses([
              _record(
                19,
                status: 'done',
                progress: 'revisions_pending',
                verdict: 'approved_with_revisions',
                minutes: 'submitted',
              ),
              _record(
                18,
                status: 'done',
                progress: 'completed',
                verdict: 'approved',
                minutes: 'completed',
              ),
            ]),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('preview')),
        'defense_records/$variant',
      );
    });
  }
}
