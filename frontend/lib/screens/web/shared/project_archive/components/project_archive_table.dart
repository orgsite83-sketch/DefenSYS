import 'package:defensys/theme/program_colors.dart';
import 'package:defensys/widgets/program_badge.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/widgets/status_badge.dart';
import 'package:defensys/widgets/table/table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/screens/web/shared/project_archive/dialogs/archive_file_details_dialog.dart';
import 'package:defensys/widgets/shadcn/defensys_breadcrumb.dart';

typedef AuditLogTable = ProjectArchiveTable;

class ProjectArchiveTable extends ConsumerStatefulWidget {
  final ProjectArchiveState state;
  final TextEditingController searchController;
  final ScrollController tableHScrollController;
  final bool showTableScrollHint;
  final bool showAdvancedFilters;
  final VoidCallback onToggleAdvancedFilters;
  final Function(String fileUrl, String fileName) onViewPdf;
  final Function(String fileUrl, String fileName) onDownloadFile;
  final Function(Map<String, dynamic> entry) onOverrideStatus;

  const ProjectArchiveTable({
    super.key,
    required this.state,
    required this.searchController,
    required this.tableHScrollController,
    required this.showTableScrollHint,
    required this.showAdvancedFilters,
    required this.onToggleAdvancedFilters,
    required this.onViewPdf,
    required this.onDownloadFile,
    required this.onOverrideStatus,
  });

  @override
  ConsumerState<ProjectArchiveTable> createState() =>
      _ProjectArchiveTableState();
}

class _ProjectArchiveTableState extends ConsumerState<ProjectArchiveTable> {
  static const _kRepoMinTableWidth = 1100.0;
  static const _kDeliverableMinTableWidth = 1000.0;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  bool _folderListView = false;
  String _sortOrder = 'a_z';

  List<Map<String, dynamic>> _applySortingToEntries(
    List<Map<String, dynamic>> entries,
  ) {
    final list = List<Map<String, dynamic>>.from(entries);
    if (_sortOrder == 'a_z') {
      list.sort((a, b) {
        final titleA = (a['deliverable_label'] ??
                a['file_name'] ??
                a['team_name'] ??
                '')
            .toString()
            .toLowerCase();
        final titleB = (b['deliverable_label'] ??
                b['file_name'] ??
                b['team_name'] ??
                '')
            .toString()
            .toLowerCase();
        return titleA.compareTo(titleB);
      });
    } else if (_sortOrder == 'z_a') {
      list.sort((a, b) {
        final titleA = (a['deliverable_label'] ??
                a['file_name'] ??
                a['team_name'] ??
                '')
            .toString()
            .toLowerCase();
        final titleB = (b['deliverable_label'] ??
                b['file_name'] ??
                b['team_name'] ??
                '')
            .toString()
            .toLowerCase();
        return titleB.compareTo(titleA);
      });
    } else if (_sortOrder == 'newest') {
      list.sort((a, b) {
        final dateA = a['uploaded_at']?.toString() ?? '';
        final dateB = b['uploaded_at']?.toString() ?? '';
        return dateB.compareTo(dateA);
      });
    } else if (_sortOrder == 'oldest') {
      list.sort((a, b) {
        final dateA = a['uploaded_at']?.toString() ?? '';
        final dateB = b['uploaded_at']?.toString() ?? '';
        return dateA.compareTo(dateB);
      });
    }
    return list;
  }

  List<Map<String, dynamic>> _applySortingToFolders(
    List<Map<String, dynamic>> folders,
  ) {
    final list = List<Map<String, dynamic>>.from(folders);
    if (_sortOrder == 'z_a') {
      list.sort((a, b) {
        final titleA = (a['title'] ?? '').toString().toLowerCase();
        final titleB = (b['title'] ?? '').toString().toLowerCase();
        return titleB.compareTo(titleA);
      });
    } else {
      list.sort((a, b) {
        final titleA = (a['title'] ?? '').toString().toLowerCase();
        final titleB = (b['title'] ?? '').toString().toLowerCase();
        return titleA.compareTo(titleB);
      });
    }
    return list;
  }

