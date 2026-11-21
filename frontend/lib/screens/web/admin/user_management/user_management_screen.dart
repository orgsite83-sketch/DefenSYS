import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/widgets/table/defensys_segmented_control.dart';
import 'package:defensys/toasts/feedback_toast.dart';

import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/import/student_bulk_import_csv.dart';
import 'package:defensys/utils/import/user_bulk_import_draft.dart';
import 'access_control/access_control_view.dart';
import 'access_control/panelist_eligibility_view.dart';
import 'bulk_import/bulk_import_view.dart';
import 'bulk_import/student_batch_enrollment_hub_view.dart';
import 'components/faculty_staff_view.dart';
import 'external_evaluators/external_evaluator_views.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'components/students_enrollment_view.dart';
import '../../../../navigation/admin_attention_context.dart';
import 'dialogs/add_student_dialog.dart';
import 'dialogs/download_sample_csv_dialog.dart';
import 'dialogs/user_create_edit_dialog.dart';

enum UserManagementTab { students, faculty, guests }

enum _SubView {
  none,
  bulkImport,
  accessControl,
  panelistEligibility,
  studentBatchHub,
}

/// Unified User & Student Management Screen Orchestrator.
class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({
    super.key,
    this.initialBulkImport = false,
    this.initialEnrollment = false,
    this.attentionContext,
    this.initialUserTab = UserManagementTab.students,
    this.initialPanelistAccess = false,
    this.initialPanelistTab = 'faculty',
    this.initialPanelistRequestId,
    this.initialAccessUserId,
  });

  final bool initialBulkImport;
  final bool initialEnrollment;
  final AdminAttentionContext? attentionContext;
  final UserManagementTab initialUserTab;
  final bool initialPanelistAccess;
  final String initialPanelistTab;
  final int? initialPanelistRequestId, initialAccessUserId;

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  late UserManagementTab _currentTab;
  _SubView _subView = _SubView.none;
  String _bulkImportType = 'student';

  Map<String, dynamic>? _accessControlUser;
  bool _accessLoading = false;
  String? _accessError;
  int _accessRequest = 0;
  int? _loadingAccessId;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialUserTab;
    if (widget.initialEnrollment) _subView = _SubView.studentBatchHub;
    if (widget.initialPanelistAccess) _subView = _SubView.panelistEligibility;
    if (widget.initialAccessUserId != null) {
      _subView = _SubView.accessControl;
      Future.microtask(() => _loadAccessUser(widget.initialAccessUserId!));
    }
    if (widget.initialBulkImport) {
      _subView = _SubView.bulkImport;
      _currentTab = UserManagementTab.faculty;
      _bulkImportType = 'faculty';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final draft = await loadUserBulkImportDraft();
      if (mounted &&
          draft != null &&
          draft.isOpen &&
          draft.rowCount > 0 &&
          _subView == _SubView.none &&
          !widget.initialBulkImport) {
        if (draft.importType == 'faculty') {
          _openBulkImport('faculty');
        } else if (draft.importType == 'student') {
          _openStudentBatchHub();
        }
      }
      ref.read(userManagementProvider.notifier).fetchUsers();
      ref.read(externalEvaluatorProvider.notifier).fetch();
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
      ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
    });
  }

  @override
  void didUpdateWidget(covariant UserManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPanelistAccess != widget.initialPanelistAccess ||
        oldWidget.initialAccessUserId != widget.initialAccessUserId ||
        oldWidget.initialUserTab != widget.initialUserTab ||
        oldWidget.initialEnrollment != widget.initialEnrollment ||
        oldWidget.attentionContext?.identity !=
            widget.attentionContext?.identity) {
      _currentTab = widget.initialUserTab;
      _subView = widget.initialEnrollment
          ? _SubView.studentBatchHub
          : widget.initialPanelistAccess
          ? _SubView.panelistEligibility
          : widget.initialAccessUserId != null
          ? _SubView.accessControl
          : _SubView.none;
      if (widget.initialAccessUserId != null &&
          _accessControlUser?['id'] != widget.initialAccessUserId) {
        Future.microtask(() => _loadAccessUser(widget.initialAccessUserId!));
      } else if (widget.initialAccessUserId == null) {
        ++_accessRequest;
        _accessControlUser = null;
        _accessLoading = false;
      }
    }
  }

  Future<void> _loadAccessUser(int id) async {
    _loadingAccessId = id;
    final request = ++_accessRequest;
    if (!mounted) return;
    setState(() {
      _accessLoading = true;
      _accessError = null;
      _accessControlUser = null;
    });
    try {
      final user = await ref
          .read(userManagementProvider.notifier)
          .fetchManagedUser(id);
      if (mounted && request == _accessRequest) {
        setState(() => _accessControlUser = user);
      }
    } catch (_) {
      if (mounted && request == _accessRequest) {
        setState(
          () => _accessError =
              'This user could not be loaded. Refresh to try again.',
        );
      }
    } finally {
      if (mounted && request == _accessRequest) {
        setState(() => _accessLoading = false);
      }
    }
  }

  bool _navigateUserView(Map<String, String> query) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return false;
    final previous = router.routeInformationProvider.value.uri.queryParameters;
    router.go(
      Uri(
        path: '/admin/users',
        queryParameters: {
          'tab': 'faculty',
          if (query['view'] == 'panelists') ...{
            if (previous['faculty'] case final faculty?) 'faculty': faculty,
            if (previous['returnTo'] case final destination?)
              'returnTo': destination,
          },
          ...query,
        },
      ).toString(),
    );
    return true;
  }

  void _openPanelistAccess() {
    if (!_navigateUserView({'view': 'panelists'})) {
      setState(() => _subView = _SubView.panelistEligibility);
    }
  }

  void _openRoleId(int id) {
    if (!_navigateUserView({'view': 'roles', 'user': '$id'})) {
      setState(() => _subView = _SubView.accessControl);
      _loadAccessUser(id);
    }
  }

  void _openStudentBatchHub() {
    setState(() {
      _subView = _SubView.studentBatchHub;
    });
  }

  void _openBulkImport(String type) {
    setState(() {
      _bulkImportType = type;
      _subView = _SubView.bulkImport;
    });
  }

  void _openAccessControl(Map<String, dynamic> user) {
    if (_navigateUserView({'view': 'roles', 'user': '${user['id']}'})) return;
    setState(() {
      _accessControlUser = Map<String, dynamic>.from(user);
      _subView = _SubView.accessControl;
    });
  }

  void _closeSubView() {
    // Imports are local subviews, so going to the current URL may not rebuild
    // this widget. Always close locally before synchronizing the route.
    final returnToStudents = _subView == _SubView.studentBatchHub;
    setState(() {
      if (returnToStudents) _currentTab = UserManagementTab.students;
      _subView = _SubView.none;
      _accessControlUser = null;
      ++_accessRequest;
      _accessLoading = false;
      _accessError = null;
    });
    final router = GoRouter.maybeOf(context);
    // A retained sidebar branch can finish importing after another tab opens.
    if (router?.routeInformationProvider.value.uri.path == '/admin/users') {
      _navigateUserView({
        'tab': _currentTab == UserManagementTab.faculty
            ? 'faculty'
            : 'students',
      });
    }
  }

  Future<void> _showUserDialog([Map<String, dynamic>? user]) async {
    final payload = await UserCreateEditDialog.show(
      context,
      user: user,
      defaultRole: 'faculty',
    );
    if (payload != null && mounted) {
      final notifier = ref.read(userManagementProvider.notifier);
      if (payload['_action'] == 'delete') {
        final id = payload['id'] ?? user?['id'];
        if (id != null) {
          final userId = id is int ? id : int.parse(id.toString());
          final success = await notifier.deleteUser(userId);
          if (success && mounted) {
            if (_accessControlUser != null &&
                _accessControlUser!['id'] == userId) {
              setState(() {
                _accessControlUser = null;
              });
            }
            showSuccessToast(context, 'User account deleted successfully.');
          } else if (mounted) {
            final err =
                ref.read(userManagementProvider).error ??
                'Failed to delete user account.';
            showErrorToast(context, err);
          }
        }
        return;
      }

      if (user != null) {
        final id = user['id'];
        final success = await notifier.updateUser(
          id is int ? id : int.parse(id.toString()),
          payload,
        );
        if (success &&
            mounted &&
            _accessControlUser != null &&
            _accessControlUser!['id'] == id) {
          final updatedUser = ref
              .read(userManagementProvider)
              .users
              .firstWhere(
                (u) => u['id'] == id,
                orElse: () => _accessControlUser!,
              );
          setState(() {
            _accessControlUser = Map<String, dynamic>.from(updatedUser);
          });
        }
      } else {
        await notifier.addUser(payload);
      }
      if (mounted) {
        showSuccessToast(
          context,
          user != null
              ? 'Faculty member updated successfully.'
              : 'Faculty member created successfully.',
        );
      }
    }
  }

  Future<void> _confirmResetPassword(Map<String, dynamic> user) async {
    final name = user['first_name'] ?? user['username'] ?? 'User';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset Password?',
      message: 'Reset password for $name to their default ID number?',
      confirmLabel: 'Reset Password',
    );
    if (confirmed == true && mounted) {
      final id = user['id'];
      await ref
          .read(userManagementProvider.notifier)
          .resetUserPassword(id is int ? id : int.parse(id.toString()));
      if (mounted) {
        showSuccessToast(context, 'Password reset to default ID number.');
      }
    }
  }

  Future<void> _showAddStudentDialog() async {
    final state = ref.read(studentAcademicRecordsProvider);
    final activeSem =
        ref.read(academicPeriodProvider).activeSemester ?? state.activeSemester;
    final payload = await AddStudentDialog.show(
      context,
      students: state.students,
      schoolYears: state.schoolYears,
      activeSemester: activeSem,
    );

    if (payload != null && mounted) {
      final success = await ref
          .read(studentAcademicRecordsProvider.notifier)
          .addRecord(payload);
      if (success && mounted) {
        showSuccessToast(context, 'Student enrolled successfully.');
      }
    }
  }

  Widget _buildHeaderActions(UserManagementState state) {
    if (_currentTab == UserManagementTab.students) {
      final studentState = ref.watch(studentAcademicRecordsProvider);
      return DefensysShadcnScope(
        maroonActions: true,
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ReportExportMenu(
              reportId: 'student-enrollment',
              params: {
                'term_context': studentState.termContext,
                'year_level': studentState.yearLevelFilter,
                'section': studentState.sectionFilter,
                'school_year': studentState.schoolYear,
                'semester': studentState.semester,
              },
            ),
            ShadButton.outline(
              onPressed: studentState.isSaving ? null : _showAddStudentDialog,
              leading: const Icon(Icons.person_add_rounded, size: 16),
              child: const Text('Add Single Student'),
            ),
            ShadButton(
              onPressed: studentState.isSaving
                  ? null
                  : () => _openStudentBatchHub(),
              leading: const Icon(Icons.dynamic_feed_rounded, size: 16),
              child: const Text('Enroll students'),
            ),
          ],
        ),
      );
    }

    if (_currentTab == UserManagementTab.faculty) {
      return DefensysShadcnScope(
        maroonActions: true,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ShadButton.outline(
              onPressed: state.isSaving ? null : _openPanelistAccess,
              height: DefensysTokens.buttonHeightPrimary,
              backgroundColor: DefensysTokens.surfaceOf(context),
              leading: const Icon(LucideIcons.shieldCheck, size: 18),
              child: const Text('Panelist access'),
            ),
            ShadButton.outline(
              onPressed: state.isSaving ? null : () => _showUserDialog(),
              height: DefensysTokens.buttonHeightPrimary,
              backgroundColor: DefensysTokens.surfaceOf(context),
              leading: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              child: const Text('Add Single Faculty'),
            ),
            ShadButton(
              onPressed: state.isSaving
                  ? null
                  : () => _openBulkImport('faculty'),
              height: DefensysTokens.buttonHeightPrimary,
              leading: const Icon(Icons.file_upload_outlined, size: 18),
              child: const Text('Bulk Import Faculty'),
            ),
          ],
        ),
      );
    }

    if (_currentTab == UserManagementTab.guests) {
      return DefensysShadcnScope(
        maroonActions: true,
        child: ShadButton(
          onPressed: () => ExternalEvaluatorCreateDialog.show(context),
          leading: const Icon(LucideIcons.plus, size: 16),
          child: const Text('Add External Evaluator'),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userManagementProvider);
    final academicState = ref.watch(academicPeriodProvider);
    final studentState = ref.watch(studentAcademicRecordsProvider);

    if (_subView == _SubView.studentBatchHub) {
      return StudentBatchEnrollmentHubView(
        key: ValueKey(
          widget.attentionContext?.identity ?? 'student-enrollment',
        ),
        attentionContext: widget.attentionContext,
        unifiedEnrollment: true,
        userState: state,
        academicState: academicState,
        onBack: _closeSubView,
        onDownloadSample: () => DownloadSampleCsvDialog.show(context),
        onConfirmFreshImport: (users, studentContext) async {
          final success = await ref
              .read(userManagementProvider.notifier)
              .bulkImport(users, studentContext: studentContext);
          if (success && context.mounted) {
            showSuccessToast(
              context,
              ref.read(userManagementProvider).message ??
                  'Student intake completed.',
            );
            ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
            _closeSubView();
          } else if (context.mounted) {
            showErrorToast(
              context,
              ref.read(userManagementProvider).error ??
                  'Failed to import students.',
            );
          }
          return success;
        },
      );
    }

    if (_subView == _SubView.bulkImport) {
      return BulkImportView(
        initialImportType: _bulkImportType,
        state: state,
        academicState: academicState,
        onBack: _closeSubView,
        onPickFile: () {},
        onDownloadSample: () async {
          await downloadTextFile(
            filename: sampleFacultyCsvFilename,
            content: sampleFacultyCsvTemplate,
          );
          if (context.mounted) {
            showSuccessToast(
              context,
              'Faculty & staff sample template downloaded.',
            );
          }
        },
        onConfirmUpload: (users, studentContext) async {
          final success = await ref
              .read(userManagementProvider.notifier)
              .bulkImport(users, studentContext: studentContext);
          if (!context.mounted) return;
          if (success) {
            await clearUserBulkImportDraft();
            if (!context.mounted) return;
            final isStudent = studentContext != null;
            final label = isStudent ? 'students' : 'faculty & staff';
            showSuccessToast(
              context,
              ref.read(userManagementProvider).message ??
                  '$label import completed.',
            );
            ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
            _closeSubView();
          } else {
            final errorMsg =
                ref.read(userManagementProvider).error ??
                'Failed to import users.';
            showErrorToast(context, errorMsg);
          }
        },
      );
    }

    if (_subView == _SubView.panelistEligibility) {
      return PanelistEligibilityView(
        onBack: _closeSubView,
        initialTab: widget.initialPanelistTab,
        initialRequestId: widget.initialPanelistRequestId,
        onEditRoles: _openRoleId,
        onTabChanged: GoRouter.maybeOf(context) == null
            ? null
            : (tab) => _navigateUserView({'view': 'panelists', 'section': tab}),
        onSelectRequest: GoRouter.maybeOf(context) == null
            ? null
            : (id) => _navigateUserView({
                'view': 'panelists',
                'section': widget.initialPanelistTab == 'history'
                    ? 'history'
                    : 'requests',
                'request': '$id',
              }),
        onRequestClosed: GoRouter.maybeOf(context) == null
            ? null
            : () => _navigateUserView({
                'view': 'panelists',
                'section': widget.initialPanelistTab,
              }),
      );
    }

    if (_subView == _SubView.accessControl &&
        (_accessLoading || _accessError != null)) {
      return Center(
        child: _accessLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_accessError!),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _loadAccessUser(_loadingAccessId!),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: _closeSubView,
                    child: const Text('Back to Users'),
                  ),
                ],
              ),
      );
    }

    if (_subView == _SubView.accessControl && _accessControlUser != null) {
      return AccessControlView(
        user: _accessControlUser!,
        state: state,
        onBack: _closeSubView,
        onOpenPanelistAccess: _openPanelistAccess,
        onEditProfile: () => _showUserDialog(_accessControlUser),
        onResetPassword: () => _confirmResetPassword(_accessControlUser!),
        onSaveRoles: (payload) async {
          final id = _accessControlUser!['id'];
          final success = await ref
              .read(userManagementProvider.notifier)
              .updateUser(id is int ? id : int.parse(id.toString()), payload);
          if (success && context.mounted) {
            showSuccessToast(context, 'Role permissions saved.');
            _closeSubView();
          }
        },
      );
    }

    final enrollment = studentState.counts['enrollment'] as Map?;
    final activeId =
        academicState.activeSemester?['id'] ??
        (academicState.schoolYears.isEmpty
            ? (studentState.activeSemester?['id'])
            : null);
    final studentCount = enrollment?['semester_id'] == activeId
        ? (enrollment?['enrolled']?.toString())
        : null;
    final facultyCount = state.users.where((u) {
      final r = u['role']?.toString().toLowerCase() ?? '';
      return r == 'faculty' || r == 'admin';
    }).length;
    final guestCount = ref.watch(externalEvaluatorProvider).evaluators.length;

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          DefensysPageHeader(
            title: 'User & Team Management',
            actionsBreakpoint: 1000,
            subtitle:
                'Manage system access, assign faculty roles, and configure student capstone teams.',
            actions: _buildHeaderActions(state),
          ),
          const SizedBox(height: 20),

          // Primary Tab Bar Switcher
          DefensysSegmentedControl<UserManagementTab>(
            value: _currentTab,
            items: [
              DefensysSegmentItem(
                value: UserManagementTab.students,
                label: 'Students & Enrollment',
                badgeLabel: studentCount,
                icon: Icons.school_rounded,
              ),
              DefensysSegmentItem(
                value: UserManagementTab.faculty,
                label: 'Faculty & Staff',
                badgeLabel: '$facultyCount',
                icon: Icons.co_present_rounded,
              ),
              DefensysSegmentItem(
                value: UserManagementTab.guests,
                label: 'External Evaluators',
                badgeLabel: '$guestCount',
                icon: Icons.vpn_key_rounded,
              ),
            ],
            onChanged: (tab) => setState(() => _currentTab = tab),
          ),

          const SizedBox(height: 24),

          // Active Tab Content
          switch (_currentTab) {
            UserManagementTab.students => StudentsEnrollmentView(
              onOpenBulkImport: () => _openStudentBatchHub(),
            ),
            UserManagementTab.faculty => FacultyStaffView(
              onOpenBulkImport: () => _openBulkImport('faculty'),
              onOpenAccessControl: _openAccessControl,
            ),
            UserManagementTab.guests => const ExternalEvaluatorDirectory(),
          },
        ],
      ),
    );
  }
}
