import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/toasts/feedback_toast.dart';

import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/import/student_bulk_import_csv.dart';
import 'access_control/access_control_view.dart';
import 'bulk_import/bulk_import_view.dart';
import 'bulk_import/official_class_list_parser.dart';
import 'bulk_import/student_batch_enrollment_hub_view.dart';
import 'components/faculty_staff_view.dart';
import 'components/guest_codes_card.dart';
import 'components/students_enrollment_view.dart';
import 'dialogs/add_student_dialog.dart';
import 'dialogs/download_sample_csv_dialog.dart';
import 'dialogs/guest_code_dialog.dart';
import 'dialogs/user_create_edit_dialog.dart';
import '../widgets/student_records_rollover_modal.dart';

enum UserManagementTab { students, faculty, guests }
enum _SubView { none, bulkImport, accessControl, studentBatchHub }

/// Unified User & Student Management Screen Orchestrator.
class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({
    super.key,
    this.initialBulkImport = false,
    this.initialUserTab = UserManagementTab.faculty,
  });

  final bool initialBulkImport;
  final UserManagementTab initialUserTab;

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  static const _maroon = DefensysUi.primaryMaroon;
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _line = Color(0xFFE5E7EB);

  late UserManagementTab _currentTab;
  _SubView _subView = _SubView.none;
  String _bulkImportType = 'student';
  StudentHubMode _studentHubInitialMode = StudentHubMode.freshIntake;

  Map<String, dynamic>? _accessControlUser;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialUserTab;
    if (widget.initialBulkImport) {
      _subView = _SubView.bulkImport;
      _currentTab = UserManagementTab.faculty;
      _bulkImportType = 'faculty';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userManagementProvider.notifier).fetchUsers();
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
    });
  }

  void _openStudentBatchHub([StudentHubMode mode = StudentHubMode.freshIntake]) {
    setState(() {
      _studentHubInitialMode = mode;
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
    setState(() {
      _accessControlUser = Map<String, dynamic>.from(user);
      _subView = _SubView.accessControl;
    });
  }

  void _closeSubView() {
    setState(() {
      _subView = _SubView.none;
      _accessControlUser = null;
    });
  }

  Future<void> _showUserDialog([Map<String, dynamic>? user]) async {
    final payload = await UserCreateEditDialog.show(
      context,
      user: user,
    );
    if (payload != null && mounted) {
      final notifier = ref.read(userManagementProvider.notifier);
      if (user != null) {
        final id = user['id'];
        final success = await notifier.updateUser(
          id is int ? id : int.parse(id.toString()),
          payload,
        );
        if (success && mounted && _accessControlUser != null && _accessControlUser!['id'] == id) {
          final updatedUser = ref.read(userManagementProvider).users.firstWhere(
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
          user != null ? 'User updated successfully.' : 'User created successfully.',
        );
      }
    }
  }

  Future<void> _confirmRevokeGuestCode(int codeId) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Revoke Guest Code?',
      message: 'This will deactivate access for this external guest panelist.',
      confirmLabel: 'Revoke Code',
      destructive: true,
    );
    if (confirmed == true && mounted) {
      await ref.read(userManagementProvider.notifier).revokeGuestCode(codeId);
      if (mounted) {
        showSuccessToast(context, 'Guest code revoked.');
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
      await ref.read(userManagementProvider.notifier).resetUserPassword(
            id is int ? id : int.parse(id.toString()),
          );
      if (mounted) {
        showSuccessToast(context, 'Password reset to default ID number.');
      }
    }
  }

  Future<void> _showGuestCodeDialog() async {
    final state = ref.read(userManagementProvider);
    final payload = await GuestCodeGenerateDialog.show(
      context,
      schedules: state.defenseSchedules,
    );
    if (payload != null && mounted) {
      final result = await ref.read(userManagementProvider.notifier).generateGuestCode(payload);
      if (result != null && mounted) {
        await GeneratedGuestCodeDialog.show(context, guestCode: result);
      }
    }
  }

  Future<void> _showAddStudentDialog() async {
    final state = ref.read(studentAcademicRecordsProvider);
    final payload = await AddStudentDialog.show(
      context,
      students: state.students,
      schoolYears: state.schoolYears,
      activeSemester: state.activeSemester,
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

  Future<void> _showRolloverDialog() async {
    final rolloverSearchCtrl = TextEditingController();
    final actions = <String, String>{};
    bool hasCsv = false;

    await ref
        .read(studentAcademicRecordsProvider.notifier)
        .fetchRolloverPreview(students: []);

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          final state = ref.watch(studentAcademicRecordsProvider);

          final filtered = state.rolloverRows.where((row) {
            final q = rolloverSearchCtrl.text.trim().toLowerCase();
            if (q.isEmpty) return true;
            final rec = row['record'] as Map? ?? {};
            final name = rec['student_name']?.toString().toLowerCase() ?? '';
            final user = rec['student_username']?.toString().toLowerCase() ?? '';
            return name.contains(q) || user.contains(q);
          }).toList();

          int nonDropCount = 0;
          for (final row in state.rolloverRows) {
            final rec = row['record'] as Map? ?? {};
            final key = rec['id'] != null
                ? rec['id'].toString()
                : rec['student_username']?.toString() ?? '';
            final act = actions[key] ?? row['action_default'] ?? 'promote';
            if (act != 'drop') nonDropCount++;
          }

          return StudentRecordsRolloverModal(
            useWarningChrome: false,
            activeLabel: state.activeSemester?['display_name'] ??
                '${state.activeSemester?['school_year']} ${state.activeSemester?['label']}',
            totalCount: state.rolloverRows.length,
            missingCount: 0,
            searchQuery: rolloverSearchCtrl.text,
            filtered: filtered,
            rolloverSearchCtrl: rolloverSearchCtrl,
            actions: actions,
            onPromoteAll: () {
              setModalState(() {
                for (final row in state.rolloverRows) {
                  final rec = row['record'] as Map? ?? {};
                  final key = rec['id'] != null
                      ? rec['id'].toString()
                      : rec['student_username']?.toString() ?? '';
                  actions[key] = 'promote';
                }
              });
            },
            onRetainAll: () {
              setModalState(() {
                for (final row in state.rolloverRows) {
                  final rec = row['record'] as Map? ?? {};
                  final key = rec['id'] != null
                      ? rec['id'].toString()
                      : rec['student_username']?.toString() ?? '';
                  actions[key] = 'retain';
                }
              });
            },
            onSearchChanged: (_) => setModalState(() {}),
            onSearchClear: () {
              rolloverSearchCtrl.clear();
              setModalState(() {});
            },
            onActionChanged: (key, val) {
              if (val != null) setModalState(() => actions[key] = val);
            },
            onClose: () => Navigator.of(dialogCtx).pop(),
            onConfirm: () async {
              final confirmActions = <Map<String, dynamic>>[];
              for (final row in state.rolloverRows) {
                final rec = row['record'] as Map? ?? {};
                final key = rec['id'] != null
                    ? rec['id'].toString()
                    : rec['student_username']?.toString() ?? '';
                final act = actions[key] ?? row['action_default'] ?? 'promote';

                final pr = row['promote_result'] as Map? ?? {};
                confirmActions.add({
                  'record_id': rec['id'],
                  'username': rec['student_username'],
                  'first_name': rec['first_name'],
                  'last_name': rec['last_name'],
                  'email': rec['student_email'],
                  'action': act,
                  'year_level': pr['year_level'],
                  'section': pr['section'],
                });
              }

              final ok = await ref
                  .read(studentAcademicRecordsProvider.notifier)
                  .confirmRollover(confirmActions);

              if (ok && mounted) {
                Navigator.of(dialogCtx).pop();
                showSuccessToast(context, 'Rollover completed successfully.');
              }
            },
            nonDropCount: nonDropCount,
            rolloverHasTarget: (row, act) => true,
            rolloverResult: (row, act) {
              if (act == 'drop') return 'Excluded from new term (LOA / Dropped)';
              if (act == 'retain') return 'Retained in same year level';
              final pr = row['promote_result'] as Map? ?? {};
              return 'Enrolled in ${pr['year_level'] ?? 'Next Level'} (${pr['section'] ?? 'Class Section'})';
            },
            asInt: (v) => v is int ? v : (v != null ? int.tryParse(v.toString()) ?? 0 : 0),
            hasCsvUploaded: hasCsv,
            onUploadCsv: () async {
              final csv = await pickCsvTextFile();
              if (csv == null) return;
              final parsed = parseOfficialClassListCsv(csv);
              if (parsed.students.isEmpty) {
                if (mounted) {
                  showErrorToast(context, 'No valid student rows found in CSV file.');
                }
                return;
              }

              hasCsv = true;
              await ref
                  .read(studentAcademicRecordsProvider.notifier)
                  .fetchRolloverPreview(students: parsed.students);
              setModalState(() {});
            },
            onClearCsv: () async {
              hasCsv = false;
              await ref
                  .read(studentAcademicRecordsProvider.notifier)
                  .fetchRolloverPreview(students: []);
              setModalState(() {});
            },
            hasValidationErrors: false,
          );
        },
      ),
    );
  }

  Widget _buildHeaderActions(UserManagementState state) {
    if (_currentTab == UserManagementTab.students) {
      final studentState = ref.watch(studentAcademicRecordsProvider);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: studentState.isSaving
                ? null
                : () => _openStudentBatchHub(StudentHubMode.freshIntake),
            icon: const Icon(Icons.dynamic_feed_rounded, size: 16),
            label: const Text('Batch Enrollment'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DefensysUi.primaryMaroon,
              side: const BorderSide(color: DefensysUi.primaryMaroon),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: studentState.isSaving ? null : _showAddStudentDialog,
            icon: const Icon(Icons.person_add_rounded, size: 16),
            label: const Text('Add Single Student'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DefensysUi.primaryMaroon,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      );
    }

    if (_currentTab == UserManagementTab.faculty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: state.isSaving ? null : () => _openBulkImport('faculty'),
            icon: const Icon(Icons.file_upload_outlined, size: 16),
            label: const Text('Bulk Import Faculty'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DefensysUi.primaryMaroon,
              side: const BorderSide(color: DefensysUi.primaryMaroon),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: state.isSaving ? null : () => _showUserDialog(),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
            label: const Text('Add Single User'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DefensysUi.primaryMaroon,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      );
    }

    if (_currentTab == UserManagementTab.guests) {
      return ElevatedButton.icon(
        onPressed: state.isSaving ? null : _showGuestCodeDialog,
        icon: const Icon(Icons.key_rounded, size: 16),
        label: const Text('Generate Guest Code'),
        style: ElevatedButton.styleFrom(
          backgroundColor: DefensysUi.warningText,
          foregroundColor: Colors.white,
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
        initialMode: _studentHubInitialMode,
        userState: state,
        academicState: academicState,
        onBack: _closeSubView,
        onDownloadSample: () => DownloadSampleCsvDialog.show(context),
        onConfirmFreshImport: (users, studentContext) async {
          final success = await ref.read(userManagementProvider.notifier).bulkImport(
                users,
                studentContext: studentContext,
              );
          if (success && context.mounted) {
            showSuccessToast(context, '${users.length} students imported successfully!');
            ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
            ref.read(userManagementProvider.notifier).fetchUsers();
            _closeSubView();
          }
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
            filename: 'faculty_staff_template.csv',
            content: sampleFacultyCsvTemplate,
          );
          if (context.mounted) {
            showSuccessToast(context, 'Faculty & staff sample template downloaded.');
          }
        },
        onConfirmUpload: (users, studentContext) async {
          final success = await ref.read(userManagementProvider.notifier).bulkImport(
                users,
                studentContext: studentContext,
              );
          if (success && context.mounted) {
            final isStudent = studentContext != null;
            final label = isStudent ? 'students' : 'users';
            showSuccessToast(context, '${users.length} $label imported successfully!');
            ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
            ref.read(userManagementProvider.notifier).fetchUsers();
            _closeSubView();
          }
        },
      );
    }

    if (_subView == _SubView.accessControl && _accessControlUser != null) {
      return AccessControlView(
        user: _accessControlUser!,
        state: state,
        onBack: _closeSubView,
        onEditProfile: () => _showUserDialog(_accessControlUser),
        onResetPassword: () => _confirmResetPassword(_accessControlUser!),
        onSaveRoles: (payload) async {
          final id = _accessControlUser!['id'];
          final success = await ref.read(userManagementProvider.notifier).updateUser(
                id is int ? id : int.parse(id.toString()),
                payload,
              );
          if (success && context.mounted) {
            showSuccessToast(context, 'Role permissions saved.');
            _closeSubView();
          }
        },
      );
    }

    final studentCount = studentState.records.length;
    final facultyCount = state.users.where((u) {
      final r = u['role']?.toString().toLowerCase() ?? '';
      return r == 'faculty' || r == 'admin';
    }).length;
    final guestCount = state.guestCodes.length;

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          DefensysPageHeader(
            title: 'User & Team Management',
            subtitle:
                'Manage system access, assign faculty roles, and configure student capstone teams.',
            actions: _buildHeaderActions(state),
          ),
          const SizedBox(height: 20),

          // Primary Tab Bar Switcher
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTabButton(
                  tab: UserManagementTab.students,
                  label: 'Students & Enrollment',
                  count: studentCount,
                  icon: Icons.school_rounded,
                ),
                const SizedBox(width: 6),
                _buildTabButton(
                  tab: UserManagementTab.faculty,
                  label: 'Faculty & Staff',
                  count: facultyCount,
                  icon: Icons.co_present_rounded,
                ),
                const SizedBox(width: 6),
                _buildTabButton(
                  tab: UserManagementTab.guests,
                  label: 'Guest Access Codes',
                  count: guestCount,
                  icon: Icons.vpn_key_rounded,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Active Tab Content
          switch (_currentTab) {
            UserManagementTab.students => StudentsEnrollmentView(
                onOpenBulkImport: () => _openStudentBatchHub(StudentHubMode.freshIntake),
              ),
            UserManagementTab.faculty => FacultyStaffView(
                onOpenBulkImport: () => _openBulkImport('faculty'),
                onOpenAccessControl: _openAccessControl,
              ),
            UserManagementTab.guests => GuestCodesCard(
                state: state,
                onRevokeGuestCode: _confirmRevokeGuestCode,
              ),
          },
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required UserManagementTab tab,
    required String label,
    required int count,
    required IconData icon,
  }) {
    final isSelected = _currentTab == tab;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _currentTab = tab),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _maroon : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected ? Colors.white : _muted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? Colors.white : _ink,
                  fontFamily: DefensysUi.fontFamily,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.22)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : _muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
