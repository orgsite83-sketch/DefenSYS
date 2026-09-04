import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/academic/student_academic_records_provider.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/pit_instructor_provider.dart';
import '../../../../services/pit_lead_cohort_provider.dart';
import '../../../../services/user_management_provider.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/defensys_skeleton.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../../admin/user_management/bulk_import/student_batch_enrollment_hub_view.dart';
import '../../admin/user_management/dialogs/add_student_dialog.dart';
import '../../admin/user_management/dialogs/download_sample_csv_dialog.dart';
import '../../admin/user_management/dialogs/student_profile_details_dialog.dart';
import '../../admin/widgets/defensys_admin_shell.dart';

enum _PitUserManagementTab { students, instructors }
enum _SubView { none, studentBatchHub }

class PitLeadCohortScreen extends ConsumerStatefulWidget {
  final VoidCallback? onCreateTeam;

  const PitLeadCohortScreen({super.key, this.onCreateTeam});

  @override
  ConsumerState<PitLeadCohortScreen> createState() =>
      _PitLeadCohortScreenState();
}

class _PitLeadCohortScreenState extends ConsumerState<PitLeadCohortScreen> {
  static const _maroon = DefensysUi.primaryMaroon;
  static const _blue = DefensysUi.techBlue;
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _line = Color(0xFFE5E7EB);
  static const _gold = Color(0xFFF59E0B);

  _PitUserManagementTab _currentTab = _PitUserManagementTab.students;
  _SubView _subView = _SubView.none;
  StudentHubMode _studentHubInitialMode = StudentHubMode.freshIntake;

  // Student Tab Controllers & Filters
  final _studentSearchCtrl = TextEditingController();
  String _selectedSection = 'ALL';
  String _teamStatusFilter = 'all';
  String _cohortScope = 'active';
  int _studentPage = 0;
  int _studentRowsPerPage = 10;

  // Instructor Tab Controllers & Filters
  final _instructorSearchCtrl = TextEditingController();
  String _instructorStatusFilter = 'ALL';
  int _instructorPage = 0;
  int _instructorRowsPerPage = 10;

