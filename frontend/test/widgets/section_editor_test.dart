import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/student_teams/components/student_teams_grid.dart';
import 'package:defensys/screens/web/admin/student_teams/dialogs/manage_sections_dialog.dart';
import 'package:defensys/screens/web/admin/student_teams/components/student_teams_toolbar.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/app_theme.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _SectionNotifier extends StudentTeamsNotifier {
  Map<String, dynamic>? saved;
  bool failSave = false;
  bool failLoad = false;
  Completer<bool>? saveGate;
  bool noEditableSections = false;
  int? savedTeamId;
  final loadedTeamIds = <int>[];

  @override
  StudentTeamsState build() => const StudentTeamsState();

  @override
  Future<List<Map<String, dynamic>>> fetchSectionTeams({
    required String level,
    String scope = 'active',
    String? yearLevel,
    String? section,
  }) async => [
    for (var i = 5; i < 13; i++)
      {
        'id': i,
        'section': 'BSIT-4b',
        'year_level': '4th Year',
        'semester_id': 1,
        'is_editable': !noEditableSections,
      },
    for (var i = 15; i < 18; i++)
      {
        'id': i,
        'section': 'BSIT-4C',
        'year_level': '4th Year',
        'semester_id': 1,
        'is_editable': !noEditableSections,
      },
    {'id': 20, 'section': 'Archived section', 'is_editable': false},
    {'id': 21, 'section': '', 'is_editable': true},
  ];

  @override
  Future<Map<String, dynamic>> fetchSectionDetails(int teamId) async {
    loadedTeamIds.add(teamId);
    if (failLoad) throw Exception('Section details unavailable.');
    return {
      'section': teamId == 15 ? 'BSIT-4C' : 'BSIT-4b',
      'system_name': teamId == 15 ? 'Library system' : 'Campus system',
      'project_manager_id': 1,
      'project_manager_name': 'Juan Cruz',
      'year_level': '4th Year',
      'semester_label': '1st Semester 2026-2027',
      'team_count': 8,
      'students': [
        {'id': 1, 'name': 'Juan Cruz', 'username': 'student-1'},
        {'id': 2, 'name': 'Maria Santos', 'username': 'student-2'},
      ],
    };
  }

  @override
  Future<bool> updateSectionDetails(
    int teamId,
    Map<String, dynamic> payload, {
    String? scope,
  }) async {
    savedTeamId = teamId;
    saved = payload;
    if (saveGate != null) return saveGate!.future;
    if (failSave) {
      state = state.copyWith(error: 'A section with this name already exists.');
      return false;
    }
    return true;
  }
}

class _PitSectionNotifier extends _SectionNotifier {
  @override
  Future<List<Map<String, dynamic>>> fetchSectionTeams({
    required String level,
    String scope = 'active',
    String? yearLevel,
    String? section,
  }) async => [
    {
      'id': 50,
      'section': 'BSIT-3A',
      'year_level': '3rd Year',
      'semester_id': 1,
      'is_editable': true,
    },
  ];

  @override
  Future<Map<String, dynamic>> fetchSectionDetails(int teamId) async => {
    'is_pit': true,
    'roster_info': {'needs_selection': true},
    'section': 'BSIT-3A',
    'system_name': 'Agro System',
    'project_manager_id': 1,
    'project_manager_name': 'Juan Cruz',
    'year_level': '3rd Year',
    'semester_label': '1st Semester 2026-2027',
    'team_count': 8,
    'students': [
      {'id': 1, 'name': 'Juan Cruz', 'username': 'student-1'},
    ],
  };
}

