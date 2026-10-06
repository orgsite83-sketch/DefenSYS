import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/audit_compliance/audit_compliance_screen.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/system_audit_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/defense/defense_stages_provider.dart';
import 'package:defensys/services/grading/grade_center_provider.dart';

import '../helpers/pump_app.dart';

class FakeAuthNotifier extends AuthNotifier {
  final Map<String, dynamic> _user;

  FakeAuthNotifier(this._user);

  @override
  AuthState build() {
    return AuthState(
      isRestoring: false,
      user: _user,
      token: 'fake_jwt_token',
    );
  }
}

class FakeSystemAuditNotifier extends SystemAuditNotifier {
  final SystemAuditState _initialState;

  FakeSystemAuditNotifier(this._initialState);

  @override
  SystemAuditState build() => _initialState;

  @override
  Future<void> fetch({int? page}) async {}

  @override
  Future<bool> updateReviewStatus(int logId, String reviewStatus, {String? reason}) async {
    final updatedLogs = state.logs.map((l) {
      if (l['id'] == logId) {
        return {
          ...l,
          'review_status': reviewStatus,
          'review_status_label': reviewStatus == 'reviewed' ? 'Reviewed' : 'Needs Review',
        };
      }
      return l;
    }).toList();
    state = state.copyWith(
      logs: updatedLogs,
      selectedLog: state.selectedLog?['id'] == logId
          ? {
              ...state.selectedLog!,
              'review_status': reviewStatus,
              'review_status_label': reviewStatus == 'reviewed' ? 'Reviewed' : 'Needs Review',
            }
          : state.selectedLog,
    );
    return true;
  }
}

class FakeAcademicPeriodNotifier extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState();

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class FakeStudentTeamsNotifier extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState();

  @override
  Future<void> fetchTeams({
    String? search,
    String? level,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? eventName,
    bool clearYearLevel = false,
    bool clearEventName = false,
    String? successMessage,
  }) async {}
}

class FakeDefenseStagesNotifier extends DefenseStagesNotifier {
  @override
  DefenseStagesState build() => const DefenseStagesState();

  @override
  Future<void> fetchStages({String? successMessage}) async {}
}

class FakeGradeCenterNotifier extends GradeCenterNotifier {
  @override
  GradeCenterState build() => const GradeCenterState();

