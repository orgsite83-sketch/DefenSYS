import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_people_picker.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_time_blocks_editor.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_session_draft.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/capture_preview.dart';

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'inline blocks validate, cancel and save at $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final draft = ScheduleSessionDraft(
            key: 'one',
            date: TextEditingController(text: '2026-10-26'),
            start: TextEditingController(text: '08:00'),
            duration: TextEditingController(text: '60'),
            room: TextEditingController(text: 'Lab 1'),
          )..teamIds = {1, 2, 3, 4, 5, 6, 7, 8};
          addTearDown(draft.dispose);
          var saved = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
              home: Scaffold(
                body: SchedulerShadcnScope(
                  child: RepaintBoundary(
                    key: const ValueKey('inline-preview'),
                    child: ColoredBox(
                      color: dark
                          ? DefensysTokens.mistSurface
                          : DefensysTokens.surface,
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: 760,
                              child: SchedulerTimeBlocksEditor(
                                draft: draft,
                                enabled: true,
                                onSaved: () => saved++,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('Break · 12:00–13:00'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('edit-time-blocks-one')));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          Finder input(String key) => find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(EditableText),
          );
          final duration = input('session-slot-duration-one');
          await tester.enterText(duration, '90');
          await tester.pumpAndSettle();
          expect(draft.duration.text, '60');
          expect(
            find.text('Saving returns 4 teams to Unassigned.'),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text('Cancel'));
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(saved, 0);
          expect(draft.duration.text, '60');
          await tester.ensureVisible(
            find.byKey(const ValueKey('edit-time-blocks-one')),
          );
          await tester.tap(find.byKey(const ValueKey('edit-time-blocks-one')));
          await tester.pumpAndSettle();
          await tester.enterText(input('time-block-start-one-1'), '11:00');
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ShadButton>(
                  find.byKey(const ValueKey('save-time-blocks-one')),
                )
                .enabled,
            isFalse,
          );
          await tester.enterText(input('time-block-start-one-1'), '13:00');
          await tester.pumpAndSettle();
          await capturePreview(
            tester,
            find.byKey(const ValueKey('inline-preview')),
            'scheduler-inline-blocks-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.enterText(duration, '90');
          await tester.pumpAndSettle();
          final save = find.byKey(const ValueKey('save-time-blocks-one'));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(saved, 1);
          expect(draft.capacity, 4);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
