import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';

import '../dialogs/student_profile_details_dialog.dart';

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

  Future<void> _showStudentHistory(Map<String, dynamic> record) async {
    final state = ref.read(studentAcademicRecordsProvider);
    final activeSem = ref.read(academicPeriodProvider).activeSemester ?? state.activeSemester;
    await StudentProfileDetailsDialog.show(
      context,
      record: record,
      schoolYears: state.schoolYears,
      activeSemester: activeSem,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studentAcademicRecordsProvider);
    final activeSem = ref.watch(academicPeriodProvider).activeSemester ?? state.activeSemester;
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
                value: '${state.records.isNotEmpty ? _count(state, 'students_with_records') : state.students.length}',
                subtitle: state.records.isEmpty && state.students.isNotEmpty
                    ? 'Unenrolled student accounts'
                    : 'Distinct student accounts',
                icon: Icons.school_outlined,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFECFDF5),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Active Term',
                value: activeSem?['label']?.toString() ?? 'None Active',
                subtitle: activeSem?['school_year']?.toString() ?? 'Setup in Academic Periods',
                icon: Icons.calendar_today_rounded,
                iconColor: activeSem != null ? _gold : const Color(0xFFD97706),
                iconBg: const Color(0xFFFEF3C7),
              ),
            ),
          ],
        ),

        if (activeSem == null && state.students.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF92400E), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${state.students.length} student account(s) have been imported into the system, but no academic semester is active. Go to Academic Periods in the sidebar to create and activate a school year and semester.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

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
                  icon: (activeSem == null && state.students.isNotEmpty)
                      ? Icons.info_outline_rounded
                      : Icons.person_off_outlined,
                  title: (activeSem == null && state.students.isNotEmpty)
                      ? 'No Active Semester Configured'
                      : (state.students.isNotEmpty && state.records.isEmpty)
                          ? 'Unenrolled Student Accounts Found'
                          : 'No Student Records Found',
                  description: (activeSem == null && state.students.isNotEmpty)
                      ? '${state.students.length} student account(s) are registered in the system, but no semester is currently active. Please set up and activate an academic semester in Setup & Configuration > Academic Periods to enroll students.'
                      : (state.students.isNotEmpty && state.records.isEmpty)
                          ? '${state.students.length} student account(s) exist in the system but have not been enrolled in an academic term yet. Use "Batch Enrollment" or "Add Single Student" to enroll them.'
                          : 'No student records match your active search criteria or filter parameters.',
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

  static const List<_StudentColumnSpec> _columns = [
    _StudentColumnSpec('Student', 2.8),
    _StudentColumnSpec('Year Level', 1.5),
    _StudentColumnSpec('Section', 2.2),
    _StudentColumnSpec('Academic Period', 2.4),
    _StudentColumnSpec('Action', 1.1),
  ];

  Widget _buildTable(List<Map<String, dynamic>> rows) {
    return Column(
      children: [
        _tableHeader(_columns),
        ...rows.map((r) => _studentRow(r)),
      ],
    );
  }

  Widget _tableHeader(List<_StudentColumnSpec> columns) {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: columns.map((col) => _tableHeaderCell(col)).toList(),
      ),
    );
  }

  Widget _tableHeaderCell(_StudentColumnSpec column) {
    return Expanded(
      flex: (column.flex * 100).round(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.centerLeft,
        child: Text(
          column.title,
          style: const TextStyle(
            color: Color(0xFF5D6678),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  Widget _studentRow(Map<String, dynamic> r) {
    final yearLevel = r['year_level']?.toString() ?? 'Unassigned';
    final section = r['section']?.toString().trim() ?? '';
    final sem = r['semester']?.toString() ?? '';
    final period = '${r['semester'] ?? ''}, ${r['school_year'] ?? ''}';
    final isCapstone = yearLevel.contains('4th') ||
        (yearLevel.contains('3rd') && sem.contains('2nd'));

    return Container(
      height: 57,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _tableCell(
            InkWell(
              onTap: () => _showStudentHistory(r),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['student_name']?.toString() ??
                          r['student_username']?.toString() ??
                          'Student',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r['student_username']?.toString() ?? '',
                      style: const TextStyle(fontSize: 11.5, color: _muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            flex: 2.8,
          ),
          _tableCell(
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            flex: 1.5,
          ),
          _tableCell(
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.isEmpty ? '—' : section,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isCapstone &&
                    r['instructor_name'] != null &&
                    r['instructor_name'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.co_present_rounded,
                          size: 11, color: Color(0xFF16A34A)),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          '${r['instructor_name']}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF15803D),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            flex: 2.2,
          ),
          _tableCell(
            Text(
              period,
              style: const TextStyle(fontSize: 12.5, color: _muted),
              overflow: TextOverflow.ellipsis,
            ),
            flex: 2.4,
          ),
          _tableCell(
            _rowActions(r),
            flex: 1.1,
          ),
        ],
      ),
    );
  }

  Widget _rowActions(Map<String, dynamic> r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'View Student Details',
          waitDuration: const Duration(milliseconds: 300),
          child: InkWell(
            onTap: () => _showStudentHistory(r),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.visibility_outlined,
                color: DefensysUi.techBlue,
                size: 19,
              ),
            ),
          ),
        ),
      ],
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

class _StudentColumnSpec {
  const _StudentColumnSpec(this.title, this.flex);
  final String title;
  final double flex;
}
