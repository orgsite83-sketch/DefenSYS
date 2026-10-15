import 'package:defensys/screens/web/admin/defense_board/components/material_deadline_dialog.dart';
import 'package:defensys/services/defense_board_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

class _DeadlineBoard extends DefenseBoardNotifier {
  bool fail = true;
  String? savedReason;
  DateTime? savedDeadline;
  int? savedRevision;

  @override
  DefenseBoardState build() => const DefenseBoardState();

  @override
  Future<void> extendMaterialDeadline({
    required int scheduleId,
    required int revision,
    required DateTime deadline,
    required String reason,
    String? mode,
  }) async {
    if (fail) throw Exception('Connection interrupted. Try again.');
    savedReason = reason;
    savedDeadline = deadline;
    savedRevision = revision;
  }
}

void main() {
  testWidgets(
    'deadline dialog validates the reason, keeps failed edits, and saves the reviewed deadline',
    (tester) async {
      final notifier = _DeadlineBoard();
      final start = DateTime.now().add(const Duration(days: 5));
      final date =
          '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
      final schedule = <String, dynamic>{
        'id': 7,
        'revision': 3,
        'team_name': 'Team SafeCity',
        'stage_label': 'Concept Proposal',
        'scheduled_date': date,
        'start_time': '09:00:00',
        'materials_readiness': {
          'status': 'overdue',
          'required_total': 1,
          'submitted_total': 0,
          'defense_starts_at': DateTime(
            start.year,
            start.month,
            start.day,
            9,
          ).toUtc().toIso8601String(),
          'items': [
            {
              'label': 'Pitch deck',
              'due_at': start
                  .subtract(const Duration(days: 1))
                  .toUtc()
                  .toIso8601String(),
            },
          ],
        },
      };
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showMaterialDeadlineDialog(context, schedule),
            child: const Text('Extend materials'),
          ),
        ),
        overrides: [defenseBoardProvider.overrideWith(() => notifier)],
      );
      await tester.tap(find.text('Extend materials'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extend deadline'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a reason of at least 5 characters.'),
        findsOneWidget,
      );
      const reason = 'Approved extra preparation time.';
      await tester.enterText(find.byType(EditableText), reason);
      await tester.tap(find.text('Extend deadline'));
      await tester.pumpAndSettle();
      expect(find.text('Connection interrupted. Try again.'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      notifier.fail = false;
      await tester.tap(find.text('Extend deadline'));
      await tester.pumpAndSettle();
      expect(notifier.savedReason, reason);
      expect(notifier.savedRevision, 3);
      expect(
        notifier.savedDeadline,
        DateTime(start.year, start.month, start.day, 9),
      );
      expect(find.text('Extend material deadline'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
