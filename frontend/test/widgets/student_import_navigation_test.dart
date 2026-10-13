import 'dart:async';

import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/screens/web/admin/user_management/user_management_screen.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic/student_batch_draft_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_management_screen_test.dart'
    show
        FakeAcademicPeriodNotifierWithActiveSemester,
        FakeStudentAcademicRecordsNotifier,
        FakeUserManagementNotifier;

class _Users extends FakeUserManagementNotifier {
  final result = Completer<bool>();
  int importCalls = 0;

  @override
  Future<bool> bulkImport(
    List<Map<String, dynamic>> rows, {
    Map<String, dynamic>? studentContext,
  }) async {
    importCalls++;
    state = state.copyWith(isSaving: true);
    final success = await result.future;
    state = state.copyWith(
      isSaving: false,
      message: success ? '${rows.length} users imported.' : null,
      error: success ? null : 'Import failed. Please retry.',
    );
    return success;
  }
}

class _Records extends FakeStudentAcademicRecordsNotifier {
  int loads = 0;
  final refresh = Completer<void>();

  @override
  Future<void> fetchRecords({
    String? schoolYear,
    String? semester,
    String? yearLevel,
    String? search,
    String? successMessage,
  }) async {
    if (++loads > 1) await refresh.future;
  }
}

class _Evaluators extends ExternalEvaluatorNotifier {
  @override
  Future<bool> fetch() async => true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> openHub(
    WidgetTester tester,
    _Users users,
    _Records records,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/admin/users?tab=faculty',
      routes: [
        GoRoute(
          path: '/admin/users',
          builder: (_, state) => Scaffold(
            body: UserManagementScreen(
              key: const ValueKey('users'),
              initialUserTab: state.uri.queryParameters['tab'] == 'faculty'
                  ? UserManagementTab.faculty
                  : UserManagementTab.students,
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userManagementProvider.overrideWith(() => users),
          studentAcademicRecordsProvider.overrideWith(() => records),
          academicPeriodProvider.overrideWith(
            FakeAcademicPeriodNotifierWithActiveSemester.new,
          ),
          externalEvaluatorProvider.overrideWith(_Evaluators.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.theme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UserManagementScreen)),
    );
    await tester.tap(find.text('Students & Enrollment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batch Enrollment'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'Back to Students closes a local import even when the URL is unchanged',
    (tester) async {
      await openHub(tester, _Users(), _Records());
      await tester.tap(find.text('Back to Students'));
      await tester.pumpAndSettle();
      expect(find.text('Batch Student Enrollment Hub'), findsNothing);
      expect(find.text('User & Team Management'), findsOneWidget);
      expect(find.text('Batch Enrollment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final success in [true, false]) {
    testWidgets(
      success
          ? '256-student success closes import while the records refresh is pending'
          : 'failed student import retains its staged draft and remains navigable',
      (tester) async {
        final users = _Users();
        final records = _Records();
        // Seed a draft before opening the hub, as when resuming a staged import.
        await openHub(tester, users, records);
        await tester.tap(find.text('Back to Students'));
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(UserManagementScreen)),
        );
        container
            .read(studentBatchDraftProvider.notifier)
            .saveFreshDraft(
              stagedFiles: [],
              parsedStudents: List.generate(
                256,
                (i) => <String, dynamic>{
                  'id_number': 'S$i',
                  'first_name': 'Student',
                  'last_name': '$i',
                  'email': 'student$i@example.com',
                  'year_level': '1st Year',
                  'role': 'student',
                },
              ),
            );
        await tester.tap(find.text('Batch Enrollment'));
        await tester.pumpAndSettle();
        final confirm = find.text('Confirm Student Intake (256 students)');
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pump();
        expect(users.importCalls, 1);
        final pendingButton = find.ancestor(
          of: find.text('Importing 256 students...'),
          matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
        );
        expect(tester.widget<ButtonStyleButton>(pendingButton).onPressed, isNull);
        expect(container.read(studentBatchDraftProvider).hasFreshDraft, isTrue);
        users.result.complete(success);
        await tester.pumpAndSettle();
        if (success) {
          expect(find.text('Batch Student Enrollment Hub'), findsNothing);
          expect(find.text('Batch Enrollment'), findsOneWidget);
          expect(
            container.read(studentBatchDraftProvider).hasFreshDraft,
            isFalse,
          );
          expect(records.refresh.isCompleted, isFalse);
          expect(records.loads, 2); // Initial load plus one post-import reload.
        } else {
          expect(find.text('Batch Student Enrollment Hub'), findsOneWidget);
          expect(
            container.read(studentBatchDraftProvider).freshParsedStudents,
            hasLength(256),
          );
          await tester.ensureVisible(find.text('Back to Students'));
          await tester.tap(find.text('Back to Students'));
          await tester.pumpAndSettle();
          expect(find.text('Batch Enrollment'), findsOneWidget);
        }
        records.refresh.complete();
        await tester.pump(const Duration(seconds: 7));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