  @override
  Future<void> fetchGrades({
    String? search,
    String? level,
    String? stage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

void main() {
  final mockAuditLogs = <Map<String, dynamic>>[
    {
      'id': 45,
      'actor': 1,
      'actor_name': 'Admin User',
      'action': 'repository.archive_upload',
      'category': 'repository',
      'category_label': 'Project Archive Evidence',
      'target_type': 'ArchiveEntry',
      'target_id': '45',
      'old_values': {'status': ''},
      'new_values': {
        'file_name': '3rdYear.CAP301.ProjectAlpha.1stSemester.pdf',
        'file_size': '2.4 MB',
        'status': 'Approved',
        'track': 'capstone',
        'year_level': '3rd Year',
        'replaced_existing': false,
        'team_id': '101',
      },
      'reason': 'Official capstone archive upload',
      'review_status': 'needs_review',
      'review_status_label': 'Needs Review',
      'created_at': '2026-08-30T07:38:00Z',
    },
    {
      'id': 44,
      'actor': 1,
      'actor_name': 'Admin User',
      'action': 'rubric.create',
      'category': 'grade_center',
      'category_label': 'Grade & Rubrics',
      'target_type': 'Rubric',
      'target_id': '9',
      'old_values': {},
      'new_values': {
        'name': 'Capstone Final Defense Rubric',
        'scope': 'capstone',
        'evaluation_type': 'Panelist',
        'semester': '1st Sem 2026-2027',
        'panel_weight': 50,
        'adviser_weight': 30,
        'peer_weight': 20,
      },
      'reason': 'Configured institutional evaluation criteria',
      'review_status': 'reviewed',
      'review_status_label': 'Reviewed',
      'created_at': '2026-08-30T07:37:00Z',
    },
    {
      'id': 43,
      'actor': 1,
      'actor_name': 'Admin User',
      'action': 'grade.finalize_for_archive',
      'category': 'grade_center',
      'category_label': 'Grade & Rubrics',
      'target_type': 'TeamGrade',
      'target_id': '12',
      'old_values': {'final_grade': '88.00'},
      'new_values': {
        'team_name': 'Team ByteForce',
        'stage_label': 'Final Defense',
        'final_grade': '94.50',
        'status': 'published',
      },
      'reason': 'Final panel grade approved',
      'review_status': 'needs_review',
      'review_status_label': 'Needs Review',
      'created_at': '2026-08-30T07:35:00Z',
    },
  ];

  final mockAuditState = SystemAuditState(
    isLoading: false,
    logs: mockAuditLogs,
    counts: {
      'filtered': 45,
      'needs_review': 17,
      'captured': 28,
      'reviewed': 28,
    },
    options: {
      'categories': [
        {'value': 'repository', 'label': 'Archive & Vault'},
        {'value': 'grade_center', 'label': 'Grade & Rubrics'},
      ],
      'review_statuses': [
        {'value': 'needs_review', 'label': 'Needs Review'},
        {'value': 'reviewed', 'label': 'Reviewed'},
      ],
      'actions': ['repository.archive_upload', 'rubric.create', 'grade.finalize_for_archive'],
    },
    totalCount: 45,
    currentPage: 1,
    totalPages: 5,
    selectedLog: mockAuditLogs.first,
  );

  testWidgets('AuditComplianceScreen renders redesigned executive tabs, KPI ribbon, and filter toolbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(
          () => FakeAuthNotifier({
            'id': 1,
            'username': 'admin',
            'role': 'admin',
            'is_superuser': true,
          }),
        ),
        systemAuditProvider.overrideWith(
          () => FakeSystemAuditNotifier(mockAuditState),
        ),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentTeamsProvider.overrideWith(() => FakeStudentTeamsNotifier()),
        defenseStagesProvider.overrideWith(() => FakeDefenseStagesNotifier()),
        gradeCenterProvider.overrideWith(() => FakeGradeCenterNotifier()),
      ],
    );

    // 1. Executive Tab Bar
    expect(find.text('Audit Trail'), findsWidgets);
    expect(find.text('Report Center'), findsOneWidget);
    expect(find.text('Live Logs'), findsOneWidget);
    expect(find.text('PDF Center'), findsOneWidget);

    // 2. Clean KPI Metrics
    expect(find.text('Total Events'), findsOneWidget);
    expect(find.text('Needs Review'), findsWidgets);
    expect(find.text('Reviewed'), findsWidgets);
    expect(find.text('Review Progress'), findsOneWidget);

    // 3. Search & Filter Toolbar
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('All Process Areas'), findsOneWidget);
    expect(find.text('All Actions'), findsOneWidget);
    expect(find.text('Date Range'), findsOneWidget);
    expect(find.text('More Filters'), findsOneWidget);

    // 4. Status Tabs
    expect(find.text('All Events'), findsOneWidget);

    // 5. Master Table Columns (Original Layout)
    expect(find.text('DATE / TIME'), findsOneWidget);
    expect(find.text('PROCESS AREA'), findsOneWidget);
    expect(find.text('CONTROL ACTIVITY'), findsOneWidget);
    expect(find.text('RESPONSIBLE USER'), findsOneWidget);
    expect(find.text('REVIEW STATUS'), findsOneWidget);

