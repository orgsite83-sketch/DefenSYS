import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/academic_periods/academic_periods_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/admin/user_management_provider.dart';
import 'package:defensys/screens/web/admin/academic_periods/semester_detail_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:toastification/toastification.dart';

import '../helpers/capture_preview.dart';

class _FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() {
    return const AcademicPeriodState(
      isLoading: false,
      schoolYears: [
        {
          'id': 1,
          'label': '2026-2027',
          'semesters': [
            {
              'id': 10,
              'label': '1st Semester',
              'is_active': true,
              'capstone_program_phase': 'capstone_2',
              'capstone_team_creation_enabled': false,
              'capstone_peer_evaluation_enabled': true,
              'capstone_adviser_grading_enabled': true,
            },
            {
              'id': 11,
              'label': '2nd Semester',
              'is_active': false,
              'capstone_program_phase': 'capstone_1',
              'capstone_team_creation_enabled': true,
              'capstone_peer_evaluation_enabled': false,
              'capstone_adviser_grading_enabled': false,
            },
          ],
        },
        {
          'id': 2,
          'label': '2025-2026',
          'semesters': [
            {'id': 9, 'label': '1st Semester', 'is_active': false},
          ],
        },
      ],
      selectedSchoolYearId: 1,
      activeSemester: {
        'id': 10,
        'school_year_id': 1,
        'display_name': '1st Semester, A.Y. 2026-2027',
        'capstone_program_phase': 'capstone_2',
        'capstone_team_creation_enabled': false,
        'capstone_peer_evaluation_enabled': true,
        'capstone_adviser_grading_enabled': true,
      },
    );
  }

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}

  Map<String, dynamic>? evaluationUpdate;

  @override
  Future<bool> updateSemesterEvaluationSettings(
    int semesterId, {
    bool? peerEvaluationEnabled,
    bool? adviserGradingEnabled,
  }) async {
    evaluationUpdate = {
      'semester_id': semesterId,
      if (peerEvaluationEnabled != null) 'peer': peerEvaluationEnabled,
      if (adviserGradingEnabled != null) 'adviser': adviserGradingEnabled,
    };
    state = state.copyWith(
      schoolYears: [
        for (final year in state.schoolYears)
          {
            ...year,
            'semesters': [
              for (final semester in year['semesters'] as List)
                if (semester['id'] == semesterId)
                  {
                    ...semester as Map<String, dynamic>,
                    if (peerEvaluationEnabled != null)
                      'capstone_peer_evaluation_enabled': peerEvaluationEnabled,
                    if (adviserGradingEnabled != null)
                      'capstone_adviser_grading_enabled': adviserGradingEnabled,
                  }
                else
                  semester,
            ],
          },
      ],
    );
    return true;
  }
}

class _FakeDefenseStagesNotifier extends DefenseStagesNotifier {
  @override
  DefenseStagesState build() {
    return const DefenseStagesState(
      isLoading: false,
      stages: [
        {
          'id': 1,
          'label': 'Title Proposal',
          'description': 'Topic and concept defense',
          'is_presentation_only': true,
        },
        {
          'id': 2,
          'label': 'Outline Defense',
          'description': 'Chapters 1-3 manuscript review',
          'is_presentation_only': false,
        },
        {
          'id': 3,
          'label': 'Final Defense',
          'description': 'Full system demo and manuscript',
          'is_presentation_only': false,
        },
      ],
    );
  }

  @override
  Future<void> fetchStages({
    String? scope,
    String? intake,
    String? phase,
    String? stage,
    String? successMessage,
  }) async {}
}

class _FakeUserManagementNotifier extends UserManagementNotifier {
  @override
  UserManagementState build() {
    return const UserManagementState(
      isLoading: false,
      users: [
        {
          'id': 101,
          'name': 'Prof. Alan Turing',
          'email': 'aturing@university.edu',
          'is_pit_lead': true,
          'pit_lead_year': '1st Year',
        },
      ],
    );
  }

  @override
  Future<void> fetchUsers({
    String? search,
    String? role,
    String? successMessage,
  }) async {}
}

