import 'package:defensys/widgets/repository/proposal_name_review.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  testWidgets(
    'an edited name retains its original review version after a background refresh',
    (tester) async {
      var version = 'original';
      late StateSetter refresh;
      final requests = <String>[];
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            refresh = setState;
            final snapshot = version;
            return DefensysShadcnScope(
              child: SingleChildScrollView(
                child: ProposalNameReview(
                  title: 'Current system',
                  confirmed: false,
                  system: true,
                  canConfirm: true,
                  onConfirm: (title) async {
                    requests.add('$snapshot:$title');
                    return false;
                  },
                ),
              ),
            );
          },
        ),
      );
      await tester.tap(find.text('Edit name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Adviser draft name');
      refresh(() => version = 'refreshed');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and confirm name'));
      await tester.pumpAndSettle();
      expect(requests, ['original:Adviser draft name']);
      expect(find.text('Adviser draft name'), findsOneWidget);
      expect(find.text('Save and confirm name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
