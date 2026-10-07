import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_session_editor.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_people_picker.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_session_draft.dart';

void main() {
  testWidgets('renders shadcn outline buttons for add time block and customize staff', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final draft = ScheduleSessionDraft(
      key: 'session-1',
      date: TextEditingController(text: '2026-10-04'),
      start: TextEditingController(text: '08:00'),
      duration: TextEditingController(text: '60'),
      room: TextEditingController(text: 'Lab 3'),
    );
    var customized = false;
    var blockAdded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulerShadcnScope(
            child: SingleChildScrollView(
              child: SchedulerSessionEditor(
                draft: draft,
                number: 1,
                faculty: const [],
                documenters: const [],
                externals: const [],
                capstone: false,
                enabled: true,
                onChanged: () {},
                onCustomize: () => customized = true,
                dateField: (_) => const SizedBox(height: 40),
                timeField: (_) => const SizedBox(height: 40),
                teamSelection: const SizedBox(height: 40),
                onAddBlock: () => blockAdded = true,
                onRemoveBlock: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check Add time block button
    final addBlockFinder = find.byKey(const ValueKey('add-time-block-1'));
    expect(addBlockFinder, findsOneWidget);
    final addBlockButton = tester.widget<ShadButton>(addBlockFinder);
    expect(addBlockButton.size, ShadButtonSize.sm);
    expect(find.byIcon(LucideIcons.plus), findsOneWidget);

    // Check Customize staff button
    final customizeStaffFinder = find.byKey(const ValueKey('customize-staff-1'));
    expect(customizeStaffFinder, findsOneWidget);
    final customizeStaffButton = tester.widget<ShadButton>(customizeStaffFinder);
    expect(customizeStaffButton.size, ShadButtonSize.sm);
    expect(find.byIcon(LucideIcons.users), findsOneWidget);
    expect(find.text('Customize staff for this session'), findsOneWidget);

    // Tap Add time block
    await tester.tap(addBlockFinder);
    expect(blockAdded, isTrue);

    // Tap Customize staff
    await tester.tap(customizeStaffFinder);
    expect(customized, isTrue);
  });
}
