import 'package:defensys/screens/app/student/student_deliverables_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

const _stageLabel = 'System Concept Pitching';
const _postLabel = 'Approved Concept Paper';
const _lockedMessage =
    'Post-Defense submissions are locked. They will open once your defense for $_stageLabel is complete.';

Map<String, dynamic> _stage({
  String? unlockFlag,
  bool forRedefense = false,
  String postType = 'post',
}) => {
  'stage_label': _stageLabel,
  'endorsed': true,
  'deliverables_configured': true,
  'has_done_schedule': false,
  'vault_unlocked': false,
  'archive_unlocked': false,
  'post_unlocked': false,
  if (unlockFlag != null) unlockFlag: true,
  if (forRedefense) 'grade': {'verdict': 'for_redefense', 'attempt_count': 2},
  'deliverables': [
    {
      'id': 'CONCEPT',
      'label': 'Concept Paper',
      'type': 'pre',
      'required': true,
      'uploaded': true,
      'can_upload': false,
      'submission': {'status': 'accepted', 'file_name': 'concept.pdf'},
    },
    {
      'id': 'APPROVED',
      'label': _postLabel,
      'type': postType,
      'required': true,
      'uploaded': false,
      'can_upload': unlockFlag != null,
      'locked': unlockFlag == null,
    },
  ],
};

class _PostDeliverablesNotifier extends CapstoneDeliverablesNotifier {
  _PostDeliverablesNotifier(this.initialStage);

  final Map<String, dynamic> initialStage;

  CapstoneDeliverablesState _stateFor(Map<String, dynamic> stage) =>
      CapstoneDeliverablesState(
        selectedStage: _stageLabel,
        stageOptions: const [_stageLabel],
        teams: [
          {'id': 7, 'name': 'Team SafeCity', 'selected_stage': stage},
        ],
      );

  @override
  CapstoneDeliverablesState build() => _stateFor(initialStage);

  void updateStage(Map<String, dynamic> stage) => state = _stateFor(stage);

  @override
  Future<void> fetchDeliverables({
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

Future<void> _pumpDeliverables(
  WidgetTester tester,
  _PostDeliverablesNotifier notifier, {
  bool isCapstone = false,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  await pumpDefensysWidget(
    tester,
    RepaintBoundary(
      key: const ValueKey('post-deliverables-preview'),
      child: StudentDeliverablesTab(
        isCapstone: isCapstone,
        studentData: null,
        hideHeader: true,
      ),
    ),
    overrides: [capstoneDeliverablesProvider.overrideWith(() => notifier)],
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
  );
}

void main() {
  for (final isCapstone in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'locked ${isCapstone ? 'Capstone' : 'PIT'} post files stay hidden in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          final notifier = _PostDeliverablesNotifier(_stage());
          await _pumpDeliverables(
            tester,
            notifier,
            isCapstone: isCapstone,
            dark: dark,
          );

          expect(find.text('Concept Paper'), findsOneWidget);
          expect(find.text('Post-Defense Submissions'), findsOneWidget);
          expect(find.text(_lockedMessage), findsOneWidget);
          expect(find.text(_postLabel), findsNothing);
          expect(find.text('Action Required'), findsNothing);
          expect(find.text('Awaiting team upload'), findsNothing);
          expect(notifier.state.hasPendingPostDeliverables, isFalse);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('post-deliverables-preview')),
            'locked-post-${isCapstone ? 'capstone' : 'pit'}-${dark ? 'dark' : 'light'}',
          );
        },
      );
    }
  }

  for (final unlockFlag in [
    'vault_unlocked',
    'archive_unlocked',
    'post_unlocked',
  ]) {
    testWidgets('post files appear when $unlockFlag grants access', (
      tester,
    ) async {
      final notifier = _PostDeliverablesNotifier(
        _stage(
          unlockFlag: unlockFlag,
          postType: unlockFlag == 'vault_unlocked' ? 'vault' : 'post',
        ),
      );
      await _pumpDeliverables(tester, notifier);

      expect(find.text(_lockedMessage), findsNothing);
      expect(find.text(_postLabel), findsOneWidget);
      expect(find.text('Upload $_postLabel'), findsOneWidget);
      expect(find.text('Action Required'), findsOneWidget);
      expect(notifier.state.hasPendingPostDeliverables, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('locking an open stage hides its post files immediately', (
    tester,
  ) async {
    final notifier = _PostDeliverablesNotifier(
      _stage(unlockFlag: 'archive_unlocked'),
    );
    await _pumpDeliverables(tester, notifier);
    expect(find.text(_postLabel), findsOneWidget);

    notifier.updateStage(_stage());
    await tester.pumpAndSettle();

    expect(find.text(_lockedMessage), findsOneWidget);
    expect(find.text(_postLabel), findsNothing);
    expect(find.text('Action Required'), findsNothing);
    expect(notifier.state.hasPendingPostDeliverables, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('re-defense keeps post files behind the lock notice', (
    tester,
  ) async {
    await _pumpDeliverables(
      tester,
      _PostDeliverablesNotifier(_stage(forRedefense: true)),
      isCapstone: true,
    );

    expect(
      find.text('Post-Defense Submissions Locked (For Re-defense)'),
      findsOneWidget,
    );
    expect(find.textContaining('Attempt #2'), findsOneWidget);
    expect(find.text(_postLabel), findsNothing);
    expect(find.text('Action Required'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
