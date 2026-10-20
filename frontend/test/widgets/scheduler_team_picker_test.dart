import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_team_picker.dart';
import 'package:defensys/theme/app_theme.dart';
import '../helpers/capture_preview.dart';

const pitTeams = [
  {
    'id': 11,
    'name': 'SoilSense',
    'section': 'BSIT-3A',
    'instructors': [
      {'id': 70, 'name': 'Florencia Dela Torre'},
    ],
  },
  {
    'id': 12,
    'name': 'AgriPulse',
    'section': 'BSIT-3A',
    'instructors': [
      {'id': 70, 'name': 'Florencia Dela Torre'},
      {'id': 80, 'name': 'Ramon Cruz'},
    ],
  },
  {
    'id': 13,
    'name': 'CampusLink',
    'section': 'BSIT-3B',
    'instructors': [
      {'id': 80, 'name': 'Ramon Cruz'},
    ],
  },
  {
    'id': 14,
    'name': 'ColdChain',
    'section': 'BSIT-3C',
    'adviser': 999,
    'adviser_name': 'Legacy adviser',
  },
];

Future<void> chooseFilter<T>(
  WidgetTester tester,
  String key,
  String label,
) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(ShadOption<T>), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

bool? selected(WidgetTester tester, int id) => tester
    .widget<CheckboxListTile>(find.byKey(ValueKey('session-team-$id')))
    .value;

