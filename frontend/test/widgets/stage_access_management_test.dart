import 'package:defensys/screens/web/shared/project_archive/dialogs/stage_access_management_dialog.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class AccessNotifier extends CapstoneDeliverablesNotifier {
  AccessNotifier({this.lead = false});
  final bool lead;
  bool reject = false;
  bool open = false;
  final requests = <Map<String, dynamic>>[];
  final reads = <Map<String, dynamic>>[];

  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState();

  @override
  Future<Map<String, dynamic>?> fetchStageAccess({
    String scope = 'global',
    String programScope = 'capstone',
    int? teamId,
    String? yearLevel,
  }) async {
    reads.add({'program': programScope, 'year': yearLevel});
    Map<String, dynamic> settings(bool enabled, {bool mixed = false}) => {
      'unlocked': enabled,
      'team_count': 2,
      'allowed_count': enabled ? (mixed ? 1 : 2) : 0,
      'mixed': mixed,
      'archived_count': 0,
    };
    final pit = programScope == 'pit';
    return {
      'scope': scope,
      'program_scope': programScope,
      'year_level': lead ? '3rd Year' : yearLevel ?? '',
      'can_choose_program': !lead,
      'semester_label': '2026-2027 · 2nd Semester',
      'team_count': 2,
      'stages': [
        {
          'stage_label': pit ? '3rd Year PIT Showcase' : 'Concept Proposal',
          'pre': settings(false),
          'post': settings(true, mixed: true),
          'deliverables': [
            {
              'id': pit ? 'P1' : 'D1',
              'label': pit ? 'PIT project paper' : 'Adviser Acceptance Form',
              'type': 'pre',
              ...settings(open),
            },
          ],
        },
      ],
    };
  }

  @override
  Future<bool> unlockDeliverables({
    int? teamId,
    required String stageLabel,
    String unlockType = 'all',
    String scope = 'team',
    String? programScope,
    String? yearLevel,
    bool? targetState,
    String reason = '',
    String? deliverableId,
  }) async {
    requests.add({
      'team_id': teamId,
      'stage': stageLabel,
      'type': unlockType,
      'scope': scope,
      'program': programScope,
      'year': yearLevel,
      'target': targetState,
      'reason': reason,
      'id': deliverableId,
    });
    if (reject) {
      state = state.copyWith(
        error: 'Only your assigned PIT year can be changed.',
      );
      return false;
    }
    open = targetState ?? false;
    return true;
  }
}

class AccessArchiveNotifier extends ProjectArchiveNotifier {
  @override
  ProjectArchiveState build() => const ProjectArchiveState();
  @override
  Future<void> fetchEntries({
    String? search,
    String? type,
    String? yearLevel,
    String? academicYear,
    String? status,
    String? semester,
    String? teamId,
    String? stage,
    String? deliverableId,
    String? submissionKind,
    String? viewMode,
    String? groupBy,
    String? folderKey,
    int? pageOffset,
    String? successMessage,
    bool clearDeliverable = false,
    bool clearTeam = false,
  }) async {}
}

Future<void> openDialog(
  WidgetTester tester,
  AccessNotifier notifier, {
  Size size = const Size(1000, 1200),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpDefensysWidget(
    tester,
    Consumer(
      builder: (context, ref, _) => TextButton(
        onPressed: () => StageAccessManagementDialog.show(
          context: context,
          ref: ref,
          scope: 'global',
          programScope: notifier.lead ? 'pit' : 'capstone',
        ),
        child: const Text('Manage access'),
      ),
    ),
    overrides: [
      capstoneDeliverablesProvider.overrideWith(() => notifier),
      projectArchiveProvider.overrideWith(AccessArchiveNotifier.new),
    ],
  );
  await tester.tap(find.text('Manage access'));
  await tester.pumpAndSettle();
}

Future<void> finishToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'saved permissions load, reason is required, and individual change persists on reopen',
    (tester) async {
      final notifier = AccessNotifier();
      await openDialog(tester, notifier);
      final individual = find.byKey(
        const ValueKey('stageAccess:Concept Proposal:D1'),
      );
      expect(tester.widget<Switch>(individual).value, isFalse);
      expect(tester.widget<Switch>(individual).onChanged, isNull);
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('stageAccess:Concept Proposal:post')),
            )
            .value,
        isTrue,
      );
      expect(find.textContaining('Mixed'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('stageAccessReason')),
        'Replace the incorrect signed form.',
      );
      await tester.pump();
      await tester.ensureVisible(individual);
      await tester.tap(individual);
      await tester.pumpAndSettle();
      expect(notifier.requests.single, {
        'team_id': null,
        'stage': 'Concept Proposal',
        'type': 'pre',
        'scope': 'global',
        'program': 'capstone',
        'year': '',
        'target': true,
        'reason': 'Replace the incorrect signed form.',
        'id': 'D1',
      });
      expect(tester.widget<Switch>(individual).value, isTrue);
      await finishToast(tester);
      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage access'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(individual).value, isTrue);
      expect(notifier.reads.length, 3);
    },
  );

  testWidgets(
    'Admin can choose PIT and an explicit year before changing a deliverable',
    (tester) async {
      final notifier = AccessNotifier();
      await openDialog(tester, notifier);
      await tester.tap(find.byKey(const ValueKey('accessProgram:capstone')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PIT').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accessYear:')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3rd Year').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('stageAccessReason')),
        'Allow the PIT project paper correction.',
      );
      await tester.pump();
      final individual = find.byKey(
        const ValueKey('stageAccess:3rd Year PIT Showcase:P1'),
      );
      await tester.ensureVisible(individual);
      await tester.tap(individual);
      await tester.pumpAndSettle();
      expect(notifier.requests.single['program'], 'pit');
      expect(notifier.requests.single['year'], '3rd Year');
      expect(notifier.requests.single['id'], 'P1');
      await finishToast(tester);
    },
  );

  testWidgets(
    'PIT Lead sees assigned year controls without Admin program selectors',
    (tester) async {
      final notifier = AccessNotifier(lead: true);
      await openDialog(tester, notifier);
      expect(
        find.text('Program Stage Access (PIT · 3rd Year)'),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('stageAccessReason')),
        'Permit the correct PIT report.',
      );
      await tester.pump();
      final individual = find.byKey(
        const ValueKey('stageAccess:3rd Year PIT Showcase:P1'),
      );
      await tester.ensureVisible(individual);
      await tester.tap(individual);
      await tester.pumpAndSettle();
      expect(notifier.requests.single['year'], '3rd Year');
      expect(notifier.requests.single['program'], 'pit');
      await finishToast(tester);
    },
  );

  testWidgets(
    'rejected change shows server error and retains saved switch value',
    (tester) async {
      final notifier = AccessNotifier()..reject = true;
      await openDialog(tester, notifier);
      await tester.enterText(
        find.byKey(const ValueKey('stageAccessReason')),
        'Request correction.',
      );
      await tester.pump();
      final individual = find.byKey(
        const ValueKey('stageAccess:Concept Proposal:D1'),
      );
      await tester.ensureVisible(individual);
      await tester.tap(individual);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(individual).value, isFalse);
      expect(
        find.text('Only your assigned PIT year can be changed.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('file access dialog supports a narrow viewport', (tester) async {
    await openDialog(tester, AccessNotifier(), size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('stageAccess:Concept Proposal:D1')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