  final List<int> _rowsPerPageOptions = const [10, 25, 50, 100];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAllData();
    });
  }

  @override
  void dispose() {
    _studentSearchCtrl.dispose();
    _instructorSearchCtrl.dispose();
    super.dispose();
  }

  void _refreshAllData() {
    ref.read(pitLeadCohortProvider.notifier).fetchCohort(
          search: _studentSearchCtrl.text,
          teamStatusFilter: _teamStatusFilter,
          scope: _cohortScope,
        );
    ref.read(pitInstructorProvider.notifier).fetchAssignments();
    ref.read(academicPeriodProvider.notifier).fetchPeriods();
    ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
    ref.read(userManagementProvider.notifier).fetchUsers();
  }

  void _applyStudentFilters() {
    ref.read(pitLeadCohortProvider.notifier).fetchCohort(
          search: _studentSearchCtrl.text,
          teamStatusFilter: _teamStatusFilter,
          scope: _cohortScope,
        );
    setState(() => _studentPage = 0);
  }

  void _openStudentBatchHub([
    StudentHubMode mode = StudentHubMode.freshIntake,
  ]) {
    setState(() {
      _studentHubInitialMode = mode;
      _subView = _SubView.studentBatchHub;
    });
  }

  void _closeSubView() {
    setState(() {
      _subView = _SubView.none;
    });
  }

  Future<void> _showAddStudentDialog() async {
    final userState = ref.read(userManagementProvider);
    final academicState = ref.read(academicPeriodProvider);
    final studentState = ref.read(studentAcademicRecordsProvider);

    final payload = await AddStudentDialog.show(
      context,
      students: userState.users
          .where((u) => u['role']?.toString().toLowerCase() == 'student')
          .toList(),
      schoolYears: studentState.schoolYears,
      activeSemester: academicState.activeSemester ?? studentState.activeSemester,
    );

    if (payload != null && mounted) {
      final success = await ref
          .read(studentAcademicRecordsProvider.notifier)
          .addRecord(payload);
      if (success && mounted) {
        showSuccessToast(context, 'Student enrolled successfully.');
        _refreshAllData();
      } else if (mounted) {
        final err = ref.read(studentAcademicRecordsProvider).error ??
            'Failed to enroll student.';
        showErrorToast(context, err);
      }
    }
  }

  Future<void> _showStudentHistory(Map<String, dynamic> student) async {
    final studentState = ref.read(studentAcademicRecordsProvider);
    final academicState = ref.read(academicPeriodProvider);
    final cohortState = ref.read(pitLeadCohortProvider);

    final activeSem = academicState.activeSemester ??
        studentState.activeSemester ??
        {'label': cohortState.activeSemester ?? 'Active Semester'};

    // Build unified student record format for details dialog
    final record = <String, dynamic>{
      'id': student['id'],
      'student_id': student['id'],
      'student_username': student['username'] ?? student['id']?.toString(),
      'first_name': student['first_name'] ?? '',
      'last_name': student['last_name'] ?? '',
      'full_name': student['name'] ?? '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'.trim(),
      'student_email': student['email'] ?? '',
      'email': student['email'] ?? '',
      'section': student['section'] ?? '',
      'year_level': student['year_level'] ?? cohortState.pitLeadYear ?? '1st Year',
      'academic_period': student['term_label'] ?? cohortState.activeSemester ?? 'Current Term',
      'team_status': student['team_status'] ?? 'unassigned',
      'team_name': student['team_name'],
      'team_id': student['team_id'],
    };

    await StudentProfileDetailsDialog.show(
      context,
      record: record,
      schoolYears: studentState.schoolYears,
      activeSemester: activeSem,
    );
  }

  Future<void> _openRolloverPreview() async {
    final notifier = ref.read(pitLeadCohortProvider.notifier);
    final preview = await notifier.fetchRolloverPreview();
    if (!mounted || preview == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _PitRolloverPreviewDialog(
        preview: preview,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () async {
          final result = await notifier.confirmRollover();
          if (!dialogContext.mounted || result == null) return;
          Navigator.of(dialogContext).pop(true);
          final created = result['created_count'] ?? 0;
          final skipped = result['skipped_count'] ?? 0;
          final target = result['target_semester'] is Map
              ? Map<String, dynamic>.from(result['target_semester'] as Map)
              : <String, dynamic>{};
          final targetLabel =
              target['display_name']?.toString() ?? 'the target term';
          if (mounted) {
            showSuccessToast(
              context,
              'Rollover complete. $created created, $skipped skipped for $targetLabel.',
            );
          }
        },
      ),
    );

    if (!mounted || confirmed != true) return;
    _refreshAllData();
  }

  Future<void> _showAssignInstructorDialog({
    String? defaultSection,
    int? defaultFacultyId,
  }) async {
    final instructorState = ref.read(pitInstructorProvider);
    final cohortState = ref.read(pitLeadCohortProvider);

    // Extract distinct sections from students
    final distinctSections = <String>{
      ...cohortState.students
          .map((s) => s['section']?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty),
      ...instructorState.assignments
          .map((a) => a['section']?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty),
    }.toList()
      ..sort();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _AssignSectionInstructorDialog(
        facultyList: instructorState.faculty,
        availableSections: distinctSections,
        yearLevel: cohortState.pitLeadYear ?? '1st Year',
        defaultSection: defaultSection,
        defaultFacultyId: defaultFacultyId,
      ),
    );

    if (result != null && mounted) {
      final success = await ref
          .read(pitInstructorProvider.notifier)
          .assignInstructor(
            facultyId: result['faculty_id'] as int,
            section: result['section'] as String,
          );
      if (success && mounted) {
        showSuccessToast(context, 'Section instructor assigned successfully.');
        _refreshAllData();
      } else if (mounted) {
        final err = ref.read(pitInstructorProvider).error ??
            'Failed to assign instructor.';
        showErrorToast(context, err);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cohortState = ref.watch(pitLeadCohortProvider);
    final instructorState = ref.watch(pitInstructorProvider);
    final userState = ref.watch(userManagementProvider);
    final academicState = ref.watch(academicPeriodProvider);

    if (_subView == _SubView.studentBatchHub) {
      return StudentBatchEnrollmentHubView(
        initialMode: _studentHubInitialMode,
        userState: userState,
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
              '${users.length} students imported successfully!',
            );
            _refreshAllData();
            _closeSubView();
          }
        },
      );
    }

    final pitYear = cohortState.pitLeadYear ?? '1st Year';
    final semester = cohortState.activeSemester ?? 'Current Semester';

    final studentCount = cohortState.students.length;
    final activeInstructorsCount = instructorState.assignments
        .where((a) => a['is_active'] == true)
        .length;

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          DefensysPageHeader(
            icon: Icons.school_outlined,
            title: 'User Management',
            subtitle: '$pitYear · $semester',
            actions: _buildHeaderActions(cohortState, instructorState),
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
                  title: 'Students & Enrollment',
                  count: studentCount,
                  icon: Icons.school_rounded,
                  tab: _PitUserManagementTab.students,
                ),
                const SizedBox(width: 4),
                _buildTabButton(
                  title: 'Section Instructors',
                  count: activeInstructorsCount,
                  icon: Icons.assignment_ind_rounded,
                  tab: _PitUserManagementTab.instructors,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tab Content
          if (_currentTab == _PitUserManagementTab.students)
            _buildStudentsView(cohortState, instructorState)
          else
            _buildInstructorsView(instructorState, cohortState),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required int count,
    required IconData icon,
    required _PitUserManagementTab tab,
  }) {
    final isSelected = _currentTab == tab;
    return InkWell(
      onTap: () {
        if (_currentTab != tab) {
          setState(() {
            _currentTab = tab;
          });
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
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
              size: 16,
              color: isSelected ? Colors.white : _muted,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : _ink,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : _muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderActions(
    PitLeadCohortState cohortState,
    PitInstructorState instructorState,
  ) {
    if (_currentTab == _PitUserManagementTab.students) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: cohortState.isSaving ? null : () => _openStudentBatchHub(),
            icon: const Icon(Icons.dynamic_feed_rounded, size: 16),
            label: const Text('Batch Enrollment'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _maroon,
              side: const BorderSide(color: _maroon),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: cohortState.isSaving ? null : _openRolloverPreview,
            icon: const Icon(Icons.update_rounded, size: 16),
            label: const Text('Rollover Preview'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _maroon,
              side: const BorderSide(color: _maroon),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: cohortState.isSaving ? null : _showAddStudentDialog,
            icon: const Icon(Icons.person_add_rounded, size: 16),
            label: const Text('Add Single Student'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      );
    }

    return ElevatedButton.icon(
      onPressed: instructorState.isSaving
          ? null
          : () => _showAssignInstructorDialog(),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
      label: const Text('Assign Section Instructor'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _maroon,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  // ==========================================
  // TAB 1: STUDENTS & ENROLLMENT
  // ==========================================
  Widget _buildStudentsView(
    PitLeadCohortState state,
    PitInstructorState instructorState,
  ) {
    // Filter students
    var list = state.students;
    final query = _studentSearchCtrl.text.trim().toLowerCase();

    if (_selectedSection != 'ALL') {
      list = list.where((s) => s['section']?.toString().trim() == _selectedSection).toList();
    }
    if (_teamStatusFilter != 'all') {
      list = list.where((s) => s['team_status']?.toString() == _teamStatusFilter).toList();
    }
    if (query.isNotEmpty) {
      list = list.where((s) {
        final id = s['id']?.toString().toLowerCase() ?? '';
        final un = s['username']?.toString().toLowerCase() ?? '';
        final name = s['name']?.toString().toLowerCase() ?? '';
        final em = s['email']?.toString().toLowerCase() ?? '';
        final sec = s['section']?.toString().toLowerCase() ?? '';
        return id.contains(query) ||
            un.contains(query) ||
            name.contains(query) ||
            em.contains(query) ||
            sec.contains(query);
      }).toList();
    }

    // Extract distinct sections for filter dropdown
    final distinctSections = <String>{
      ...state.students
          .map((s) => s['section']?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty),
    }.toList()
      ..sort();

    // Map active instructor by section
    final instructorBySection = <String, String>{};
    for (final assignment in instructorState.assignments.where((a) => a['is_active'] == true)) {
      final sec = assignment['section']?.toString().trim() ?? '';
      if (sec.isNotEmpty) {
        instructorBySection[_slug(sec)] = assignment['faculty_name']?.toString() ?? 'Faculty';
      }
    }

    final totalCount = state.counts['all'] is num
        ? (state.counts['all'] as num).toInt()
        : state.students.length;
    final filteredCount = list.length;
    final distinctStudents = state.students.length;
    final activeTerm = state.activeSemester ?? 'Active Term';

    final start = _studentPage * _studentRowsPerPage;
    final end = (start + _studentRowsPerPage).clamp(0, list.length);
    final visibleRows = (start < list.length) ? list.sublist(start, end) : <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 4 Metric Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'All Records',
                value: '$totalCount',
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
                value: '$filteredCount',
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
                value: '$distinctStudents',
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
                value: activeTerm.contains(',') ? activeTerm.split(',').first.trim() : activeTerm,
                subtitle: activeTerm.contains(',') ? activeTerm.split(',').last.trim() : (state.pitLeadYear ?? 'PIT Year'),
                icon: Icons.calendar_today_rounded,
                iconColor: _gold,
                iconBg: const Color(0xFFFEF3C7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Main Table Card
        DefensysCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search & Filter Toolbar
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _studentSearchCtrl,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _muted,
                            size: 18,
                          ),
                          hintText: 'Search by student name, ID, or email...',
                          hintStyle: const TextStyle(color: _muted, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _maroon),
                          ),
                        ),
                        onChanged: (_) => _applyStudentFilters(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Section Filter
                  _buildDropdownFilter(
                    value: _selectedSection,
                    items: [
                      const DropdownMenuItem(value: 'ALL', child: Text('All Sections')),
                      ...distinctSections.map((sec) => DropdownMenuItem(value: sec, child: Text(sec))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedSection = val;
                          _studentPage = 0;
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  // Team Status Filter
                  _buildDropdownFilter(
                    value: _teamStatusFilter,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Team Statuses')),
                      DropdownMenuItem(value: 'on_team', child: Text('On Team')),
                      DropdownMenuItem(value: 'unassigned', child: Text('Unassigned')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _teamStatusFilter = val;
                        });
                        _applyStudentFilters();
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  // Scope Filter
                  _buildDropdownFilter(
                    value: _cohortScope,
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Current Term')),
                      DropdownMenuItem(value: 'history', child: Text('Historical Roster')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _cohortScope = val;
                        });
                        _applyStudentFilters();
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      _studentSearchCtrl.clear();
                      setState(() {
                        _selectedSection = 'ALL';
                        _teamStatusFilter = 'all';
                        _cohortScope = 'active';
                        _studentPage = 0;
                      });
                      _applyStudentFilters();
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

              // Table / Skeleton / Empty
              if (state.isLoading && state.students.isEmpty)
                DefensysSkeleton.list(count: 6, rowHeight: 56)
              else if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: DefensysEmptyState(
                      icon: Icons.school_outlined,
                      title: 'No student records found',
                      description: 'No students match your search or filter criteria in this cohort.',
                      size: DefensysEmptyStateSize.compact,
                    ),
                  ),
                )
              else
                _buildStudentsTable(visibleRows, instructorBySection, state.pitLeadYear ?? '1st Year', state.activeSemester ?? 'Active Term'),

              const SizedBox(height: 19),
              Container(height: 1, color: _line),
              const SizedBox(height: 15),
              _buildPagination(
                totalCount: list.length,
                page: _studentPage,
                rowsPerPage: _studentRowsPerPage,
                onPageChanged: (p) => setState(() => _studentPage = p),
                onRowsPerPageChanged: (r) => setState(() {
                  _studentRowsPerPage = r;
                  _studentPage = 0;
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStudentsTable(
    List<Map<String, dynamic>> rows,
    Map<String, String> instructorBySection,
    String pitYear,
    String activeSem,
  ) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.5), // Student
        1: FlexColumnWidth(1.2), // Year Level
        2: FlexColumnWidth(2.2), // Section
        3: FlexColumnWidth(1.8), // Team Status
        4: FlexColumnWidth(2.0), // Academic Period
        5: FlexColumnWidth(0.8), // Action
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Header
        TableRow(
          decoration: const BoxDecoration(
            color: Color(0xFFF9FAFB),
            border: Border(bottom: BorderSide(color: _line)),
          ),
          children: [
            _th('Student'),
            _th('Year Level'),
            _th('Section'),
            _th('Team Status'),
            _th('Academic Period'),
            _th('Action', align: TextAlign.center),
          ],
        ),
        // Rows
        for (final student in rows)
          TableRow(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            children: [
              // Student Name & ID
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student['name']?.toString() ??
                          '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'.trim(),
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      student['username']?.toString() ?? student['id']?.toString() ?? '',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Year Level
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      student['year_level']?.toString() ?? pitYear,
                      style: const TextStyle(
                        color: Color(0xFF1D4ED8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              // Section (with Instructor Name underneath)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Builder(
                  builder: (context) {
                    final section = student['section']?.toString().trim() ?? '';
                    final displaySec = section.isNotEmpty ? section : 'Unassigned';
                    final instructorName = instructorBySection[_slug(section)];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displaySec,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_pin_circle_outlined,
                              size: 13,
                              color: instructorName != null ? const Color(0xFF059669) : _muted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                instructorName ?? 'Instructor TBD',
                                style: TextStyle(
                                  color: instructorName != null ? const Color(0xFF059669) : _muted,
                                  fontSize: 11,
                                  fontWeight: instructorName != null ? FontWeight.w600 : FontWeight.w500,
                                  fontStyle: instructorName == null ? FontStyle.italic : FontStyle.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              // Team Status
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Builder(
                  builder: (context) {
                    final onTeam = student['team_status'] == 'on_team' || student['team_name'] != null;
                    final teamName = student['team_name']?.toString() ?? '';

                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: onTeam ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: onTeam ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                          ),
                        ),
                        child: Text(
                          onTeam ? (teamName.isNotEmpty ? 'On Team: $teamName' : 'On Team') : 'Unassigned',
                          style: TextStyle(
                            color: onTeam ? const Color(0xFF047857) : const Color(0xFFB45309),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Academic Period
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Text(
                  student['term_label']?.toString() ?? activeSem,
                  style: const TextStyle(
                    color: Color(0xFF4B5565),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Action (i)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Center(
                  child: IconButton(
                    icon: const Icon(
                      Icons.info_outline_rounded,
                      color: _blue,
                      size: 20,
                    ),
                    tooltip: 'View Student Profile & History',
                    onPressed: () => _showStudentHistory(student),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ==========================================
  // TAB 2: SECTION INSTRUCTORS
  // ==========================================
  Widget _buildInstructorsView(
    PitInstructorState instructorState,
    PitLeadCohortState cohortState,
  ) {
    var assignments = instructorState.assignments;
    final query = _instructorSearchCtrl.text.trim().toLowerCase();

    if (_instructorStatusFilter != 'ALL') {
      final wantActive = _instructorStatusFilter == 'active';
      assignments = assignments.where((a) => (a['is_active'] == true) == wantActive).toList();
    }
    if (query.isNotEmpty) {
      assignments = assignments.where((a) {
        final name = a['faculty_name']?.toString().toLowerCase() ?? '';
        final sec = a['section']?.toString().toLowerCase() ?? '';
        final sem = a['semester_label']?.toString().toLowerCase() ?? '';
        return name.contains(query) || sec.contains(query) || sem.contains(query);
      }).toList();
    }

    // Metrics calculation
    final distinctInstructors = <int>{
      ...instructorState.assignments
          .where((a) => a['is_active'] == true)
          .map((a) => (a['faculty_id'] is num ? (a['faculty_id'] as num).toInt() : 0))
          .where((id) => id > 0),
    }.length;

    final distinctSectionsInCohort = <String>{
      ...cohortState.students
          .map((s) => s['section']?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty),
    };

    final assignedSections = <String>{
      ...instructorState.assignments
          .where((a) => a['is_active'] == true)
          .map((a) => a['section']?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty),
    };

    final sectionsCoveredCount = assignedSections.length;
    final totalSectionsCount = distinctSectionsInCohort.isNotEmpty
        ? distinctSectionsInCohort.length
        : assignedSections.length;
    final needsAssignmentCount = (totalSectionsCount - sectionsCoveredCount).clamp(0, totalSectionsCount);

    final activeTerm = instructorState.activeSemester ?? cohortState.activeSemester ?? 'Active Term';

    final start = _instructorPage * _instructorRowsPerPage;
    final end = (start + _instructorRowsPerPage).clamp(0, assignments.length);
    final visibleRows = (start < assignments.length)
        ? assignments.sublist(start, end)
        : <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 4 Metric Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Total Instructors',
                value: '$distinctInstructors',
                subtitle: 'Assigned section instructors',
                icon: Icons.assignment_ind_outlined,
                iconColor: _maroon,
                iconBg: const Color(0xFFFDF2F2),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Sections Covered',
                value: '$sectionsCoveredCount of $totalSectionsCount',
                subtitle: 'Sections with instructor',
                icon: Icons.assignment_turned_in_rounded,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFECFDF5),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Needs Assignment',
                value: '$needsAssignmentCount',
                subtitle: 'Unassigned class sections',
                icon: Icons.assignment_late_rounded,
                iconColor: needsAssignmentCount > 0 ? const Color(0xFFEA580C) : _muted,
                iconBg: needsAssignmentCount > 0 ? const Color(0xFFFFF7ED) : const Color(0xFFF3F4F6),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Active Term',
                value: activeTerm.contains(',') ? activeTerm.split(',').first.trim() : activeTerm,
                subtitle: activeTerm.contains(',') ? activeTerm.split(',').last.trim() : (cohortState.pitLeadYear ?? 'PIT Year'),
                icon: Icons.calendar_today_rounded,
                iconColor: _gold,
                iconBg: const Color(0xFFFEF3C7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Main Instructors Card
        DefensysCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Toolbar
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _instructorSearchCtrl,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _muted,
                            size: 18,
                          ),
                          hintText: 'Search instructor by name or section...',
                          hintStyle: const TextStyle(color: _muted, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _maroon),
                          ),
                        ),
                        onChanged: (_) => setState(() => _instructorPage = 0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildDropdownFilter(
                    value: _instructorStatusFilter,
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
                      DropdownMenuItem(value: 'active', child: Text('Active Only')),
                      DropdownMenuItem(value: 'inactive', child: Text('Inactive Only')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _instructorStatusFilter = val;
                          _instructorPage = 0;
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      _instructorSearchCtrl.clear();
                      setState(() {
                        _instructorStatusFilter = 'ALL';
                        _instructorPage = 0;
                      });
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

              if (instructorState.isLoading && instructorState.assignments.isEmpty)
                DefensysSkeleton.list(count: 4, rowHeight: 56)
              else if (assignments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: DefensysEmptyState(
                      icon: Icons.assignment_ind_outlined,
                      title: 'No Section Instructor Assignments',
                      description: 'Assign faculty members to teach sections in your PIT year level.',
                      size: DefensysEmptyStateSize.compact,
                      primaryAction: DefensysEmptyAction(
                        label: 'Assign First Instructor',
                        icon: Icons.person_add_alt_1_rounded,
                        onPressed: () => _showAssignInstructorDialog(),
                      ),
                    ),
                  ),
                )
              else
                _buildInstructorsTable(visibleRows, cohortState.pitLeadYear ?? '1st Year', instructorState.isSaving),

              const SizedBox(height: 19),
              Container(height: 1, color: _line),
              const SizedBox(height: 15),
              _buildPagination(
                totalCount: assignments.length,
                page: _instructorPage,
                rowsPerPage: _instructorRowsPerPage,
                onPageChanged: (p) => setState(() => _instructorPage = p),
                onRowsPerPageChanged: (r) => setState(() {
                  _instructorRowsPerPage = r;
                  _instructorPage = 0;
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstructorsTable(
    List<Map<String, dynamic>> rows,
    String pitYear,
    bool isSaving,
  ) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.5), // Instructor
        1: FlexColumnWidth(1.8), // Assigned Section
        2: FlexColumnWidth(1.4), // Year Level
        3: FlexColumnWidth(2.0), // Academic Period
        4: FlexColumnWidth(1.2), // Status
        5: FlexColumnWidth(2.0), // Actions
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(
            color: Color(0xFFF9FAFB),
            border: Border(bottom: BorderSide(color: _line)),
          ),
          children: [
            _th('Instructor'),
            _th('Assigned Section'),
            _th('Year Level'),
            _th('Academic Period'),
            _th('Status'),
            _th('Action', align: TextAlign.center),
          ],
        ),
        for (final assignment in rows)
          TableRow(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            children: [
              // Instructor Name & Email
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment['faculty_name']?.toString() ?? 'Faculty',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      assignment['faculty_email']?.toString() ??
                          'ID: ${assignment['faculty_id'] ?? '-'}',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Assigned Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      assignment['section']?.toString() ?? '-',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              // Year Level
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      assignment['year_level']?.toString() ?? pitYear,
                      style: const TextStyle(
                        color: Color(0xFF1D4ED8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              // Semester
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Text(
                  assignment['semester_label']?.toString() ?? '-',
                  style: const TextStyle(
                    color: Color(0xFF4B5565),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Status
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Builder(
                  builder: (context) {
                    final active = assignment['is_active'] == true;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: active ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: active ? const Color(0xFFA7F3D0) : const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: Text(
                          active ? 'Active' : 'Inactive',
                          style: TextStyle(
                            color: active ? const Color(0xFF047857) : _muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Action
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Builder(
                  builder: (context) {
                    final id = assignment['id'] is num
                        ? (assignment['id'] as num).toInt()
                        : int.tryParse(assignment['id']?.toString() ?? '');
                    final active = assignment['is_active'] == true;

                    return Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: isSaving || id == null
                              ? null
                              : () => _showAssignInstructorDialog(
                                    defaultSection: assignment['section']?.toString(),
                                    defaultFacultyId: assignment['faculty_id'] is num
                                        ? (assignment['faculty_id'] as num).toInt()
                                        : null,
                                  ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          child: const Text('Change'),
                        ),
                        TextButton(
                          onPressed: isSaving || id == null
                              ? null
                              : () async {
                                  final success = await ref
                                      .read(pitInstructorProvider.notifier)
                                      .setAssignmentActive(id, !active);
                                  if (success && mounted) {
                                    showSuccessToast(
                                      context,
                                      active ? 'Instructor deactivated.' : 'Instructor restored.',
                                    );
                                    _refreshAllData();
                                  }
                                },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            foregroundColor: active ? const Color(0xFFDC2626) : const Color(0xFF059669),
                          ),
                          child: Text(active ? 'Deactivate' : 'Restore'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ==========================================
  // SHARED REUSABLE COMPONENTS
  // ==========================================
  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: DefensysUi.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 22,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
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
          value: value,
          style: const TextStyle(
            color: _ink,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: _muted,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _th(String label, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        label.toUpperCase(),
        textAlign: align,
        style: const TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPagination({
    required int totalCount,
    required int page,
    required int rowsPerPage,
    required ValueChanged<int> onPageChanged,
    required ValueChanged<int> onRowsPerPageChanged,
  }) {
    final maxPage = (totalCount / rowsPerPage).ceil();
    final startItem = totalCount == 0 ? 0 : page * rowsPerPage + 1;
    final endItem = ((page + 1) * rowsPerPage).clamp(0, totalCount);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text(
              'Rows per page:',
              style: TextStyle(
                color: _muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: rowsPerPage,
              underline: const SizedBox(),
              style: const TextStyle(
                color: _ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              items: _rowsPerPageOptions
                  .map((r) => DropdownMenuItem(value: r, child: Text('$r')))
                  .toList(),
              onChanged: (val) {
                if (val != null) onRowsPerPageChanged(val);
              },
            ),
            const SizedBox(width: 16),
            Text(
              'Showing $startItem–$endItem of $totalCount',
              style: const TextStyle(
                color: _muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
            ),
            Text(
              '${totalCount == 0 ? 0 : page + 1} / ${maxPage == 0 ? 1 : maxPage}',
              style: const TextStyle(
                color: _ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: (page + 1) < maxPage ? () => onPageChanged(page + 1) : null,
            ),
          ],
        ),
      ],
    );
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(' ', '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

// ==========================================
// ASSIGN SECTION INSTRUCTOR MODAL DIALOG
// ==========================================
class _AssignSectionInstructorDialog extends StatefulWidget {
  final List<Map<String, dynamic>> facultyList;
  final List<String> availableSections;
  final String yearLevel;
  final String? defaultSection;
  final int? defaultFacultyId;

  const _AssignSectionInstructorDialog({
    required this.facultyList,
    required this.availableSections,
    required this.yearLevel,
    this.defaultSection,
    this.defaultFacultyId,
  });

  @override
  State<_AssignSectionInstructorDialog> createState() =>
      _AssignSectionInstructorDialogState();
}

class _AssignSectionInstructorDialogState
    extends State<_AssignSectionInstructorDialog> {
  int? _selectedFacultyId;
  final _sectionCtrl = TextEditingController();
  String? _error;

  static const _maroon = DefensysUi.primaryMaroon;
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _line = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    _selectedFacultyId = widget.defaultFacultyId;
    if (widget.defaultSection != null && widget.defaultSection!.isNotEmpty) {
      _sectionCtrl.text = widget.defaultSection!;
    }
  }

  @override
  void dispose() {
    _sectionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final facultyItems = widget.facultyList.map((user) {
      final id = user['id'] is num ? (user['id'] as num).toInt() : int.tryParse(user['id']?.toString() ?? '');
      final name = user['name']?.toString() ?? user['username']?.toString() ?? 'Faculty';
      final role = user['displayRole'] is Map
          ? (user['displayRole']['label']?.toString() ?? 'Faculty')
          : 'Faculty';
      return DropdownMenuItem<int>(
        value: id,
        child: Text('$name ($role)'),
      );
    }).where((item) => item.value != null).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.assignment_ind_outlined, color: _maroon, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assign Section Instructor',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cohort: ${widget.yearLevel}',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              // Faculty Selector
              const Text(
                'Faculty Member',
                style: TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: _selectedFacultyId,
                decoration: InputDecoration(
                  hintText: 'Select faculty member...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: facultyItems,
                onChanged: (val) => setState(() => _selectedFacultyId = val),
              ),
              const SizedBox(height: 16),
              // Section Name
              const Text(
                'Class Section',
                style: TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _sectionCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. BSIT-1A',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setState(() {}),
              ),
              if (widget.availableSections.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: widget.availableSections.map((sec) {
                    final selected = _sectionCtrl.text.trim() == sec;
                    return ActionChip(
                      label: Text(sec),
                      backgroundColor: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF3F4F6),
                      side: BorderSide(color: selected ? const Color(0xFF3B82F6) : _line),
                      onPressed: () {
                        setState(() {
                          _sectionCtrl.text = sec;
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      side: const BorderSide(color: _line),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      final facultyId = _selectedFacultyId;
                      final section = _sectionCtrl.text.trim();
                      if (facultyId == null) {
                        setState(() => _error = 'Please select a faculty member.');
                        return;
                      }
                      if (section.isEmpty) {
                        setState(() => _error = 'Please enter or select a class section.');
                        return;
                      }
                      Navigator.of(context).pop({
                        'faculty_id': facultyId,
                        'section': section,
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Confirm Assignment'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// PIT ROLLOVER PREVIEW DIALOG
// ==========================================
class _PitRolloverPreviewDialog extends StatefulWidget {
  final Map<String, dynamic> preview;
  final VoidCallback onCancel;
  final Future<void> Function() onConfirm;

  const _PitRolloverPreviewDialog({
    required this.preview,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<_PitRolloverPreviewDialog> createState() =>
      _PitRolloverPreviewDialogState();
}

class _PitRolloverPreviewDialogState extends State<_PitRolloverPreviewDialog> {
  var _isConfirming = false;

  static const _maroon = DefensysUi.primaryMaroon;
  static const _ink = DefensysUi.textDark;
  static const _muted = Color(0xFF6B7280);
  static const _line = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    final counts = _map(widget.preview['counts']);
    final rows = _list(widget.preview['rows']);
    final source = _map(widget.preview['source_semester']);
    final target = _map(widget.preview['target_semester']);
    final pitYear = widget.preview['pit_lead_year']?.toString() ?? 'PIT year';
    final targetYear =
        widget.preview['target_year_level']?.toString() ?? pitYear;
    final sourceLabel =
        source['display_name']?.toString() ?? 'No source term found';
    final targetLabel =
        target['display_name']?.toString() ?? 'No target active term found';

    final total = counts['total_source_students'] ?? rows.length;
    final promote = counts['promote_count'] ?? 0;
    final existing = counts['already_enrolled_count'] ?? 0;
    final canConfirm = target.isNotEmpty && promote > 0 && !_isConfirming;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4F4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.update_rounded,
                      color: _maroon,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PIT Cohort Rollover Preview',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$pitYear ($sourceLabel) -> $targetYear ($targetLabel)',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isConfirming ? null : widget.onCancel,
                    icon: const Icon(Icons.close_rounded, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _statBox('Source Students', '$total', const Color(0xFFF3F4F6), _ink),
                  const SizedBox(width: 10),
                  _statBox('To Promote', '$promote', const Color(0xFFECFDF5), const Color(0xFF047857)),
                  const SizedBox(width: 10),
                  _statBox('Already Enrolled', '$existing', const Color(0xFFFFFBEB), const Color(0xFFB45309)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Candidate Roster',
                style: TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: rows.isEmpty
                      ? const Center(
                          child: Text(
                            'No eligible students found in source term.',
                            style: TextStyle(color: _muted, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            final rec = _map(row['record']);
                            final res = _map(row['promote_result']);
                            final willPromote = row['will_promote'] == true;
                            final name = '${rec['first_name'] ?? ''} ${rec['last_name'] ?? ''}'.trim();
                            final username = rec['student_username']?.toString() ?? '-';
                            final fromSec = rec['section']?.toString() ?? '-';
                            final toSec = res['section']?.toString() ?? fromSec;

                            return ListTile(
                              dense: true,
                              title: Text(
                                name.isEmpty ? username : name,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '$username · Current: $fromSec -> Target: $toSec ($targetYear)',
                                style: const TextStyle(color: _muted, fontSize: 11.5),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: willPromote ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  willPromote ? 'Promote' : 'Skip (Enrolled)',
                                  style: TextStyle(
                                    color: willPromote ? const Color(0xFF047857) : _muted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isConfirming ? null : widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: canConfirm
                        ? () async {
                            setState(() => _isConfirming = true);
                            await widget.onConfirm();
                            if (mounted) setState(() => _isConfirming = false);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_isConfirming ? 'Processing...' : 'Confirm Rollover'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statBox(String label, String value, Color bg, Color text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(dynamic v) =>
      v is List ? v.map((item) => _map(item)).toList() : <Map<String, dynamic>>[];
}
