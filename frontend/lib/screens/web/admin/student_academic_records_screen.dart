import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/student_academic_records_provider.dart';
import '../../../utils/csv_file_io.dart';
import '../../../widgets/feedback_toast.dart';
import 'widgets/defensys_admin_shell.dart';
import 'widgets/student_records_rollover_modal.dart';

class StudentAcademicRecordsScreen extends ConsumerStatefulWidget {
  const StudentAcademicRecordsScreen({super.key});

  @override
  ConsumerState<StudentAcademicRecordsScreen> createState() =>
      _StudentAcademicRecordsScreenState();
}

class _StudentAcademicRecordsScreenState
    extends ConsumerState<StudentAcademicRecordsScreen> {
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _gold = DefensysUi.accentGold;
  static const _blue = DefensysUi.techBlue;
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFDC2626);
  static const _line = Color(0xFFE5E7EB);

  final _searchController = TextEditingController();

  static const List<int> _rowsPerPageOptions = [10, 25, 50, 100, 200, 500];
  int _rowsPerPage = 10;
  int _page = 0;

  static const _yearLevels = ['1st Year', '2nd Year', '3rd Year', '4th Year'];
  static const _semesterLabels = ['1st Semester', '2nd Semester', 'Summer'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _ensurePageInRange(int recordCount) {
    final pages = recordCount == 0 ? 1 : (recordCount / _rowsPerPage).ceil();
    final maxPage = pages - 1;
    if (_page > maxPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _page = maxPage);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studentAcademicRecordsProvider);
    _ensurePageInRange(state.records.length);

    ref.listen(studentAcademicRecordsProvider, (previous, next) {
      final error = next.error;
      if (error != null && error.isNotEmpty && error != previous?.error) {
        showErrorToast(context, error);
      }

      final message = next.message;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.message) {
        showSuccessToast(context, message);
      }
    });

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.badge_outlined,
            title: 'Student Academic Records',
            subtitle:
                'Track each student by school year, semester, and year level before teams and schedules are migrated.',
            actions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _secondaryButton(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh',
                  onTap: state.isSaving
                      ? null
                      : () {
                          setState(() => _page = 0);
                          ref
                              .read(studentAcademicRecordsProvider.notifier)
                              .fetchRecords();
                        },
                ),
                const SizedBox(width: 14),
                _secondaryButton(
                  icon: Icons.rotate_right_rounded,
                  label: 'Rollover Preview',
                  onTap: state.isSaving ? null : _showRolloverDialog,
                ),
                const SizedBox(width: 14),
                _primaryButton(
                  icon: Icons.add_rounded,
                  label: 'Add Record',
                  onTap: state.isSaving ? null : () => _showRecordDialog(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _buildStats(state),

          const SizedBox(height: 22),
          _recordsTableCard(state),
        ],
      ),
    );
  }

  Widget _buildStats(StudentAcademicRecordsState state) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'All Records',
            _count(state, 'all'),
            Icons.badge_outlined,
            subtitle: 'Total academic records',
            selected: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Filtered',
            _count(state, 'filtered'),
            Icons.filter_alt_outlined,
            subtitle: 'Current table results',
            iconColor: _blue,
            iconBg: const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Students',
            _count(state, 'students_with_records'),
            Icons.school_outlined,
            subtitle: 'With records',
            iconColor: const Color(0xFF047857),
            iconBg: const Color(0xFFD1FAE5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildActiveSemesterCard(state)),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    int count,
    IconData icon, {
    bool selected = false,
    String subtitle = '',
    Color iconColor = _blue,
    Color iconBg = const Color(0xFFEFF6FF),
  }) {
    return Container(
      height: 101,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? _maroon : Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          _iconBox(
            icon,
            selected ? _ink : iconColor,
            selected ? const Color(0xFFF1F2F4) : iconBg,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  count.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F2743),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSemesterCard(StudentAcademicRecordsState state) {
    final active = state.activeSemester;

    return Container(
      height: 101,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          _iconBox(
            Icons.event_available_outlined,
            const Color(0xFFB45309),
            const Color(0xFFFEF3C7),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active Semester',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  active?['display_name']?.toString() ?? 'Not configured',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F2743),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordsTableCard(StudentAcademicRecordsState state) {
    final visibleRecords = _pageRecords(state.records);
    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField(state)),
              const SizedBox(width: 16),
              _schoolYearFilter(state),
              const SizedBox(width: 12),
              _semesterFilter(state),
              const SizedBox(width: 12),
              _clearButton(),
            ],
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator(color: _maroon)),
            )
          else if (state.records.isEmpty)
            _buildEmptyState()
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 640),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: _recordsTable(state, visibleRecords),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: _line),
          const SizedBox(height: 15),
          _pagination(state),
        ],
      ),
    );
  }

  Widget _searchField(StudentAcademicRecordsState state) {
    return SizedBox(
      height: 43,
      child: TextField(
        controller: _searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 19),
          hintText: 'Search by student name or ID...',
          hintStyle: const TextStyle(color: _muted, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _maroon),
          ),
        ),
        onSubmitted: (value) {
          setState(() => _page = 0);
          ref
              .read(studentAcademicRecordsProvider.notifier)
              .fetchRecords(search: value);
        },
      ),
    );
  }

  Widget _schoolYearFilter(StudentAcademicRecordsState state) {
    return Container(
      width: 190,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.schoolYear,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: _ink,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('All School Years')),
            ...state.schoolYears.map(
              (year) => DropdownMenuItem(
                value: year['label']?.toString() ?? '',
                child: Text(year['label']?.toString() ?? ''),
              ),
            ),
          ],
          onChanged: state.isSaving
              ? null
              : (value) {
                  setState(() => _page = 0);
                  ref
                      .read(studentAcademicRecordsProvider.notifier)
                      .fetchRecords(schoolYear: value ?? '');
                },
        ),
      ),
    );
  }

  Widget _semesterFilter(StudentAcademicRecordsState state) {
    return Container(
      width: 180,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.semester,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: _ink,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('All Semesters')),
            ..._semesterLabels.map(
              (label) => DropdownMenuItem(value: label, child: Text(label)),
            ),
          ],
          onChanged: state.isSaving
              ? null
              : (value) {
                  setState(() => _page = 0);
                  ref
                      .read(studentAcademicRecordsProvider.notifier)
                      .fetchRecords(semester: value ?? '');
                },
        ),
      ),
    );
  }

  Widget _clearButton() {
    return SizedBox(
      height: 43,
      child: OutlinedButton.icon(
        onPressed: () {
          _searchController.clear();
          setState(() => _page = 0);
          ref
              .read(studentAcademicRecordsProvider.notifier)
              .fetchRecords(search: '', schoolYear: '', semester: '');
        },
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('Clear'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _recordsTable(
    StudentAcademicRecordsState state,
    List<Map<String, dynamic>> visibleRecords,
  ) {
    return Column(
      children: [
        _tableHeader(const [
          _ColumnSpec('Student', 1.35),
          _ColumnSpec('School Year', 1.05),
          _ColumnSpec('Semester', 1.05),
          _ColumnSpec('Year Level', 0.95),
          _ColumnSpec('Created', 0.85),
          _ColumnSpec('Action', 0.7),
        ]),
        ...visibleRecords.map((record) => _recordRow(state, record)),
      ],
    );
  }

  List<Map<String, dynamic>> _pageRecords(List<Map<String, dynamic>> records) {
    final pages = records.isEmpty ? 1 : (records.length / _rowsPerPage).ceil();
    final safePage = _page.clamp(0, pages - 1);
    final start = safePage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, records.length);
    return records.sublist(start, end);
  }

  Widget _pagination(StudentAcademicRecordsState state) {
    final total = state.records.length;
    final pages = total == 0 ? 1 : (total / _rowsPerPage).ceil();
    final safePage = _page.clamp(0, pages - 1);
    final start = total == 0 ? 0 : safePage * _rowsPerPage + 1;
    final end = total == 0
        ? 0
        : (safePage * _rowsPerPage + _rowsPerPage).clamp(0, total);

    return Row(
      children: [
        Text(
          'Showing $start-$end of $total records',
          style: const TextStyle(
            color: Color(0xFF5D6678),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 16),
        _rowsPerPageDropdown(),
        const Spacer(),
        _pageButton(Icons.chevron_left_rounded, safePage > 0, () {
          setState(() => _page = safePage - 1);
        }),
        const SizedBox(width: 8),
        if (pages <= 10)
          ...List.generate(pages, (index) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _numberPageButton(index + 1, safePage == index, () {
                setState(() => _page = index);
              }),
            );
          })
        else ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Page ${safePage + 1} of $pages',
              style: const TextStyle(
                color: Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        _pageButton(Icons.chevron_right_rounded, safePage < pages - 1, () {
          setState(() => _page = safePage + 1);
        }),
      ],
    );
  }

  Widget _rowsPerPageDropdown() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Rows per page',
          style: TextStyle(
            color: Color(0xFF5D6678),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _rowsPerPageOptions.contains(_rowsPerPage)
                  ? _rowsPerPage
                  : _rowsPerPageOptions.first,
              isDense: true,
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              items: _rowsPerPageOptions
                  .map(
                    (n) => DropdownMenuItem<int>(
                      value: n,
                      child: Text('$n'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _rowsPerPage = value;
                  _page = 0;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _pageButton(IconData icon, bool enabled, VoidCallback onTap) {
    return SizedBox(
      width: 30,
      height: 36,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }

  Widget _numberPageButton(int number, bool selected, VoidCallback onTap) {
    return SizedBox(
      width: 30,
      height: 36,
      child: OutlinedButton(
        onPressed: selected ? null : onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          disabledForegroundColor: _maroon,
          foregroundColor: _ink,
          side: BorderSide(color: selected ? _maroon : _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Text(
          number.toString(),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _tableHeader(List<_ColumnSpec> columns) {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(children: columns.map(_tableHeaderCell).toList()),
    );
  }

  Widget _tableHeaderCell(_ColumnSpec column) {
    return Expanded(
      flex: (column.flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            column.label,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordRow(
    StudentAcademicRecordsState state,
    Map<String, dynamic> record,
  ) {
    return Container(
      height: 57,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          _tableCell(
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record['student_name']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  record['student_username']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            flex: 1.35,
          ),
          _tableCell(
            _bodyText(record['school_year']?.toString() ?? ''),
            flex: 1.05,
          ),
          _tableCell(
            _bodyText(record['semester']?.toString() ?? ''),
            flex: 1.05,
          ),
          _tableCell(
            _yearLevelBadge(record['year_level']?.toString() ?? ''),
            flex: 0.95,
          ),
          _tableCell(_bodyText(_dateLabel(record['created_at'])), flex: 0.85),
          _tableCell(_buildActions(state, record), flex: 0.7),
        ],
      ),
    );
  }

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildActions(
    StudentAcademicRecordsState state,
    Map<String, dynamic> record,
  ) {
    final recordId = _asInt(record['id']);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: state.isSaving ? null : () => _showRecordDialog(record),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.edit_square, color: _blue, size: 18),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: state.isSaving || recordId == null
              ? null
              : () => _confirmDelete(
                  recordId,
                  record['student_name']?.toString() ?? 'student',
                ),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.delete_rounded, color: _red, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _maroon,
          foregroundColor: _gold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Future<void> _showRecordDialog([Map<String, dynamic>? record]) async {
    final editing = record != null;
    final state = ref.read(studentAcademicRecordsProvider);
    int? selectedStudentId =
        _asInt(record?['student_id']) ?? _firstStudentId(state);
    String? selectedSchoolYear =
        record?['school_year']?.toString() ??
        state.activeSemester?['school_year']?.toString();
    int? selectedSemesterId =
        _asInt(record?['semester_id']) ?? _asInt(state.activeSemester?['id']);
    String selectedYearLevel =
        record?['year_level']?.toString() ?? _yearLevels.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final semesters = _semestersForYear(state, selectedSchoolYear);
            selectedSemesterId ??= _firstSemesterId(semesters);

            return AlertDialog(
              title: Text(
                editing ? 'Edit Academic Record' : 'Add Academic Record',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: selectedStudentId,
                        decoration: const InputDecoration(labelText: 'Student'),
                        items: state.students
                            .map(
                              (student) => DropdownMenuItem(
                                value: _asInt(student['id']),
                                child: Text(
                                  '${student['name']} (${student['username']})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedStudentId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedSchoolYear,
                        decoration: const InputDecoration(
                          labelText: 'School Year',
                        ),
                        items: state.schoolYears
                            .map(
                              (year) => DropdownMenuItem(
                                value: year['label']?.toString(),
                                child: Text(year['label']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedSchoolYear = value;
                            selectedSemesterId = _firstSemesterId(
                              _semestersForYear(state, value),
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey(
                          '$selectedSchoolYear-$selectedSemesterId',
                        ),
                        initialValue: selectedSemesterId,
                        decoration: const InputDecoration(
                          labelText: 'Semester',
                        ),
                        items: semesters
                            .map(
                              (semester) => DropdownMenuItem(
                                value: _asInt(semester['id']),
                                child: Text(
                                  semester['label']?.toString() ?? '',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedSemesterId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedYearLevel,
                        decoration: const InputDecoration(
                          labelText: 'Year Level',
                        ),
                        items: _yearLevels
                            .map(
                              (level) => DropdownMenuItem(
                                value: level,
                                child: Text(level),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedYearLevel = value ?? _yearLevels.first;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      selectedStudentId == null || selectedSemesterId == null
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: Text(editing ? 'Save Changes' : 'Save Record'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || saved != true) {
      return;
    }

    final payload = {
      'student_id': selectedStudentId,
      'semester_id': selectedSemesterId,
      'year_level': selectedYearLevel,
    };

    if (editing) {
      await ref
          .read(studentAcademicRecordsProvider.notifier)
          .updateRecord(_asInt(record['id'])!, payload);
    } else {
      await ref
          .read(studentAcademicRecordsProvider.notifier)
          .addRecord(payload);
    }
  }

  Future<void> _showRolloverDialog() async {
    final rolloverSearchCtrl = TextEditingController();

    // Clear previous preview state
    ref.read(studentAcademicRecordsProvider.notifier).fetchRolloverPreview(students: []);

    final Map<String, String>? dialogActions = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        String searchQuery = '';
        String? uploadedCsv;
        final actions = <String, String>{};

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final state = ref.watch(studentAcademicRecordsProvider);
            final activeLabel =
                state.activeSemester?['display_name'] ?? 'Not configured';
            final hasCsv = uploadedCsv != null;

            final filtered = state.rolloverRows.where((row) {
              if (searchQuery.isEmpty) return true;
              final record = row['record'] as Map? ?? {};
              final name =
                  (record['student_name']?.toString() ?? '').toLowerCase();
              final username =
                  (record['student_username']?.toString() ?? '').toLowerCase();
              final q = searchQuery.toLowerCase().trim();
              return name.contains(q) || username.contains(q);
            }).toList();

            final totalCount = state.rolloverRows.length;
            final nonDropCount =
                actions.values.where((a) => a != 'drop').length;

            final missingCount = state.rolloverRows
                .where((row) => !_rolloverHasTarget(row, 'promote'))
                .length;
            final useWarningChrome = missingCount > 0;

            bool hasValidationErrors = false;
            for (final row in state.rolloverRows) {
              final rec = row['record'] as Map? ?? {};
              final recordKeyId = rec['id'] != null 
                  ? rec['id'].toString() 
                  : rec['student_username'].toString();
              final action = actions[recordKeyId] ?? row['action_default'] ?? 'promote';
              if (action != 'drop' && row['validation_error'] != null) {
                hasValidationErrors = true;
                break;
              }
            }

            return StudentRecordsRolloverModal(
              useWarningChrome: useWarningChrome,
              activeLabel: activeLabel,
              totalCount: totalCount,
              missingCount: missingCount,
              searchQuery: searchQuery,
              filtered: filtered,
              rolloverSearchCtrl: rolloverSearchCtrl,
              actions: actions,
              onPromoteAll: () => setDialogState(() {
                for (final row in state.rolloverRows) {
                  final rec = row['record'] as Map? ?? {};
                  final isNew = row['is_new_student'] == true;
                  final recordKeyId = rec['id'] != null 
                      ? rec['id'].toString() 
                      : rec['student_username'].toString();
                  actions[recordKeyId] = isNew ? 'create' : 'promote';
                }
              }),
              onRetainAll: () => setDialogState(() {
                for (final row in state.rolloverRows) {
                  final rec = row['record'] as Map? ?? {};
                  final recordKeyId = rec['id'] != null 
                      ? rec['id'].toString() 
                      : rec['student_username'].toString();
                  actions[recordKeyId] = 'retain';
                }
              }),
              onSearchChanged: (v) => setDialogState(() => searchQuery = v),
              onSearchClear: () {
                rolloverSearchCtrl.clear();
                setDialogState(() => searchQuery = '');
              },
              onActionChanged: (id, value) => setDialogState(() {
                actions[id] = value ?? 'promote';
              }),
              onClose: () => Navigator.pop(dialogContext, null),
              onConfirm: () => Navigator.pop(dialogContext, actions),
              nonDropCount: nonDropCount,
              rolloverHasTarget: _rolloverHasTarget,
              rolloverResult: _rolloverResult,
              asInt: _asInt,
              hasCsvUploaded: hasCsv,
              hasValidationErrors: hasValidationErrors,
              onUploadCsv: () async {
                try {
                  final csv = await pickCsvTextFile();
                  if (csv == null) return;
                  if (!context.mounted) return;

                  final parsed = _parseOfficialClassListCsv(csv);
                  if (parsed.validationError != null) {
                    showValidationToast(context, parsed.validationError!);
                    return;
                  }
                  if (parsed.students.isEmpty) {
                    showValidationToast(
                      context,
                      'Selected file has no valid student records or header is invalid.',
                    );
                    return;
                  }

                  final activeSem = ref.read(studentAcademicRecordsProvider).activeSemester;
                  if (activeSem == null) {
                    showValidationToast(context, 'No active target semester is configured.');
                    return;
                  }

                  final targetSchoolYear = activeSem['school_year']?.toString().trim();
                  final targetSemester = activeSem['label']?.toString().trim();

                  final csvSchoolYear = parsed.metadata['school_year']?.toString().trim();
                  final csvSemester = parsed.metadata['semester']?.toString().trim();

                  if (csvSchoolYear != targetSchoolYear || csvSemester != targetSemester) {
                    showValidationToast(
                      context,
                      'Semester mismatch: The CSV is for $csvSemester A.Y. $csvSchoolYear, but the target semester is $targetSemester A.Y. $targetSchoolYear.',
                    );
                    return;
                  }

                  final ok = await ref
                      .read(studentAcademicRecordsProvider.notifier)
                      .fetchRolloverPreview(students: parsed.students);
                  if (!context.mounted) return;
                  if (ok) {
                    final updatedState = ref.read(studentAcademicRecordsProvider);
                    setDialogState(() {
                      uploadedCsv = csv;
                      actions.clear();
                      for (final row in updatedState.rolloverRows) {
                        final rec = row['record'] as Map? ?? {};
                        final recordKeyId = rec['id'] != null 
                            ? rec['id'].toString() 
                            : rec['student_username'].toString();
                        actions[recordKeyId] = row['action_default']?.toString() ?? 'promote';
                      }
                    });
                  }
                } catch (e) {
                  if (context.mounted) {
                    showErrorToast(context, 'Failed to process CSV file: $e');
                  }
                }
              },
              onClearCsv: () => setDialogState(() {
                uploadedCsv = null;
                actions.clear();
                ref
                    .read(studentAcademicRecordsProvider.notifier)
                    .fetchRolloverPreview(students: []);
              }),
            );
          },
        );
      },
    );

    rolloverSearchCtrl.dispose();

    if (!mounted || dialogActions == null) {
      return;
    }

    final state = ref.read(studentAcademicRecordsProvider);
    final List<Map<String, dynamic>> confirmActions = [];

    for (final row in state.rolloverRows) {
      final rec = row['record'] as Map? ?? {};
      final recordId = _asInt(rec['id']);
      final username = rec['student_username']?.toString() ?? '';
      final recordKeyId = recordId != null ? recordId.toString() : username;

      final action = dialogActions[recordKeyId] ?? row['action_default'] ?? 'promote';
      final isNew = row['is_new_student'] == true;

      final pr = row['promote_result'] ?? {};
      final targetYear = pr['year_level']?.toString() ?? '';
      final targetSection = pr['section']?.toString() ?? '';

      if (isNew) {
        confirmActions.add({
          'username': username,
          'first_name': rec['first_name']?.toString() ?? '',
          'last_name': rec['last_name']?.toString() ?? '',
          'email': rec['student_email']?.toString() ?? '',
          'action': action,
          'year_level': targetYear,
          'section': targetSection,
        });
      } else {
        confirmActions.add({
          'record_id': recordId,
          'username': username,
          'action': action,
          'year_level': targetYear,
          'section': targetSection,
        });
      }
    }

    await ref
        .read(studentAcademicRecordsProvider.notifier)
        .confirmRollover(confirmActions);
  }

  Future<void> _confirmDelete(int recordId, String studentName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Academic Record'),
        content: Text('Delete the academic record for $studentName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await ref
        .read(studentAcademicRecordsProvider.notifier)
        .deleteRecord(recordId);
  }

  String _rolloverResult(Map<String, dynamic> row, String action) {
    if (action == 'drop') {
      return 'Excluded';
    }
    if (action == 'create') {
      final pr = row['promote_result'] ?? {};
      return '${pr['year_level']} · ${pr['section']}';
    }
    final key = action == 'retain' ? 'retain_result' : 'promote_result';
    final result = Map<String, dynamic>.from(row[key] as Map);
    final hasTarget = result['target_semester_id'] != null;
    final sectionStr = result['section'] != null && result['section'].toString().isNotEmpty ? ' · ${result['section']}' : '';
    if (!hasTarget && action == 'promote') {
      return '${result['year_level']}$sectionStr (semester not found)';
    }
    return '${result['year_level']}$sectionStr';
  }

  bool _rolloverHasTarget(Map<String, dynamic> row, String action) {
    if (action == 'drop' || action == 'retain' || action == 'create') return true;
    final result = row['promote_result'];
    if (result is! Map) return false;
    return result['target_semester_id'] != null;
  }

  _OfficialClassListParseResult _parseOfficialClassListCsv(String csv) {
    final rows = csv
        .split(RegExp(r'\r?\n'))
        .map(_splitCsvLine)
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) {
      return const _OfficialClassListParseResult(
        metadata: {},
        students: [],
        validationError: 'Selected file is empty.',
      );
    }

    String? csvSchoolYear;
    String? csvSemester;
    final schoolYearRegex = RegExp(r'\b(\d{4}-\d{4})\b');
    final semesterRegex = RegExp(r'\b(1st|2nd|Summer)\s*(?:Semester|sem)?\b', caseSensitive: false);

    final limit = rows.length < 10 ? rows.length : 10;
    for (var i = 0; i < limit; i++) {
      for (final cell in rows[i]) {
        final trimmed = cell.trim();
        if (trimmed.isEmpty) continue;

        if (csvSchoolYear == null) {
          final syMatch = schoolYearRegex.firstMatch(trimmed);
          if (syMatch != null) {
            csvSchoolYear = syMatch.group(1);
          }
        }

        if (csvSemester == null) {
          final semMatch = semesterRegex.firstMatch(trimmed);
          if (semMatch != null) {
            final rawSem = semMatch.group(1)!.toLowerCase();
            if (rawSem.contains('1st')) {
              csvSemester = '1st Semester';
            } else if (rawSem.contains('2nd')) {
              csvSemester = '2nd Semester';
            } else if (rawSem.contains('summer')) {
              csvSemester = 'Summer';
            }
          }
        }
      }
      if (csvSchoolYear != null && csvSemester != null) break;
    }

    if (csvSchoolYear == null || csvSemester == null) {
      return const _OfficialClassListParseResult(
        metadata: {},
        students: [],
        validationError: 'Missing school year/semester header in the CSV (e.g., "2026-2027 1st Semester").',
      );
    }

    final metadata = <String, dynamic>{
      'school_year': csvSchoolYear,
      'semester': csvSemester,
    };
    var headerIndex = -1;

    for (var i = 0; i < rows.length; i++) {
      final normalized = rows[i].map(_normalizeHeader).toList();

      void readMeta(String key, List<String> labels) {
        if (metadata[key]?.toString().trim().isNotEmpty == true) return;
        for (final label in labels) {
          final index = normalized.indexWhere((cell) => cell == label);
          if (index == -1) continue;
          final value = _nextCell(rows[i], index);
          if (value.isNotEmpty) metadata[key] = value;
          return;
        }
      }

      readMeta('faculty', ['faculty', 'instructor']);
      readMeta('section', ['class section', 'section']);
      readMeta('year_level', ['year level', 'level']);

      final hasStudentNumber = normalized.any(
        (cell) =>
            cell.contains('student') &&
            (cell.contains('number') ||
                cell.contains('no') ||
                cell == 'student n'),
      );
      final hasFullName = normalized.contains('full name');
      if (hasStudentNumber && hasFullName) {
        headerIndex = i;
        break;
      }
    }

    if (metadata['year_level'] != null) {
      metadata['year_level'] = _normalizeYearLevel(
        metadata['year_level'].toString(),
      );
    }
    if (headerIndex == -1) {
      return _OfficialClassListParseResult(
        metadata: metadata,
        students: const [],
      );
    }

    final headers = rows[headerIndex].map(_normalizeHeader).toList();
    int findHeader(bool Function(String value) matches) =>
        headers.indexWhere(matches);
    final idIndex = findHeader(
      (value) =>
          value.contains('student') &&
          (value.contains('number') ||
              value.contains('no') ||
              value == 'student n'),
    );
    final nameIndex = findHeader((value) => value == 'full name');
    final levelIndex = findHeader((value) => value == 'level');
    final emailIndex = findHeader((value) => value == 'email');
    final section = metadata['section']?.toString() ?? '';
    final yearLevel = metadata['year_level']?.toString() ?? '';
    final students = <Map<String, dynamic>>[];

    for (final row in rows.skip(headerIndex + 1)) {
      String read(int index) =>
          index >= 0 && index < row.length ? row[index].trim() : '';
      final id = read(idIndex);
      final name = read(nameIndex);
      if (id.isEmpty || name.isEmpty) continue;
      final splitName = _splitOfficialFullName(name);
      final rowYear = levelIndex != -1
          ? _normalizeYearLevel(read(levelIndex))
          : yearLevel;
      students.add({
        'id_number': id,
        'first_name': splitName.firstName,
        'last_name': splitName.lastName,
        'email': emailIndex == -1 ? '' : read(emailIndex),
        'role': 'student',
        if (rowYear.isNotEmpty) 'year_level': rowYear,
        if (section.isNotEmpty) 'section': section,
      });
    }

    return _OfficialClassListParseResult(
      metadata: metadata,
      students: students,
    );
  }

  List<String> _splitCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        values.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString().trim());
    return values;
  }

  String _nextCell(List<String> row, int index) {
    for (var i = index + 1; i < row.length; i++) {
      final value = row[i].trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _normalizeHeader(String value) => value
      .trim()
      .replaceFirst('\ufeff', '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  String _normalizeYearLevel(String value) {
    final cleaned = value.trim().toLowerCase();
    if (cleaned.contains('1') || cleaned.contains('first')) {
      return '1st Year';
    }
    if (cleaned.contains('2') || cleaned.contains('second')) {
      return '2nd Year';
    }
    if (cleaned.contains('3') || cleaned.contains('third')) {
      return '3rd Year';
    }
    if (cleaned.contains('4') || cleaned.contains('fourth')) {
      return '4th Year';
    }
    return value;
  }

  _OfficialNameParts _splitOfficialFullName(String value) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.contains(',')) {
      final parts = clean.split(',');
      final lastName = parts.first.trim();
      final firstName = parts.skip(1).join(',').trim();
      return _OfficialNameParts(firstName: firstName, lastName: lastName);
    }
    final parts = clean.split(' ');
    if (parts.length == 1) {
      return _OfficialNameParts(firstName: clean, lastName: '');
    }
    return _OfficialNameParts(
      firstName: parts.first,
      lastName: parts.skip(1).join(' '),
    );
  }

  List<Map<String, dynamic>> _semestersForYear(
    StudentAcademicRecordsState state,
    String? schoolYear,
  ) {
    final year = state.schoolYears.firstWhere(
      (item) => item['label']?.toString() == schoolYear,
      orElse: () => const {},
    );
    final semesters = year['semesters'];
    if (semesters is! List) {
      return [];
    }
    return semesters
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int? _firstStudentId(StudentAcademicRecordsState state) {
    if (state.students.isEmpty) {
      return null;
    }
    return _asInt(state.students.first['id']);
  }

  int? _firstSemesterId(List<Map<String, dynamic>> semesters) {
    if (semesters.isEmpty) {
      return null;
    }
    return _asInt(semesters.first['id']);
  }


  Widget _yearLevelBadge(String raw) {
    final label = raw.trim().isEmpty ? '-' : raw.trim();
    final (Color bg, Color fg) = switch (label) {
      '1st Year' => (const Color(0xFFEFF6FF), const Color(0xFF1E40AF)),
      '2nd Year' => (const Color(0xFFF0FDF4), const Color(0xFF166534)),
      '3rd Year' => (const Color(0xFFEEF2FF), const Color(0xFF4338CA)),
      '4th Year' => (const Color(0xFFFDE8E8), const Color(0xFF9B1C1C)),
      _ => (const Color(0xFFF1F5F9), const Color(0xFF334155)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 150,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge_outlined, size: 38, color: Color(0xFF98A2B3)),
          SizedBox(height: 10),
          Text(
            'No academic records found',
            style: TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Create records manually or import students with academic context.',
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon, Color iconColor, Color background) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: iconColor, size: 20),
    );
  }

  String _dateLabel(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length >= 10) {
      return text.substring(0, 10);
    }
    return text;
  }

  int _count(StudentAcademicRecordsState state, String key) {
    final value = state.counts[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

class _ColumnSpec {
  final String label;
  final double flex;

  const _ColumnSpec(this.label, this.flex);
}

class _OfficialClassListParseResult {
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> students;
  final String? validationError;

  const _OfficialClassListParseResult({
    required this.metadata,
    required this.students,
    this.validationError,
  });
}

class _OfficialNameParts {
  final String firstName;
  final String lastName;

  const _OfficialNameParts({required this.firstName, required this.lastName});
}
