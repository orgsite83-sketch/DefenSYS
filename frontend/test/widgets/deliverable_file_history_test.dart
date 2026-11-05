import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'file details expose only matching read-only revisions at $width',
      (tester) async {
        await loadPreviewFonts();
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpDefensysWidget(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDeliverableFileDetails(
                context: context,
                label: 'Chapter 1-5',
                stageLabel: 'Final Defense',
                status: 'Accepted',
                file: const {
                  'id': 30,
                  'slot_key': 'primary',
                  'revision': 3,
                  'file_name': 'current.pdf',
                  'is_current': true,
                },
                onReplace: () async {},
                onRemove: () async {},
                history: const [
                  {
                    'id': 10,
                    'slot_key': 'primary',
                    'revision': 1,
                    'file_name': 'original.pdf',
                    'feedback': 'Clarify the scope.',
                    'uploaded_by_name': 'Student One',
                    'uploaded_at': '2026-11-01T10:00:00Z',
                    'file_url': '/media/original.pdf',
                    'is_current': false,
                  },
                  {
                    'id': 20,
                    'slot_key': 'primary',
                    'revision': 2,
                    'file_name': 'revised.pdf',
                    'is_current': false,
                  },
                  {
                    'id': 40,
                    'slot_key': 'other',
                    'revision': 8,
                    'file_name': 'unrelated.pdf',
                    'is_current': false,
                  },
                  {
                    'id': 30,
                    'slot_key': 'primary',
                    'revision': 3,
                    'file_name': 'current.pdf',
                    'is_current': true,
                  },
                ],
              ),
              child: const Text('Details'),
            ),
          ),
        );
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Previous versions (2)'));
        await tester.tap(find.text('Previous versions (2)'));
        await tester.pumpAndSettle();
        expect(find.text('unrelated.pdf'), findsNothing);
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'deliverable-history-${width.toInt()}',
          viewport: true,
        );
        expect(
          tester.getTopLeft(find.text('Revision 2')).dy,
          lessThan(tester.getTopLeft(find.text('Revision 1')).dy),
        );
        await tester.ensureVisible(find.text('Revision 1'));
        await tester.tap(find.text('Revision 1'));
        await tester.pumpAndSettle();
        expect(find.text('Previous version'), findsOneWidget);
        expect(find.text('Student One'), findsOneWidget);
        expect(find.text('Feedback: Clarify the scope.'), findsOneWidget);
        // The historical dialog is read-only even if the current file is editable.
        final historical = find
            .ancestor(
              of: find.text('Previous version'),
              matching: find.byType(SingleChildScrollView),
            )
            .first;
        expect(
          find.descendant(of: historical, matching: find.text('Replace File')),
          findsNothing,
        );
        expect(
          find.descendant(of: historical, matching: find.text('Remove')),
          findsNothing,
        );
        expect(
          find.descendant(of: historical, matching: find.text('View Document')),
          findsOneWidget,
        );
      },
    );
  }
}
