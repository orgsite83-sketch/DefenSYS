import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'deliverables_status_filter.dart';

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

int _count(CapstoneDeliverablesState state, String key) {
  return _asInt(state.counts[key]);
}

BoxDecoration _cardDecoration(BuildContext context) {
  return BoxDecoration(
    color: DefensysTokens.surfaceOf(context),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: DefensysTokens.borderOf(context)),
  );
}

Widget _compactStatItem(BuildContext context, String label, int count, IconData icon, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: DefensysTokens.textPrimaryOf(context),
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textSecondaryOf(context),
              height: 1.1,
            ),
          ),
        ],
      ),
    ],
  );
}

Widget buildDeliverablesStats(CapstoneDeliverablesState state) {
  return Builder(builder: (context) {
  final teamLabel = state.scope == 'pit' ? 'PIT Teams' : 'Capstone Teams';
  final items = [
    _compactStatItem(context, teamLabel, _count(state, 'teams'), Icons.groups_2_outlined, DefensysTokens.maroonTextOf(context)),
    _compactStatItem(context, 'Ready', _count(state, 'ready'), Icons.verified_outlined, AppColors.success),
    _compactStatItem(context, 'Pending', _count(state, 'pending_review'), Icons.rate_review_outlined, WorkflowStatusStyle.of(context, WorkflowStatusTone.active).foreground),
    _compactStatItem(context, 'Missing', _count(state, 'missing_requirements'), Icons.warning_amber_outlined, AppColors.warning),
    _compactStatItem(context, 'Files', _count(state, 'submitted_files'), Icons.folder_copy_outlined, Colors.blue),
    _compactStatItem(context, 'Archive Files', _count(state, 'archive_files'), Icons.inventory_2_outlined, AppColors.gold),
  ];

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: _cardDecoration(context),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            children: items,
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final isLast = index == items.length - 1;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                items[index],
                if (!isLast) ...[
                  const SizedBox(width: 12),
                  Container(
                    height: 24,
                    width: 1,
                    color: const Color(0xFFE2E8F0),
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            );
          }),
        );
      },
    ),
  );
  });
}

class DeliverablesFilterBar extends ConsumerStatefulWidget {
  final CapstoneDeliverablesState state;
  final TextEditingController searchController;
  final bool isAdviser;
  final DeliverablesViewMode viewMode;
  final ValueChanged<DeliverablesViewMode>? onViewModeChanged;
  final TeamTriageFilter activeTriageFilter;
  final ValueChanged<TeamTriageFilter>? onTriageFilterChanged;
  final Map<TeamTriageFilter, int>? triageCounts;
  final bool showViewToggle;

  const DeliverablesFilterBar({
    super.key,
    required this.state,
    required this.searchController,
    required this.isAdviser,
    this.viewMode = DeliverablesViewMode.dossier,
    this.onViewModeChanged,
    this.activeTriageFilter = TeamTriageFilter.all,
    this.onTriageFilterChanged,
    this.triageCounts,
    this.showViewToggle = false,
  });

  @override
  ConsumerState<DeliverablesFilterBar> createState() =>
      _DeliverablesFilterBarState();
}

