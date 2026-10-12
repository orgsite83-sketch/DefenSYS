import 'package:defensys/screens/web/shared/project_archive/components/project_archive_table.dart';
import 'package:defensys/screens/web/shared/project_archive/dialogs/archive_resubmission_dialog.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

const historicalRemarks =
    'Remarks by admin (Admin): Unlocked for file replacement by Admin';

class MenuArchiveNotifier extends ProjectArchiveNotifier {
  MenuArchiveNotifier(this.entry);
  final Map<String, dynamic> entry;

  @override
  ProjectArchiveState build() => ProjectArchiveState(
    scope: const {'scope': 'admin'},
    deliverableId: 'D1',
    entries: [entry],
  );

  @override
  Future<bool> cancelFileReplacement(
    String entryId, {
    required String reason,
  }) async {
    state = state.copyWith(
      entries: [
        {
          ...state.entries.single,
          'file_replacement_unlocked': false,
          'file_replacement_reason': '',
        },
      ],
    );
    return true;
  }
}

Future<void> showTable(
  WidgetTester tester,
  MenuArchiveNotifier notifier,
) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final search = TextEditingController();
  final horizontalScroll = ScrollController();
  addTearDown(search.dispose);
  addTearDown(horizontalScroll.dispose);
  await loadPreviewFonts(force: true);
  await pumpDefensysWidget(
    tester,
    Consumer(
      builder: (context, ref, _) => SingleChildScrollView(
        child: ProjectArchiveTable(
          state: ref.watch(projectArchiveProvider),
          searchController: search,
          tableHScrollController: horizontalScroll,
          showTableScrollHint: false,
          showAdvancedFilters: false,
          onToggleAdvancedFilters: () {},
          onViewPdf: (_, _) {},
          onDownloadFile: (_, _) {},
          onOverrideStatus: (entry) =>
              ArchiveResubmissionDialog.showResubmissionDialog(
                context: context,
                ref: ref,
                entry: entry,
              ),
        ),
      ),
    ),
    overrides: [projectArchiveProvider.overrideWith(() => notifier)],
  );
}

Map<String, dynamic> archiveEntry({
  bool? unlocked,
  String status = 'Approved',
}) => {
  'id': 'capstone-1-2',
  'file_name': 'Claveria.pdf',
  'file_url': '/media/Claveria.pdf',
  'has_file': true,
  'can_override': true,
  'team_id': 1,
  'team_name': 'Team AgriSense',
  'type': 'capstone', 'stage': 'Concept Proposal', 'deliverable_type': 'pre',
  'status': status, 'feedback': historicalRemarks,
  // These broad upload flags are not a Choice B permission.
  'archive_unlocked': true, 'unlocked': true,
  if (unlocked != null) 'file_replacement_unlocked': unlocked,
};

void main() {
  testWidgets(
    'canceling Choice B restores the original archive menu despite historical remarks',
    (tester) async {
      final notifier = MenuArchiveNotifier(archiveEntry(unlocked: true));
      await showTable(tester, notifier);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Manage File Access'), findsOneWidget);
      await tester.tap(find.text('Manage File Access'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fileReplacementReason')),
        'The original form is correct.',
      );
      final cancel = find.byKey(const ValueKey('cancelFileReplacement'));
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Request Resubmission / Replace'), findsOneWidget);
      expect(find.text('Manage File Access'), findsNothing);
      expect(find.text('Download File'), findsOneWidget);
      expect(notifier.state.entries.single['feedback'], historicalRemarks);
      expect(tester.takeException(), isNull);
    },
  );

  for (final unlocked in [false, null]) {
    testWidgets(
      'remarks and broad upload grants cannot show an active replacement menu (flag: $unlocked)',
      (tester) async {
        await showTable(
          tester,
          MenuArchiveNotifier(archiveEntry(unlocked: unlocked)),
        );
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        expect(find.text('Request Resubmission / Replace'), findsOneWidget);
        expect(find.text('Manage File Access'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
