import 'package:defensys/screens/app/student/student_deliverables_tab.dart';
import 'package:defensys/screens/web/admin/audit_compliance/components/audit_format_utils.dart';
import 'package:defensys/screens/web/shared/project_archive/dialogs/archive_resubmission_dialog.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

const replacementReason = 'Upload the signed acceptance form.';

class ReplacementDeliverablesNotifier extends CapstoneDeliverablesNotifier {
  ReplacementDeliverablesNotifier(this.unlocked);
  final bool unlocked;

  @override
  CapstoneDeliverablesState build() {
    final stage = <String, dynamic>{
      'stage_label': 'Concept Proposal',
      'endorsed': true,
      'deliverables_configured': true,
      'deliverables': [
        {
          'id': 'D1',
          'label': 'Adviser Acceptance Form',
          'type': 'pre',
          'required': true,
          'uploaded': true,
          'locked': true,
          'submission': {
            'status': 'accepted',
            'file_name': 'wrong.pdf',
            'file_size': '12 KB',
            'feedback':
                'Remarks by admin (Admin): Unlocked for file replacement by Admin',
            'file_replacement_unlocked': unlocked,
            'file_replacement_reason': unlocked ? replacementReason : '',
          },
        },
      ],
    };
    return CapstoneDeliverablesState(
      selectedStage: 'Concept Proposal',
      stageOptions: const ['Concept Proposal'],
      teams: [
        {
          'id': 1,
          'name': 'Team AgriSense',
          'selected_stage': stage,
          'stages': [stage],
        },
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

class ReplacementArchiveNotifier extends ProjectArchiveNotifier {
  Map<String, dynamic>? sent;
  Map<String, dynamic>? canceled;
  bool rejectCancel = false;

  @override
  ProjectArchiveState build() => const ProjectArchiveState();

  @override
  Future<bool> requestResubmission(
    String entryId, {
    String status = 'Needs Revision',
    String feedback = '',
  }) async {
    sent = {'entry_id': entryId, 'status': status, 'feedback': feedback};
    return true;
  }

  @override
  Future<bool> cancelFileReplacement(
    String entryId, {
    required String reason,
  }) async {
    canceled = {'entry_id': entryId, 'reason': reason};
    if (rejectCancel) {
      state = state.copyWith(error: 'There is no active replacement unlock.');
      return false;
    }
    return true;
  }
}

void main() {
  testWidgets(
    'approved file exposes replacement in card and details after explicit unlock',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        const StudentDeliverablesTab(
          isCapstone: true,
          studentData: null,
          hideHeader: true,
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(
            () => ReplacementDeliverablesNotifier(true),
          ),
        ],
      );
      expect(find.text('Replace File'), findsOneWidget);
      expect(find.textContaining(replacementReason), findsOneWidget);
      await tester.tap(find.text('wrong.pdf'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(OutlinedButton, 'Replace File'),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove Submission'), findsNothing);
    },
  );

  testWidgets('remarks alone do not grant replacement to an approved file', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpDefensysWidget(
      tester,
      const StudentDeliverablesTab(
        isCapstone: true,
        studentData: null,
        hideHeader: true,
      ),
      overrides: [
        capstoneDeliverablesProvider.overrideWith(
          () => ReplacementDeliverablesNotifier(false),
        ),
      ],
    );
    expect(find.text('Replace File'), findsNothing);
    await tester.tap(find.text('wrong.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Replace File'), findsNothing);
  });

  testWidgets(
    'Choice B requires a reason and sends Approved with the entered reason',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ReplacementArchiveNotifier();
      await pumpDefensysWidget(
        tester,
        Consumer(
          builder: (context, ref, _) {
            return TextButton(
              onPressed: () => ArchiveResubmissionDialog.showResubmissionDialog(
                context: context,
                ref: ref,
                entry: {
                  'id': 'capstone-1-2',
                  'file_name': 'wrong.pdf',
                  'team_name': 'Team AgriSense',
                  'status': 'Approved',
                  'deliverable_type': 'pre',
                  'feedback': 'unlocked',
                },
              ),
              child: const Text('Manage file'),
            );
          },
        ),
        overrides: [repositoryAuditProvider.overrideWith(() => notifier)],
      );
      await tester.tap(find.text('Manage file'));
      await tester.pumpAndSettle();
      final button = find.ancestor(
        of: find.text(
          'Unlock Replacement (Keep Status Approved)',
          skipOffstage: false,
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is ElevatedButton,
          skipOffstage: false,
        ),
      );
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
      expect(
        find.text('File Replacement is currently UNLOCKED for students.'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('cancelFileReplacement')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('fileReplacementReason')),
        replacementReason,
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(notifier.sent, {
        'entry_id': 'capstone-1-2',
        'status': 'Approved',
        'feedback': replacementReason,
      });
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Choice A requires remarks and sends Needs Revision with its reason',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ReplacementArchiveNotifier();
      await pumpDefensysWidget(
        tester,
        Consumer(
          builder: (context, ref, _) {
            return TextButton(
              onPressed: () => ArchiveResubmissionDialog.showResubmissionDialog(
                context: context,
                ref: ref,
                entry: {
                  'id': 'capstone-1-2',
                  'file_name': 'wrong.pdf',
                  'team_name': 'Team AgriSense',
                  'status': 'Approved',
                  'deliverable_type': 'pre',
                },
              ),
              child: const Text('Manage file'),
            );
          },
        ),
        overrides: [repositoryAuditProvider.overrideWith(() => notifier)],
      );
      await tester.tap(find.text('Manage file'));
      await tester.pumpAndSettle();
      final button = find.ancestor(
        of: find.text(
          'Unlock with "Needs Revision" Status',
          skipOffstage: false,
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is ElevatedButton,
          skipOffstage: false,
        ),
      );
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
      await tester.enterText(
        find.byType(TextField).first,
        'Correct the form contents.',
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(notifier.sent, {
        'entry_id': 'capstone-1-2',
        'status': 'Needs Revision',
        'feedback': 'Correct the form contents.',
      });
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final reject in [false, true]) {
    testWidgets(
      'unused Choice B can be canceled with a reason (server rejection: $reject)',
      (tester) async {
        await tester.binding.setSurfaceSize(
          reject ? const Size(1100, 1000) : const Size(390, 844),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final notifier = ReplacementArchiveNotifier()..rejectCancel = reject;
        await pumpDefensysWidget(
          tester,
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ArchiveResubmissionDialog.showResubmissionDialog(
                context: context,
                ref: ref,
                entry: {
                  'id': 'capstone-1-2',
                  'file_name': 'wrong.pdf',
                  'team_name': 'Team AgriSense',
                  'status': 'Approved',
                  'deliverable_type': 'pre',
                  'file_replacement_unlocked': true,
                },
              ),
              child: const Text('Manage file'),
            ),
          ),
          overrides: [repositoryAuditProvider.overrideWith(() => notifier)],
        );
        await tester.tap(find.text('Manage file'));
        await tester.pumpAndSettle();
        final button = find.byKey(const ValueKey('cancelFileReplacement'));
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        await tester.enterText(
          find.byKey(const ValueKey('fileReplacementReason')),
          'The current form is correct.',
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(notifier.canceled, {
          'entry_id': 'capstone-1-2',
          'reason': 'The current form is correct.',
        });
        expect(notifier.sent, isNull);
        expect(
          find.text(
            reject
                ? 'There is no active replacement unlock.'
                : 'Replacement unlock canceled. The file stays Approved.',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 7));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'replacement requests remain student action items despite approved status',
    () {
      final item = <String, dynamic>{
        'type': 'pre',
        'required': false,
        'uploaded': true,
        'submission': {'status': 'accepted', 'file_replacement_unlocked': true},
      };
      expect(StudentTaskBadgeHelper.isDeliverablePending(item), isTrue);
      item['submission'] = {
        'status': 'accepted',
        'file_replacement_unlocked': false,
      };
      expect(StudentTaskBadgeHelper.isDeliverablePending(item), isFalse);
      expect(
        AuditFormatUtils.formatAction('repository.file_replacement_unlock'),
        'Student file replacement unlocked',
      );
      expect(
        AuditFormatUtils.formatAction('repository.student_file_replace'),
        'Student replaced approved file',
      );
      expect(
        AuditFormatUtils.formatAction('repository.file_replacement_cancel'),
        'Student file replacement unlock canceled',
      );
    },
  );
}