class _DeliverablesFilterBarState extends ConsumerState<DeliverablesFilterBar> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  InputDecoration _toolbarInputDec({
    required String label,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
      filled: true,
      fillColor: DefensysTokens.surfaceHigherOf(context),
      labelStyle: TextStyle(
        color: DefensysTokens.textSecondaryOf(context),
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: DefensysTokens.maroonOf(context),
          width: 1.5,
        ),
      ),
    );
  }

  List<String> _uniqueStrings(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final List<String> stageOptions = _uniqueStrings(widget.state.stageOptions);
    final selectedStage = stageOptions.contains(widget.state.selectedStage)
        ? widget.state.selectedStage
        : null;
    final searchField = TextField(
      controller: widget.searchController,
      decoration: _toolbarInputDec(
        label: widget.isAdviser
            ? 'Search team, project'
            : (widget.state.scope == 'pit'
                  ? 'Search team, project, instructor'
                  : 'Search team, project, adviser'),
        prefixIcon: Icons.search,
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (value) {
        if (_debounceTimer?.isActive ?? false) {
          _debounceTimer!.cancel();
        }
        _debounceTimer = Timer(const Duration(milliseconds: 500), () {
          ref
              .read(capstoneDeliverablesProvider.notifier)
              .fetchDeliverables(search: value);
        });
      },
      onSubmitted: (value) {
        if (_debounceTimer?.isActive ?? false) {
          _debounceTimer!.cancel();
        }
        ref
            .read(capstoneDeliverablesProvider.notifier)
            .fetchDeliverables(search: value);
      },
    );

    final stageDropdown = DropdownButtonFormField<String>(
      initialValue: selectedStage,
      isExpanded: true,
      decoration: _toolbarInputDec(
        label: widget.state.scope == 'pit' ? 'PIT Event' : 'Stage View',
      ),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 13,
        color: DefensysTokens.textPrimaryOf(context),
      ),
      hint: Text(
        stageOptions.isEmpty
            ? (widget.state.scope == 'pit'
                  ? 'No events configured'
                  : 'No stages configured')
            : 'Select stage',
        style: const TextStyle(fontSize: 13),
      ),
      items: stageOptions
          .map(
            (stage) => DropdownMenuItem(
              value: stage,
              child: Text(
                stage,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          )
          .toList(),
      onChanged: stageOptions.isEmpty
          ? null
          : (value) => ref
                .read(capstoneDeliverablesProvider.notifier)
                .fetchDeliverables(selectedStage: value ?? selectedStage ?? ''),
    );

    final statusFilter = DeliverablesStatusFilter(
      value: widget.activeTriageFilter,
      counts: widget.triageCounts ?? DeliverablesTriageHelper.computeCounts(widget.state.teams),
      isPit: widget.state.scope == 'pit',
      onChanged: widget.onTriageFilterChanged,
    );

    final clearButton = OutlinedButton.icon(
      onPressed: () {
        widget.searchController.clear();
        if (_debounceTimer?.isActive ?? false) {
          _debounceTimer!.cancel();
        }
        widget.onTriageFilterChanged?.call(TeamTriageFilter.all);
        ref
            .read(capstoneDeliverablesProvider.notifier)
            .fetchDeliverables(search: '', status: '');
      },
      icon: const Icon(Icons.clear_all_rounded, size: 16),
      label: const Text(
        'Clear Filters',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: DefensysTokens.textSecondaryOf(context),
        side: BorderSide(color: DefensysTokens.borderOf(context)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    final filterFields = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 12),
              stageDropdown,
              const SizedBox(height: 12),
              statusFilter,
              const SizedBox(height: 12),
              clearButton,
            ],
          );
        } else if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: stageDropdown),
                  const SizedBox(width: 16),
                  Expanded(child: statusFilter),
                  const SizedBox(width: 16),
                  clearButton,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 16),
            SizedBox(width: 220, child: stageDropdown),
            const SizedBox(width: 16),
            SizedBox(width: 240, child: statusFilter),
            const SizedBox(width: 16),
            clearButton,
          ],
        );
      },
    );

    return Container(
      decoration: _cardDecoration(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterFields,
          if (widget.showViewToggle) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: _buildViewToggle()),
          ],
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      padding: const EdgeInsets.all(2.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewToggleButton(
            mode: DeliverablesViewMode.matrix,
            icon: Icons.table_chart_rounded,
            label: 'Cohort Matrix',
          ),
          _viewToggleButton(
            mode: DeliverablesViewMode.dossier,
            icon: Icons.view_agenda_rounded,
            label: 'Team Dossier',
          ),
        ],
      ),
    );
  }

  Widget _viewToggleButton({
    required DeliverablesViewMode mode,
    required IconData icon,
    required String label,
  }) {
    final isActive = widget.viewMode == mode;
    return InkWell(
      onTap: () => widget.onViewModeChanged?.call(mode),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? DefensysTokens.surfaceOf(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? DefensysTokens.maroonTextOf(context) : DefensysTokens.textSecondaryOf(context),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive ? DefensysTokens.maroonTextOf(context) : DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
