import 'package:defensys/screens/app/student/student_deliverables_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/defense_material_readiness.dart';
import 'package:defensys/widgets/repository/deliverable_timing_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _readiness({bool overdue = false}) => {
  'required_total': 1,
  'submitted_total': 0,
  'status': overdue ? 'overdue' : 'pending',
  'items': [
    {
      'id': 'DECK',
      'label': 'Pitch deck',
      'due_at': '2030-11-19T09:00:00+08:00',
    },
  ],
};

class _MaterialsNotifier extends CapstoneDeliverablesNotifier {
  _MaterialsNotifier({
    this.closed = false,
    this.pitAutoEligible = false,
    this.awaitingSchedule = false,
  });
  final bool closed;
  final bool pitAutoEligible;
  final bool awaitingSchedule;

  @override
  CapstoneDeliverablesState build() {
    final pre = [
      <String, dynamic>{
        'id': 'PAPER',
        'label': 'Concept paper',
        'type': 'pre',
        'required': true,
        'uploaded': true,
        'can_upload': false,
        'locked': true,
        'requirement_timing': 'scheduling',
        'submission': {
          'id': 1,
          'status': 'accepted',
          'file_name': 'paper.pdf',
          'files': [],
        },
      },
      <String, dynamic>{
        'id': 'DECK',
        'label': 'Pitch deck',
        'type': 'pre',
        'required': true,
        'uploaded': false,
        'can_upload': !closed,
        'locked': closed,
        'requirement_timing': 'defense',
        'due_at': awaitingSchedule ? null : '2030-11-19T09:00:00+08:00',
        'file_format': 'presentation',
        'materials_submitted': false,
        'materials_status': awaitingSchedule ? 'awaiting_schedule' : 'pending',
        'upload_lock_reason': closed
            ? 'The submission deadline has passed. Ask an administrator to extend it.'
            : '',
      },
    ];
    final visiblePre = pitAutoEligible ? [pre.last] : pre;
    final stage = <String, dynamic>{
      'stage_label': 'Concept Proposal',
      'endorsed': !pitAutoEligible,
      'endorsement_required': !pitAutoEligible,
      'deliverables_configured': true,
      'required_complete': true,
      'required_total': pitAutoEligible ? 0 : 1,
      'required_uploaded': pitAutoEligible ? 0 : 1,
      'pre': visiblePre,
      'deliverables': visiblePre,
      'post': [],
      'materials_readiness': awaitingSchedule
          ? {
              'required_total': 1,
              'submitted_total': 0,
              'status': 'awaiting_schedule',
              'items': [
                {'id': 'DECK', 'label': 'Pitch deck', 'due_at': null},
              ],
            }
          : _readiness(overdue: closed),
    };
    return CapstoneDeliverablesState(
      selectedStage: 'Concept Proposal',
      stageOptions: const ['Concept Proposal'],
      teams: [
        {'id': 7, 'name': 'Team SafeCity', 'selected_stage': stage},
      ],
    );
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
  }) async {}
}

