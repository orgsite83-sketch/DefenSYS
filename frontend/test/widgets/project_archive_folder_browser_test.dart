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

void main() {
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
