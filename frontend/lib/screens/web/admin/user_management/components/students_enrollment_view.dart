import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';

import '../dialogs/add_student_dialog.dart';
import '../dialogs/user_create_edit_dialog.dart';
import '../../widgets/student_records_rollover_modal.dart';
import '../bulk_import/official_class_list_parser.dart';

/// The Students & Academic Enrollment view within User Management.
class StudentsEnrollmentView extends ConsumerStatefulWidget {
  const StudentsEnrollmentView({
    super.key,
    this.onOpenBulkImport,
  });

  final VoidCallback? onOpenBulkImport;

  @override
  ConsumerState<StudentsEnrollmentView> createState() =>
      _StudentsEnrollmentViewState();
}

class _StudentsEnrollmentViewState extends ConsumerState<StudentsEnrollmentView> {
  static const _maroon = DefensysUi.primaryMaroon;
  static const _blue = DefensysUi.techBlue;
  static const _muted = DefensysUi.steelGrey;
  static const _ink = DefensysUi.textDark;
  static const _line = Color(0xFFE5E7EB);
  static const _gold = Color(0xFFF59E0B);

  final TextEditingController _searchCtrl = TextEditingController();
  int _page = 0;
  int _rowsPerPage = 10;
  final List<int> _rowsPerPageOptions = const [10, 25, 50, 100];