    // 6. Master-Detail Inspector Panel
    expect(find.text('Event Details'), findsOneWidget);
    expect(find.text('Actor'), findsOneWidget);
    expect(find.text('Date & Time'), findsOneWidget);
    expect(find.text('Process Area'), findsOneWidget);
    expect(find.text('Target Resource'), findsOneWidget);
    expect(find.text('Mark as reviewed'), findsWidgets);
  });

  testWidgets('AuditComplianceScreen opens and tests raw JSON modal dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(
          () => FakeAuthNotifier({
            'id': 1,
            'username': 'admin',
            'role': 'admin',
            'is_superuser': true,
          }),
        ),
        systemAuditProvider.overrideWith(
          () => FakeSystemAuditNotifier(mockAuditState),
        ),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentTeamsProvider.overrideWith(() => FakeStudentTeamsNotifier()),
        defenseStagesProvider.overrideWith(() => FakeDefenseStagesNotifier()),
        gradeCenterProvider.overrideWith(() => FakeGradeCenterNotifier()),
      ],
    );

    // Open "More options" popup menu
    final moreOptionsBtn = find.byTooltip('More options');
    expect(moreOptionsBtn, findsOneWidget);
    await tester.ensureVisible(moreOptionsBtn);
    await tester.tap(moreOptionsBtn);
    await tester.pumpAndSettle();

    // Click "View Raw JSON" menu item
    final viewJsonItem = find.text('View Raw JSON');
    expect(viewJsonItem, findsOneWidget);
    await tester.tap(viewJsonItem);
    await tester.pumpAndSettle();

    expect(find.text('Raw Audit Log Payload'), findsOneWidget);
    expect(find.text('Copy JSON'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    // Dismiss modal
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('AuditComplianceScreen displays diff and status correctly across create, update, and delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final rubricCreateLog = mockAuditLogs[1]; // rubric.create
    final rubricDeleteLog = {
      'id': 99,
      'actor': 1,
      'actor_name': 'Admin User',
      'action': 'rubric.delete',
      'category': 'grade_center',
      'category_label': 'Grade & Rubrics',
      'target_type': 'Rubric',
      'target_id': '9',
      'old_values': {'name': 'Deleted Proposal Rubric'},
      'new_values': {'deleted': true},
      'reason': 'Deprecated criteria',
      'review_status': 'needs_review',
      'review_status_label': 'Needs Review',
      'created_at': '2026-08-30T08:00:00Z',
    };

    final rubricAuditState = mockAuditState.copyWith(
      logs: [rubricCreateLog, rubricDeleteLog],
      selectedLog: rubricCreateLog,
    );

    await pumpDefensysWidget(
      tester,
      const AuditComplianceScreen(),
      overrides: [
        authProvider.overrideWith(
          () => FakeAuthNotifier({
            'id': 1,
            'username': 'admin',
            'role': 'admin',
            'is_superuser': true,
          }),
        ),
        systemAuditProvider.overrideWith(
          () => FakeSystemAuditNotifier(rubricAuditState),
        ),
        academicPeriodProvider.overrideWith(() => FakeAcademicPeriodNotifier()),
        studentTeamsProvider.overrideWith(() => FakeStudentTeamsNotifier()),
        defenseStagesProvider.overrideWith(() => FakeDefenseStagesNotifier()),
        gradeCenterProvider.overrideWith(() => FakeGradeCenterNotifier()),
      ],
    );

    // When rubric.create is selected:
    expect(find.text('Rubric created'), findsOneWidget);
    expect(find.text('Resource Details'), findsOneWidget);

    // Verify "Open Rubric" is present in More options menu
    final moreOptionsBtn = find.byTooltip('More options');
    await tester.tap(moreOptionsBtn);
    await tester.pumpAndSettle();
    expect(find.text('Open Rubric'), findsOneWidget);

    // Dismiss menu by tapping outside
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Now select the rubric.delete entry in the table
    await tester.tap(find.text('rubric.delete'));
    await tester.pumpAndSettle();

    expect(find.text('This resource has been deleted'), findsOneWidget);
    expect(find.text('Last Known State'), findsOneWidget);
  });
}


