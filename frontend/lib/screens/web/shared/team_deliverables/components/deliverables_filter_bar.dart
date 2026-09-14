import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';

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

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFFE2E8F0)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.02),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

Widget _compactStatItem(String label, int count, IconData icon, Color color) {
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              height: 1.1,
            ),
          ),
        ],
      ),
    ],
  );
}

Widget buildDeliverablesStats(CapstoneDeliverablesState state) {
  final teamLabel = state.scope == 'pit' ? 'PIT Teams' : 'Capstone Teams';
  final items = [
    _compactStatItem(teamLabel, _count(state, 'teams'), Icons.groups_2_outlined, AppColors.maroon),
    _compactStatItem('Ready', _count(state, 'ready'), Icons.verified_outlined, AppColors.success),
    _compactStatItem('Pending', _count(state, 'pending_review'), Icons.rate_review_outlined, Colors.orange),
    _compactStatItem('Missing', _count(state, 'missing_requirements'), Icons.warning_amber_outlined, AppColors.warning),
    _compactStatItem('Files', _count(state, 'submitted_files'), Icons.folder_copy_outlined, Colors.blue),
    _compactStatItem('Archive Files', _count(state, 'archive_files'), Icons.inventory_2_outlined, AppColors.gold),
  ];

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: _cardDecoration(),
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
  ConsumerState<DeliverablesFilterBar> createState() => _DeliverablesFilterBarState();
}

class _DeliverablesFilterBarState extends ConsumerState<DeliverablesFilterBar> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  InputDecoration _toolbarInputDec({required String label, IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      labelStyle: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
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
    final List<Map<String, dynamic>> statuses = widget.state.statuses.isEmpty
        ? const <Map<String, dynamic>>[
            {'value': '', 'label': 'All Teams'},
            {'value': 'awaiting_endorsement', 'label': 'Awaiting Endorsement'},
            {'value': 'ready', 'label': 'Endorsed'},
            {'value': 'scheduled', 'label': 'Defense Scheduled'},
            {'value': 'pending_post_defense', 'label': 'Pending Post-Defense'},
            {'value': 'passed', 'label': 'Completed / Passed'},
            {'value': 'missing', 'label': 'Missing Requirements'},
          ]
        : widget.state.statuses;

    final searchField = TextField(
      controller: widget.searchController,
      decoration: _toolbarInputDec(
        label: widget.isAdviser ? 'Search team, project' : 'Search team, project, adviser',
        prefixIcon: Icons.search,
      ),
      style: const TextStyle(
        fontSize: 13,
      ),
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
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
      hint: Text(
        stageOptions.isEmpty
            ? (widget.state.scope == 'pit' ? 'No events configured' : 'No stages configured')
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
                style: const TextStyle(
                  fontSize: 13,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: stageOptions.isEmpty
          ? null
          : (value) => ref
                .read(capstoneDeliverablesProvider.notifier)
                .fetchDeliverables(
                  selectedStage: value ?? selectedStage ?? '',
                ),
    );

    final statusDropdown = DropdownButtonFormField<String>(
      initialValue: widget.state.status,
      decoration: _toolbarInputDec(label: 'Status'),
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
      isExpanded: true,
      items: statuses
          .map(
            (item) => DropdownMenuItem(
              value: item['value']?.toString() ?? '',
              child: Text(
                item['label']?.toString() ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (value) => ref
          .read(capstoneDeliverablesProvider.notifier)
          .fetchDeliverables(status: value ?? ''),
    );

    final clearButton = OutlinedButton.icon(
      onPressed: () {
        widget.searchController.clear();
        if (_debounceTimer?.isActive ?? false) {
          _debounceTimer!.cancel();
        }
        ref
            .read(capstoneDeliverablesProvider.notifier)
            .fetchDeliverables(search: '', status: '');
      },
      icon: const Icon(Icons.clear_all_rounded, size: 18),
      label: const Text(
        'Clear Filters',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF64748B),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
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
              statusDropdown,
              const SizedBox(height: 12),
              clearButton,
            ],
          );
        } else if (constraints.maxWidth < 900) {
          final calculatedWidth = (constraints.maxWidth - 48) / 2;
          final dropdownWidth = calculatedWidth.clamp(0.0, double.infinity);
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: double.infinity, child: searchField),
              SizedBox(width: dropdownWidth, child: stageDropdown),
              SizedBox(width: dropdownWidth, child: statusDropdown),
              SizedBox(width: double.infinity, child: clearButton),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 16),
            SizedBox(width: 220, child: stageDropdown),
            const SizedBox(width: 16),
            SizedBox(width: 220, child: statusDropdown),
            const SizedBox(width: 16),
            clearButton,
          ],
        );
      },
    );

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterFields,
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),
          _buildTriageAndToggleRow(),
        ],
      ),
    );
  }

  Widget _buildTriageChip({
    required TeamTriageFilter filter,
    required String label,
    Color? dotColor,
    IconData? icon,
  }) {
    final isSelected = widget.activeTriageFilter == filter;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onTriageFilterChanged?.call(filter);
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.maroon.withValues(alpha: 0.08)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.maroon : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: isSelected ? AppColors.maroon : const Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? AppColors.maroon : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
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
          color: isActive ? Colors.white : Colors.transparent,
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
              color: isActive ? AppColors.maroon : const Color(0xFF64748B),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive ? AppColors.maroon : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTriageAndToggleRow() {
    final counts = widget.triageCounts ??
        DeliverablesTriageHelper.computeCounts(widget.state.teams);
    final allCount = counts[TeamTriageFilter.all] ?? widget.state.teams.length;
    final needsReviewCount = counts[TeamTriageFilter.needsReview] ?? 0;
    final readyCount = counts[TeamTriageFilter.readyForDefense] ?? 0;
    final overdueCount = counts[TeamTriageFilter.overdue] ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 750;
        final chips = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildTriageChip(
              filter: TeamTriageFilter.all,
              label: 'All ($allCount)',
            ),
            _buildTriageChip(
              filter: TeamTriageFilter.needsReview,
              label: 'Needs Review ($needsReviewCount)',
              dotColor: const Color(0xFFEF4444),
            ),
            _buildTriageChip(
              filter: TeamTriageFilter.readyForDefense,
              label: 'Ready for Defense ($readyCount)',
              dotColor: const Color(0xFF10B981),
            ),
            _buildTriageChip(
              filter: TeamTriageFilter.overdue,
              label: 'Missing / Overdue ($overdueCount)',
              dotColor: const Color(0xFFF59E0B),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chips,
              if (widget.showViewToggle) ...[
                const SizedBox(height: 12),
                _buildViewToggle(),
              ],
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: chips),
            if (widget.showViewToggle) ...[
              const SizedBox(width: 12),
              _buildViewToggle(),
            ],
          ],
        );
      },
    );
  }
}
