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
    expect(find.text('Audit Trail Register'), findsWidgets);
    expect(find.text('Report Export Center'), findsOneWidget);
    expect(find.text('Live Logs'), findsOneWidget);
    expect(find.text('PDF Center'), findsOneWidget);

    // 2. Compact KPI Ribbon
    expect(find.text('ISO 9001 Readiness'), findsOneWidget);
    expect(find.text('Open Findings'), findsOneWidget);
    expect(find.text('Verified Evidence'), findsOneWidget);
    expect(find.text('Pending Action'), findsOneWidget);
    expect(find.text('Reviewed Ratio'), findsOneWidget);

    // 3. Compact Filter Toolbar
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);

    // Tap "Filters" button to open modal
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    expect(find.text('Filter Audit Register'), findsOneWidget);
    expect(find.text('Academic Scope'), findsOneWidget);
    expect(find.text('Process Area (Category)'), findsOneWidget);
    expect(find.text('Review & Compliance Status'), findsOneWidget);
    expect(find.text('Date Range'), findsOneWidget);
    expect(find.text('Apply Filters'), findsOneWidget);

    // Tap "Cancel" to dismiss modal
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 4. Primary Hero Table
    expect(find.text('45 entries'), findsOneWidget);
    expect(find.text('DATE / TIME'), findsOneWidget);
    expect(find.text('PROCESS AREA'), findsOneWidget);
    expect(find.text('CONTROL ACTIVITY'), findsOneWidget);
    expect(find.text('RESPONSIBLE USER'), findsOneWidget);
    expect(find.text('REVIEW STATUS'), findsOneWidget);

    // 5. Rich Evidence Preview Card for Repository Upload
    expect(find.text('Evidence Packet Review'), findsOneWidget);
    expect(find.text('#45'), findsOneWidget);
    expect(find.text('3rdYear.CAP301.ProjectAlpha.1stSemester.pdf'), findsWidgets);
    expect(find.text('Visual Change Diff'), findsOneWidget);
    expect(find.text('Raw Audit JSON'), findsOneWidget);
  });

  testWidgets('AuditComplianceScreen switches to Raw Audit JSON view and verifies status', (
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

    // Click "Raw Audit JSON" tab
    final rawJsonTab = find.text('Raw Audit JSON');
    expect(rawJsonTab, findsOneWidget);
    await tester.tap(rawJsonTab);
    await tester.pumpAndSettle();

    expect(find.text('Copy JSON'), findsOneWidget);
    expect(find.text('Audit Event Payload (JSON)'), findsOneWidget);

    // Click "Verify & Mark as Reviewed" button
    final verifyBtn = find.text('Verify & Mark as Reviewed');
    expect(verifyBtn, findsOneWidget);
    await tester.tap(verifyBtn);
    await tester.pumpAndSettle();

    // Verify it updated to "Revert to Needs Review"
    expect(find.text('Revert to Needs Review'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