Future<void> pumpPitPicker(
  WidgetTester tester, {
  double width = 1280,
  bool dark = false,
  Set<int> initialSelected = const {},
  Map<int, String> assignedElsewhere = const {},
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('team-picker-preview'),
          child: SchedulerTeamPicker(
            teams: pitTeams,
            selected: initialSelected,
            assignedElsewhere: assignedElsewhere,
            sessionNumber: 1,
            scope: 'pit',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPreviewFonts);
  final testTeams = [
    {
      'id': 1,
      'name': 'Team BioPulse',
      'adviser': 10,
      'adviser_name': 'Prof Smith',
      'project_title': 'AI Triage',
      'section': 'CS4A',
    },
    {
      'id': 2,
      'name': 'Team CodeLearners',
      'adviser': 10,
      'adviser_name': 'Prof Smith',
      'project_title': 'Event Hub',
      'section': 'CS4A',
    },
    {
      'id': 3,
      'name': 'Team SafeCity',
      'adviser': 20,
      'adviser_name': 'Prof Jones',
      'project_title': 'Smart City',
      'section': 'CS4B',
    },
  ];

  Widget buildPicker({
    Set<int> initialSelected = const {},
    Map<int, String> assignedElsewhere = const {},
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SchedulerTeamPicker(
          teams: testTeams,
          selected: initialSelected,
          assignedElsewhere: assignedElsewhere,
          sessionNumber: 1,
        ),
      ),
    );
  }

  testWidgets('renders shadcn styled select and clear buttons with icons', (
    tester,
  ) async {
    await tester.pumpWidget(buildPicker());
    await tester.pumpAndSettle();

    final selectButtonFinder = find.byKey(
      const ValueKey('session-select-shown-teams'),
    );
    final clearButtonFinder = find.byKey(
      const ValueKey('session-clear-shown-teams'),
    );

    expect(selectButtonFinder, findsOneWidget);
    expect(clearButtonFinder, findsOneWidget);

    final selectButton = tester.widget<ShadButton>(selectButtonFinder);
    final clearButton = tester.widget<ShadButton>(clearButtonFinder);

    // Both are ShadButton widgets with small size
    expect(selectButton.size, ShadButtonSize.sm);
    expect(clearButton.size, ShadButtonSize.sm);

    // Verify icons
    expect(find.byIcon(LucideIcons.listChecks), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);

    // Initially, select is enabled and clear is disabled (nothing selected)
    expect(selectButton.enabled, isTrue);
    expect(clearButton.enabled, isFalse);

    // Tap "Select shown teams"
    await tester.tap(selectButtonFinder);
    await tester.pumpAndSettle();

    // Now clear button should be enabled
    final clearButtonAfterSelect = tester.widget<ShadButton>(clearButtonFinder);
    expect(clearButtonAfterSelect.enabled, isTrue);

    // Tap "Clear shown teams"
    await tester.tap(clearButtonFinder);
    await tester.pumpAndSettle();

    // Clear button should be disabled again
    final clearButtonAfterClear = tester.widget<ShadButton>(clearButtonFinder);
    expect(clearButtonAfterClear.enabled, isFalse);
  });

  testWidgets('initial selected teams enable the clear button', (tester) async {
    await tester.pumpWidget(buildPicker(initialSelected: {1}));
    await tester.pumpAndSettle();

    final clearButtonFinder = find.byKey(
      const ValueKey('session-clear-shown-teams'),
    );
    final clearButton = tester.widget<ShadButton>(clearButtonFinder);
    expect(clearButton.enabled, isTrue);

    await tester.tap(clearButtonFinder);
    await tester.pumpAndSettle();

    final clearButtonAfterClear = tester.widget<ShadButton>(clearButtonFinder);
    expect(clearButtonAfterClear.enabled, isFalse);
  });

  testWidgets(
    'PIT section and instructor filters intersect and preserve hidden selections',
    (tester) async {
      await pumpPitPicker(tester, initialSelected: {14});
      expect(find.text('All instructors'), findsOneWidget);
      expect(find.text('All advisers'), findsNothing);
      expect(find.textContaining('No adviser'), findsNothing);
      await chooseFilter<String>(tester, 'session-team-section-', 'BSIT-3A');
      expect(find.byKey(const ValueKey('session-team-11')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-team-12')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-team-13')), findsNothing);
      await chooseFilter<int>(
        tester,
        'session-team-instructor-0',
        'Ramon Cruz',
      );
      expect(find.byKey(const ValueKey('session-team-11')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('session-select-shown-teams')),
      );
      await tester.pumpAndSettle();
      expect(selected(tester, 12), isTrue);
      expect(find.text('2 teams selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('session-clear-shown-teams')));
      await tester.pumpAndSettle();
      expect(selected(tester, 12), isFalse);
      await chooseFilter<int>(
        tester,
        'session-team-instructor-80',
        'All instructors',
      );
      await chooseFilter<String>(
        tester,
        'session-team-section-BSIT-3A',
        'All sections',
      );
      expect(selected(tester, 14), isTrue);
    },
  );

  testWidgets(
    'PIT bulk selection excludes other sessions and search includes instructors',
    (tester) async {
      await pumpPitPicker(tester, assignedElsewhere: {12: 'Session 2'});
      await chooseFilter<int>(
        tester,
        'session-team-instructor-0',
        'Ramon Cruz',
      );
      expect(find.byKey(const ValueKey('session-team-11')), findsNothing);
      expect(find.byKey(const ValueKey('session-team-13')), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('session-team-12')),
            )
            .onChanged,
        isNull,
      );
      expect(find.textContaining('Assigned to Session 2'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('session-select-shown-teams')),
      );
      await tester.pumpAndSettle();
      expect(selected(tester, 12), isFalse);
      expect(selected(tester, 13), isTrue);
      await chooseFilter<int>(
        tester,
        'session-team-instructor-80',
        'All instructors',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('session-team-search')),
          matching: find.byType(EditableText),
        ),
        'florencia',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('session-team-11')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-team-13')), findsNothing);
    },
  );

  testWidgets(
    'unassigned PIT instructors never fall back to the adviser field',
    (tester) async {
      await pumpPitPicker(tester);
      await chooseFilter<int>(
        tester,
        'session-team-instructor-0',
        'No instructor assigned',
      );
      expect(find.byKey(const ValueKey('session-team-14')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-team-11')), findsNothing);
      expect(find.textContaining('Legacy adviser'), findsNothing);
      await chooseFilter<String>(tester, 'session-team-section-', 'BSIT-3A');
      expect(
        find.text('No eligible teams match this selection.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('session-select-shown-teams')),
            )
            .enabled,
        isFalse,
      );
    },
  );

  for (final width in [390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'PIT filters fit at $width in ${dark ? 'dark' : 'light'} theme',
        (tester) async {
          await pumpPitPicker(tester, width: width, dark: dark);
          expect(find.text('All sections'), findsOneWidget);
          expect(find.text('All instructors'), findsOneWidget);
          final sectionTop = tester
              .getTopLeft(find.byKey(const ValueKey('session-team-section-')))
              .dy;
          final instructorTop = tester
              .getTopLeft(
                find.byKey(const ValueKey('session-team-instructor-0')),
              )
              .dy;
          expect(
            instructorTop,
            width < 600 ? greaterThan(sectionTop) : sectionTop,
          );
          expect(
            find.textContaining('BSIT-3A · Florencia Dela Torre'),
            findsWidgets,
          );
          await capturePreview(
            tester,
            find.byKey(const ValueKey('team-picker-preview')),
            'pit-team-picker-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
