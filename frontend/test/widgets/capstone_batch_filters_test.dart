import 'package:defensys/screens/web/shared/team_deliverables/components/capstone_batch_filters.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Batches extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState(
    batchFiltersEnabled: true,
    batchOptions: [
      {'value': '12', 'label': '2nd Semester, A.Y. 2026-2027'},
      {'value': '9', 'label': '2nd Semester, A.Y. 2025-2026'},
    ],
  );

  @override
  Future<void> selectBatchFilters(String batchId, String participation) async {
    state = state.copyWith(batchId: batchId, participation: participation);
  }
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  for (final width in [390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('batch and participation selectors at $width, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const previewKey = ValueKey('batch-filters-preview');
        await pumpDefensysWidget(
          tester,
          Padding(
            padding: const EdgeInsets.all(24),
            child: RepaintBoundary(
              key: previewKey,
              child: Consumer(
                builder: (context, ref, _) => CapstoneBatchFilters(
                  state: ref.watch(capstoneDeliverablesProvider),
                ),
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [capstoneDeliverablesProvider.overrideWith(_Batches.new)],
        );
        expect(find.text('Ongoing'), findsOneWidget);
        await tester.tap(find.text('All batches'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2nd Semester, A.Y. 2025-2026'));
        await tester.pumpAndSettle();
        expect(find.text('2nd Semester, A.Y. 2025-2026'), findsOneWidget);
        await tester.tap(find.text('Ongoing'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Completed'));
        await tester.pumpAndSettle();
        expect(find.text('Completed'), findsOneWidget);
        await capturePreview(
          tester,
          find.byKey(previewKey),
          'capstone-batch-filters-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
