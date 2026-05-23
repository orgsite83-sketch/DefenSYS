import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/pit_lead_cohort_provider.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class PitLeadCohortScreen extends ConsumerStatefulWidget {
  final VoidCallback? onCreateTeam;

  const PitLeadCohortScreen({super.key, this.onCreateTeam});

  @override
  ConsumerState<PitLeadCohortScreen> createState() => _PitLeadCohortScreenState();
}

class _PitLeadCohortScreenState extends ConsumerState<PitLeadCohortScreen> {
  final _searchController = TextEditingController();
  String _teamStatusFilter = 'all';
  String _cohortScope = 'active';

  static const _ink = DefensysUi.textDark;
  static const _line = Color(0xFFF3F4F6);
  static const _maroon = DefensysUi.primaryMaroon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pitLeadCohortProvider.notifier).fetchCohort();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    ref.read(pitLeadCohortProvider.notifier).fetchCohort(
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
            actions: widget.onCreateTeam == null || _isAuditMode
                ? null
                : FilledButton.icon(
                    onPressed: widget.onCreateTeam,
                    style: FilledButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.groups_outlined, size: 18),
                    label: const Text('Manage PIT teams'),
                  ),
          ),
          const SizedBox(height: 20),
          if (state.operatingMessage != null &&
              state.operatingMessage!.trim().isNotEmpty) ...[
            _notice(state.operatingMessage!, warning: _isAuditMode),
            const SizedBox(height: 14),
          ],
          _cohortScopeToggle(state),
          const SizedBox(height: 14),
          _filtersRow(state),
          const SizedBox(height: 16),
          if (state.error != null) ...[
            _notice(state.error!, warning: true),
            const SizedBox(height: 14),
          ],
          _rosterTable(state),
        ],
      ),
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
              ref.read(pitLeadCohortProvider.notifier).fetchCohort(
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
}