  String _scopeKey(RepositoryAuditState state) =>
      state.scope['scope']?.toString() ?? 'admin';

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return [];
    return value.map((item) => item.toString()).toList();
  }

  String _prettyDate(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) {
      return '-';
    }

    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text.split('T').first;
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistSurface : Colors.white,
        borderRadius: BorderRadius.circular(
          DefensysTableTokens.cardBorderRadius,
        ),
        border: Border.all(
          color: _isDark
              ? DefensysTokens.mistBorder
              : DefensysTableTokens.cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: _isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _isDark ? const Color(0xFFF87171) : AppColors.maroon,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Project Archive Records',
                  style: TextStyle(
                    color: _isDark
                        ? DefensysTokens.textPrimaryDark
                        : const Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                if (_scopeKey(state) == 'pit_lead')
                  _yearBadge(state.scope['pit_year_level']?.toString() ?? ''),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 920;
              final searchWidget = _searchField(state);
              final groupByWidget = SizedBox(
                width: isNarrow ? double.infinity : 205,
                child: _groupByFilter(state),
              );
              final sortWidget = SizedBox(
                width: isNarrow ? double.infinity : 155,
                child: _sortFilter(),
              );
              final filtersWidget = _advancedFiltersButton();
              final clearWidget = _clearFiltersButton();

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchWidget,
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: groupByWidget),
                        const SizedBox(width: 8),
                        Expanded(child: sortWidget),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: filtersWidget),
                        const SizedBox(width: 8),
                        Expanded(child: clearWidget),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: searchWidget),
                  const SizedBox(width: 12),
                  groupByWidget,
                  const SizedBox(width: 12),
                  sortWidget,
                  const SizedBox(width: 12),
                  filtersWidget,
                  const SizedBox(width: 12),
                  clearWidget,
                ],
              );
            },
          ),
          if (widget.showAdvancedFilters) ...[
            const SizedBox(height: 16),
            if (_scopeKey(state) == 'admin') ...[
              Row(
                children: [
                  Expanded(
                    child: _filterFromStrings(
                      value: state.academicYear,
                      label: 'All Years',
                      items: _stringList(state.options['academic_years']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(academicYear: value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _filterFromStrings(
                      value: state.semester,
                      label: 'All Semesters',
                      items: _stringList(state.options['semesters']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(semester: value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _filterFromMaps(
                      value: state.status,
                      label: 'All Statuses',
                      items: _mapList(state.options['status_options']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(status: value ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _filterFromStrings(
                      value: state.stage,
                      label: 'All Stages',
                      items: _stringList(state.options['stage_options']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(stage: value ?? ''),
                    ),
                  ),
                  if (state.type != 'pit') ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: _filterFromMaps(
                        value: state.submissionKind,
                        label: 'All Kinds',
                        items: _mapList(
                          state.options['submission_kind_options'],
                        ),
                        onChanged: (value) => ref
                            .read(repositoryAuditProvider.notifier)
                            .fetchEntries(submissionKind: value ?? ''),
                      ),
                    ),
                  ],
                  const SizedBox(width: 14),
                  Expanded(
                    flex: state.type == 'pit' ? 2 : 1,
                    child: _filterFromMaps(
                      value: state.deliverableId,
                      label: 'All Deliverables',
                      items: _mapList(state.options['deliverable_options']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(
                            deliverableId: value ?? '',
                            clearDeliverable: (value ?? '').isEmpty,
                            clearTeam: (value ?? '').isNotEmpty,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _filterFromStrings(
                      value: state.yearLevel,
                      label: 'All Year Levels',
                      items: _stringList(state.options['year_levels']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(yearLevel: value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Spacer(flex: 2),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _filterFromMaps(
                      value: state.teamId,
                      label: 'All Teams',
                      items: _mapList(state.options['team_counts']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(teamId: value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _filterFromStrings(
                      value: state.stage,
                      label: 'All Stages',
                      items: _stringList(state.options['stage_options']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(stage: value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _filterFromMaps(
                      value: state.status,
                      label: 'All Statuses',
                      items: _mapList(state.options['status_options']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(status: value ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _filterFromStrings(
                      value: state.academicYear,
                      label: 'All Years',
                      items: _stringList(state.options['academic_years']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(academicYear: value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _filterFromStrings(
                      value: state.semester,
                      label: 'All Semesters',
                      items: _stringList(state.options['semesters']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(semester: value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _filterFromMaps(
                      value: state.deliverableId,
                      label: 'All Deliverables',
                      items: _mapList(state.options['deliverable_options']),
                      onChanged: (value) => ref
                          .read(repositoryAuditProvider.notifier)
                          .fetchEntries(
                            deliverableId: value ?? '',
                            clearDeliverable: (value ?? '').isEmpty,
                          ),
                    ),
                  ),
                ],
              ),

            ],
          ],
          const SizedBox(height: 18),
          if (state.isLoading && state.entries.isEmpty)
            DefensysSkeleton.list(count: 6, rowHeight: 48)
          else if (state.entries.isEmpty && state.folderBrowser.isEmpty)
            _emptyRepositoryTable()
          else
            _buildEntriesBody(state),
          const SizedBox(height: 18),
          Container(
            height: 1,
            color: _isDark
                ? DefensysTokens.mistBorder
                : const Color(0xFFE5E7EB),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              state.folderBrowser.isNotEmpty
                  ? '${state.folderBrowser['file_count'] ?? 0} files · ${state.folderBrowser['missing_count'] ?? 0} missing or not uploaded'
                  : 'Showing ${state.entries.length} records',
              style: TextStyle(
                color: _isDark
                    ? DefensysTokens.textSecondaryDark
                    : const Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupByFilter(RepositoryAuditState state) {
    return _filterShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey('archiveGroupBy'),
          value: state.groupBy,
          isExpanded: true,
          dropdownColor: _isDark ? DefensysTokens.mistSurface : Colors.white,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: _isDark
                ? DefensysTokens.textSecondaryDark
                : const Color(0xFF64748B),
          ),
          style: TextStyle(
            color: _isDark
                ? DefensysTokens.textPrimaryDark
                : AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          items: const [
            DropdownMenuItem(value: 'team', child: Text('Group by Team')),
            DropdownMenuItem(
              value: 'stage',
              child: Text('Group by Stage / Event'),
            ),
            DropdownMenuItem(
              value: 'deliverable',
              child: Text('Group by Deliverable'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              ref
                  .read(repositoryAuditProvider.notifier)
                  .fetchEntries(groupBy: value);
            }
          },
        ),
      ),
    );
  }

  Widget _sortFilter() {
    return _filterShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey('archiveSortOrder'),
          value: _sortOrder,
          isExpanded: true,
          dropdownColor: _isDark ? DefensysTokens.mistSurface : Colors.white,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: _isDark
                ? DefensysTokens.textSecondaryDark
                : const Color(0xFF64748B),
          ),
          style: TextStyle(
            color: _isDark
                ? DefensysTokens.textPrimaryDark
                : AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          items: const [
            DropdownMenuItem(
              value: 'a_z',
              child: Text('Sort: A to Z', overflow: TextOverflow.ellipsis),
            ),
            DropdownMenuItem(
              value: 'z_a',
              child: Text('Sort: Z to A', overflow: TextOverflow.ellipsis),
            ),
            DropdownMenuItem(
              value: 'newest',
              child: Text('Sort: Newest', overflow: TextOverflow.ellipsis),
            ),
            DropdownMenuItem(
              value: 'oldest',
              child: Text('Sort: Oldest', overflow: TextOverflow.ellipsis),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _sortOrder = value);
            }
          },
        ),
      ),
    );
  }

  Widget _teamBadge(String teamName, Map<String, dynamic> entry) =>
      ProgramBadge(data: entry, label: '${ProgramColors.of(context, data: entry).label} · $teamName');

  Widget _advancedFiltersButton() {
    final activeColor = _isDark ? const Color(0xFFF87171) : AppColors.maroon;
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: widget.onToggleAdvancedFilters,
        icon: Icon(
          widget.showAdvancedFilters
              ? Icons.filter_alt_off_rounded
              : Icons.filter_alt_rounded,
          size: 15,
          color: widget.showAdvancedFilters
              ? activeColor
              : (_isDark
                    ? DefensysTokens.textSecondaryDark
                    : const Color(0xFF475569)),
        ),
        label: Text(widget.showAdvancedFilters ? 'Hide Filters' : 'Filters'),
        style: OutlinedButton.styleFrom(
          foregroundColor: widget.showAdvancedFilters
              ? activeColor
              : (_isDark
                    ? DefensysTokens.textPrimaryDark
                    : const Color(0xFF0F172A)),
          side: BorderSide(
            color: widget.showAdvancedFilters
                ? activeColor
                : (_isDark
                      ? DefensysTokens.mistBorder
                      : const Color(0xFFE2E8F0)),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _searchField(RepositoryAuditState state) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: widget.searchController,
        enabled: !state.isSaving,
        style: TextStyle(
          fontSize: 13,
          color: _isDark
              ? DefensysTokens.textPrimaryDark
              : const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.search_rounded,
            color: _isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8),
            size: 18,
          ),
          hintText: 'Search by file name, course, team, or semester...',
          hintStyle: TextStyle(
            color: _isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8),
            fontSize: 13,
          ),
          filled: true,
          fillColor: _isDark
              ? DefensysTokens.mistInputFill
              : const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: _isDark
                  ? DefensysTokens.mistBorder
                  : const Color(0xFFE2E8F0),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: _isDark
                  ? DefensysTokens.mistBorder
                  : const Color(0xFFE2E8F0),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: _isDark ? const Color(0xFFF87171) : AppColors.maroon,
              width: 1.5,
            ),
          ),
        ),
        onSubmitted: (value) {
          ref
              .read(repositoryAuditProvider.notifier)
              .fetchEntries(search: value);
        },
      ),
    );
  }

  Widget _clearFiltersButton() {
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: () {
          widget.searchController.clear();
          setState(() => _sortOrder = 'a_z');
          ref
              .read(repositoryAuditProvider.notifier)
              .fetchEntries(
                search: '',
                type: '',
                yearLevel: '',
                academicYear: '',
                status: '',
                semester: '',
                teamId: '',
                stage: '',
                deliverableId: '',
                submissionKind: '',
                viewMode: '',
                groupBy: 'team',
                folderKey: '',
                clearDeliverable: true,
                clearTeam: true,
              );
        },
        icon: const Icon(Icons.refresh_rounded, size: 15),
        label: const Text('Clear Filters'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _isDark
              ? DefensysTokens.textSecondaryDark
              : const Color(0xFF475569),
          side: BorderSide(
            color: _isDark
                ? DefensysTokens.mistBorder
                : const Color(0xFFE2E8F0),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _filterFromMaps({
    required String value,
    required String label,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = items.isEmpty
        ? [
            {'value': '', 'label': label},
          ]
        : [
            {'value': '', 'label': label},
            ...items.where(
              (item) => (item['value']?.toString() ?? '').isNotEmpty,
            ),
          ];

    final values = options
        .map((item) => item['value']?.toString() ?? '')
        .toSet();
    final selected = values.contains(value) ? value : '';

    return _filterShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          dropdownColor: _isDark ? DefensysTokens.mistSurface : Colors.white,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: _isDark
                ? DefensysTokens.textSecondaryDark
                : const Color(0xFF64748B),
          ),
          style: TextStyle(
            color: _isDark
                ? DefensysTokens.textPrimaryDark
                : AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: options
              .map(
                (item) => DropdownMenuItem(
                  value: item['value']?.toString() ?? '',
                  child: Text(
                    item['label']?.toString() ?? label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: _isDark
                          ? DefensysTokens.textPrimaryDark
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _filterFromStrings({
    required String value,
    required String label,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final options = [label, ...items.where((item) => item.isNotEmpty)];
    final selected = items.contains(value) ? value : label;

    return _filterShell(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          dropdownColor: _isDark ? DefensysTokens.mistSurface : Colors.white,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: _isDark
                ? DefensysTokens.textSecondaryDark
                : const Color(0xFF64748B),
          ),
          style: TextStyle(
            color: _isDark
                ? DefensysTokens.textPrimaryDark
                : AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: options
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    item,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: _isDark
                          ? DefensysTokens.textPrimaryDark
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (val) {
            if (val == label) {
              onChanged('');
            } else {
              onChanged(val);
            }
          },
        ),
      ),
    );
  }

  Widget _filterShell({required Widget child, double height = 40}) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: child,
    );
  }

  Widget _tableScrollHint() {
    if (!widget.showTableScrollHint) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Scroll horizontally for more columns',
        style: TextStyle(
          color:
              (_isDark
                      ? DefensysTokens.textSecondaryDark
                      : AppColors.textSecondary)
                  .withValues(alpha: 0.85),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _wrapWithHorizontalScroll({
    required double minWidth,
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final needsHorizontalScroll = constraints.maxWidth < minWidth;

        Widget content = child;
        if (needsHorizontalScroll) {
          content = Scrollbar(
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minWidth, child: child),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [content, if (needsHorizontalScroll) _tableScrollHint()],
        );
      },
    );
  }

  Widget _repositoryTable(RepositoryAuditState state) {
    final compact = state.teamId.isNotEmpty;
    final isInsideTeam = state.teamId.isNotEmpty ||
        (state.folderBrowser.isNotEmpty &&
            (state.groupBy == 'team' && state.folderBrowser['is_leaf'] == true ||
                (state.folderBrowser['breadcrumbs'] is List &&
                    (state.folderBrowser['breadcrumbs'] as List).length >= 5)));
    final entries = _applySortingToEntries(state.entries);
    return _wrapWithHorizontalScroll(
      minWidth: compact ? 880.0 : _kRepoMinTableWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _repositoryHeaderData(compactColumns: compact),
          ...entries.map(
            (entry) => _repositoryRowData(
              entry,
              compactColumns: compact,
              showTeamBadge: !isInsideTeam,
            ),
          ),
        ],
      ),
    );
  }

  Widget _repositoryHeaderData({bool compactColumns = false}) {
    return Container(
      height: DefensysTableTokens.headerHeight,
      decoration: BoxDecoration(
        color: DefensysTableTokens.headerBackgroundOf(context),
        border: Border(
          bottom: BorderSide(
            color: DefensysTableTokens.headerBorderOf(context),
          ),
        ),
      ),
      child: Row(
        children: [
          _tableHeaderCell('File Name', flex: compactColumns ? 3.5 : 3.2),
          if (!compactColumns) ...[
            _tableHeaderCell('Year Level', flex: 0.85),
            _tableHeaderCell('Academic Year', flex: 1.0),
          ],
          _tableHeaderCell('Semester', flex: compactColumns ? 1.1 : 0.95),
          _tableHeaderCell('Status', flex: 1.0),
          _tableHeaderCell('Uploaded', flex: 0.85),
          _tableHeaderCell(
            'Actions',
            flex: 1.1,
            alignment: Alignment.centerRight,
          ),
        ],
      ),
    );
  }

  Widget _emptyRepositoryTable() {
    return _wrapWithHorizontalScroll(
      minWidth: _kRepoMinTableWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _repositoryHeaderData(),
          Container(
            height: 220,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _isDark ? DefensysTokens.mistSurface : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: _isDark
                      ? DefensysTokens.mistBorder
                      : const Color(0xFFE5E7EB),
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isDark
                        ? DefensysTokens.mistInputFill
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.folder_open_outlined,
                    size: 32,
                    color: _isDark
                        ? DefensysTokens.textSecondaryDark
                        : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'No archive records found',
                  style: TextStyle(
                    color: _isDark
                        ? DefensysTokens.textPrimaryDark
                        : const Color(0xFF1E293B),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try searching or adjusting your filter settings',
                  style: TextStyle(
                    color: _isDark
                        ? DefensysTokens.textSecondaryDark
                        : const Color(0xFF64748B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _repositoryRowData(
    Map<String, dynamic> entry, {
    bool compactColumns = false,
    bool showTeamBadge = true,
  }) {
    final isPit = entry['type'] == 'pit';
    final isMissing = entry['is_missing'] == true;
    final hasFile = entry['has_file'] == true && !isMissing;
    final title = isPit
        ? entry['file_name']?.toString() ?? ''
        : entry['deliverable_label']?.toString() ??
              entry['file_name']?.toString() ??
              '';
    final uploadedBy = entry['uploaded_by']?.toString() ?? 'System';
    final deliverableId = entry['deliverable_id']?.toString() ?? '';
    final teamName =
        entry['team_name']?.toString() ?? entry['team']?.toString() ?? '';

    return Container(
      constraints: const BoxConstraints(
        minHeight: DefensysTableTokens.rowHeightMultiline,
      ),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistPanel : Colors.white,
        border: Border(
          bottom: BorderSide(color: DefensysTableTokens.rowBorderOf(context)),
        ),
      ),
      child: Row(
        children: [
          _tableCell(
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _isDark
                        ? const Color(0xFF7F1D1D).withValues(alpha: 0.35)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _isDark
                          ? const Color(0xFF991B1B).withValues(alpha: 0.5)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_rounded,
                    color: _isDark
                        ? const Color(0xFFF87171)
                        : const Color(0xFFDC2626),
                    size: 15,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showTeamBadge &&
                          widget.state.teamId.isEmpty &&
                          teamName.isNotEmpty) ...[
                        _teamBadge(teamName, entry),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        deliverableId.isNotEmpty
                            ? (title.startsWith('$deliverableId ·') ||
                                    title.startsWith('$deliverableId -')
                                ? title
                                : '$deliverableId · ${title.isEmpty ? '—' : title}')
                            : (title.isEmpty ? '-' : title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isDark
                              ? DefensysTokens.textPrimaryDark
                              : const Color(0xFF0F172A),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isMissing
                            ? (entry['archive_note']?.toString().isNotEmpty ==
                                      true
                                  ? entry['archive_note'].toString()
                                  : 'No file uploaded yet')
                            : 'By $uploadedBy',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isDark
                              ? DefensysTokens.textSecondaryDark
                              : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            flex: compactColumns ? 3.5 : 3.2,
          ),
          if (!compactColumns) ...[
            _tableCell(
              _yearBadge(entry['year_level']?.toString() ?? ''),
              flex: 0.85,
            ),
            _tableCell(
              _bodyText(entry['academic_year']?.toString() ?? ''),
              flex: 1.0,
            ),
          ],
          _tableCell(
            _bodyText(entry['semester']?.toString() ?? ''),
            flex: compactColumns ? 1.1 : 0.95,
          ),
          _tableCell(
            _statusBadge(entry['status']?.toString() ?? ''),
            flex: 1.0,
          ),
          _tableCell(_bodyText(_prettyDate(entry['uploaded_at'])), flex: 0.85),
          _tableCell(
            hasFile ? _rowActions(entry) : const SizedBox.shrink(),
            flex: 1.1,
            alignment: Alignment.centerRight,
          ),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(
    String label, {
    required double flex,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: alignment,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DefensysTableTokens.headerTextStyleOf(context),
          ),
        ),
      ),
    );
  }

  Widget _tableCell(
    Widget child, {
    required double flex,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(alignment: alignment, child: child),
      ),
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _yearBadge(String value) {
    if (value.isEmpty || value == '-') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _isDark
              ? DefensysTokens.textSecondaryDark
              : const Color(0xFF475569),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final s = status.trim();
    if (s == 'Approved' || s == 'Post-Defense' || s == 'Accepted' || s == 'Uploaded') {
      return StatusBadge.success(label: s.isEmpty ? 'Approved' : s);
    }
    if (s == 'Needs Revision' || s == 'Needs Re-upload') {
      return StatusBadge.revision(label: s);
    }
    if (s == 'Rejected' || s == 'Failed') {
      return StatusBadge.danger(label: s);
    }
    if (s.toLowerCase().contains('overridden')) {
      return StatusBadge.overridden(label: s);
    }
    if (s == 'Pending Review' || s == 'Pending') {
      return StatusBadge.warning(label: s);
    }
    return StatusBadge.inactive(label: s.isEmpty ? 'Approved' : s);
  }

  Widget _rowActions(Map<String, dynamic> entry) {
    final fileUrl = entry['file_url']?.toString() ?? '';
    final fileName = entry['file_name']?.toString() ?? '';
    final status = entry['status']?.toString() ?? '';

    final isPendingResubmission =
        status == 'Needs Revision' ||
        status == 'Rejected' ||
        status == 'Needs Re-upload';
    final isReplacementUnlocked =
        status == 'Approved' &&
        entry['deliverable_type'] == 'pre' &&
        entry['file_replacement_unlocked'] == true;

    final actionIconData = isPendingResubmission
        ? Icons.hourglass_top_rounded
        : (isReplacementUnlocked
              ? Icons.lock_open_rounded
              : Icons.published_with_changes_rounded);

    final actionIconColor = isPendingResubmission
        ? const Color(0xFFD97706)
        : (isReplacementUnlocked
              ? const Color(0xFF0D9488)
              : const Color(0xFF475569));

    final actionLabel =
        entry['deliverable_type'] == 'post' && status == 'Approved'
        ? 'Reopen for Revision'
        : isPendingResubmission
        ? 'Review Re-upload'
        : (isReplacementUnlocked
              ? 'Manage File Access'
              : 'Request Resubmission / Replace');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actionIcon(
          tooltip: 'View PDF',
          icon: Icons.visibility_outlined,
          color: _isDark
              ? DefensysTokens.textSecondaryDark
              : const Color(0xFF475569),
          onTap: () => widget.onViewPdf(fileUrl, fileName),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          offset: const Offset(0, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: _isDark
                  ? DefensysTokens.mistBorder
                  : const Color(0xFFE2E8F0),
            ),
          ),
          color: _isDark ? DefensysTokens.mistSurface : Colors.white,
          elevation: 4,
          padding: EdgeInsets.zero,
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isDark
                  ? DefensysTokens.mistInputFill
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isDark
                    ? DefensysTokens.mistBorder
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Icon(
              Icons.more_vert_rounded,
              color: _isDark
                  ? DefensysTokens.textSecondaryDark
                  : const Color(0xFF475569),
              size: 15,
            ),
          ),
          onSelected: (value) {
            switch (value) {
              case 'details':
                ArchiveFileDetailsDialog.show(
                  context: context,
                  entry: entry,
                  onViewPdf: widget.onViewPdf,
                  onDownloadFile: widget.onDownloadFile,
                  onOverrideStatus: widget.onOverrideStatus,
                );
                break;
              case 'view':
                widget.onViewPdf(fileUrl, fileName);
                break;
              case 'download':
                widget.onDownloadFile(fileUrl, fileName);
                break;
              case 'override':
                widget.onOverrideStatus(entry);
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'details',
              height: 36,
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: _isDark
                        ? DefensysTokens.textSecondaryDark
                        : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'File Details',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _isDark
                          ? DefensysTokens.textPrimaryDark
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(height: 1),
            PopupMenuItem<String>(
              value: 'download',
              height: 36,
              child: Row(
                children: [
                  Icon(
                    Icons.download_rounded,
                    size: 15,
                    color: _isDark
                        ? DefensysTokens.textSecondaryDark
                        : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Download File',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _isDark
                          ? DefensysTokens.textPrimaryDark
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
            if (entry['can_override'] == true) ...[
              const PopupMenuDivider(height: 1),
              PopupMenuItem<String>(
                value: 'override',
                height: 36,
                child: Row(
                  children: [
                    Icon(actionIconData, size: 15, color: actionIconColor),
                    const SizedBox(width: 9),
                    Text(
                      actionLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: actionIconColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _actionIcon({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _isDark
                ? DefensysTokens.mistInputFill
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isDark
                  ? DefensysTokens.mistBorder
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
      ),
    );
  }

  Widget _buildEntriesBody(RepositoryAuditState state) {
    if (state.folderBrowser.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Showing ${state.entries.length} ${state.entries.length == 1 ? 'record' : 'records'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _isDark
                        ? DefensysTokens.textSecondaryDark
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'List view',
                onPressed: () => setState(() => _folderListView = true),
                icon: Icon(
                  Icons.view_list_rounded,
                  color: _folderListView ? AppColors.maroon : null,
                ),
              ),
              IconButton(
                tooltip: 'Grid view',
                onPressed: () => setState(() => _folderListView = false),
                icon: Icon(
                  Icons.grid_view_rounded,
                  color: !_folderListView ? AppColors.maroon : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_folderListView)
            _repositoryTable(state)
          else
            _fileGrid(state.entries),
        ],
      );
    }
    return _buildFolderBrowser(state);
  }

  Widget _buildFolderBrowser(RepositoryAuditState state) {
    final browser = state.folderBrowser;
    final folders = _applySortingToFolders(_mapList(browser['folders']));
    final breadcrumbs = _mapList(browser['breadcrumbs']);
    final isLeaf = browser['is_leaf'] == true;
    final fileCount = browser['file_count'] ?? 0;
    final missingCount = browser['missing_count'] ?? 0;
    final rootLabel = _scopeKey(state) == 'pit_lead'
        ? '${state.scope['pit_year_level'] ?? ''} PIT Archive'
        : 'Project Archive';
    final parentKey = breadcrumbs.length > 1
        ? breadcrumbs[breadcrumbs.length - 2]['key']?.toString() ?? ''
        : '';
    final crumbItems = <DefensysBreadcrumbItem>[
      DefensysBreadcrumbItem(
        label: rootLabel,
        icon: const Icon(LucideIcons.folderArchive, size: 14),
        onTap: state.folderKey.isEmpty
            ? null
            : () => ref
                  .read(repositoryAuditProvider.notifier)
                  .fetchEntries(folderKey: ''),
        isCurrent: state.folderKey.isEmpty,
      ),
      for (final crumb in breadcrumbs)
        DefensysBreadcrumbItem(
          label: crumb['title']?.toString() ?? '',
          onTap: crumb['key']?.toString() == state.folderKey
              ? null
              : () => ref
                    .read(repositoryAuditProvider.notifier)
                    .fetchEntries(
                      folderKey: crumb['key']?.toString() ?? '',
                    ),
          isCurrent: crumb['key']?.toString() == state.folderKey,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DefensysBreadcrumb(
          onBack: state.folderKey.isNotEmpty
              ? () => ref
                    .read(repositoryAuditProvider.notifier)
                    .fetchEntries(folderKey: parentKey)
              : null,
          items: crumbItems,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                isLeaf
                    ? '$fileCount ${fileCount == 1 ? 'file' : 'files'}${missingCount == 0 ? '' : ' · $missingCount missing'}'
                    : '${folders.length} ${folders.length == 1 ? 'folder' : 'folders'} · $fileCount files${missingCount == 0 ? '' : ' · $missingCount missing'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _isDark
                      ? DefensysTokens.textSecondaryDark
                      : const Color(0xFF64748B),
                ),
              ),
            ),
            IconButton(
              tooltip: 'List view',
              onPressed: () => setState(() => _folderListView = true),
              icon: Icon(
                Icons.view_list_rounded,
                color: _folderListView ? AppColors.maroon : null,
              ),
            ),
            IconButton(
              tooltip: 'Grid view',
              onPressed: () => setState(() => _folderListView = false),
              icon: Icon(
                Icons.grid_view_rounded,
                color: !_folderListView ? AppColors.maroon : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isLeaf) ...[
          if (_folderListView) ...[
            if (state.groupBy == 'deliverable')
              _wrapWithHorizontalScroll(
                minWidth: _kDeliverableMinTableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _deliverableTableHeaderData(),
                    ..._applySortingToEntries(state.entries)
                        .map(_repositoryDeliverableRowData),
                  ],
                ),
              )
            else
              _repositoryTable(state),
          ] else
            _fileGrid(state.entries),
          _folderPager(state),
        ] else if (folders.isEmpty)
          _emptyRepositoryTable()
        else if (_folderListView)
          Column(
            children: [
              for (final folder in folders) _folderCard(folder, list: true),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080
                  ? 4
                  : constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 470
                  ? 2
                  : 1;
              const gap = 12.0;
              final cardWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final folder in folders)
                    SizedBox(width: cardWidth, child: _folderCard(folder)),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _folderCard(Map<String, dynamic> folder, {bool list = false}) {
    final title = folder['title']?.toString() ?? 'Folder';
    final subtitle = folder['subtitle']?.toString() ?? '';
    final count = folder['file_count'] ?? 0;
    final missing = folder['missing_count'] ?? 0;
    final countLabel = '$count ${count == 1 ? 'file' : 'files'}${missing == 0 ? '' : ' · $missing missing'}';
    return Padding(
      padding: EdgeInsets.only(bottom: list ? 8 : 0),
      child: Material(
        color: _isDark ? DefensysTokens.mistPanel : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('archiveFolder_${folder['key']}'),
          onTap: () => ref
              .read(repositoryAuditProvider.notifier)
              .fetchEntries(folderKey: folder['key']?.toString() ?? ''),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: list ? 72 : 148),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: _isDark
                    ? DefensysTokens.mistBorder
                    : const Color(0xFFE2E8F0),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: list
                ? Row(
                    children: [
                      const Icon(
                        Icons.folder_rounded,
                        color: Color(0xFFE8AA12),
                        size: 30,
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: _folderLabels(title, subtitle)),
                      Text(countLabel),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.folder_rounded,
                        color: Color(0xFFE8AA12),
                        size: 34,
                      ),
                      const SizedBox(height: 18),
                      _folderLabels(title, subtitle),
                      const SizedBox(height: 6),
                      Text(
                        countLabel,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _folderLabels(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: _isDark
                ? DefensysTokens.textSecondaryDark
                : const Color(0xFF64748B),
          ),
        ),
      ],
    ],
  );

  Widget _folderPager(RepositoryAuditState state) {
    final total =
        (state.pagination['total'] as num?)?.toInt() ?? state.entries.length;
    final limit = (state.pagination['limit'] as num?)?.toInt() ?? 100;
    if (total <= limit) return const SizedBox.shrink();
    final offset = state.pageOffset;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('${offset + 1}-${(offset + limit).clamp(0, total)} of $total'),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: offset == 0
                ? null
                : () => ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(
                        pageOffset: (offset - limit).clamp(0, total),
                      ),
            child: const Text('Previous'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: offset + limit >= total
                ? null
                : () => ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(pageOffset: offset + limit),
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  Widget _fileGrid(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return _emptyRepositoryTable();
    final sortedEntries = _applySortingToEntries(entries);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1200
            ? 4
            : constraints.maxWidth >= 840
            ? 3
            : constraints.maxWidth >= 540
            ? 2
            : 1;
        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final entry in sortedEntries)
              SizedBox(width: cardWidth, child: _fileCard(entry)),
          ],
        );
      },
    );
  }

  Widget _fileCard(Map<String, dynamic> entry) {
    final isPit = entry['type'] == 'pit';
    final isMissing = entry['is_missing'] == true;
    final hasFile = entry['has_file'] == true && !isMissing;
    final title = isPit
        ? entry['file_name']?.toString() ?? ''
        : entry['deliverable_label']?.toString() ??
              entry['file_name']?.toString() ??
              '';
    final deliverableId = entry['deliverable_id']?.toString() ?? '';
    final status = entry['status']?.toString() ?? '';
    final fileName = entry['file_name']?.toString() ?? '';
    final uploadedAt = _prettyDate(entry['uploaded_at']);

    final format = DeliverableFormatInfo.fromFileName(fileName);
    final displayTitle = deliverableId.isNotEmpty
        ? (title.startsWith('$deliverableId ·') ||
                title.startsWith('$deliverableId -')
            ? title
            : '$deliverableId · ${title.isEmpty ? '—' : title}')
        : (title.isEmpty ? (fileName.isNotEmpty ? fileName : '—') : title);

    return Material(
      color: _isDark ? DefensysTokens.mistPanel : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('archiveFile_${entry['id'] ?? deliverableId}'),
        onTap: () => ArchiveFileDetailsDialog.show(
          context: context,
          entry: entry,
          onViewPdf: widget.onViewPdf,
          onDownloadFile: widget.onDownloadFile,
          onOverrideStatus: widget.onOverrideStatus,
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 180),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: _isDark
                  ? DefensysTokens.mistBorder
                  : const Color(0xFFE2E8F0),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top row: Status Badge aligned to right
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _statusBadge(status),
                ],
              ),
              const SizedBox(height: 6),

              // Center: 52x52 Squircle Hero Icon
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isMissing
                        ? (_isDark
                            ? const Color(0xFF3F3F46).withValues(alpha: 0.3)
                            : const Color(0xFFF1F5F9))
                        : (_isDark
                            ? format.color.withValues(alpha: 0.25)
                            : format.color.withValues(alpha: 0.08)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isMissing
                          ? (_isDark
                              ? const Color(0xFF52525B)
                              : const Color(0xFFCBD5E1))
                          : (_isDark
                              ? format.color.withValues(alpha: 0.45)
                              : format.color.withValues(alpha: 0.22)),
                      width: 1.2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isMissing ? Icons.description_outlined : format.icon,
                    color: isMissing
                        ? (_isDark
                            ? const Color(0xFFA1A1AA)
                            : const Color(0xFF64748B))
                        : format.color,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // File Title (Centered, 2 lines max)
              Text(
                displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isDark
                      ? DefensysTokens.textPrimaryDark
                      : const Color(0xFF0F172A),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),

              // Bottom row: Upload Date + Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    hasFile ? uploadedAt : 'Not uploaded',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _isDark
                          ? DefensysTokens.textSecondaryDark
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                  if (hasFile)
                    _rowActions(entry)
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _isDark
              ? DefensysTokens.textSecondaryDark
              : const Color(0xFF64748B),
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _deliverableTableHeaderData() {
    return Container(
      height: DefensysTableTokens.headerHeight,
      decoration: BoxDecoration(
        color: DefensysTableTokens.headerBackgroundOf(context),
        border: Border(
          bottom: BorderSide(
            color: DefensysTableTokens.headerBorderOf(context),
          ),
        ),
      ),
      child: Row(
        children: [
          _tableHeaderCell('Team', flex: 1.2),
          _tableHeaderCell('Project', flex: 1.4),
          _tableHeaderCell('Stage', flex: 0.9),
          _tableHeaderCell('File', flex: 1.6),
          _tableHeaderCell('Status', flex: 0.9),
          _tableHeaderCell('Uploaded', flex: 0.8),
          _tableHeaderCell(
            'Actions',
            flex: 1.1,
            alignment: Alignment.centerRight,
          ),
        ],
      ),
    );
  }

  Widget _repositoryDeliverableRowData(Map<String, dynamic> entry) {
    final hasFile = entry['has_file'] == true;
    final fileName = entry['file_name']?.toString() ?? '';
    final format = DeliverableFormatInfo.fromFileName(fileName);
    return Container(
      constraints: const BoxConstraints(
        minHeight: DefensysTableTokens.rowHeightStandard,
      ),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistPanel : Colors.white,
        border: Border(
          bottom: BorderSide(color: DefensysTableTokens.rowBorderOf(context)),
        ),
      ),
      child: Row(
        children: [
          _tableCell(
            _bodyText(entry['team_name']?.toString() ?? ''),
            flex: 1.2,
          ),
          _tableCell(
            _bodyText(entry['project_title']?.toString() ?? ''),
            flex: 1.4,
          ),
          _tableCell(_bodyText(entry['stage']?.toString() ?? ''), flex: 0.9),
          _tableCell(
            hasFile
                ? Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: format.color.withValues(
                            alpha: _isDark ? 0.25 : 0.1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: format.color.withValues(
                              alpha: _isDark ? 0.45 : 0.25,
                            ),
                          ),
                        ),
                        child: Icon(
                          format.icon,
                          size: 14,
                          color: format.color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _bodyText(
                          fileName.isNotEmpty ? fileName : '—',
                        ),
                      ),
                    ],
                  )
                : _bodyText('—'),
            flex: 1.6,
          ),
          _tableCell(
            _statusBadge(entry['status']?.toString() ?? ''),
            flex: 0.9,
          ),
          _tableCell(_bodyText(_prettyDate(entry['uploaded_at'])), flex: 0.8),
          _tableCell(
            hasFile ? _rowActions(entry) : const SizedBox.shrink(),
            flex: 1.1,
            alignment: Alignment.centerRight,
          ),
        ],
      ),
    );
  }
}
