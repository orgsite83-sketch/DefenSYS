import 'package:defensys/screens/web/admin/defense_scheduler/dialogs/panelist_pool_dialog.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/theme/app_theme.dart';
import '../helpers/capture_preview.dart';

const _approved = {
  'id': 11,
  'name': 'Alex Reyes',
  'username': 'FAC-11',
  'is_panelist': true,
};
const _nominee = {
  'id': 12,
  'name': 'Lina Santos',
  'username': 'FAC-12',
  'is_panelist': false,
};
const _request = {
  'id': 1,
  'faculty_id': 12,
  'faculty_name': 'Lina Santos',
  'requested_by_name': 'PIT Lead',
  'pit_year': '1st Year',
  'reason': 'Relevant expertise',
  'status': 'pending',
};

class _Pool extends DefenseSchedulerNotifier {
  _Pool({this.admin = false});
  final bool admin;
  int requests = 0;
  int reviews = 0;
  final List<bool> eligibilityChanges = [];
  String? reason;

  @override
  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {}

  @override
  DefenseSchedulerState build() => DefenseSchedulerState(
    canApprovePanelists: admin,
    requiresPanelistApproval: !admin,
    faculty: const [_approved, _nominee],
    panelists: const [_approved],
    panelistRequests: admin ? const [_request] : const [],
    generatedSlots: const [
      {'team_id': 99},
    ],
  );

  @override
  Future<bool> requestPanelistEligibility(int facultyId, String note) async {
    requests++;
    reason = note;
    state = state.copyWith(
      panelistRequests: [
        {..._request, 'faculty_id': facultyId},
      ],
    );
    return true;
  }

  void approveRemotely() {
    final approvedNominee = {..._nominee, 'is_panelist': true};
    state = state.copyWith(
      faculty: [_approved, approvedNominee],
      panelists: [_approved, approvedNominee],
      panelistRequests: const [],
    );
  }

  @override
  Future<bool> reviewPanelistEligibility(
    int requestId, {
    required bool approve,
    String note = '',
  }) async {
    reviews++;
    if (approve) {
      approveRemotely();
    } else {
      state = state.copyWith(panelistRequests: const []);
    }
    return true;
  }

  @override
  Future<bool> setPanelistEligibility(
    int facultyId, {
    required bool eligible,
  }) async {
    eligibilityChanges.add(eligible);
    state = state.copyWith(
      faculty: state.faculty
          .map(
            (p) => p['id'] == facultyId ? {...p, 'is_panelist': eligible} : p,
          )
          .toList(),
      panelists: eligible
          ? [
              ...state.panelists,
              {..._nominee, 'is_panelist': true},
            ]
          : state.panelists.where((p) => p['id'] != facultyId).toList(),
      panelistRequests: eligible ? const [] : state.panelistRequests,
    );
    return true;
  }
}

void main() {
  setUpAll(loadPreviewFonts);
  Future<ProviderContainer> pump(
    WidgetTester tester,
    _Pool pool, {
    double width = 900,
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final container = ProviderContainer(
      overrides: [defenseSchedulerProvider.overrideWith(() => pool)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: const ValueKey('pool-preview'),
          child: MaterialApp(
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => PanelistPoolDialog.show(context),
                  child: const Text('Open pool'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open pool'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'PIT lead requests once, keeps draft, and can reuse later approval',
    (tester) async {
      final pool = _Pool();
      final container = await pump(tester, pool);
      await tester.tap(find.text('Request eligibility'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(EditableText).last,
        'Relevant topic experience',
      );
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      expect(pool.requests, 1);
      expect(pool.reason, 'Relevant topic experience');
      expect(find.text('Request pending'), findsOneWidget);
      expect(find.text('Request eligibility'), findsNothing);
      expect(container.read(defenseSchedulerProvider).generatedSlots, [
        {'team_id': 99},
      ]);
      expect(
        container.read(defenseSchedulerProvider).isEligiblePanelist(12),
        isFalse,
      );
      pool.approveRemotely();
      await tester.pumpAndSettle();
      expect(find.text('ID: FAC-12'), findsOneWidget);
      expect(find.text('Eligible panelist'), findsNWidgets(2));
      expect(find.text('Request eligibility'), findsNothing);
      expect(
        container.read(defenseSchedulerProvider).selectablePanelists.length,
        2,
      );
      expect(pool.requests, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('admin reviews nomination and makes faculty reusable', (
    tester,
  ) async {
    final pool = _Pool(admin: true);
    final container = await pump(tester, pool);
    await tester.tap(find.text('Requests (1)'));
    await tester.pumpAndSettle();
    await capturePreview(
      tester,
      find.byKey(const ValueKey('pool-preview')),
      'panelist-requests-light',
    );
    await tester.tap(find.text('Approve eligibility'));
    await tester.pumpAndSettle();
    expect(pool.reviews, 1);
    expect(
      container.read(defenseSchedulerProvider).isEligiblePanelist(12),
      isTrue,
    );
    expect(find.text('Requests (0)'), findsOneWidget);
    await tester.tap(find.text('Faculty (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Eligible panelist'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'admin grants and removes eligibility while keeping a schedule draft',
    (tester) async {
      final pool = _Pool(admin: true);
      final container = await pump(tester, pool);
      await tester.tap(find.byKey(const ValueKey('panelist-eligibility-12')));
      await tester.pumpAndSettle();
      expect(pool.eligibilityChanges, [true]);
      expect(
        container.read(defenseSchedulerProvider).isEligiblePanelist(12),
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('panelist-eligibility-12')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove eligibility').last);
      await tester.pumpAndSettle();
      expect(pool.eligibilityChanges, [true, false]);
      expect(
        container.read(defenseSchedulerProvider).isEligiblePanelist(12),
        isFalse,
      );
      expect(container.read(defenseSchedulerProvider).generatedSlots, [
        {'team_id': 99},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pool fits a narrow screen and supports faculty search', (
    tester,
  ) async {
    final pool = _Pool();
    await pump(tester, pool);
    tester.view.physicalSize = const Size(390, 850);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Lina');
    await tester.pumpAndSettle();
    expect(find.text('Lina Santos'), findsOneWidget);
    expect(find.text('Alex Reyes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'eligibility directory fits $width in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          await pump(tester, _Pool(admin: true), width: width, dark: dark);
          expect(find.text('Grant eligibility'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('pool-preview')),
            'panelist-pool-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
        },
      );
    }
  }
}