class _EmptyDefenseStagesNotifier extends _FakeDefenseStagesNotifier {
  @override
  DefenseStagesState build() => const DefenseStagesState();
}

class _FakeDefenseSchedulerNotifier extends DefenseSchedulerNotifier {
  Map<String, dynamic>? savedPayload;
  bool saveSucceeds = true;
  final List<Map<String, dynamic>> _configs = [
    {
      'id': 201,
      'event_name': 'CS 101 Concept Pitch',
      'panel_weight': 80,
      'peer_weight': 20,
      'peer_grading_enabled': true,
      'is_locked': false,
    },
    {
      'id': 202,
      'event_name': 'CS 201 Architecture Demo',
      'panel_weight': 80,
      'peer_weight': 20,
      'peer_grading_enabled': false,
      'is_locked': true,
      'lock_reason': 'Defenses already scheduled for sophomore cohort',
    },
  ];

  @override
  DefenseSchedulerState build() {
    return const DefenseSchedulerState();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPitEventConfigs({
    int? semesterId,
    void Function(List<Map<String, dynamic>>)? onHistorySemesters,
  }) async {
    return _configs;
  }

  @override
  Future<bool> savePitEventConfig(Map<String, dynamic> payload) async {
    savedPayload = payload;
    return saveSucceeds;
  }
}

void main() {
  tearDown(() => toastification.dismissAll(delayForAnimation: false));
  testWidgets(
    'AcademicPeriod Redesign: Accordion renders and drill-down into SemesterDetailScreen shows Capstone and PIT tabs',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            academicPeriodProvider.overrideWith(
              _FakeAcademicPeriodNotifier.new,
            ),
            defenseStagesProvider.overrideWith(_FakeDefenseStagesNotifier.new),
            userManagementProvider.overrideWith(
              _FakeUserManagementNotifier.new,
            ),
            defenseSchedulerProvider.overrideWith(
              _FakeDefenseSchedulerNotifier.new,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.mistDarkTheme,
            home: const Scaffold(body: AcademicPeriodsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify Level 1 Hub: Accordion School Years are present
      expect(find.text('A.Y. 2026-2027'), findsOneWidget);
      expect(find.text('A.Y. 2025-2026'), findsOneWidget);
      expect(find.textContaining('Current school year'), findsOneWidget);

      // 2. Verify that active A.Y. 2026-2027 is expanded and shows its terms
      expect(find.text('1st Semester'), findsWidgets);
      expect(find.text('2nd Semester'), findsWidgets);

      // Inactive semesters use the same destination without claiming to be upcoming.
      await tester.tap(find.text('Open semester').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Upcoming'), findsNothing);
      expect(find.text('Set as Active Semester'), findsOneWidget);
      await tester.tap(find.text('Back to academic periods'));
      await tester.pumpAndSettle();
      expect(find.text('Open semester'), findsNWidgets(2));
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Capstone 2 · Continuation'), findsOneWidget);
      expect(find.text('PIT'), findsWidgets);

      // Keep manually expanded years when opening a semester and returning.
      await tester.tap(find.text('A.Y. 2025-2026'));
      await tester.pumpAndSettle();
      expect(find.text('Open semester'), findsNWidgets(3));

      // 3. Tap "Open semester" button on 1st Semester to open SemesterDetailScreen
      final manageButtons = find.text('Open semester');
      expect(manageButtons, findsWidgets);
      await tester.tap(manageButtons.first);
      await tester.pumpAndSettle();

      // 4. Verify SemesterDetailScreen Command Center is loaded
      expect(find.text('Back to academic periods'), findsOneWidget);
      expect(find.text('Capstone'), findsOneWidget);
      expect(find.text('PIT'), findsOneWidget);
      expect(find.text('General settings'), findsOneWidget);

      // 5. In Capstone Tab (default selected): verify policies and defense stages pipeline
      expect(find.text('Capstone this semester'), findsOneWidget);
      expect(find.text('Course'), findsOneWidget);
      expect(find.text('Capstone 2'), findsOneWidget);
      expect(find.text('Continuing teams only'), findsOneWidget);
      expect(find.text('Evaluation access'), findsOneWidget);
      expect(find.text('Defense stages'), findsOneWidget);
      expect(find.text('Title Proposal'), findsOneWidget);
      expect(find.text('Outline Defense'), findsOneWidget);
      expect(find.text('Final Defense'), findsOneWidget);

      // 6. Switch to the PIT tab
      await tester.tap(find.text('PIT'));
      await tester.pumpAndSettle();

      expect(find.text('Year coordinators & events'), findsOneWidget);
      expect(find.text('1st Year'), findsOneWidget);
      expect(find.text('2nd Year'), findsOneWidget);
      expect(find.text('3rd Year'), findsOneWidget);
      expect(find.text('No events configured'), findsOneWidget);

      // Verify Assigned Coordinator for 1st Year (Prof. Alan Turing)
      expect(find.text('Prof. Alan Turing'), findsOneWidget);

      // Verify Unassigned Coordinator prompt for cohorts without assigned lead
      expect(find.text('Assign lead'), findsNWidgets(2));

      await tester.tap(find.text('View events · 1st Year'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View events · 2nd Year'));
      await tester.pumpAndSettle();

      // Verify Configured PIT Events for cohorts
      expect(find.text('CS 101 Concept Pitch'), findsOneWidget);
      expect(find.text('CS 201 Architecture Demo'), findsOneWidget);
      expect(find.text('Settings locked'), findsOneWidget);
      expect(find.text('Panel 80% · Peer 20%'), findsNWidgets(2));

      // Verify interactive Peer Evaluation switches
      final peerSwitch = find.byKey(const ValueKey('pit-peer-201'));
      final lockedSwitch = tester.widget<ShadSwitch>(
        find.byKey(const ValueKey('pit-peer-202')),
      );
      expect(lockedSwitch.enabled, isFalse);

      // Tap peer evaluation toggle on 1st event
      await tester.ensureVisible(peerSwitch);
      await tester.tap(peerSwitch);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SemesterDetailScreen)),
      );
      final scheduler =
          container.read(defenseSchedulerProvider.notifier)
              as _FakeDefenseSchedulerNotifier;
      expect(scheduler.savedPayload, containsPair('semester_id', 10));
      expect(
        scheduler.savedPayload,
        containsPair('peer_grading_enabled', false),
      );
      scheduler.saveSucceeds = false;
      await tester.tap(peerSwitch);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ShadSwitch>(peerSwitch).value,
        isFalse,
        reason: 'A failed save must restore the previous event access setting.',
      );
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      // 7. Switch to Semester settings
      await tester.ensureVisible(find.text('General settings'));
      await tester.tap(find.text('General settings'));
      await tester.pumpAndSettle();

      expect(find.text('Semester details'), findsOneWidget);
      await tester.tap(find.text('Advanced settings'));
      await tester.pumpAndSettle();
      expect(
        find.text('The active semester cannot be deleted.'),
        findsOneWidget,
      );
      final delete = tester.widget<ShadButton>(
        find.widgetWithText(ShadButton, 'Delete semester'),
      );
      expect(delete.enabled, isFalse);

      // 8. Test Back Button returns to Academic Cycles Hub
      await tester.tap(find.text('Back to academic periods'));
      await tester.pumpAndSettle();

      expect(find.text('A.Y. 2026-2027'), findsOneWidget);
      expect(find.text('Academic periods'), findsOneWidget);
      expect(find.text('Open semester'), findsNWidgets(3));

      // Restore the older year's collapsed state for the row-action checks.
      await tester.tap(find.text('A.Y. 2025-2026'));
      await tester.pumpAndSettle();

      // 9. Verify [ ··· ] More Options popup menu on semester rows
      final moreOptionsButtons = find.byTooltip('More options');
      expect(moreOptionsButtons, findsWidgets);

      // Tap more options on the 2nd Semester (inactive term, index 1)
      await tester.tap(moreOptionsButtons.at(1));
      await tester.pumpAndSettle();

      expect(find.text('Set as Active Semester'), findsOneWidget);
      expect(find.text('Delete Semester'), findsOneWidget);

      // Dismiss menu
      await tester.tapAt(const Offset(50, 50));
      await tester.pumpAndSettle();

      // 10. Test Collapsing (Minimizing) the School Year Card
      // Tap on the header of A.Y. 2026-2027 to collapse it
      await tester.tap(find.text('A.Y. 2026-2027'));
      await tester.pumpAndSettle();

      // The terms table under A.Y. 2026-2027 should now be collapsed/minimized
      expect(find.text('1st Semester'), findsNothing);
      expect(find.text('2nd Semester'), findsNothing);

      // Tap on the header again to expand it back
      await tester.tap(find.text('A.Y. 2026-2027'));
      await tester.pumpAndSettle();

      // The terms table should be visible again
      expect(find.text('1st Semester'), findsWidgets);
      expect(find.text('2nd Semester'), findsWidgets);
    },
  );

  testWidgets('Capstone 1 explains adding teams and offers defense setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts(force: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academicPeriodProvider.overrideWith(_FakeAcademicPeriodNotifier.new),
          defenseStagesProvider.overrideWith(_EmptyDefenseStagesNotifier.new),
          userManagementProvider.overrideWith(_FakeUserManagementNotifier.new),
          defenseSchedulerProvider.overrideWith(
            _FakeDefenseSchedulerNotifier.new,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const SemesterDetailScreen(semesterId: 11),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Course'), findsOneWidget);
    expect(find.text('Capstone 1'), findsOneWidget);
    expect(find.text('Allowed'), findsOneWidget);
    expect(
      find.text('Create or import teams in Student Teams.'),
      findsOneWidget,
    );
    expect(find.text('Not configured'), findsOneWidget);
    expect(find.text('Configure stages'), findsOneWidget);
    await capturePreview(
      tester,
      find.byType(SemesterDetailScreen),
      'semester-setup-capstone-intake-refined-light',
      viewport: true,
    );
    await tester.tap(find.text('Continuing to Capstone 2'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'You’ll review which teams can continue to Capstone 2 before activating the next semester.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Semester setup keeps controls usable across widths and themes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await loadPreviewFonts(force: true);
    for (final config in [
      (1280.0, false, 1.0),
      (1280.0, true, 1.0),
      (600.0, false, 1.0),
      (320.0, false, 1.25),
      (320.0, true, 1.25),
    ]) {
      final (width, dark, scale) = config;
      tester.view.physicalSize = Size(width, 1100);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            academicPeriodProvider.overrideWith(
              _FakeAcademicPeriodNotifier.new,
            ),
            defenseStagesProvider.overrideWith(_FakeDefenseStagesNotifier.new),
            userManagementProvider.overrideWith(
              _FakeUserManagementNotifier.new,
            ),
            defenseSchedulerProvider.overrideWith(
              _FakeDefenseSchedulerNotifier.new,
            ),
          ],
          child: MaterialApp(
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const SemesterDetailScreen(semesterId: 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SemesterDetailScreen)),
      );
      final peerAccess = find.byKey(const ValueKey('capstone-peer-access'));
      await tester.ensureVisible(peerAccess);
      await tester.tap(peerAccess);
      await tester.pumpAndSettle();
      expect(
        (container.read(academicPeriodProvider.notifier)
                as _FakeAcademicPeriodNotifier)
            .evaluationUpdate,
        {'semester_id': 10, 'peer': false},
      );
      expect(tester.widget<ShadSwitch>(peerAccess).value, isFalse);
      for (final tab in ['Capstone', 'PIT', 'General settings']) {
        await tester.ensureVisible(find.text(tab));
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        if (tab == 'PIT') {
          await tester.ensureVisible(find.text('View events · 1st Year'));
          await tester.tap(find.text('View events · 1st Year'));
          await tester.pumpAndSettle();
          expect(find.text('CS 101 Concept Pitch'), findsOneWidget);
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '$tab / width=$width / dark=$dark / scale=$scale',
        );
        await tester.ensureVisible(find.text('Back to academic periods'));
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byType(SemesterDetailScreen),
          'semester-setup-${tab.split(' ').first.toLowerCase()}-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
