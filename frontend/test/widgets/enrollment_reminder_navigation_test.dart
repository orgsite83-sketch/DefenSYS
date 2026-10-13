import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/user_management/bulk_import/student_batch_enrollment_hub_view.dart';
import 'package:defensys/screens/web/admin/user_management/components/students_enrollment_view.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic/student_batch_draft_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/feedback/action_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Periods extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState();

  void activate() {
    state = const AcademicPeriodState(
      activeSemester: {
        'id': 1,
        'label': '1st Semester',
        'school_year': '2026-2027',
        'display_name': '1st Semester, A.Y. 2026-2027',
      },
    );
  }
}

class _Records extends StudentAcademicRecordsNotifier {
  @override
  StudentAcademicRecordsState build() => const StudentAcademicRecordsState(
    students: [
      {'id': 1, 'username': 'S001'},
    ],
  );

  @override
  Future<bool> fetchRolloverPreview({
    List<Map<String, dynamic>>? students,
  }) async => true;
}

class _Draft extends StudentBatchDraftNotifier {
  @override
  StudentBatchDraftState build() => const StudentBatchDraftState(
    freshParsedStudents: [
      {
        'id_number': 'S001',
        'first_name': 'Test',
        'last_name': 'Student',
        'email': 'student@example.com',
        'year_level': '1st Year',
        'role': 'student',
      },
    ],
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(GoRouter, ProviderContainer)> openScreen(
    WidgetTester tester, {
    StudentHubMode mode = StudentHubMode.freshIntake,
    bool showHub = true,
    VoidCallback? onOpenBulkImport,
  }) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: AdminRoutes.users,
      routes: [
        GoRoute(
          path: AdminRoutes.users,
          builder: (_, __) => Scaffold(
            body: showHub
                ? StudentBatchEnrollmentHubView(
                    userState: const UserManagementState(),
                    academicState: const AcademicPeriodState(),
                    initialMode: mode,
                    onBack: () {},
                    onDownloadSample: null,
                    onConfirmFreshImport: (_, __) async => throw StateError(
                      'A reminder must not import students.',
                    ),
                  )
                : SingleChildScrollView(
                    child: StudentsEnrollmentView(
                      onOpenBulkImport: onOpenBulkImport,
                    ),
                  ),
          ),
        ),
        GoRoute(
          path: AdminRoutes.academicPeriods,
          builder: (_, __) =>
              const Scaffold(body: Text('Academic Periods destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          academicPeriodProvider.overrideWith(_Periods.new),
          studentAcademicRecordsProvider.overrideWith(_Records.new),
          studentBatchDraftProvider.overrideWith(_Draft.new),
        ],
        child: MaterialApp.router(theme: AppTheme.theme, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return (
      router,
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)),
    );
  }

  for (final mode in StudentHubMode.values) {
    testWidgets(
      '$mode warning opens Academic Periods and keeps the intake draft',
      (tester) async {
        final (router, container) = await openScreen(tester, mode: mode);
        expect(
          router.routeInformationProvider.value.uri.path,
          AdminRoutes.users,
        );
        await tester.tap(find.text('Open Academic Periods'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          AdminRoutes.academicPeriods,
        );
        expect(find.text('Academic Periods destination'), findsOneWidget);
        expect(container.read(studentBatchDraftProvider).hasFreshDraft, isTrue);

        (container.read(academicPeriodProvider.notifier) as _Periods)
            .activate();
        router.go(AdminRoutes.users);
        await tester.pumpAndSettle();
        expect(find.byType(DefensysActionBanner), findsNothing);
        expect(
          container
              .read(studentBatchDraftProvider)
              .freshParsedStudents
              .single['id_number'],
          'S001',
        );
        if (mode == StudentHubMode.freshIntake) {
          expect(
            find.text('Confirm Student Intake (1 students)'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final actionIndex in [0, 1]) {
    testWidgets('enrollment setup action $actionIndex opens Academic Periods', (
      tester,
    ) async {
      final (router, _) = await openScreen(tester, showHub: false);
      final action = find.text('Open Academic Periods').at(actionIndex);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        AdminRoutes.academicPeriods,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unenrolled account reminder opens Batch Enrollment', (
    tester,
  ) async {
    var opened = false;
    final (_, container) = await openScreen(
      tester,
      showHub: false,
      onOpenBulkImport: () => opened = true,
    );
    (container.read(academicPeriodProvider.notifier) as _Periods).activate();
    await tester.pumpAndSettle();
    expect(find.text('Open Academic Periods'), findsNothing);
    final action = find.text('Open Batch Enrollment');
    await tester.ensureVisible(action);
    await tester.tap(action);
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reminder action fits narrow layouts in light and dark themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: DefensysActionBanner(
                title:
                    'Active Academic Semester Required for Student Enrollment',
                description:
                    'Create and activate a semester to enroll students.',
                actionLabel: 'Open Academic Periods',
                onAction: () => opened = true,
                isBlocking: true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Academic Periods'));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    }
  });
}
