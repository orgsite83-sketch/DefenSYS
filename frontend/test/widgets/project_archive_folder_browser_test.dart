import 'package:defensys/screens/web/shared/project_archive/components/project_archive_table.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class FolderArchiveNotifier extends ProjectArchiveNotifier {
  @override
  ProjectArchiveState build() => const ProjectArchiveState(
    scope: {'scope': 'pit_lead', 'pit_year_level': '2nd Year'},
    type: 'pit',
    entries: [
      {
        'id': 'pit-1',
        'type': 'pit',
        'team_id': 5,
        'team_name': 'Team Atlas',
        'file_name': 'Atlas.pdf',
        'has_file': true,
        'stage': '2nd Year Expo',
      },
    ],
    folderBrowser: {
      'group_by': 'team',
      'folder_key': '',
      'is_leaf': false,
      'file_count': 1,
      'missing_count': 0,
      'breadcrumbs': [],
      'folders': [
        {
          'key': 'folder-key',
          'title': 'Team Atlas',
          'subtitle': '2026-2027 · 1st Semester · 2nd Year PIT',
          'file_count': 1,
          'missing_count': 0,
        },
      ],
    },
  );
}

class EmptyTermArchiveNotifier extends FolderArchiveNotifier {
  @override
  ProjectArchiveState build() => super.build().copyWith(
    entries: [],
    folderKey: 'semester-key',
    folderBrowser: {
      'is_leaf': false,
      'file_count': 0,
      'breadcrumbs': [
        {'title': '2026-2027', 'key': 'year-key'},
        {'title': '2nd Semester', 'key': 'semester-key'},
      ],
      'folders': [],
    },
  );
}

class LeafFolderArchiveNotifier extends ProjectArchiveNotifier {
  @override
  ProjectArchiveState build() => const ProjectArchiveState(
    scope: {'scope': 'admin'},
    type: 'pit',
    entries: [
      {
        'id': 'pit-doc-1',
        'type': 'pit',
        'team_id': 10,
        'team_name': 'Team CloudPulse',
        'file_name': 'D3 · CampusLostFound.pdf',
        'deliverable_id': 'D3',
        'has_file': true,
        'status': 'Approved',
        'uploaded_by': 'Noel ESTRELLA',
        'academic_year': '2026-2027',
        'semester': '1st Semester',
        'year_level': '2nd Year',
      },
    ],
    folderBrowser: {
      'group_by': 'team',
      'folder_key': 'cloudpulse-key',
      'is_leaf': true,
      'file_count': 1,
      'missing_count': 0,
      'breadcrumbs': [
        {'title': '2026-2027', 'key': 'year-key'},
        {'title': '1st Semester', 'key': 'semester-key'},
        {'title': '2nd Year', 'key': 'year-level-key'},
        {'title': 'Team CloudPulse', 'key': 'cloudpulse-key'},
      ],
      'folders': [],
    },
  );
}

void main() {
  testWidgets('Leaf folder displays file box cards and toggles to table view', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final search = TextEditingController();
    final scroll = ScrollController();
    addTearDown(search.dispose);
    addTearDown(scroll.dispose);

    await pumpDefensysWidget(
      tester,
      Consumer(
        builder: (context, ref, _) => SingleChildScrollView(
          child: ProjectArchiveTable(
            state: ref.watch(projectArchiveProvider),
            searchController: search,
            tableHScrollController: scroll,
            showTableScrollHint: false,
            showAdvancedFilters: false,
            onToggleAdvancedFilters: () {},
            onViewPdf: (_, _) {},
            onDownloadFile: (_, _) {},
            onOverrideStatus: (_) {},
          ),
        ),
      ),
      overrides: [
        projectArchiveProvider.overrideWith(() => LeafFolderArchiveNotifier()),
      ],
    );

    // Group By and Sort controls are accessible outside advanced filters
    expect(find.byKey(const ValueKey('archiveGroupBy')), findsOneWidget);
    expect(find.byKey(const ValueKey('archiveSortOrder')), findsOneWidget);

    // Both toggle buttons exist in leaf folder
    expect(find.byTooltip('Grid view'), findsOneWidget);
    expect(find.byTooltip('List view'), findsOneWidget);

    // In grid view (default), file is shown as clean box card
    expect(find.byKey(const ValueKey('archiveFile_pit-doc-1')), findsOneWidget);
    expect(find.text('D3 · CampusLostFound.pdf'), findsOneWidget);

    // Tapping card opens the File Details popup
    await tester.tap(find.byKey(const ValueKey('archiveFile_pit-doc-1')));
    await tester.pumpAndSettle();
    expect(find.text('Noel ESTRELLA'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Switch to list view (table)
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();

    // In list view, table header and uploader are shown
    expect(find.text('File Name'), findsOneWidget);
    expect(find.text('Academic Year'), findsOneWidget);
    expect(find.text('By Noel ESTRELLA'), findsOneWidget);

    // Switch back to grid view (box cards)
    await tester.tap(find.byTooltip('Grid view'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('archiveFile_pit-doc-1')), findsOneWidget);
  });

  for (final emptyTerm in [false, true]) {
    testWidgets(
      'PIT lead gets folder browser and breadcrumbs (empty term: $emptyTerm)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1500, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final search = TextEditingController();
        final scroll = ScrollController();
        addTearDown(search.dispose);
        addTearDown(scroll.dispose);

        await pumpDefensysWidget(
          tester,
          Consumer(
            builder: (context, ref, _) => SingleChildScrollView(
              child: ProjectArchiveTable(
                state: ref.watch(projectArchiveProvider),
                searchController: search,
                tableHScrollController: scroll,
                showTableScrollHint: false,
                showAdvancedFilters: true,
                onToggleAdvancedFilters: () {},
                onViewPdf: (_, _) {},
                onDownloadFile: (_, _) {},
                onOverrideStatus: (_) {},
              ),
            ),
          ),
          overrides: [
            projectArchiveProvider.overrideWith(
              () => emptyTerm
                  ? EmptyTermArchiveNotifier()
                  : FolderArchiveNotifier(),
            ),
          ],
        );

        expect(find.text('By Team'), findsNothing);
        expect(find.text('By Stage'), findsNothing);
        expect(find.byKey(const ValueKey('archiveGroupBy')), findsOneWidget);
        expect(find.text('Group by Team'), findsOneWidget);
        expect(find.text('2nd Year PIT Archive'), findsOneWidget);
        expect(
          find.text('Team Atlas'),
          emptyTerm ? findsNothing : findsOneWidget,
        );
        if (emptyTerm) {
          expect(find.text('2026-2027'), findsOneWidget);
          expect(find.text('2nd Semester'), findsOneWidget);
          expect(find.text('Back'), findsOneWidget);
        }
        expect(find.byTooltip('Grid view'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