void main() {
  Future<void> pumpEditor(
    WidgetTester tester,
    _SectionNotifier notifier, {
    bool dark = false,
    String? preview,
  }) async {
    final search = TextEditingController();
    addTearDown(search.dispose);
    await pumpDefensysWidget(
      tester,
      Builder(
        builder: (context) => RepaintBoundary(
          key: const Key('section-toolbar-preview'),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                StudentTeamsListToolbar(
                  search: StudentTeamsSearchField(
                    controller: search,
                    isSaving: false,
                    isPitContext: false,
                    onSubmitted: (_) {},
                  ),
                  controls: [
                    StudentTeamsLevelFilter(
                      isPitLeadManager: false,
                      isPitInstructor: false,
                      currentLevel: 'Capstone',
                      isSaving: false,
                      onLevelChanged: (_) {},
                    ),
                    ManageSectionsButton(
                      onPressed: () => showManageSectionsDialog(
                        context: context,
                        level: 'Capstone',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GroupedSectionView(
                  state: const StudentTeamsState(
                    teams: [
                      {
                        'id': 5,
                        'name': 'Team One',
                        'section': 'BSIT-4b',
                        'is_editable': true,
                      },
                    ],
                  ),
                  isPit: false,
                  searchQuery: '',
                  onOpenTeamDetail: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
      theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
      overrides: [studentTeamsProvider.overrideWith(() => notifier)],
    );
    expect(find.text('Edit section'), findsNothing);
    if (preview != null) {
      await capturePreview(
        tester,
        find.byKey(const Key('section-toolbar-preview')),
        'section-toolbar-$preview',
      );
    }
    await tester.tap(find.byKey(const Key('manage-sections')));
    await tester.pumpAndSettle();
    if (preview != null) {
      await capturePreview(
        tester,
        find
            .ancestor(
              of: find.byType(ShadDialog),
              matching: find.byType(RepaintBoundary),
            )
            .first,
        'section-manager-$preview',
      );
    }
  }

  testWidgets(
    'central shadcn control opens prefilled editor and saves all details',
    (tester) async {
      final notifier = _SectionNotifier();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPreviewFonts();
      await pumpEditor(tester, notifier, preview: 'light');
      expect(find.byType(ShadDialog), findsOneWidget);
      expect(find.textContaining('all 8 teams'), findsOneWidget);
      expect(find.text('Campus system'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('edit-section-name')),
        'BSIT-4B',
      );
      await tester.enterText(
        find.byKey(const Key('edit-section-system-name')),
        'New campus system',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-section-manager-5-1')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-section-manager-5-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maria Santos (student-2)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-section-details')));
      await tester.pumpAndSettle();
      expect(notifier.saved, {
        'expected_section': 'BSIT-4b',
        'section': 'BSIT-4B',
        'system_name': 'New campus system',
        'project_manager_id': 2,
      });
      expect(notifier.savedTeamId, 5);
      expect(find.byType(ShadDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed save retains edits and cancel leaves data unsaved', (
    tester,
  ) async {
    final notifier = _SectionNotifier()..failSave = true;
    await pumpEditor(tester, notifier);
    await tester.enterText(
      find.byKey(const Key('edit-section-name')),
      'BSIT-4C',
    );
    await tester.tap(find.byKey(const Key('save-section-details')));
    await tester.pumpAndSettle();
    expect(
      find.text('A section with this name already exists.'),
      findsOneWidget,
    );
    expect(find.text('BSIT-4C'), findsOneWidget);
    notifier.saved = null;
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(notifier.saved, isNull);
    expect(find.byType(ShadDialog), findsNothing);
  });

  testWidgets('blank name is rejected before save and failed load can retry', (
    tester,
  ) async {
    final notifier = _SectionNotifier()..failLoad = true;
    await pumpEditor(tester, notifier);
    expect(find.text('Section details unavailable.'), findsOneWidget);
    expect(
      tester
          .widget<ShadButton>(find.byKey(const Key('save-section-details')))
          .onPressed,
      isNull,
    );
    notifier.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-section-name')), ' ');
    await tester.tap(find.byKey(const Key('save-section-details')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a section name.'), findsOneWidget);
    expect(notifier.saved, isNull);
  });

  testWidgets('historical sections have no edit action', (tester) async {
    await pumpDefensysWidget(
      tester,
      GroupedSectionView(
        state: const StudentTeamsState(
          teams: [
            {'id': 5, 'section': 'BSIT-4b', 'is_editable': false},
          ],
        ),
        isPit: false,
        searchQuery: '',
        onOpenTeamDetail: (_) {},
      ),
    );
    expect(find.text('Edit section'), findsNothing);
  });

  testWidgets(
    'short screen keeps save visible and prevents dismissal while saving',
    (tester) async {
      tester.view.physicalSize = const Size(800, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final notifier = _SectionNotifier()..saveGate = Completer<bool>();
      await pumpEditor(tester, notifier, preview: 'compact');
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('save-section-details')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('save-section-details')));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(find.widgetWithText(ShadButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      notifier.saveGate!.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(ShadDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('section selector loads and saves the chosen section', (
    tester,
  ) async {
    final notifier = _SectionNotifier();
    await pumpEditor(tester, notifier);
    await tester.tap(find.byKey(const Key('section-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Archived section'), findsNothing);
    await tester.tap(find.text('BSIT-4C · 4th Year · 3 teams').last);
    await tester.pumpAndSettle();
    expect(find.text('Library system'), findsOneWidget);
    expect(notifier.loadedTeamIds, [5, 15]);
    await tester.tap(find.byKey(const Key('save-section-details')));
    await tester.pumpAndSettle();
    expect(notifier.savedTeamId, 15);
    expect(notifier.saved!['expected_section'], 'BSIT-4C');
  });

  testWidgets('shadcn section manager supports dark mode', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts();
    await pumpEditor(tester, _SectionNotifier(), dark: true, preview: 'dark');
    expect(find.byType(ShadDialog), findsOneWidget);
    expect(find.byType(ShadInputFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching sections protects unsaved edits', (tester) async {
    final notifier = _SectionNotifier();
    await pumpEditor(tester, notifier);
    await tester.enterText(
      find.byKey(const Key('edit-section-name')),
      'BSIT-4D',
    );
    await tester.tap(find.byKey(const Key('section-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BSIT-4C · 4th Year · 3 teams').last);
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('BSIT-4D'), findsOneWidget);
    expect(notifier.loadedTeamIds, [5]);
    await tester.tap(find.byKey(const Key('section-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BSIT-4C · 4th Year · 3 teams').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Library system'), findsOneWidget);
    expect(notifier.loadedTeamIds, [5, 15]);
    expect(notifier.saved, isNull);
  });

  testWidgets(
    'historical and unassigned sections cannot be selected for editing',
    (tester) async {
      final notifier = _SectionNotifier()..noEditableSections = true;
      await pumpEditor(tester, notifier);
      expect(find.textContaining('No editable sections'), findsOneWidget);
      expect(find.byKey(const Key('save-section-details')), findsNothing);
      expect(notifier.loadedTeamIds, isEmpty);
    },
  );

  testWidgets('pit section displays Team Roster card with import callback', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifier = _PitSectionNotifier();
    String? importedSection;
    await pumpDefensysWidget(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showManageSectionsDialog(
            context: context,
            level: 'PIT',
            scope: 'pit',
            onImportSectionRoster: (sec) => importedSection = sec,
          ),
          child: const Text('Open Manage Sections'),
        ),
      ),
      overrides: [studentTeamsProvider.overrideWith(() => notifier)],
    );
    await tester.tap(find.text('Open Manage Sections'));
    await tester.pumpAndSettle();
    expect(find.text('Team Roster'), findsOneWidget);
    expect(find.text('Teams require review before events can be scheduled.'), findsOneWidget);
    expect(find.byKey(const Key('manage-roster-btn')), findsOneWidget);
    expect(find.byKey(const Key('import-roster-btn')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('import-roster-btn')));
    await tester.tap(find.byKey(const Key('import-roster-btn')));
    await tester.pumpAndSettle();
    expect(importedSection, 'BSIT-3A');
    expect(find.byType(ShadDialog), findsNothing);
  });
}
