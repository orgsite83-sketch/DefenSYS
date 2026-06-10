import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:excel/excel.dart' as xl;
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
  static const _line = Color(0xFFF3F4F6);
  static const _maroon = DefensysUi.primaryMaroon;

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
          const SizedBox(height: 20),
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
          _cohortScopeToggle(state),
          const SizedBox(height: 14),
          _viewModeToggle(),
          const SizedBox(height: 14),
          _viewMode == _CohortViewMode.sections
              ? _sectionFiltersRow(state, instructorState)
              : _filtersRow(state),
          const SizedBox(height: 16),
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
          OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('CSV Template'),
            onPressed: busy ? null : () => _downloadOfficialTemplate(pitYear),
          ),
        if (!auditMode)
          OutlinedButton.icon(
            icon: importState.isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('Import Official Class List'),
            onPressed: busy ? null : _pickOfficialClassList,
          ),
        OutlinedButton.icon(
          icon: state.isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.rotate_right_outlined, size: 18),
          label: const Text('Rollover Preview'),
          onPressed: busy ? null : _openRolloverPreview,
        ),
        if (!auditMode && widget.onCreateTeam != null)
          FilledButton.icon(
            onPressed: busy ? null : widget.onCreateTeam,
            style: FilledButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.groups_outlined, size: 18),
            label: const Text('Manage PIT teams'),
          ),
      ],
    );
  }

  Widget _cohortScopeToggle(PitLeadCohortState state) {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('Current term'),
          selected: _cohortScope == 'active',
          onSelected: state.isLoading
              ? null
              : (_) {
                  setState(() => _cohortScope = 'active');
                  _applyFilters();
                },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('History'),
          selected: _cohortScope == 'history',
          onSelected: state.isLoading
              ? null
              : (_) {
                  setState(() => _cohortScope = 'history');
                  _applyFilters();
                },
        ),
      ],
    );
  }

  Widget _viewModeToggle() {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('Sections'),
          selected: _viewMode == _CohortViewMode.sections,
          onSelected: (_) {
            setState(() => _viewMode = _CohortViewMode.sections);
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Students'),
          selected: _viewMode == _CohortViewMode.students,
          onSelected: (_) {
            setState(() => _viewMode = _CohortViewMode.students);
          },
        ),
      ],
    );
  }

  Widget _sectionFiltersRow(
    PitLeadCohortState state,
    PitInstructorState instructorState,
  ) {
    final summaries = _sectionSummaries(state.students, instructorState);
    final assignedCount = summaries.where((item) => item.hasInstructor).length;
    final needsCount = summaries.length - assignedCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: DefensysUi.cardDecoration(),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search section or instructor',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          _sectionFilterChip('All', 'all', summaries.length),
          _sectionFilterChip('Assigned', 'assigned', assignedCount),
          _sectionFilterChip(
            'Needs assignment',
            'needs_assignment',
            needsCount,
          ),
        ],
      ),
    );
  }

  Widget _sectionFilterChip(String label, String value, int count) {
    final selected = _sectionStatusFilter == value;
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => setState(() => _sectionStatusFilter = value),
      selectedColor: const Color(0xFFFEE2E2),
      checkmarkColor: _maroon,
    );
  }

  Widget _filtersRow(PitLeadCohortState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: DefensysUi.cardDecoration(),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search name, ID, or email',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onSubmitted: (_) => _applyFilters(),
            ),
          ),
          _filterChip('All', 'all', state),
          _filterChip('Unassigned', 'unassigned', state),
          _filterChip('On team', 'on_team', state),
          FilledButton(
            onPressed: state.isLoading ? null : _applyFilters,
            style: FilledButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: Colors.white,
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
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, PitLeadCohortState state) {
    final selected = _teamStatusFilter == value;
    final countKey = value == 'all' ? 'all' : value;
    final count = state.counts[countKey]?.toString() ?? '0';

    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: state.isLoading
          ? null
          : (_) {
              setState(() => _teamStatusFilter = value);
              ref
                  .read(pitLeadCohortProvider.notifier)
                  .fetchCohort(
                    search: _searchController.text,
                    teamStatusFilter: value,
                    scope: _cohortScope,
                  );
            },
      selectedColor: const Color(0xFFFEE2E2),
      checkmarkColor: _maroon,
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
        padding: const EdgeInsets.all(32),
        decoration: DefensysUi.cardDecoration(),
        child: Text(
          emptyText,
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
        ),
      );
    }

    return Container(
      decoration: DefensysUi.cardDecoration(),
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Name',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Student ID',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Email',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Section',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Team status',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.students.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
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

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        student['name']?.toString() ?? '-',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        student['username']?.toString() ?? '-',
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        student['email']?.toString() ?? '-',
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        student['section']?.toString().trim().isNotEmpty == true
                            ? student['section'].toString()
                            : '-',
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        teamLabel,
                        style: TextStyle(
                          color: onTeam
                              ? const Color(0xFF047857)
                              : const Color(0xFF92400E),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
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
        padding: const EdgeInsets.all(32),
        decoration: DefensysUi.cardDecoration(),
        child: Text(
          state.students.isEmpty
              ? 'No section roster for $pitYear yet. Import an official class list to create section records.'
              : 'No sections match the current filters.',
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
        ),
      );
    }

    return Container(
      decoration: DefensysUi.cardDecoration(),
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Section',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Instructor',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Students',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Team status',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    'Action',
                    style: TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: summaries.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
            itemBuilder: (context, index) {
              final summary = summaries[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        summary.section,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: summary.hasInstructor
                          ? Text(
                              summary.instructorName!,
                              style: const TextStyle(
                                color: Color(0xFF374151),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : _statusPill(
                              'Needs assignment',
                              const Color(0xFFFFFBEB),
                              const Color(0xFF92400E),
                            ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${summary.studentCount}',
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        summary.teamLabel,
                        style: TextStyle(
                          color: summary.teamCount > 0
                              ? const Color(0xFF047857)
                              : const Color(0xFF92400E),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 72,
                      child: Tooltip(
                        message: 'Assign PIT instructor',
                        child: IconButton(
                          icon: const Icon(Icons.shield_outlined, size: 20),
                          color: _maroon,
                          onPressed: summary.isAssignable
                              ? () => _openInstructorAssignment(summary.section)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, Color bg, Color fg) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
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

  void _openInstructorAssignment(String section) {
    context.go(
      '${FacultyRoutes.pitInstructors}?section=${Uri.encodeComponent(section)}',
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

  Future<void> _pickOfficialClassList() async {
    final notifier = ref.read(userManagementProvider.notifier);
    final file = await pickTabularDataFile();
    if (!mounted || file == null) return;
    final parsed = file.isXlsx
        ? _parseOfficialClassListXlsx(file.bytes)
        : _parseOfficialClassListCsv(file.text ?? '');
    if (parsed.students.isEmpty) {
      notifier.showError(
        'No valid student rows found in the selected class list.',
      );
      return;
    }
    final responsePayload = await notifier.pitLeadOfficialClassListImport(
      metadata: parsed.metadata,
      students: parsed.students,
    );
    if (!mounted || responsePayload == null) return;

    final warnings = responsePayload['warnings'] as List? ?? const [];
    final errors = responsePayload['errors'] as List? ?? const [];
    if (warnings.isNotEmpty || errors.isNotEmpty) {
      _showImportSummaryDialog(warnings, errors);
    }

    ref.read(pitInstructorProvider.notifier).fetchAssignments();
    _applyFilters();
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

  _OfficialClassListParseResult _parseOfficialClassListCsv(String csv) {
    final rows = csv
        .split(RegExp(r'\r?\n'))
        .map(_splitCsvLine)
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    return _parseOfficialClassListRows(rows);
  }

  _OfficialClassListParseResult _parseOfficialClassListXlsx(List<int> bytes) {
    final workbook = xl.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      return const _OfficialClassListParseResult(metadata: {}, students: []);
    }
    final sheet = workbook.tables.values.first;
    final rows = sheet.rows
        .map((row) => row.map((cell) => _excelCellText(cell?.value)).toList())
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    return _parseOfficialClassListRows(rows);
  }

  _OfficialClassListParseResult _parseOfficialClassListRows(
    List<List<String>> rows,
  ) {
    final metadata = <String, dynamic>{};
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
    final programIndex = findHeader((value) => value == 'program');
    final levelIndex = findHeader((value) => value == 'level');
    final emailIndex = findHeader((value) => value == 'email');
    final sectionColumnIndex = findHeader((value) => value == 'section' || value == 'class section');
    final students = <Map<String, dynamic>>[];

    for (final row in rows.skip(headerIndex + 1)) {
      String read(int index) =>
          index >= 0 && index < row.length ? row[index].trim() : '';
      final id = read(idIndex);
      final name = read(nameIndex);
      if (id.isEmpty || name.isEmpty) continue;
      students.add({
        'id_number': id,
        'full_name': name,
        if (programIndex != -1) 'program': read(programIndex),
        if (levelIndex != -1)
          'year_level': _normalizeYearLevel(read(levelIndex)),
        if (emailIndex != -1) 'email': read(emailIndex),
        if (sectionColumnIndex != -1) 'section': read(sectionColumnIndex),
      });
    }

    return _OfficialClassListParseResult(
      metadata: metadata,
      students: students,
    );
  }

  String _excelCellText(xl.CellValue? value) {
    if (value == null) return '';
    if (value is xl.TextCellValue) return value.value.toString().trim();
    if (value is xl.IntCellValue) return value.value.toString();
    if (value is xl.DoubleCellValue) {
      final number = value.value;
      if (number == number.roundToDouble()) {
        return number.round().toString();
      }
      return number.toString();
    }
    return value.toString().trim();
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
    final lower = value.toLowerCase();
    if (lower.contains('1')) return '1st Year';
    if (lower.contains('2')) return '2nd Year';
    if (lower.contains('3')) return '3rd Year';
    if (lower.contains('4')) return '4th Year';
    return value.trim();
  }

  String _slug(String value) => value
      .toLowerCase()
      .replaceAll(' ', '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '');

  Widget _notice(String message, {bool warning = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warning ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFF374151), fontSize: 13),
      ),
    );
  }

  List<String> _formatBulkImportErrorLines(dynamic messages) {
    if (messages is List) {
      return messages.map((item) => item.toString()).toList();
    }
    if (messages is Map) {
      final lines = <String>[];
      for (final entry in messages.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          for (final item in value) {
            lines.add('$key: $item');
          }
        } else {
          lines.add('$key: $value');
        }
      }
      return lines;
    }
    return [messages?.toString() ?? 'Unknown error'];
  }

  Future<void> _showImportSummaryDialog(List<dynamic> warnings, List<dynamic> errors) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Class List Import Details'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errors.isNotEmpty) ...[
                  const Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Errors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...errors.map((error) {
                    final row = error['row'];
                    final id = error['id_number'] ?? '';
                    final issueLines = _formatBulkImportErrorLines(error['errors']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Row $row ${id.isNotEmpty ? "· Student ID: $id" : ""}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ...issueLines.map((line) => Text('• $line', style: const TextStyle(fontSize: 12.5))),
                        ],
                      ),
                    );
                  }),
                  if (warnings.isNotEmpty) const Divider(),
                ],
                if (warnings.isNotEmpty) ...[
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Text('Warnings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amber)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...warnings.map((warning) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $warning', style: const TextStyle(fontSize: 13)),
                  )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _OfficialClassListParseResult {
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> students;

  const _OfficialClassListParseResult({
    required this.metadata,
    required this.students,
  });
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
