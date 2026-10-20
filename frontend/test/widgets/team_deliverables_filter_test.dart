import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_filter_bar.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_status_filter.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _team(
  int id,
  String status, {
  Map<String, dynamic>? stage,
}) => {
  'id': id,
  'current_stage': 'Old stage',
  'stages': [
    {'stage_label': 'Old stage', 'status': 'passed'},
  ],
  'selected_stage': {
    'stage_label': 'Concept Proposal',
    'deliverables_configured': true,
    'stage_status_detail': status,
    ...?stage,
  },
};

class _Filters extends CapstoneDeliverablesNotifier {
  final CapstoneDeliverablesState initial;
  final requests = <(String?, String?)>[];
  _Filters(this.initial);

  @override
  CapstoneDeliverablesState build() => initial;

  void replaceTeams(List<Map<String, dynamic>> teams) {
    state = state.copyWith(teams: teams);
  }

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
  }) async {
    requests.add((search, status));
    state = state.copyWith(
      search: search,
      status: status,
      selectedStage: selectedStage,
    );
  }
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  testWidgets('the grouped status panel is bounded and closes with Escape', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const previewKey = ValueKey('status-panel-preview');
    await tester.pumpWidget(RepaintBoundary(
      key: previewKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: Scaffold(body: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(width: 280, child: DeliverablesStatusFilter(
              value: TeamTriageFilter.all,
              counts: DeliverablesTriageHelper.computeCounts([_team(1, 'scheduled')]),
              isPit: false,
              onChanged: (_) {},
            )),
          ),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    final picker = find.byType(ShadSelect<TeamTriageFilter>);
    final options = tester.widget<ShadSelect<TeamTriageFilter>>(picker).options!
      .whereType<ShadOption<TeamTriageFilter>>().map((option) => option.value).toList();
    expect(options.toSet(), TeamTriageFilter.values.toSet());
    expect(options.length, TeamTriageFilter.values.length);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await capturePreview(tester, find.byKey(previewKey), 'team-status-panel');
    await tester.enterText(find.byType(EditableText).last, 'archive');
    await tester.pumpAndSettle();
    expect(find.text('Archive review (0)'), findsOneWidget);
    expect(find.text('Archived (0)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Archive review (0)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'lifecycle filters use the selected stage and include later workflow states',
    () {
      final teams = [
        _team(1, 'scheduled'),
        _team(2, 'awaiting_evaluation'),
        _team(3, 'defense_ongoing'),
        _team(4, 'awaiting_verdict'),
        _team(5, 'grading_incomplete'),
        _team(6, 'awaiting_results'),
        _team(7, 'awaiting_completion'),
        _team(8, 'pending_post_defense'),
        _team(9, 'revisions_pending'),
        _team(10, 'for_redefense'),
        _team(11, 'completed'),
        _team(12, 'passed'),
        _team(13, 'postponed'),
        _team(14, 'no_show'),
        _team(15, 'cancelled'),
        _team(16, 'archived'),
        _team(17, 'failed'),
      ];
      final counts = DeliverablesTriageHelper.computeCounts(teams);
      expect(counts[TeamTriageFilter.all], 17);
      for (final filter in [
        TeamTriageFilter.scheduled,
        TeamTriageFilter.awaitingEvaluation,
        TeamTriageFilter.evaluating,
        TeamTriageFilter.awaitingVerdict,
        TeamTriageFilter.gradingIncomplete,
        TeamTriageFilter.awaitingResults,
        TeamTriageFilter.awaitingCompletion,
        TeamTriageFilter.pendingPostDefense,
        TeamTriageFilter.revisionsPending,
        TeamTriageFilter.redefenseRequired,
        TeamTriageFilter.postponed,
        TeamTriageFilter.noShow,
        TeamTriageFilter.cancelled,
        TeamTriageFilter.archived,
        TeamTriageFilter.failed,
      ]) {
        expect(counts[filter], 1, reason: filter.name);
      }
      expect(counts[TeamTriageFilter.completed], 2);
    },
  );

  test(
    'file review and archive clearance take precedence over recorded completion',
    () {
      final counts = DeliverablesTriageHelper.computeCounts([
        _team(
          1,
          'scheduled',
          stage: {
            'pre': [
              {
                'required': true,
                'uploaded': true,
                'submission': {'status': 'pending'},
              },
            ],
          },
        ),
        _team(2, 'completed', stage: {'archive_complete': false}),
        _team(
          3,
          'completed',
          stage: {
            'post': [
              {
                'type': 'post',
                'required': true,
                'uploaded': true,
                'submission': {'status': 'pending'},
              },
            ],
          },
        ),
      ]);
      expect(counts[TeamTriageFilter.needsReview], 1);
      expect(counts[TeamTriageFilter.scheduled], 0);
      expect(counts[TeamTriageFilter.pendingPostDefense], 1);
      expect(counts[TeamTriageFilter.archiveReviewPending], 1);
      expect(counts[TeamTriageFilter.completed], 0);
    },
  );

  for (final width in [1280.0, 720.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('visible filters update and clear at $width, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final notifier = _Filters(
          CapstoneDeliverablesState(
            selectedStage: 'Concept Proposal',
            stageOptions: const ['Concept Proposal', 'Final Defense'],
            teams: [_team(1, 'scheduled'), _team(2, 'awaiting_verdict')],
          ),
        );
        var selected = TeamTriageFilter.all;
        const previewKey = ValueKey('filters-preview');
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: previewKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) => Consumer(
                  builder: (context, ref, _) => DeliverablesFilterBar(
                    state: ref.watch(capstoneDeliverablesProvider),
                    searchController: controller,
                    isAdviser: true,
                    activeTriageFilter: selected,
                    onTriageFilterChanged: (filter) =>
                        setState(() => selected = filter),
                  ),
                ),
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [
            capstoneDeliverablesProvider.overrideWith(() => notifier),
          ],
        );
        expect(find.byType(ExpansionTile), findsNothing);
        expect(find.text('Search & team filters'), findsNothing);
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        expect(find.text('Scheduled (1)'), findsNothing);
        expect(find.text('Changes requested (0)'), findsNothing);
        final picker = find.byType(ShadSelect<TeamTriageFilter>);
        expect(
          tester.widget<ShadSelect<TeamTriageFilter>>(picker).maxHeight,
          400,
        );
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        expect(find.text('Requirements'), findsOneWidget);
        await tester.enterText(find.byType(EditableText).last, 'scheduled');
        await tester.pumpAndSettle();
        expect(find.text('Defense'), findsOneWidget);
        await tester.tap(find.text('Scheduled (1)'));
        await tester.pumpAndSettle();
        expect(selected, TeamTriageFilter.scheduled);

        notifier.replaceTeams([
          _team(1, 'completed'),
          _team(2, 'awaiting_verdict'),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Scheduled (0)'), findsOneWidget);
        expect(find.text('Completed / Passed (1)'), findsNothing);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(EditableText).last,
          'unrecognized status',
        );
        await tester.pumpAndSettle();
        expect(find.text('No matching statuses'), findsOneWidget);
        await tester.enterText(find.byType(EditableText).last, 'completed');
        await tester.pumpAndSettle();
        expect(find.text('Post-defense / Outcomes'), findsOneWidget);
        await tester.tap(find.text('Completed / Passed (1)'));
        await tester.pumpAndSettle();
        expect(selected, TeamTriageFilter.completed);
        await capturePreview(
          tester,
          find.byKey(previewKey),
          'team-filters-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );

        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'pending search');
        await tester.ensureVisible(find.text('Clear Filters'));
        await tester.tap(find.text('Clear Filters'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 600));
        expect(selected, TeamTriageFilter.all);
        expect(controller.text, isEmpty);
        expect(notifier.requests, [('', '')]);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
