import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/audit_compliance/components/audit_format_utils.dart';
import 'package:defensys/screens/web/admin/audit_compliance/components/event_details_panel.dart';

import '../helpers/pump_app.dart';

void main() {
  const oldValues = {
    'panelist_ids': [1],
  };
  const newValues = {
    'panelist_ids': [2],
  };
  const displayOld = {
    'panelist_ids': ['Grace Hopper (ID: 1)'],
  };
  const displayNew = {
    'panelist_ids': ['Alan Turing (ID: 2)'],
  };

  test('audit diffs use names while retaining identity changes', () {
    final diff = AuditFormatUtils.computeDiff(
      oldValues,
      newValues,
      displayOldVals: displayOld,
      displayNewVals: displayNew,
    ).single;
    expect(diff.field, 'Panelists');
    expect(diff.before, 'Grace Hopper (ID: 1)');
    expect(diff.after, 'Alan Turing (ID: 2)');
    expect(AuditFormatUtils.formatValue(['One', 'Two']), 'One\nTwo');
    expect(AuditFormatUtils.formatValue([]), 'None');
    expect(
      AuditFormatUtils.displayValues({'old_values': oldValues}, 'old_values'),
      oldValues,
    );
  });

  test('distinct IDs remain a change even when supplied names match', () {
    expect(
      AuditFormatUtils.computeDiff(
        oldValues,
        newValues,
        displayOldVals: {
          'panelist_ids': ['Same Name'],
        },
        displayNewVals: {
          'panelist_ids': ['Same Name'],
        },
      ),
      hasLength(1),
    );
  });

  testWidgets(
    'invitation details show names and multiline schedules with raw JSON available',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const log = {
        'id': 1,
        'action': 'external_invitation.create',
        'category': 'guest_access',
        'target_type': 'GuestPanelistCode',
        'target_id': '7',
        'target_label': 'Maria Santos (GuestPanelistCode #7)',
        'old_values': <String, dynamic>{},
        'new_values': {
          'evaluator_id': 1,
          'schedule_ids': [41, 42],
          'semester': 1,
        },
        'display_old_values': <String, dynamic>{},
        'display_new_values': {
          'evaluator_id': 'Maria Santos (ID: 1)',
          'schedule_ids': [
            'Team Atlas / Project Proposal / Oct 12, 2026 09:00 AM (ID: 41)',
            'Team ByteForce / Project Proposal / Oct 12, 2026 10:00 AM (ID: 42)',
          ],
          'semester': '1st Semester, A.Y. 2026-2027 (ID: 1)',
        },
      };
      await pumpDefensysWidget(
        tester,
        const SingleChildScrollView(
          child: SizedBox(width: 650, child: EventDetailsPanel(log: log)),
        ),
      );
      expect(find.text('Evaluator'), findsOneWidget);
      expect(find.text('Maria Santos (ID: 1)'), findsOneWidget);
      expect(find.text('Defense Schedules'), findsOneWidget);
      expect(
        find.textContaining('Team ByteForce / Project Proposal'),
        findsOneWidget,
      );
      expect(find.text('1st Semester, A.Y. 2026-2027 (ID: 1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('View as JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"evaluator_id": 1'), findsOneWidget);
    },
  );
}
