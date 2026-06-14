import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../services/pit_instructor_provider.dart';
import '../../../services/pit_lead_cohort_provider.dart';
import '../../../services/user_management_provider.dart';
import '../../../utils/csv_file_io.dart';
import '../admin/widgets/defensys_admin_shell.dart';

enum _CohortViewMode { sections, students }

class PitLeadCohortScreen extends ConsumerStatefulWidget {
  final VoidCallback? onCreateTeam;

  const PitLeadCohortScreen({super.key, this.onCreateTeam});

  @override
  ConsumerState<PitLeadCohortScreen> createState() =>
      _PitLeadCohortScreenState();
}

class _PitLeadCohortScreenState extends ConsumerState<PitLeadCohortScreen> {
  final _searchController = TextEditingController();
  String _teamStatusFilter = 'all';
  String _cohortScope = 'active';
  String _sectionStatusFilter = 'all';
  _CohortViewMode _viewMode = _CohortViewMode.sections;

  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _line = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pitLeadCohortProvider.notifier).fetchCohort();
      ref.read(pitInstructorProvider.notifier).fetchAssignments();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    ref
        .read(pitLeadCohortProvider.notifier)
        .fetchCohort(
          search: _searchController.text,
          teamStatusFilter: _teamStatusFilter,
          scope: _cohortScope,
        );
  }

  bool get _isAuditMode =>
      ref.read(pitLeadCohortProvider).operatingMode == 'audit';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pitLeadCohortProvider);
    final instructorState = ref.watch(pitInstructorProvider);
    final importState = ref.watch(userManagementProvider);
    final pitYear = state.pitLeadYear ?? 'Unscoped';
    final semester = state.activeSemester ?? 'No active semester';

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.school_outlined,
            title: 'Cohort roster',
            subtitle: '$pitYear · $semester',
            actions: _headerActions(
              state,
              importState,
              pitYear,
              auditMode: _isAuditMode,
            ),
          ),
          const SizedBox(height: 28),
          if (importState.error != null) ...[
            _notice(importState.error!, warning: true),
            const SizedBox(height: 14),
          ],
          if (importState.message != null) ...[
            _notice(importState.message!),
            const SizedBox(height: 14),
          ],
          if (state.operatingMessage != null &&
              state.operatingMessage!.trim().isNotEmpty) ...[
            _notice(state.operatingMessage!, warning: _isAuditMode),
            const SizedBox(height: 14),
          ],
          _viewModeTabs(),
          const SizedBox(height: 24),
          _summaryCards(state, instructorState),
          const SizedBox(height: 30),
          DefensysCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _searchBarRow(state, instructorState),
                const SizedBox(height: 20),
                if (state.error != null) ...[
                  _notice(state.error!, warning: true),
                  const SizedBox(height: 14),
                ],
                if (instructorState.error != null &&
                    _viewMode == _CohortViewMode.sections) ...[
                  _notice(instructorState.error!, warning: true),
                  const SizedBox(height: 14),
                ],
                _viewMode == _CohortViewMode.sections
                    ? _sectionTable(state, instructorState)
                    : _rosterTable(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secondaryButton({
    required Widget icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon,
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

  Widget _primaryButton({
    required Widget icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: icon,
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _maroon,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _headerActions(
    PitLeadCohortState state,
    UserManagementState importState,
    String pitYear, {
    required bool auditMode,
  }) {
    final busy = importState.isSaving || state.isSaving;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        if (!auditMode)
          _secondaryButton(
            icon: const Icon(Icons.download_outlined, size: 18),
            label: 'CSV Template',
            onTap: busy ? null : () => _downloadOfficialTemplate(pitYear),
          ),
        if (!auditMode)
          _secondaryButton(
            icon: importState.isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined, size: 18),
            label: 'Import Official Class List',
            onTap: busy
                ? null
                : () => context.go(FacultyRoutes.pitStudentImport),
          ),
        _secondaryButton(
          icon: state.isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.rotate_right_outlined, size: 18),
          label: 'Rollover Preview',
          onTap: busy ? null : _openRolloverPreview,
        ),
        if (!auditMode && widget.onCreateTeam != null)
          _primaryButton(
            icon: const Icon(Icons.groups_outlined, size: 18),
            label: 'Manage PIT teams',
            onTap: busy ? null : widget.onCreateTeam,
          ),
      ],
    );
  }

  Widget _viewModeTabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _tabItem('Sections', _viewMode == _CohortViewMode.sections, () {
            setState(() => _viewMode = _CohortViewMode.sections);
          }),
          const SizedBox(width: 24),
          _tabItem('Students', _viewMode == _CohortViewMode.students, () {
            setState(() => _viewMode = _CohortViewMode.students);
          }),
        ],
      ),
    );
  }

  Widget _tabItem(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? _maroon : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? _maroon : _muted,
            fontSize: 14,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _scopeFilter(PitLeadCohortState state) {
    return Container(
      width: 168,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _cohortScope,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: _ink,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: const [
            DropdownMenuItem(value: 'active', child: Text('Current Term')),
            DropdownMenuItem(value: 'history', child: Text('History')),
          ],
          onChanged: state.isLoading
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _cohortScope = value);
                  _applyFilters();
                },
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    bool selected = false,
    Color iconColor = _muted,
    VoidCallback? onTap,
  }) {
    final card = Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? _maroon : const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F2F4),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 25),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        mouseCursor: SystemMouseCursors.click,
        child: card,
      ),
    );
  }

  Widget _summaryCards(
    PitLeadCohortState state,
    PitInstructorState instructorState,
  ) {
    final canTap = !state.isLoading && !instructorState.isLoading;

    if (_viewMode == _CohortViewMode.sections) {
      final summaries = _sectionSummaries(state.students, instructorState);
      final assignedCount = summaries.where((item) => item.hasInstructor).length;
      final needsCount = summaries.length - assignedCount;

      return Row(
        children: [
          Expanded(
            child: _summaryCard(
              title: 'All Sections',
              subtitle: '${summaries.length} Total',
              icon: Icons.folder_open_rounded,
              selected: _sectionStatusFilter == 'all',
              onTap: canTap ? () => setState(() => _sectionStatusFilter = 'all') : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _summaryCard(
              title: 'Assigned',
              subtitle: '$assignedCount Assigned',
              icon: Icons.assignment_turned_in_rounded,
              iconColor: const Color(0xFF047857),
              selected: _sectionStatusFilter == 'assigned',
              onTap: canTap ? () => setState(() => _sectionStatusFilter = 'assigned') : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _summaryCard(
              title: 'Needs Assignment',
              subtitle: '$needsCount Pending',
              icon: Icons.assignment_late_rounded,
              iconColor: const Color(0xFFEA580C),
              selected: _sectionStatusFilter == 'needs_assignment',
              onTap: canTap ? () => setState(() => _sectionStatusFilter = 'needs_assignment') : null,
            ),
          ),
        ],
      );
    } else {
      final allCount = state.counts['all']?.toString() ?? '0';
      final onTeamCount = state.counts['on_team']?.toString() ?? '0';
      final unassignedCount = state.counts['unassigned']?.toString() ?? '0';

      return Row(
        children: [
          Expanded(
            child: _summaryCard(
              title: 'All Students',
              subtitle: '$allCount Total',
              icon: Icons.school_rounded,
              iconColor: const Color(0xFF2563EB),
              selected: _teamStatusFilter == 'all',
              onTap: canTap
                  ? () {
                      setState(() => _teamStatusFilter = 'all');
                      ref.read(pitLeadCohortProvider.notifier).fetchCohort(
                            search: _searchController.text,
                            teamStatusFilter: 'all',
                            scope: _cohortScope,
                          );
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _summaryCard(
              title: 'On Team',
              subtitle: '$onTeamCount Active',
              icon: Icons.groups_rounded,
              iconColor: const Color(0xFF047857),
              selected: _teamStatusFilter == 'on_team',
              onTap: canTap
                  ? () {
                      setState(() => _teamStatusFilter = 'on_team');
                      ref.read(pitLeadCohortProvider.notifier).fetchCohort(
                            search: _searchController.text,
                            teamStatusFilter: 'on_team',
                            scope: _cohortScope,
                          );
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _summaryCard(
              title: 'Unassigned',
              subtitle: '$unassignedCount Pending',
              icon: Icons.person_rounded,
              iconColor: const Color(0xFFEA580C),
              selected: _teamStatusFilter == 'unassigned',
              onTap: canTap
                  ? () {
                      setState(() => _teamStatusFilter = 'unassigned');
                      ref.read(pitLeadCohortProvider.notifier).fetchCohort(
                            search: _searchController.text,
                            teamStatusFilter: 'unassigned',
                            scope: _cohortScope,
                          );
                    }
                  : null,
            ),
          ),
        ],
      );
    }
  }

  Widget _searchBarRow(
    PitLeadCohortState state,
    PitInstructorState instructorState,
  ) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              enabled: !state.isLoading && !instructorState.isLoading,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 19),
                hintText: _viewMode == _CohortViewMode.sections
                    ? 'Search section or instructor...'
                    : 'Search name, ID, or email...',
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
              onChanged: _viewMode == _CohortViewMode.sections
                  ? (_) => setState(() {})
                  : null,
              onSubmitted: _viewMode == _CohortViewMode.students
                  ? (_) => _applyFilters()
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 16),
        _scopeFilter(state),
        const SizedBox(width: 16),
        if (_viewMode == _CohortViewMode.students) ...[
          SizedBox(
            height: 42,
            child: ElevatedButton(
              onPressed: state.isLoading ? null : _applyFilters,
              style: ElevatedButton.styleFrom(
                backgroundColor: _maroon,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              child: state.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Search'),
            ),
          ),
          const SizedBox(width: 12),
        ],
        SizedBox(
          height: 42,
          child: OutlinedButton.icon(
            onPressed: state.isLoading
                ? null
                : () {
                    _searchController.clear();
                    setState(() {
                      _cohortScope = 'active';
                      _teamStatusFilter = 'all';
                      _sectionStatusFilter = 'all';
                    });
                    _applyFilters();
                  },
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Clear'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
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

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _bodyText(String value, {bool bold = false}) {
    return Text(
      value,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      ),
    );
  }

  Widget _rosterTable(PitLeadCohortState state) {
    if (state.isLoading && state.students.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (state.students.isEmpty) {
      final pitYear = state.pitLeadYear ?? 'your year level';
      final emptyText = _cohortScope == 'history'
          ? 'No historical roster entries for $pitYear in prior terms.'
          : _isAuditMode
          ? 'No active-term roster for $pitYear — view History for prior-term students and teams.'
          : 'No students with academic records for $pitYear on the active term. '
                'Ask an administrator to import students or set up academic records.';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        child: Text(
          emptyText,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
        ),
      );
    }

    return Column(
      children: [
        _tableHeader(const [
          _ColumnSpec('Name', 3.0),
          _ColumnSpec('Student ID', 2.0),
          _ColumnSpec('Email', 2.0),
          _ColumnSpec('Section', 1.5),
          _ColumnSpec('Team status', 2.5),
        ]),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.students.length,
          itemBuilder: (context, index) {
            final student = state.students[index];
            final onTeam = student['team_status'] == 'on_team';
            final isHistorical = student['is_historical'] == true;
            var teamLabel = onTeam
                ? student['team_name']?.toString() ?? 'On team'
                : 'Unassigned';
            if (isHistorical && onTeam) {
              final term = student['term_label']?.toString();
              if (term != null && term.isNotEmpty) {
                teamLabel = '$teamLabel ($term)';
              }
            }

            return Container(
              height: 57,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: _line)),
              ),
              child: Row(
                children: [
                  _tableCell(
                    Text(
                      student['name']?.toString() ?? '-',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    flex: 3.0,
                  ),
                  _tableCell(
                    _bodyText(student['username']?.toString() ?? '-'),
                    flex: 2.0,
                  ),
                  _tableCell(
                    _bodyText(student['email']?.toString() ?? '-'),
                    flex: 2.0,
                  ),
                  _tableCell(
                    Text(
                      student['section']?.toString().trim().isNotEmpty == true
                          ? student['section'].toString()
                          : '-',
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    flex: 1.5,
                  ),
                  _tableCell(
                    onTeam
                        ? DefensysStatusBadge.success(
                            label: teamLabel,
                            showDot: false,
                          )
                        : const DefensysStatusBadge.inactive(
                            label: 'Unassigned',
                          ),
                    flex: 2.5,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _sectionTable(
    PitLeadCohortState state,
    PitInstructorState instructorState,
  ) {
    if ((state.isLoading && state.students.isEmpty) ||
        (instructorState.isLoading && instructorState.assignments.isEmpty)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final summaries = _filteredSectionSummaries(state, instructorState);
    if (summaries.isEmpty) {
      final pitYear = state.pitLeadYear ?? 'your year level';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        child: Text(
          state.students.isEmpty
              ? 'No section roster for $pitYear yet. Import an official class list to create section records.'
              : 'No sections match the current filters.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
        ),
      );
    }

    return Column(
      children: [
        _tableHeader(const [
          _ColumnSpec('Section', 2.0),
          _ColumnSpec('Instructor', 3.0),
          _ColumnSpec('Students', 2.0),
          _ColumnSpec('Team status', 2.0),
          _ColumnSpec('Action', 1.5),
        ]),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: summaries.length,
          itemBuilder: (context, index) {
            final summary = summaries[index];
            return Container(
              height: 57,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: _line)),
              ),
              child: Row(
                children: [
                  _tableCell(
                    _bodyText(summary.section, bold: true),
                    flex: 2.0,
                  ),
                  _tableCell(
                    summary.hasInstructor
                        ? _bodyText(summary.instructorName!)
                        : const DefensysStatusBadge.inactive(
                            label: 'Needs assignment',
                          ),
                    flex: 3.0,
                  ),
                  _tableCell(
                    _bodyText('${summary.studentCount}'),
                    flex: 2.0,
                  ),
                  _tableCell(
                    summary.teamCount > 0
                        ? DefensysStatusBadge.success(
                            label: summary.teamLabel,
                            showDot: false,
                          )
                        : const DefensysStatusBadge.inactive(
                            label: 'No teams yet',
                          ),
                    flex: 2.0,
                  ),
                  _tableCell(
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: _maroon,
                        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => _showSectionDetails(summary.section),
                      child: const Text('Details'),
                    ),
                    flex: 1.5,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _notice(
    String message, {
    bool warning = false,
    VoidCallback? onDismiss,
  }) {
    final color = warning ? DefensysUi.warningText : DefensysUi.successText;
    final background = warning ? DefensysUi.warningBg : DefensysUi.successBg;
    final border = warning ? DefensysUi.warningBorder : DefensysUi.successBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                message,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss',
              icon: Icon(Icons.close_rounded, size: 18, color: color),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
        ],
      ),
    );
  }

  List<_SectionSummary> _filteredSectionSummaries(
    PitLeadCohortState state,
    PitInstructorState instructorState,
  ) {
    final search = _searchController.text.trim().toLowerCase();
    return _sectionSummaries(state.students, instructorState).where((summary) {
      if (_sectionStatusFilter == 'assigned' && !summary.hasInstructor) {
        return false;
      }
      if (_sectionStatusFilter == 'needs_assignment' && summary.hasInstructor) {
        return false;
      }
      if (search.isEmpty) return true;
      return summary.section.toLowerCase().contains(search) ||
          (summary.instructorName ?? '').toLowerCase().contains(search);
    }).toList();
  }

  List<_SectionSummary> _sectionSummaries(
    List<Map<String, dynamic>> students,
    PitInstructorState instructorState,
  ) {
    final bySection = <String, _SectionDraft>{};
    for (final student in students) {
      final rawSection = student['section']?.toString().trim() ?? '';
      final section = rawSection.isNotEmpty ? rawSection : 'Unassigned section';
      final key = _sectionKey(section);
      final draft = bySection.putIfAbsent(
        key,
        () => _SectionDraft(section: section),
      );
      draft.studentCount += 1;
      final teamName = student['team_name']?.toString().trim() ?? '';
      if (teamName.isNotEmpty) draft.teamNames.add(teamName);
    }

    final activeAssignments = instructorState.assignments.where(
      (assignment) => assignment['is_active'] == true,
    );
    final instructorBySection = <String, String>{};
    for (final assignment in activeAssignments) {
      final section = assignment['section']?.toString().trim() ?? '';
      if (section.isEmpty) continue;
      instructorBySection[_sectionKey(section)] =
          assignment['faculty_name']?.toString() ?? 'Faculty';
    }

    final summaries = bySection.values.map((draft) {
      final instructorName = instructorBySection[_sectionKey(draft.section)];
      return _SectionSummary(
        section: draft.section,
        instructorName: instructorName,
        studentCount: draft.studentCount,
        teamCount: draft.teamNames.length,
      );
    }).toList()..sort((a, b) => a.section.compareTo(b.section));

    return summaries;
  }

  String _sectionKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  void _showSectionDetails(String section) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SectionDetailsDialog(
        sectionName: section,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<void> _downloadOfficialTemplate(String year) async {
    await downloadTextFile(
      filename: 'defensys-official-class-list-${_slug(year)}.csv',
      content:
          'OFFICIAL LIST OF ENROLLED STUDENTS\n'
          '2026-2027 1st Semester\n'
          '\n'
          'Subject Code,IT111\n'
          'Subject Title,Introduction to Computing\n'
          'Instructor,"Daga-ang, Jubilee S."\n'
          'Class Section,BSIT-1A\n'
          'Year Level,$year\n'
          '\n'
          '#,Student Number,Full Name,Program,Gender,Level,Email,Contact\n'
          '1,20300001,"ABAJAR, Mae Ann P",BSIT,F,1st Yr.,mae@example.com,09170000001\n'
          '2,20300002,"ABAO, Mary Vhel Y",BSIT,F,1st Yr.,mary@example.com,09170000002\n',
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Rollover complete. $created created, $skipped skipped for $targetLabel.',
                ),
              ),
            );
          }
        },
      ),
    );

    if (!mounted || confirmed != true) return;
    _applyFilters();
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '');
}

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
        target['display_name']?.toString() ??
        widget.preview['target_semester_label']?.toString() ??
        'No target term configured';
    final willCreate = _asInt(counts['will_create']);
    final alreadyExists = _asInt(counts['already_exists']);
    final blocked = _asInt(counts['blocked']);
    final total = _asInt(counts['all']);
    final isCapstoneIntake = widget.preview['is_capstone_intake'] == true;
    final canConfirm =
        !_isConfirming && willCreate > 0 && blocked == 0 && target.isNotEmpty;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PIT Rollover Preview',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$pitYear cohort -> $targetYear',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isConfirming ? null : widget.onCancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _line),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _summaryTile('Source', sourceLabel),
                      _summaryTile('Target', targetLabel),
                      _summaryTile('Students', '$total total'),
                    ],
                  ),
                  if (isCapstoneIntake) ...[
                    const SizedBox(height: 12),
                    _notice(
                      'This target term is marked as Capstone intake. Rollover will create academic records only; Capstone teams, advisers, panels, schedules, and grades stay under admin setup.',
                    ),
                  ],
                  if (blocked > 0) ...[
                    const SizedBox(height: 12),
                    _notice(
                      '$blocked student record${blocked == 1 ? '' : 's'} cannot roll over because the target academic period is missing.',
                      warning: true,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _countPill(
                        'Will create',
                        willCreate,
                        const Color(0xFF047857),
                      ),
                      _countPill(
                        'Already exists',
                        alreadyExists,
                        const Color(0xFF2563EB),
                      ),
                      _countPill('Blocked', blocked, const Color(0xFFB91C1C)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _line),
            Flexible(
              child: rows.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'No source PIT cohort records are available for rollover.',
                          style: TextStyle(color: _muted, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: _line),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final record = _map(row['record']);
                        final status = row['status']?.toString() ?? 'blocked';
                        final reason = row['reason']?.toString() ?? '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record['student_name']?.toString() ?? '-',
                                      style: const TextStyle(
                                        color: _ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      record['student_username']?.toString() ??
                                          '-',
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  record['section']
                                              ?.toString()
                                              .trim()
                                              .isNotEmpty ==
                                          true
                                      ? record['section'].toString()
                                      : 'No section',
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: _statusPill(status, reason),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1, color: _line),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isConfirming ? null : widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: canConfirm
                        ? () async {
                            setState(() => _isConfirming = true);
                            await widget.onConfirm();
                            if (mounted) {
                              setState(() => _isConfirming = false);
                            }
                          }
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                    ),
                    icon: _isConfirming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: Text('Create Rollover Records ($willCreate)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(String label, String value) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String message, {bool warning = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFFBEB) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warning ? const Color(0xFFF59E0B) : const Color(0xFF93C5FD),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF374151),
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _countPill(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _statusPill(String status, String reason) {
    final color = switch (status) {
      'create' => const Color(0xFF047857),
      'exists' => const Color(0xFF2563EB),
      _ => const Color(0xFFB91C1C),
    };
    final label = switch (status) {
      'create' => 'Will create',
      'exists' => 'Already exists',
      _ => 'Blocked',
    };
    return Tooltip(
      message: reason.isEmpty ? label : reason,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _SectionDraft {
  final String section;
  int studentCount = 0;
  final Set<String> teamNames = <String>{};

  _SectionDraft({required this.section});
}

class _SectionSummary {
  final String section;
  final String? instructorName;
  final int studentCount;
  final int teamCount;

  const _SectionSummary({
    required this.section,
    required this.instructorName,
    required this.studentCount,
    required this.teamCount,
  });

  bool get hasInstructor =>
      instructorName != null && instructorName!.trim().isNotEmpty;

  bool get isAssignable => section != 'Unassigned section';

  String get teamLabel {
    if (teamCount == 0) return 'No teams yet';
    if (teamCount == 1) return '1 team';
    return '$teamCount teams';
  }
}

class _ColumnSpec {
  final String label;
  final double flex;

  const _ColumnSpec(this.label, this.flex);
}

class _SectionDetailsDialog extends ConsumerStatefulWidget {
  final String sectionName;
  final VoidCallback onClose;

  const _SectionDetailsDialog({
    required this.sectionName,
    required this.onClose,
  });

  @override
  ConsumerState<_SectionDetailsDialog> createState() => _SectionDetailsDialogState();
}

class _SectionDetailsDialogState extends ConsumerState<_SectionDetailsDialog> {
  int? _selectedFacultyId;
  bool _isReplacing = false;

  static const _maroon = DefensysUi.primaryMaroon;
  static const _ink = DefensysUi.textDark;
  static const _muted = Color(0xFF6B7280);
  static const _line = Color(0xFFE5E7EB);

  String _sectionKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final cohortState = ref.watch(pitLeadCohortProvider);
    final instructorState = ref.watch(pitInstructorProvider);

    // Filter students
    final sectionStudents = cohortState.students.where((s) {
      final sSec = s['section']?.toString().trim() ?? '';
      final targetSec = widget.sectionName.trim();
      if (targetSec == 'Unassigned section') {
        return sSec.isEmpty || sSec == 'Unassigned section';
      }
      return _sectionKey(sSec) == _sectionKey(targetSec);
    }).toList();

    // Count teams
    final teamNames = sectionStudents
        .map((s) => s['team_name']?.toString().trim() ?? '')
        .where((t) => t.isNotEmpty)
        .toSet();
    final teamCount = teamNames.length;

    // Find active assignment
    final activeAssignment = instructorState.assignments.firstWhere(
      (a) =>
          _sectionKey(a['section']?.toString() ?? '') ==
              _sectionKey(widget.sectionName) &&
          a['is_active'] == true,
      orElse: () => <String, dynamic>{},
    );
    final hasInstructor = activeAssignment.isNotEmpty;

    final isAssignable = widget.sectionName != 'Unassigned section';

    // Faculty drop down items
    final facultyItems = instructorState.faculty
        .map((user) {
          final id = _asInt(user['id']);
          if (id == null) return null;
          final name =
              user['name']?.toString() ??
              user['username']?.toString() ??
              'Faculty';
          final role = user['displayRole'] is Map
              ? (user['displayRole']['label']?.toString() ?? 'Faculty')
              : 'Faculty';
          return DropdownMenuItem<int>(
            value: id,
            child: Text('$name ($role)'),
          );
        })
        .whereType<DropdownMenuItem<int>>()
        .toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with subtle maroon/gold background decoration
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFF4F4), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Section Details: ${widget.sectionName}',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'PIT Instructor & Student Roster',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: instructorState.isSaving ? null : widget.onClose,
                    icon: const Icon(Icons.close_rounded, size: 24),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _line),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (instructorState.error != null) ...[
                      _dialogNotice(instructorState.error!, warning: true),
                      const SizedBox(height: 16),
                    ],
                    if (instructorState.message != null) ...[
                      _dialogNotice(instructorState.message!),
                      const SizedBox(height: 16),
                    ],

                    // Stat cards Row
                    Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            title: '${sectionStudents.length}',
                            subtitle: 'Enrolled Students',
                            icon: Icons.people_alt_outlined,
                            iconColor: const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _statCard(
                            title: '$teamCount',
                            subtitle: teamCount == 1 ? 'Active Team' : 'Active Teams',
                            icon: Icons.groups_outlined,
                            iconColor: const Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Instructor Assignment Card
                    const Text(
                      'PIT INSTRUCTOR',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _line),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: !isAssignable
                          ? const Text(
                              'Instructor assignment is not available for Unassigned section.',
                              style: TextStyle(
                                color: _muted,
                                fontStyle: FontStyle.italic,
                                fontSize: 13,
                              ),
                            )
                          : _buildInstructorSection(
                              activeAssignment,
                              hasInstructor,
                              instructorState,
                              facultyItems,
                            ),
                    ),
                    const SizedBox(height: 24),

                    // Student Roster Section
                    Row(
                      children: [
                        const Text(
                          'STUDENT ROSTER',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                      ),
                    ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${sectionStudents.length} total',
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildRosterTable(sectionStudents),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: _line),
            // Footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: instructorState.isSaving ? null : widget.onClose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructorSection(
    Map<String, dynamic> activeAssignment,
    bool hasInstructor,
    PitInstructorState instructorState,
    List<DropdownMenuItem<int>> facultyItems,
  ) {
    if (hasInstructor) {
      final name = activeAssignment['faculty_name']?.toString() ?? 'Faculty';
      final email = activeAssignment['faculty_email']?.toString() ?? '';
      
      if (!_isReplacing) {
        return Row(
          children: [
            CircleAvatar(
              backgroundColor: _maroon.withValues(alpha: 0.1),
              foregroundColor: _maroon,
              radius: 20,
              child: const Icon(Icons.person_rounded, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const StatusBadge.success(label: 'Active'),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: _muted),
              onSelected: (val) {
                if (val == 'replace') {
                  setState(() => _isReplacing = true);
                } else if (val == 'remove') {
                  _removeInstructor(activeAssignment['id']);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'replace',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Replace Instructor'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Remove Assignment', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      } else {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, color: _muted, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Replacing $name',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _selectedFacultyId,
              hint: const Text('Select replacement faculty'),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: facultyItems,
              onChanged: instructorState.isSaving
                  ? null
                  : (val) => setState(() => _selectedFacultyId = val),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: instructorState.isSaving
                      ? null
                      : () => setState(() {
                            _isReplacing = false;
                            _selectedFacultyId = null;
                          }),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _selectedFacultyId == null || instructorState.isSaving
                      ? null
                      : () => _replaceInstructor(
                            activeAssignment['id'],
                            _selectedFacultyId!,
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _maroon,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: instructorState.isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Assign Replacement'),
                ),
              ],
            ),
          ],
        );
      }
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: DefensysUi.warningText, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No instructor assigned to this section.',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              StatusBadge(
                label: 'Needs assignment',
                background: DefensysUi.warningBg,
                textColor: DefensysUi.warningText,
                borderColor: DefensysUi.warningBorder,
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _selectedFacultyId,
            hint: const Text('Select instructor faculty'),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: facultyItems,
            onChanged: instructorState.isSaving
                ? null
                : (val) => setState(() => _selectedFacultyId = val),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                icon: instructorState.isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Assign Instructor'),
                onPressed: _selectedFacultyId == null || instructorState.isSaving
                    ? null
                    : () => _assignInstructor(_selectedFacultyId!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _maroon,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      );
    }
  }

  Widget _buildRosterTable(List<Map<String, dynamic>> students) {
    if (students.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: const Text(
          'No students enrolled in this section.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFF3F4F6),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
            ),
            child: Row(
              children: [
                _headerCell('Name', 3.0),
                _headerCell('Student ID', 2.0),
                _headerCell('Team status', 2.5),
              ],
            ),
          ),
          // Scrollable roster rows
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: students.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
              itemBuilder: (context, index) {
                final student = students[index];
                final onTeam = student['team_status'] == 'on_team';
                final teamLabel = onTeam
                    ? (student['team_name']?.toString() ?? 'On team')
                    : 'Unassigned';

                return SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      _rowCell(
                        Text(
                          student['name']?.toString() ?? '-',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        flex: 3.0,
                      ),
                      _rowCell(
                        Text(
                          student['username']?.toString() ?? '-',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12.5),
                        ),
                        flex: 2.0,
                      ),
                      _rowCell(
                        onTeam
                            ? DefensysStatusBadge.success(
                                label: teamLabel,
                                showDot: false,
                              )
                            : const DefensysStatusBadge.inactive(
                                label: 'Unassigned',
                              ),
                        flex: 2.5,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text, double flex) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _dialogNotice(String message, {bool warning = false}) {
    final color = warning ? DefensysUi.warningText : DefensysUi.successText;
    final bg = warning ? DefensysUi.warningBg : DefensysUi.successBg;
    final border = warning ? DefensysUi.warningBorder : DefensysUi.successBorder;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Future<void> _assignInstructor(int facultyId) async {
    final ok = await ref
        .read(pitInstructorProvider.notifier)
        .assignInstructor(facultyId: facultyId, section: widget.sectionName);
    if (ok && mounted) {
      setState(() {
        _selectedFacultyId = null;
      });
    }
  }

  Future<void> _removeInstructor(int assignmentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Removal'),
        content: const Text(
          'Are you sure you want to remove the instructor assignment for this section?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref
          .read(pitInstructorProvider.notifier)
          .setAssignmentActive(assignmentId, false);
    }
  }

  Future<void> _replaceInstructor(int currentAssignmentId, int newFacultyId) async {
    // 1. Deactivate old
    final deactivated = await ref
        .read(pitInstructorProvider.notifier)
        .setAssignmentActive(currentAssignmentId, false);
    if (!deactivated || !mounted) return;

    // 2. Assign new
    final assigned = await ref
        .read(pitInstructorProvider.notifier)
        .assignInstructor(facultyId: newFacultyId, section: widget.sectionName);
        
    if (assigned && mounted) {
      setState(() {
        _isReplacing = false;
        _selectedFacultyId = null;
      });
    }
  }
}

