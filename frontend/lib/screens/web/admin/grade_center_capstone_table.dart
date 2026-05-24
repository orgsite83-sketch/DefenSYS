import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/grade_center_provider.dart';
import 'grade_center_shared.dart';
import 'widgets/defensys_admin_shell.dart';

/// Option B: one card with term settings, filters, and capstone stages table.
class CapstoneStagesUnifiedCard extends ConsumerWidget {
  const CapstoneStagesUnifiedCard({
    super.key,
    required this.state,
    required this.stages,
    required this.stagesLoading,
    required this.isAdmin,
    required this.searchController,
    required this.scopeFilter,
    required this.yearLevelFilter,
    required this.statusFilter,
    required this.onOpenStage,
    required this.onOfficiallyCompleteChanged,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSearchFocusChanged,
  });

  final GradeCenterState state;
  final List<Map<String, dynamic>> stages;
  final bool stagesLoading;
  final bool isAdmin;
  final TextEditingController searchController;
  final Widget scopeFilter;
  final Widget yearLevelFilter;
  final Widget statusFilter;
  final void Function(CapstoneStageRow row) onOpenStage;
  final void Function(CapstoneStageRow row, bool value)
  onOfficiallyCompleteChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final ValueChanged<bool> onSearchFocusChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = buildCapstoneStageRows(state: state, defenseStages: stages);
    final sem = state.activeSemester;
    final termLabel = sem?['display_name']?.toString().trim() ?? '';

    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.rocket_launch_rounded,
                  color: DefensysUi.primaryMaroon,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Capstone stages',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: DefensysUi.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Manage grading by defense stage for the active term.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: DefensysUi.steelGrey,
                          height: 1.35,
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(height: 8),
                        capstoneTermStatusBadgeRow(
                          state,
                          showPeerEvaluation: true,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Change term-wide peer and adviser settings in Academic Periods.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF98A2B3),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (termLabel.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _headerPill(termLabel),
                ],
                const SizedBox(width: 8),
                _headerPill(
                  rows.isEmpty
                      ? '0 stages'
                      : '1–${rows.length} of ${rows.length} stages',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: _filterToolbar(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Text(
              'Open a stage to view teams, edit scores, and mark officially complete.',
              style: TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          if (unscheduledCapstoneTeamCount(state) > 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: gradeCenterUnscheduledBanner(
                teamCount: unscheduledCapstoneTeamCount(state),
              ),
            ),
          ],
          _tableBody(rows),
        ],
      ),
    );
  }

  Widget _headerPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5D6678),
        ),
      ),
    );
  }

  Widget _filterToolbar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isAdmin) ...[
          Expanded(
            flex: 2,
            child: gradeCenterFilterField(
              label: 'Scope',
              icon: Icons.layers_outlined,
              dropdown: gradeCenterFilterDropdownShell(child: scopeFilter),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 2,
          child: gradeCenterFilterField(
            label: 'Year level',
            icon: Icons.school_outlined,
            dropdown: gradeCenterFilterDropdownShell(child: yearLevelFilter),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: gradeCenterFilterField(
            label: 'Status',
            icon: Icons.flag_outlined,
            dropdown: gradeCenterFilterDropdownShell(child: statusFilter),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: gradeCenterFilterField(
            label: 'Search',
            icon: Icons.search_rounded,
            dropdown: SizedBox(
              height: 40,
              child: TextField(
                controller: searchController,
                enabled: !state.isSaving,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search teams...',
                  hintStyle: const TextStyle(
                    color: DefensysUi.steelGrey,
                    fontSize: 12.5,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(
                      color: DefensysUi.primaryMaroon,
                    ),
                  ),
                ),
                onChanged: onSearchChanged,
                onSubmitted: onSearchSubmitted,
                onTap: () => onSearchFocusChanged(true),
                onEditingComplete: () => onSearchFocusChanged(false),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const double _tableMinWidth = 1100;
  Widget _tableColumn(List<CapstoneStageRow> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: _tableHeaderRow(),
        ),
        ...rows.map(_tableDataRow),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _tableBody(List<CapstoneStageRow> rows) {
    if (state.isLoading || (stagesLoading && stages.isEmpty)) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(color: DefensysUi.primaryMaroon),
        ),
      );
    }

    if (stages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No defense stages configured. Add stages under Defense Stages.',
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No active stages to display. Activate stages under Defense Stages.',
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < _tableMinWidth
            ? _tableMinWidth
            : constraints.maxWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: tableWidth, child: _tableColumn(rows)),
        );
      },
    );
  }

  Widget _tableHeaderRow() {
    const style = TextStyle(
      color: Color(0xFF98A2B3),
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    );
    return const Row(
      children: [
        SizedBox(width: 40, child: Text('', style: style)),
        Expanded(flex: 4, child: Text('STAGE', style: style)),
        Expanded(flex: 2, child: Text('STATUS', style: style)),
        Expanded(flex: 2, child: Text('TEAMS', style: style)),
        Expanded(flex: 3, child: Text('OFFICIALLY COMPLETE', style: style)),
        Expanded(flex: 3, child: Text('TERM SETTINGS', style: style)),
        SizedBox(width: 130, child: Text('ACTIONS', style: style)),
      ],
    );
  }

  Widget _tableDataRow(CapstoneStageRow row) {
    final order = row.displayOrder > 0 ? row.displayOrder : 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 40, child: capstoneStageOrderBadge(order)),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: const TextStyle(
                    color: DefensysUi.textDark,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (row.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    row.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: capstoneStageWorkflowPill(row.workflowStatus),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                const Icon(
                  Icons.groups_outlined,
                  size: 16,
                  color: Color(0xFF98A2B3),
                ),
                const SizedBox(width: 4),
                Text(
                  '${row.teamCount} team${row.teamCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF5D6678),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: officialCompleteToggleRow(
              value: row.isOfficiallyComplete,
              enabled: !state.isSaving,
              onChanged: (value) => onOfficiallyCompleteChanged(row, value),
            ),
          ),
          Expanded(flex: 3, child: capstoneTermSettingsChips(state)),
          SizedBox(
            width: 130,
            child: OutlinedButton.icon(
              onPressed: () => onOpenStage(row),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('View Details'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DefensysUi.primaryMaroon,
                side: BorderSide(
                  color: DefensysUi.primaryMaroon.withValues(alpha: 0.35),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// PIT / All scopes: unified card shell with filters and grouped event cards.
class GradeCenterGroupedUnifiedCard extends StatelessWidget {
  const GradeCenterGroupedUnifiedCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.isAdmin,
    required this.searchController,
    required this.scopeFilter,
    required this.yearLevelFilter,
    required this.statusFilter,
    required this.listContent,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSearchFocusChanged,
  });

  final String title;
  final String subtitle;
  final GradeCenterState state;
  final bool isAdmin;
  final TextEditingController searchController;
  final Widget scopeFilter;
  final Widget yearLevelFilter;
  final Widget statusFilter;
  final Widget listContent;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final ValueChanged<bool> onSearchFocusChanged;

  @override
  Widget build(BuildContext context) {
    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: DefensysUi.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: DefensysUi.steelGrey,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isAdmin) ...[
                  Expanded(
                    flex: 2,
                    child: gradeCenterFilterField(
                      label: 'Scope',
                      icon: Icons.layers_outlined,
                      dropdown: gradeCenterFilterDropdownShell(
                        child: scopeFilter,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: gradeCenterFilterField(
                    label: 'Year level',
                    icon: Icons.school_outlined,
                    dropdown: gradeCenterFilterDropdownShell(
                      child: yearLevelFilter,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: gradeCenterFilterField(
                    label: 'Status',
                    icon: Icons.flag_outlined,
                    dropdown: gradeCenterFilterDropdownShell(
                      child: statusFilter,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: gradeCenterFilterField(
                    label: 'Search',
                    icon: Icons.search_rounded,
                    dropdown: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: searchController,
                        enabled: !state.isSaving,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search teams...',
                          hintStyle: const TextStyle(
                            color: DefensysUi.steelGrey,
                            fontSize: 12.5,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: DefensysUi.primaryMaroon,
                            ),
                          ),
                        ),
                        onChanged: onSearchChanged,
                        onSubmitted: onSearchSubmitted,
                        onTap: () => onSearchFocusChanged(true),
                        onEditingComplete: () => onSearchFocusChanged(false),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Text(
              'Open a stage to view teams, edit scores, and mark officially complete.',
              style: TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: listContent,
          ),
        ],
      ),
    );
  }
}