  String _yearLevelFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v != null) return int.tryParse(v.toString()) ?? 0;
    return 0;
  }

  int _count(StudentAcademicRecordsState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value != null) {
      final parsed = int.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    if (key == 'all') return state.records.length;
    if (key == 'filtered') return state.records.length;
    if (key == 'students_with_records') return state.students.length;
    return 0;
  }

  List<Map<String, dynamic>> _filteredRecords(List<Map<String, dynamic>> records) {
    var list = records;
    if (_yearLevelFilter != 'ALL') {
      list = list.where((r) => r['year_level']?.toString() == _yearLevelFilter).toList();
    }
    return list;
  }

  List<Map<String, dynamic>> _visibleRows(List<Map<String, dynamic>> list) {
    final start = _page * _rowsPerPage;
    if (start >= list.length) return [];
    final end = (start + _rowsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  Future<void> _showAddOrEditStudentDialog([Map<String, dynamic>? record]) async {
    final state = ref.read(studentAcademicRecordsProvider);
    final payload = await AddStudentDialog.show(
      context,
      record: record,
      students: state.students,
      schoolYears: state.schoolYears,
      activeSemester: state.activeSemester,
    );

    if (payload != null && mounted) {
      final notifier = ref.read(studentAcademicRecordsProvider.notifier);
      final bool success;
      if (record != null && record['id'] != null) {
        final recordId = _asInt(record['id']);
        success = await notifier.updateRecord(recordId, payload);
      } else {
        success = await notifier.addRecord(payload);
      }

      if (success && mounted) {
        showSuccessToast(
          context,
          record != null ? 'Academic record updated.' : 'Student enrolled successfully.',
        );
      }
    }
  }

  Future<void> _showStudentHistory(Map<String, dynamic> record) async {
    final username = record['student_username']?.toString() ?? '';
    final studentName = record['student_name']?.toString() ?? username;
    final studentEmail = record['student_email']?.toString() ?? '';
    final studentId = record['student_id'];
    if (username.isEmpty) return;

    final history = await ref
        .read(studentAcademicRecordsProvider.notifier)
        .fetchStudentHistory(username);

    if (!mounted) return;

    final users = ref.read(userManagementProvider).users;
    Map<String, dynamic> studentUser;
    try {
      final existing = users.firstWhere(
        (u) => (studentId != null && u['id'] == studentId) || u['username'] == username,
      );
      studentUser = Map<String, dynamic>.from(existing);
    } catch (_) {
      studentUser = {
        if (studentId != null) 'id': studentId,
        'username': username,
        'first_name': record['first_name'] ?? (studentName.contains(' ') ? studentName.split(' ').first : studentName),
        'last_name': record['last_name'] ?? (studentName.contains(' ') ? studentName.split(' ').skip(1).join(' ') : ''),
        'name': studentName,
        'email': studentEmail,
        'role': 'student',
        'is_active': record['is_active'] != false,
      };
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentIsActive = studentUser['is_active'] != false;
          final currentName = (studentUser['name']?.toString().trim().isNotEmpty == true)
              ? studentUser['name']
              : '${studentUser['first_name'] ?? ''} ${studentUser['last_name'] ?? ''}'.trim();
          final currentEmail = studentUser['email']?.toString() ?? studentEmail;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.school_rounded, color: _maroon),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Student Profile & Enrollment',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Student Personal Profile Header Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _line),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _maroon.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _maroon.withValues(alpha: 0.3)),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: _maroon,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentName.isNotEmpty ? currentName : studentName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: _ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      currentEmail.isNotEmpty ? currentEmail : 'No email provided',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: _muted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Student ID: $username',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: currentIsActive
                                      ? const Color(0xFFDCFCE7)
                                      : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  currentIsActive ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: currentIsActive
                                        ? const Color(0xFF166534)
                                        : const Color(0xFF991B1B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final payload = await UserCreateEditDialog.show(
                                      context,
                                      user: studentUser,
                                    );
                                    if (payload != null && mounted) {
                                      final id = studentUser['id'];
                                      if (id != null) {
                                        final success = await ref
                                            .read(userManagementProvider.notifier)
                                            .updateUser(
                                              id is int ? id : int.parse(id.toString()),
                                              payload,
                                            );
                                        if (success && mounted) {
                                          showSuccessToast(context, 'Student profile updated.');
                                          ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
                                          ref.read(userManagementProvider.notifier).fetchUsers();
                                          setDialogState(() {
                                            studentUser.addAll(payload);
                                            if (payload['first_name'] != null || payload['last_name'] != null) {
                                              studentUser['name'] = '${payload['first_name'] ?? ''} ${payload['last_name'] ?? ''}'.trim();
                                            }
                                          });
                                        }
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.person_outline_rounded, size: 15),
                                  label: const Text('Edit User Profile'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _maroon,
                                    side: const BorderSide(color: _line),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final name = studentUser['first_name'] ?? studentUser['name'] ?? username;
                                    final confirmed = await showConfirmDialog(
                                      context,
                                      title: 'Reset Password?',
                                      message: 'Reset password for $name to their default ID number ($username)?',
                                      confirmLabel: 'Reset Password',
                                    );
                                    if (confirmed == true && mounted) {
                                      final id = studentUser['id'];
                                      if (id != null) {
                                        await ref
                                            .read(userManagementProvider.notifier)
                                            .resetUserPassword(
                                              id is int ? id : int.parse(id.toString()),
                                            );
                                        if (mounted) {
                                          showSuccessToast(context, 'Password reset to default ID number.');
                                        }
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.lock_reset_rounded, size: 15),
                                  label: const Text('Reset Password'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: DefensysUi.warningText,
                                    side: const BorderSide(color: _line),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'ENROLLMENT HISTORY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    history.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: Text('No historical records found.')),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: history.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final item = history[i];
                              final isCurrent = item['id'] == record['id'];
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCurrent ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item['year_level']?.toString() ?? '-',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isCurrent ? const Color(0xFF166534) : _ink,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  '${item['school_year'] ?? ''} · ${item['semester'] ?? ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                subtitle: Text(
                                  'Section: ${item['section']?.toString().isEmpty ?? true ? 'No Section' : item['section']}',
                                  style: const TextStyle(fontSize: 12, color: _muted),
                                ),
                                trailing: isCurrent
                                    ? const Chip(
                                        label: Text('Active Term', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                                        backgroundColor: Color(0xFFDCFCE7),
                                        labelStyle: TextStyle(color: Color(0xFF166534)),
                                        padding: EdgeInsets.zero,
                                      )
                                    : null,
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showAddOrEditStudentDialog(record);
                },
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('Edit Academic Record'),
                style: FilledButton.styleFrom(backgroundColor: _maroon),
              ),
            ],
          );
        },
      ),
    );
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
            asInt: _asInt,
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studentAcademicRecordsProvider);
    final allFiltered = _filteredRecords(state.records);
    final visibleRows = _visibleRows(allFiltered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stat Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'All Records',
                value: '${_count(state, 'all')}',
                subtitle: 'Total academic records',
                icon: Icons.badge_outlined,
                iconColor: _maroon,
                iconBg: const Color(0xFFFDF2F2),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Filtered',
                value: '${allFiltered.length}',
                subtitle: 'Current table results',
                icon: Icons.filter_alt_outlined,
                iconColor: _blue,
                iconBg: const Color(0xFFEFF6FF),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Students',
                value: '${_count(state, 'students_with_records')}',
                subtitle: 'Distinct student accounts',
                icon: Icons.school_outlined,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFECFDF5),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Active Term',
                value: state.activeSemester?['label']?.toString() ?? 'Active Sem',
                subtitle: state.activeSemester?['school_year']?.toString() ?? 'A.Y. Configured',
                icon: Icons.calendar_today_rounded,
                iconColor: _gold,
                iconBg: const Color(0xFFFEF3C7),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // Table Card
        DefensysCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _searchCtrl,
                        onSubmitted: (val) {
                          setState(() => _page = 0);
                          ref
                              .read(studentAcademicRecordsProvider.notifier)
                              .fetchRecords(search: val);
                        },
                        decoration: InputDecoration(
                          hintText: 'Search by student name, ID, or email...',
                          hintStyle: const TextStyle(fontSize: 13, color: _muted),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _muted),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _line),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _yearLevelDropdown(),
                  const SizedBox(width: 12),
                  _schoolYearDropdown(state),
                  const SizedBox(width: 12),
                  _semesterDropdown(state),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _page = 0;
                        _yearLevelFilter = 'ALL';
                      });
                      ref.read(studentAcademicRecordsProvider.notifier).fetchRecords(
                            search: '',
                            schoolYear: '',
                            semester: '',
                          );
                    },
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _muted,
                      side: const BorderSide(color: _line),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              if (state.isLoading && state.records.isEmpty)
                DefensysSkeleton.list(count: 6, rowHeight: 52)
              else if (visibleRows.isEmpty)
                DefensysEmptyState.table(
                  icon: Icons.person_off_outlined,
                  title: 'No Student Records Found',
                  description:
                      'No student records match your active search criteria or filter parameters.',
                  size: DefensysEmptyStateSize.standard,
                )
              else
                _buildTable(visibleRows),

              const SizedBox(height: 18),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 14),
              _buildPagination(allFiltered.length),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _yearLevelDropdown() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _yearLevelFilter,
          style: const TextStyle(fontSize: 13, color: _ink, fontFamily: DefensysUi.fontFamily),
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('All Year Levels')),
            DropdownMenuItem(value: '1st Year', child: Text('1st Year')),
            DropdownMenuItem(value: '2nd Year', child: Text('2nd Year')),
            DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
            DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _yearLevelFilter = val;
                _page = 0;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _schoolYearDropdown(StudentAcademicRecordsState state) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.schoolYear.isEmpty ? '' : state.schoolYear,
          style: const TextStyle(fontSize: 13, color: _ink, fontFamily: DefensysUi.fontFamily),
          items: [
            const DropdownMenuItem(value: '', child: Text('All School Years')),
            ...state.schoolYears.map((sy) {
              final label = sy['label']?.toString() ?? '';
              return DropdownMenuItem(value: label, child: Text(label));
            }),
          ],
          onChanged: (val) {
            setState(() => _page = 0);
            ref.read(studentAcademicRecordsProvider.notifier).fetchRecords(schoolYear: val ?? '');
          },
        ),
      ),
    );
  }

  Widget _semesterDropdown(StudentAcademicRecordsState state) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.semester.isEmpty ? '' : state.semester,
          style: const TextStyle(fontSize: 13, color: _ink, fontFamily: DefensysUi.fontFamily),
          items: const [
            DropdownMenuItem(value: '', child: Text('All Semesters')),
            DropdownMenuItem(value: '1st Semester', child: Text('1st Semester')),
            DropdownMenuItem(value: '2nd Semester', child: Text('2nd Semester')),
          ],
          onChanged: (val) {
            setState(() => _page = 0);
            ref.read(studentAcademicRecordsProvider.notifier).fetchRecords(semester: val ?? '');
          },
        ),
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> rows) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.5),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(1.4),
        3: FlexColumnWidth(2.2),
        4: FlexColumnWidth(1.2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Header
        TableRow(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line, width: 1.5)),
          ),
          children: [
            _th('Student'),
            _th('Year Level'),
            _th('Section'),
            _th('Academic Period'),
            _th('Action', align: TextAlign.end),
          ],
        ),
        // Rows
        ...rows.asMap().entries.map((e) {
          final index = e.key;
          final r = e.value;
          final isEven = index.isEven;
          final yearLevel = r['year_level']?.toString() ?? 'Unassigned';
          final section = r['section']?.toString().trim() ?? '';
          final period = '${r['semester'] ?? ''}, ${r['school_year'] ?? ''}';

          return TableRow(
            decoration: BoxDecoration(
              color: isEven ? Colors.white : const Color(0xFFFAFAFA),
              border: const Border(bottom: BorderSide(color: _line)),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['student_name']?.toString() ?? r['student_username']?.toString() ?? 'Student',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r['student_username']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: Text(
                      yearLevel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  section.isEmpty ? '—' : section,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  period,
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => _showStudentHistory(r),
                    icon: const Icon(Icons.folder_open_rounded, size: 14),
                    label: const Text('Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _maroon,
                      side: const BorderSide(color: Color(0xFFFECDD3)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _th(String title, {TextAlign align = TextAlign.start}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        textAlign: align,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: _muted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPagination(int totalCount) {
    final totalPages = (totalCount / _rowsPerPage).ceil();
    final startItem = totalCount == 0 ? 0 : _page * _rowsPerPage + 1;
    final endItem = ((_page + 1) * _rowsPerPage).clamp(0, totalCount);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text('Rows per page: ', style: TextStyle(fontSize: 12.5, color: _muted)),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _rowsPerPage,
                items: _rowsPerPageOptions.map((n) {
                  return DropdownMenuItem(value: n, child: Text('$n', style: const TextStyle(fontSize: 12.5)));
                }).toList(),
                onChanged: (n) {
                  if (n != null) {
                    setState(() {
                      _rowsPerPage = n;
                      _page = 0;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '$startItem - $endItem of $totalCount',
              style: const TextStyle(fontSize: 12.5, color: _muted),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _page > 0 ? () => setState(() => _page--) : null,
            ),
            Text(
              '${_page + 1} / ${totalPages == 0 ? 1 : totalPages}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _page < totalPages - 1 ? () => setState(() => _page++) : null,
            ),
          ],
        ),
      ],
    );
  }
}