void main() {
  testWidgets(
    'defense material highlights timing without changing the due rule',
    (tester) async {
      tester.view.physicalSize = const Size(420, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPreviewFonts();
      var timing = 'scheduling';
      var material = false;
      var hours = 24;
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, update) => RepaintBoundary(
            key: const ValueKey('defense-material-timing-preview'),
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DefenseMaterialToggle(
                      value: material,
                      onChanged: (value) => update(() => material = value),
                    ),
                    const SizedBox(height: 8),
                    DeliverableTimingFields(
                      timing: timing,
                      hoursBefore: hours,
                      showTimingChoices: true,
                      isDefenseMaterial: material,
                      onTimingChanged: (value) => update(() => timing = value),
                      onHoursChanged: (value) => update(() => hours = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Before endorsement'), findsOneWidget);
      expect(find.text('Before scheduled defense'), findsOneWidget);
      expect(find.text('Submission deadline'), findsNothing);
      expect(
        find.byTooltip(
          'Panelists use this file during oral defense. Marking it as defense material does not change its due time.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Defense material for panelists'));
      await tester.pumpAndSettle();
      expect(material, true);
      expect(timing, 'scheduling');

      await tester.tap(find.text('Before scheduled defense'));
      await tester.pumpAndSettle();
      expect(timing, 'defense');
      expect(material, true);
      expect(find.text('How long before defense?'), findsOneWidget);
      await tester.tap(find.text('48 hours'));
      await tester.pumpAndSettle();
      expect(hours, 48);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('stage-custom-deadline-hours')),
        '36',
      );
      await tester.pumpAndSettle();
      expect(hours, 36);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('defense-material-timing-preview')),
        'defense-material-timing-choices',
      );
      await tester.enterText(
        find.byKey(const ValueKey('stage-custom-deadline-hours')),
        '721',
      );
      await tester.pumpAndSettle();
      expect(hours, 36);
      expect(find.text('Enter 0 to 720 hours.'), findsOneWidget);

      await tester.tap(find.text('Defense material for panelists'));
      await tester.pumpAndSettle();
      expect(material, false);
      final ex = tester.takeException();
      if (ex is FlutterError) {
        FlutterError.dumpErrorToConsole(
          FlutterErrorDetails(
            exception: ex,
            stack: StackTrace.current,
          ),
        );
      }
      expect(ex, isNull);
    },
  );

  testWidgets(
    'admin can move a required deliverable to a later defense deadline',
    (tester) async {
      var timing = 'scheduling';
      var hours = 24;
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, update) => Padding(
            padding: const EdgeInsets.all(16),
            child: DeliverableTimingFields(
              timing: timing,
              hoursBefore: hours,
              onTimingChanged: (value) => update(() => timing = value),
              onHoursChanged: (value) => update(() => hours = value),
            ),
          ),
        ),
      );
      expect(find.text('Submission deadline'), findsNothing);
      await tester.tap(find.text('Before endorsement / scheduling'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Before scheduled defense').last);
      await tester.pumpAndSettle();
      expect(timing, 'defense');
      expect(find.text('Submission deadline'), findsOneWidget);
      await tester.tap(find.text('24 hours before defense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('48 hours before defense').last);
      await tester.pumpAndSettle();
      expect(hours, 48);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('locked timing remains visible but cannot be changed', (
    tester,
  ) async {
    var timing = 'scheduling';
    await pumpDefensysWidget(
      tester,
      DeliverableTimingFields(
        timing: timing,
        hoursBefore: 24,
        enabled: false,
        showTimingChoices: true,
        onTimingChanged: (value) => timing = value,
        onHoursChanged: (_) {},
      ),
    );
    expect(find.text('Before scheduled defense'), findsOneWidget);
    await tester.tap(find.text('Before scheduled defense'));
    await tester.pumpAndSettle();
    expect(timing, 'scheduling');
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'overdue readiness stays readable at 360px in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts();
        await pumpDefensysWidget(
          tester,
          Builder(
            builder: (context) => RepaintBoundary(
              key: const ValueKey('timing-preview'),
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      DefenseMaterialReadiness(
                        readiness: _readiness(overdue: true),
                      ),
                      DeliverableTimingFields(
                        timing: 'defense',
                        hoursBefore: 24,
                        onTimingChanged: (_) {},
                        onHoursChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(
          find.text('Defense files · 0/1 uploaded · Deadline passed'),
          findsOneWidget,
        );
        expect(
          find.textContaining('An administrator can extend'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('timing-preview')),
          'submission-timing-${dark ? 'dark' : 'light'}',
        );
      },
    );
  }

  for (final closed in [false, true]) {
    testWidgets(
      'endorsed student ${closed ? 'sees an overdue locked deck' : 'can upload a pending deck'}',
      (tester) async {
        tester.view.physicalSize = const Size(440, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpDefensysWidget(
          tester,
          const StudentDeliverablesTab(
            isCapstone: true,
            studentData: null,
            hideHeader: true,
          ),
          overrides: [
            capstoneDeliverablesProvider.overrideWith(
              () => _MaterialsNotifier(closed: closed),
            ),
          ],
        );
        expect(find.text('Scheduling Clearance Status'), findsOneWidget);
        expect(find.text('Before Your Defense'), findsOneWidget);
        expect(
          find.text('Upload Pitch deck'),
          closed ? findsNothing : findsOneWidget,
        );
        if (closed) {
          expect(
            find.textContaining('The submission deadline has passed'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unscheduled defense file is due later and does not block endorsement',
    (tester) async {
      expect(
        StudentTaskBadgeHelper.isDeliverablePending({
          'type': 'pre',
          'required': true,
          'requirement_timing': 'defense',
          'materials_status': 'awaiting_schedule',
          'materials_submitted': false,
        }),
        isFalse,
      );
      tester.view.physicalSize = const Size(440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        const StudentDeliverablesTab(
          isCapstone: true,
          studentData: null,
          hideHeader: true,
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(
            () => _MaterialsNotifier(awaitingSchedule: true),
          ),
        ],
      );

      expect(find.text('Before endorsement'), findsOneWidget);
      expect(find.text('Before Your Defense'), findsOneWidget);
      expect(find.text('Due later'), findsOneWidget);
      expect(find.text('Action Required'), findsNothing);
      expect(
        find.textContaining('do not block endorsement or scheduling'),
        findsOneWidget,
      );
      expect(
        find.text('Deadline set when your defense is scheduled'),
        findsOneWidget,
      );
      expect(find.text('Upload Pitch deck'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PIT student can see pending defense files without an endorsement gate',
    (tester) async {
      tester.view.physicalSize = const Size(440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        const StudentDeliverablesTab(isCapstone: false, studentData: null),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(
            () => _MaterialsNotifier(pitAutoEligible: true),
          ),
        ],
      );
      expect(find.text('Ready to Schedule'), findsOneWidget);
      expect(find.text('Before Your Defense'), findsOneWidget);
      expect(find.text('Upload Pitch deck'), findsOneWidget);
      expect(find.text('Awaiting Endorsement'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'DefenseMaterialReadiness shows late-upload window banner and triggers edit deadline callback',
    (tester) async {
      var editClicked = false;
      await pumpDefensysWidget(
        tester,
        DefenseMaterialReadiness(
          readiness: const {
            'required_total': 1,
            'submitted_total': 0,
            'status': 'late_window',
            'late_window_active': true,
            'late_upload_until': '2030-11-20T17:00:00+08:00',
            'items': [
              {
                'id': 'DECK',
                'label': 'Pitch deck',
                'due_at': '2030-11-19T09:00:00+08:00',
              },
            ],
          },
          onEditDeadline: () => editClicked = true,
        ),
      );
      expect(find.textContaining('Late-upload window active'), findsOneWidget);
      expect(find.textContaining('Late-upload window open until'), findsOneWidget);
      expect(find.text('Edit deadline'), findsOneWidget);

      await tester.tap(find.text('Edit deadline'));
      await tester.pump();
      expect(editClicked, isTrue);
    },
  );
}
