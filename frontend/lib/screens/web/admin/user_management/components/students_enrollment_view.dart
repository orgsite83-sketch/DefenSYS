import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';
import 'package:defensys/widgets/feedback/action_banner.dart';

import '../dialogs/student_profile_details_dialog.dart';
import 'package:defensys/widgets/academic/student_capstone_history.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

/// The Students & Academic Enrollment view within User Management.
class StudentsEnrollmentView extends ConsumerStatefulWidget {
  const StudentsEnrollmentView({super.key, this.onOpenBulkImport});

  final VoidCallback? onOpenBulkImport;

  @override
  ConsumerState<StudentsEnrollmentView> createState() =>
      _StudentsEnrollmentViewState();
}

class _StudentsEnrollmentViewState
    extends ConsumerState<StudentsEnrollmentView> {
  static const _maroon = DefensysUi.primaryMaroon;
  static const _blue = DefensysUi.techBlue;
  static const _muted = DefensysUi.steelGrey;
  static const _ink = DefensysUi.textDark;
  static const _line = Color(0xFFE5E7EB);

  final TextEditingController _searchCtrl = TextEditingController();
  int _page = 0;
  int _rowsPerPage = 10;
  final List<int> _rowsPerPageOptions = const [10, 25, 50, 100];

  String get _yearLevelFilter =>
      ref.read(studentAcademicRecordsProvider).yearLevelFilter;
  String get _sectionFilter =>
      ref.read(studentAcademicRecordsProvider).sectionFilter;
  bool _returningCapstoneOnly = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filteredRecords(
    List<Map<String, dynamic>> records,
  ) {
    var list = records;
    if (_returningCapstoneOnly) {
      list = list
          .where(
            (r) => (r['capstone_participation'] as Map?)?['returning'] == true,
          )
          .toList();
    }
    if (_yearLevelFilter != 'ALL') {
      list = list
          .where((r) => r['year_level']?.toString() == _yearLevelFilter)
          .toList();
    }
    if (_sectionFilter == 'UNASSIGNED') {
      list = list.where((r) {
        final sec = r['section']?.toString().trim() ?? '';
        return sec.isEmpty || sec.toUpperCase() == 'BSIT';
      }).toList();
    } else if (_sectionFilter != 'ALL') {
      list = list
          .where(
            (r) => (r['section']?.toString().trim() ?? '') == _sectionFilter,
          )
          .toList();
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
    final activeSem =
        ref.read(academicPeriodProvider).activeSemester ?? state.activeSemester;
    await StudentProfileDetailsDialog.show(
      context,
      record: record,
      schoolYears: state.schoolYears,
      activeSemester: activeSem,
    );
  }

  String? _enrollmentWarning(Map? enrollment) {
    if (enrollment == null) return null;
    final enrolled = enrollment['enrolled'] as num?;
    final pending = enrollment['pending_continuations'] as num? ?? 0;
    final emptyYears = (enrollment['by_year'] as List? ?? [])
        .whereType<Map>()
        .where((row) => row['enrolled'] == 0)
        .map((row) => row['year_level'])
        .whereType<String>()
        .toList();
    final messages = <String>[];
    if (enrolled == 0) {
      messages.add('This semester is active. No students are enrolled yet.');
    } else if (emptyYears.isNotEmpty) {
      final years = emptyYears.length == 1
          ? emptyYears.single
          : emptyYears.length == 2
          ? emptyYears.join(' and ')
          : '${emptyYears.take(emptyYears.length - 1).join(', ')}, and ${emptyYears.last}';
      messages.add('No students are enrolled in $years this semester.');
    }
    if (pending > 0) {
      messages.add(
        '$pending continuing ${pending == 1 ? 'student still needs' : 'students still need'} enrollment.',
      );
    }
    return messages.isEmpty ? null : messages.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studentAcademicRecordsProvider);
    final periods = ref.watch(academicPeriodProvider);
    final activeSem =
        periods.activeSemester ??
        (periods.schoolYears.isEmpty ? state.activeSemester : null);
    final enrollment = state.counts['enrollment'] as Map?;
    final summaryIsCurrent =
        activeSem != null && enrollment?['semester_id'] == activeSem['id'];
    final enrolled = summaryIsCurrent
        ? (enrollment?['enrolled'] as num?)?.toInt()
        : null;
    final enrollmentWarning = _enrollmentWarning(
      summaryIsCurrent ? enrollment : null,
    );
    final period =
        activeSem?['display_name']?.toString() ??
        '${activeSem?['label'] ?? 'No active semester'}${activeSem == null ? '' : ', A.Y. ${activeSem['school_year'] ?? ''}'}';
    final current = state.termContext == 'current';
    final responseIsCurrent = state.activeSemester?['id'] == activeSem?['id'];
    final records = current && !responseIsCurrent
        ? <Map<String, dynamic>>[]
        : state.records;
    final allFiltered = _filteredRecords(records);
    final totalPages = (allFiltered.length / _rowsPerPage).ceil();
    _page = _page.clamp(0, totalPages > 0 ? totalPages - 1 : 0);
    final visibleRows = _visibleRows(allFiltered);
    final emptyTerm =
        current &&
        enrolled == 0 &&
        state.search.isEmpty &&
        _yearLevelFilter == 'ALL' &&
        _sectionFilter == 'ALL' &&
        !_returningCapstoneOnly;

    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 700
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: width,
                    child: _buildMetricCard(
                      title: 'Enrolled this semester',
                      value: enrolled?.toString() ?? '—',
                      subtitle: period,
                      icon: Icons.school_outlined,
                      iconColor: _maroon,
                      iconBg: const Color(0xFFFDF2F2),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildMetricCard(
                      title: 'Student accounts',
                      value:
                          '${state.counts['student_accounts'] ?? state.students.length}',
                      subtitle: 'Active accounts across all semesters',
                      icon: Icons.people_outline_rounded,
                      iconColor: _blue,
                      iconBg: const Color(0xFFEFF6FF),
                    ),
                  ),
                ],
              );
            },
          ),
          if (activeSem == null) ...[
            const SizedBox(height: 16),
            DefensysActionBanner(
              title: 'Active Academic Semester Required',
              description:
                  'Activate a semester in Academic Periods to enroll students.',
              actionLabel: 'Open Academic Periods',
              onAction: () => context.go(AdminRoutes.academicPeriods),
            ),
          ] else if (enrollmentWarning != null) ...[
            const SizedBox(height: 16),
            DefensysActionBanner(
              title: 'Enrollment required',
              description: enrollmentWarning,
              actionLabel: 'Start enrollment',
              onAction: widget.onOpenBulkImport ?? () {},
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 16),
            DefensysActionBanner(
              title: 'Enrollment could not be loaded',
              description: state.error!,
              actionLabel: 'Retry',
              onAction: () => ref
                  .read(studentAcademicRecordsProvider.notifier)
                  .fetchRecords(),
              isBlocking: true,
            ),
          ],
          const SizedBox(height: 22),
          DefensysCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Text(
                      'Students',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    _selectFilter(
                      label: 'Enrollment records',
                      value: state.termContext,
                      options: const {
                        'current': 'Active semester',
                        'history': 'All academic records',
                      },
                      onChanged: (value) {
                        setState(() {
                          _page = 0;
                        });
                        ref
                            .read(studentAcademicRecordsProvider.notifier)
                            .selectTermContext(value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ShadCheckbox(
                  value: _returningCapstoneOnly,
                  onChanged: (value) => setState(() {
                    _returningCapstoneOnly = value;
                    _page = 0;
                  }),
                  label: const Text(
                    'Returning Capstone students awaiting a new roster',
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth > 540
                            ? 400
                            : constraints.maxWidth,
                        child: ShadInput(
                          controller: _searchCtrl,
                          placeholder: const Text(
                            'Search by student name, ID, or email...',
                          ),
                          leading: const Icon(LucideIcons.search, size: 16),
                          onSubmitted: (value) {
                            setState(() => _page = 0);
                            ref
                                .read(studentAcademicRecordsProvider.notifier)
                                .fetchRecords(search: value);
                          },
                        ),
                      ),
                      _yearLevelDropdown(),
                      _sectionDropdown(records),
                      if (!current) ...[
                        _schoolYearDropdown(state),
                        _semesterDropdown(state),
                      ],
                      ShadButton.outline(
                        leading: const Icon(LucideIcons.x, size: 16),
                        child: const Text('Clear'),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _page = 0;
                            _returningCapstoneOnly = false;
                          });
                          ref
                              .read(studentAcademicRecordsProvider.notifier)
                              .setListFilters(yearLevel: 'ALL', section: 'ALL');
                          ref
                              .read(studentAcademicRecordsProvider.notifier)
                              .fetchRecords(
                                search: '',
                                schoolYear: '',
                                semester: '',
                              );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (state.isLoading ||
                    (current && !responseIsCurrent && state.error == null))
                  DefensysSkeleton.list(count: 6, rowHeight: 52)
                else if (visibleRows.isEmpty)
                  DefensysEmptyState.table(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    icon: Icons.school_outlined,
                    title: activeSem == null && current
                        ? 'No Active Semester Configured'
                        : emptyTerm
                        ? 'No enrollments for this semester'
                        : 'No matching student records',
                    description: activeSem == null && current
                        ? 'Activate a semester to begin enrollment.'
                        : emptyTerm
                        ? 'Upload the current university class lists to enroll new and existing students together.'
                        : 'Adjust the search or filters to see other records.',
                    size: DefensysEmptyStateSize.standard,
                    primaryAction: activeSem == null && current
                        ? DefensysEmptyAction(
                            label: 'Open Academic Periods',
                            icon: Icons.arrow_forward_rounded,
                            onPressed: () =>
                                context.go(AdminRoutes.academicPeriods),
                          )
                        : emptyTerm && widget.onOpenBulkImport != null
                        ? DefensysEmptyAction(
                            label: 'Upload class lists',
                            icon: Icons.upload_file_outlined,
                            onPressed: widget.onOpenBulkImport!,
                          )
                        : null,
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: constraints.maxWidth < 900
                            ? 900
                            : constraints.maxWidth,
                        child: _buildTable(visibleRows),
                      ),
                    ),
                  ),
                if (allFiltered.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Divider(height: 1, color: DefensysTokens.borderOf(context)),
                  const SizedBox(height: 14),
                  _buildPagination(allFiltered.length),
                ],
              ],
            ),
          ),
        ],
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? DefensysTokens.mistSurface : Colors.white;
    final borderColor = isDark ? DefensysTokens.mistBorder : _line;
    final textTitle = isDark ? DefensysTokens.textSecondaryDark : _muted;
    final textValue = isDark ? DefensysTokens.textPrimaryDark : _ink;
    final textSub = isDark ? DefensysTokens.textSecondaryDark : _muted;
    final actualIconBg = isDark ? iconColor.withValues(alpha: 0.18) : iconBg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
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
              color: actualIconBg,
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
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: textTitle,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: textValue,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: textSub),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectFilter({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Semantics(
      label: label,
      child: ShadSelect<String>(
        key: ValueKey('$label-$value'),
        initialValue: options.containsKey(value) ? value : options.keys.first,
        options: [
          for (final option in options.entries)
            ShadOption(value: option.key, child: Text(option.value)),
        ],
        selectedOptionBuilder: (_, value) => Text(options[value] ?? value),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }

  Widget _yearLevelDropdown() => _selectFilter(
    label: 'Year level',
    value: _yearLevelFilter,
    options: const {
      'ALL': 'All year levels',
      '1st Year': '1st Year',
      '2nd Year': '2nd Year',
      '3rd Year': '3rd Year',
      '4th Year': '4th Year',
    },
    onChanged: (value) {
      setState(() => _page = 0);
      ref
          .read(studentAcademicRecordsProvider.notifier)
          .setListFilters(yearLevel: value);
    },
  );

  Widget _sectionDropdown(List<Map<String, dynamic>> records) {
    final sections =
        records
            .map((row) => row['section']?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty && s.toUpperCase() != 'BSIT')
            .toSet()
            .toList()
          ..sort();
    return _selectFilter(
      label: 'Section',
      value: _sectionFilter,
      options: {
        'ALL': 'All sections',
        'UNASSIGNED': 'Unassigned section',
        for (final section in sections) section: section,
      },
      onChanged: (value) {
        setState(() => _page = 0);
        ref
            .read(studentAcademicRecordsProvider.notifier)
            .setListFilters(section: value);
      },
    );
  }

  Widget _schoolYearDropdown(StudentAcademicRecordsState state) =>
      _selectFilter(
        label: 'School year',
        value: state.schoolYear,
        options: {
          '': 'All school years',
          for (final year in state.schoolYears)
            '${year['label']}': '${year['label']}',
        },
        onChanged: (value) {
          setState(() => _page = 0);
          ref
              .read(studentAcademicRecordsProvider.notifier)
              .fetchRecords(schoolYear: value);
        },
      );

  Widget _semesterDropdown(StudentAcademicRecordsState state) => _selectFilter(
    label: 'Semester',
    value: state.semester,
    options: const {
      '': 'All semesters',
      '1st Semester': '1st Semester',
      '2nd Semester': '2nd Semester',
      'Summer': 'Summer',
    },
    onChanged: (value) {
      setState(() => _page = 0);
      ref
          .read(studentAcademicRecordsProvider.notifier)
          .fetchRecords(semester: value);
    },
  );

  static const List<_StudentColumnSpec> _columns = [
    _StudentColumnSpec('Student', 2.8),
    _StudentColumnSpec('Year Level', 1.5),
    _StudentColumnSpec('Section', 2.2),
    _StudentColumnSpec('Academic Period', 2.4),
    _StudentColumnSpec('Action', 1.1),
  ];

  Widget _buildTable(List<Map<String, dynamic>> rows) {
    return Column(
      children: [_tableHeader(_columns), ...rows.map((r) => _studentRow(r))],
    );
  }

  Widget _tableHeader(List<_StudentColumnSpec> columns) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: columns.map((col) => _tableHeaderCell(col)).toList(),
      ),
    );
  }

  Widget _tableHeaderCell(_StudentColumnSpec column) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      flex: (column.flex * 100).round(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.centerLeft,
        child: Text(
          column.title,
          style: TextStyle(
            color: isDark
                ? DefensysTokens.textSecondaryDark
                : const Color(0xFF5D6678),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rowBg = isDark ? DefensysTokens.mistSurface : Colors.white;
    final borderColor = isDark
        ? DefensysTokens.mistBorder
        : const Color(0xFFE5E7EB);
    final textPrimary = isDark ? DefensysTokens.textPrimaryDark : _ink;
    final textSecondary = isDark ? DefensysTokens.textSecondaryDark : _muted;

    final yearLevel = r['year_level']?.toString() ?? 'Unassigned';
    final section = r['section']?.toString().trim() ?? '';
    final sem = r['semester']?.toString() ?? '';
    final period = '${r['semester'] ?? ''}, ${r['school_year'] ?? ''}';
    final isCapstone =
        yearLevel.contains('4th') ||
        (yearLevel.contains('3rd') && sem.contains('2nd'));

    return Container(
      height: 57,
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(bottom: BorderSide(color: borderColor)),
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r['student_username']?.toString() ?? '',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E3A8A).withValues(alpha: 0.35)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF1E3A8A).withValues(alpha: 0.7)
                        : const Color(0xFFDBEAFE),
                  ),
                ),
                child: Text(
                  yearLevel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFF93C5FD)
                        : const Color(0xFF1D4ED8),
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
                if (section.isEmpty || section.toUpperCase() == 'BSIT')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF78350F).withValues(alpha: 0.35)
                          : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF78350F).withValues(alpha: 0.7)
                            : const Color(0xFFFDE68A),
                      ),
                    ),
                    child: Text(
                      'Unassigned',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFFB45309),
                      ),
                    ),
                  )
                else
                  Text(
                    section,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
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
                      Icon(
                        Icons.co_present_rounded,
                        size: 11,
                        color: isDark
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          '${r['instructor_name']}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFF15803D),
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
              style: TextStyle(fontSize: 12.5, color: textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
            flex: 2.4,
          ),
          _tableCell(_rowActions(r), flex: 1.1),
        ],
      ),
    );
  }

  Widget _rowActions(Map<String, dynamic> r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (r['capstone_participation'] != null)
          Tooltip(
            message: 'Capstone participation history',
            child: DefensysShadcnScope(
              child: ShadButton.ghost(
                onPressed: () {
                  final id = (r['student_id'] as num?)?.toInt();
                  if (id != null) {
                    showStudentCapstoneHistory(
                      context,
                      id,
                      r['student_name']?.toString() ?? 'Student',
                    );
                  }
                },
                child: const Icon(LucideIcons.history, size: 17),
              ),
            ),
          ),
        Tooltip(
          message: 'Student Details',
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
    final startItem = _page * _rowsPerPage + 1;
    final endItem = ((_page + 1) * _rowsPerPage).clamp(0, totalCount);
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          SizedBox(
            width: constraints.maxWidth < 320 ? constraints.maxWidth : 320,
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Rows per page:', style: TextStyle(fontSize: 12)),
                ShadSelect<int>(
                  initialValue: _rowsPerPage,
                  options: [
                    for (final n in _rowsPerPageOptions)
                      ShadOption(value: n, child: Text('$n')),
                  ],
                  selectedOptionBuilder: (_, n) => Text('$n'),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _rowsPerPage = value;
                        _page = 0;
                      });
                    }
                  },
                ),
                Text(
                  '$startItem–$endItem of $totalCount',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: _page > 0 ? () => setState(() => _page--) : null,
                child: const Icon(LucideIcons.chevronLeft, size: 16),
              ),
              Text(
                '${_page + 1} / $totalPages',
                style: const TextStyle(fontSize: 12),
              ),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: _page < totalPages - 1
                    ? () => setState(() => _page++)
                    : null,
                child: const Icon(LucideIcons.chevronRight, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudentColumnSpec {
  const _StudentColumnSpec(this.title, this.flex);
  final String title;
  final double flex;
}
