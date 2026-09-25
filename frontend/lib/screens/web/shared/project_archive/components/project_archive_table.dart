import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/screens/web/shared/project_archive/dialogs/stage_access_management_dialog.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/widgets/status_badge.dart';
import 'package:defensys/widgets/table/table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  ConsumerState<ProjectArchiveTable> createState() => _ProjectArchiveTableState();
}

class _ProjectArchiveTableState extends ConsumerState<ProjectArchiveTable> {
  static const _kRepoMinTableWidth = 1100.0;
  static const _kDeliverableMinTableWidth = 1000.0;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  String _mainViewMode = 'team';
  final Set<String> _expandedTeamIds = {};
  bool _hasManuallyToggledExpansion = false;

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

  bool _isPitEntry(Map<String, dynamic> entry) => entry['type'] == 'pit';

  bool _isCapstoneEntry(Map<String, dynamic> entry) {
    final type = entry['type']?.toString();
    return type == null || type.isEmpty || type == 'capstone';
  }

  bool _isAdminBrowseLayout(RepositoryAuditState state) {
    return _scopeKey(state) == 'admin';
  }

  String _teamTrack(Map<String, dynamic> team) {
    final t = team['track']?.toString().toLowerCase() ?? '';
    if (t.contains('pit')) return 'pit';
    if (t.contains('capstone')) return 'capstone';
    final name = team['name']?.toString().toLowerCase() ?? '';
    if (name.contains('pit')) return 'pit';
    return 'capstone';
  }

  Map<String, dynamic>? _selectedTeamMeta(RepositoryAuditState state) {
    if (state.teamId.isEmpty) return null;
    final teams = _mapList(state.options['team_counts']);
    for (final team in teams) {
      if (team['id']?.toString() == state.teamId) {
        return team;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _entriesForTeam(
    RepositoryAuditState state, {
    required String track,
  }) {
    return state.entries.where((entry) {
      if (entry['team_id']?.toString() != state.teamId) return false;
      if (entry['has_file'] != true || entry['is_missing'] == true) return false;
      return track == 'pit' ? _isPitEntry(entry) : _isCapstoneEntry(entry);
    }).toList();
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
        borderRadius: BorderRadius.circular(DefensysTableTokens.cardBorderRadius),
        border: Border.all(
          color: _isDark ? DefensysTokens.mistBorder : DefensysTableTokens.cardBorder,
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
                    color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                _buildViewModeToggle(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _searchField(state)),
              const SizedBox(width: 12),
              _advancedFiltersButton(),
              const SizedBox(width: 12),
              _clearFiltersButton(),
            ],
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
                            state.options['submission_kind_options']),
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
            ],
          ],
          const SizedBox(height: 18),
          if (state.isLoading && state.entries.isEmpty)
            DefensysSkeleton.list(count: 6, rowHeight: 48)
          else if (state.entries.isEmpty)
            _emptyRepositoryTable()
          else
            _buildEntriesBody(state),
          const SizedBox(height: 18),
          Container(
            height: 1,
            color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              state.deliverableId.isNotEmpty
                  ? 'Showing ${state.entries.length} teams for ${state.deliverableSummary['label'] ?? state.deliverableId}'
                  : 'Showing ${state.entries.length} records',
              style: TextStyle(
                color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle() {
    Widget modeBtn(String label, IconData icon, String mode) {
      final selected = _mainViewMode == mode;
      return InkWell(
        onTap: () {
          setState(() {
            _mainViewMode = mode;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? (_isDark ? DefensysTokens.mistSurface : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _isDark
                          ? Colors.black.withValues(alpha: 0.25)
                          : Colors.black.withValues(alpha: 0.05),
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
                color: selected
                    ? (_isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A))
                    : (_isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? (_isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A))
                      : (_isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          modeBtn('By Team', Icons.groups_rounded, 'team'),
          const SizedBox(width: 2),
          modeBtn('By Stage', Icons.style_rounded, 'stage'),
        ],
      ),
    );
  }

  Widget _teamBadge(String teamName) {
    if (teamName.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups_rounded,
            size: 11,
            color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
          ),
          const SizedBox(width: 4),
          Text(
            teamName,
            style: TextStyle(
              color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF334155),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

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
              : (_isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569)),
        ),
        label: Text(widget.showAdvancedFilters ? 'Hide Filters' : 'Filters'),
        style: OutlinedButton.styleFrom(
          foregroundColor: widget.showAdvancedFilters
              ? activeColor
              : (_isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A)),
          side: BorderSide(
            color: widget.showAdvancedFilters
                ? activeColor
                : (_isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
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
          color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
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
          fillColor: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
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
          ref.read(repositoryAuditProvider.notifier).fetchEntries(
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
                clearDeliverable: true,
                clearTeam: true,
              );
        },
        icon: const Icon(Icons.refresh_rounded, size: 15),
        label: const Text('Clear Filters'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
          side: BorderSide(
            color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
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

    final values =
        options.map((item) => item['value']?.toString() ?? '').toSet();
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
            color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
          ),
          style: TextStyle(
            color: _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
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
                      color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
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
    final options = [
      label,
      ...items.where((item) => item.isNotEmpty),
    ];
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
            color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
          ),
          style: TextStyle(
            color: _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
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
                      color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
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

  Widget _filterShell({required Widget child}) {
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : Colors.white,
        borderRadius: BorderRadius.circular(10),
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
          color: (_isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary)
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
          children: [
            content,
            if (needsHorizontalScroll) _tableScrollHint(),
          ],
        );
      },
    );
  }

  Widget _repositoryTable(RepositoryAuditState state) {
    final compact = state.teamId.isNotEmpty;
    final entries = state.entries;
    return _wrapWithHorizontalScroll(
      minWidth: compact ? 880.0 : _kRepoMinTableWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _repositoryHeaderData(compactColumns: compact),
          ...entries.map(
            (entry) => _repositoryRowData(entry, compactColumns: compact),
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
          bottom: BorderSide(color: DefensysTableTokens.headerBorderOf(context)),
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
          _tableHeaderCell('Actions', flex: 1.1, alignment: Alignment.centerRight),
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
                  color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB),
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.folder_open_outlined,
                    size: 32,
                    color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'No archive records found',
                  style: TextStyle(
                    color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF1E293B),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try searching or adjusting your filter settings',
                  style: TextStyle(
                    color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
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
    final teamName = entry['team_name']?.toString() ?? entry['team']?.toString() ?? '';

    return Container(
      constraints: const BoxConstraints(minHeight: DefensysTableTokens.rowHeightMultiline),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistPanel : Colors.white,
        border: Border(bottom: BorderSide(color: DefensysTableTokens.rowBorderOf(context))),
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
                    color: _isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                    size: 15,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showTeamBadge && widget.state.teamId.isEmpty && teamName.isNotEmpty) ...[
                        _teamBadge(teamName),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        deliverableId.isNotEmpty
                            ? '$deliverableId · ${title.isEmpty ? '—' : title}'
                            : (title.isEmpty ? '-' : title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
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
                          color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
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
          _tableCell(
            _bodyText(_prettyDate(entry['uploaded_at'])),
            flex: 0.85,
          ),
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
          color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final s = status.trim();
    if (s == 'Approved' || s == 'Post-Defense' || s == 'Accepted') {
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
    final feedback = (entry['feedback']?.toString() ?? entry['remarks']?.toString() ?? '').toLowerCase();

    final isPendingResubmission =
        status == 'Needs Revision' || status == 'Rejected' || status == 'Needs Re-upload';
    final isReplacementUnlocked = !isPendingResubmission &&
        ((entry['archive_unlocked'] == true) ||
            (entry['unlocked'] == true) ||
            feedback.contains('unlocked for file replacement') ||
            (status == 'Approved' && feedback.contains('unlocked')));

    final actionIconData = isPendingResubmission
        ? Icons.hourglass_top_rounded
        : (isReplacementUnlocked ? Icons.lock_open_rounded : Icons.published_with_changes_rounded);

    final actionIconColor = isPendingResubmission
        ? const Color(0xFFD97706)
        : (isReplacementUnlocked ? const Color(0xFF0D9488) : const Color(0xFF475569));

    final actionLabel = isPendingResubmission
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
          color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
          onTap: () => widget.onViewPdf(fileUrl, fileName),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          offset: const Offset(0, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
            ),
          ),
          color: _isDark ? DefensysTokens.mistSurface : Colors.white,
          elevation: 4,
          padding: EdgeInsets.zero,
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
              ),
            ),
            child: Icon(
              Icons.more_vert_rounded,
              color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
              size: 15,
            ),
          ),
          onSelected: (value) {
            switch (value) {
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
              value: 'download',
              height: 36,
              child: Row(
                children: [
                  Icon(
                    Icons.download_rounded,
                    size: 15,
                    color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Download File',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
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
            color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
            ),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
      ),
    );
  }

  Widget _browseModeTip(RepositoryAuditState state) {
    if (state.deliverableId.isNotEmpty || state.teamId.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Pick a deliverable to compare all teams, or explore teams and their submitted archive records below.',
        style: TextStyle(
          color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEntriesBody(RepositoryAuditState state) {
    if (!_isAdminBrowseLayout(state)) {
      return _repositoryTable(state);
    }
    if (state.deliverableId.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_browseModeTip(state), _repositoryDeliverableTable(state)],
      );
    }
    if (state.teamId.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(clearTeam: true);
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 15),
                label: const Text('Back to all teams'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                  side: BorderSide(
                    color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFCBD5E1),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildTeamDetailPanel(state),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _browseModeTip(state),
        _buildAllTeamsBrowsePanel(state),
      ],
    );
    }

  Widget _trackBadge(String track) {
    final isPit = track == 'pit';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isPit
            ? (_isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9))
            : (_isDark
                ? DefensysTokens.mistMaroon.withValues(alpha: 0.18)
                : AppColors.maroon.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isPit
              ? (_isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0))
              : (_isDark
                  ? DefensysTokens.mistMaroon.withValues(alpha: 0.45)
                  : AppColors.maroon.withValues(alpha: 0.2)),
        ),
      ),
      child: Text(
        isPit ? 'PIT' : 'Capstone',
        style: TextStyle(
          color: isPit
              ? (_isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569))
              : (_isDark ? const Color(0xFFF87171) : AppColors.maroon),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String? _teamProjectFromEntries(RepositoryAuditState state, String teamId) {
    for (final entry in state.entries) {
      if (entry['team_id']?.toString() == teamId) {
        final project = entry['project_title']?.toString() ?? '';
        if (project.isNotEmpty) return project;
      }
    }
    return null;
  }

  Widget _teamDetailHeader(RepositoryAuditState state) {
    final team = _selectedTeamMeta(state);
    if (team == null) return const SizedBox.shrink();
    final name = team['name']?.toString() ?? 'Team';
    final level = team['level']?.toString() ?? '';
    final track = _teamTrack(team);
    final project = _teamProjectFromEntries(state, state.teamId) ?? '';
    final teamId = int.tryParse(state.teamId.toString()) ?? 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistPanel : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: _isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.groups_rounded,
                    color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _trackBadge(track),
                          if (level.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _yearBadge(level),
                          ],
                        ],
                      ),
                      if (project.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Project: $project',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        'Showing archive records for this team.',
                        style: TextStyle(
                          color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if ((_scopeKey(state) == 'admin' || _scopeKey(state) == 'pit_lead') && teamId > 0) ...[
            Tooltip(
              message: 'Manually grant or revoke student file upload permissions for this team',
              child: OutlinedButton.icon(
                onPressed: () {
                  StageAccessManagementDialog.show(
                    context: context,
                    ref: ref,
                    teamId: teamId,
                    teamName: name,
                    scope: 'team',
                  );
                },
                icon: const Icon(Icons.lock_open_rounded, size: 14),
                label: const Text('Manage Access'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
                  side: BorderSide(
                    color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFCBD5E1),
                  ),
                  backgroundColor: _isDark ? DefensysTokens.mistInputFill : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTeamDetailPanel(RepositoryAuditState state) {
    final team = _selectedTeamMeta(state);
    final track = team == null ? '' : _teamTrack(team);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _teamDetailHeader(state),
        if (track == 'pit')
          _buildPitGroupedPanel(
            _entriesForTeam(state, track: 'pit'),
            compactColumns: true,
            showTeamBadge: false,
          )
        else
          _buildCapstoneGroupedPanel(
            state,
            entries: _entriesForTeam(state, track: 'capstone'),
            compactColumns: true,
            showTeamBadge: false,
          ),
      ],
    );
  }

  Widget _buildTeamCentricGroupedPanel(RepositoryAuditState state) {
    final teams = _mapList(state.options['team_counts']);
    if (teams.isEmpty || state.entries.isEmpty) {
      return _emptyRepositoryTable();
    }

    final capstoneTeams = teams.where((t) => _teamTrack(t) == 'capstone').toList();
    final pitTeams = teams.where((t) => _teamTrack(t) == 'pit').toList();
    final showCapstone = state.type.isEmpty || state.type == 'capstone';
    final showPit = state.type.isEmpty || state.type == 'pit';

    final allVisibleTeams = [
      if (showCapstone) ...capstoneTeams,
      if (showPit) ...pitTeams,
    ].where((team) {
      final teamId = team['id']?.toString() ?? '';
      final track = _teamTrack(team);
      return state.entries.any((entry) =>
          entry['team_id']?.toString() == teamId &&
          entry['has_file'] == true &&
          entry['is_missing'] != true &&
          (track == 'pit' ? _isPitEntry(entry) : _isCapstoneEntry(entry)));
    }).toList();

    if (!_hasManuallyToggledExpansion &&
        _expandedTeamIds.isEmpty &&
        allVisibleTeams.isNotEmpty) {
      _expandedTeamIds.add(allVisibleTeams.first['id']?.toString() ?? '');
    }

    Widget expandCollapseBar() {
      if (allVisibleTeams.isEmpty) return const SizedBox.shrink();
      final allVisibleIds =
          allVisibleTeams.map((t) => t['id']?.toString() ?? '').toSet();
      final isAllExpanded = _expandedTeamIds.length >= allVisibleIds.length &&
          allVisibleIds.isNotEmpty;

      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${allVisibleTeams.length} ${allVisibleTeams.length == 1 ? 'team' : 'teams'} in directory',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
              ),
            ),
            InkWell(
              onTap: () {
                setState(() {
                  _hasManuallyToggledExpansion = true;
                  if (isAllExpanded) {
                    _expandedTeamIds.clear();
                  } else {
                    _expandedTeamIds.addAll(allVisibleIds);
                  }
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAllExpanded
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                      size: 15,
                      color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isAllExpanded ? 'Collapse All' : 'Expand All',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget teamCardGroup(Map<String, dynamic> team) {
      final teamId = team['id']?.toString() ?? '';
      final name = team['name']?.toString() ?? 'Team';
      final level = team['level']?.toString() ?? '';
      final track = _teamTrack(team);
      final project = _teamProjectFromEntries(state, teamId) ?? '';

      final teamEntries = state.entries.where((entry) {
        if (entry['team_id']?.toString() != teamId) return false;
        if (entry['has_file'] != true || entry['is_missing'] == true) return false;
        return track == 'pit' ? _isPitEntry(entry) : _isCapstoneEntry(entry);
      }).toList();

      if (teamEntries.isEmpty) return const SizedBox.shrink();

      final isExpanded = _expandedTeamIds.contains(teamId);

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _isDark ? DefensysTokens.mistPanel : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isExpanded
                ? (_isDark ? const Color(0xFF4B5563) : const Color(0xFFCBD5E1))
                : (_isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),
            width: isExpanded ? 1.2 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: _isDark
                  ? Colors.black.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: isExpanded ? 0.03 : 0.015),
              blurRadius: isExpanded ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _hasManuallyToggledExpansion = true;
                  if (isExpanded) {
                    _expandedTeamIds.remove(teamId);
                  } else {
                    _expandedTeamIds.add(teamId);
                  }
                });
              },
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(10),
                bottom: Radius.circular(isExpanded ? 0 : 10),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isExpanded
                      ? (_isDark ? const Color(0xFF28272D) : const Color(0xFFF8FAFC))
                      : (_isDark ? DefensysTokens.mistPanel : Colors.white),
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(10),
                    bottom: Radius.circular(isExpanded ? 0 : 10),
                  ),
                  border: isExpanded
                      ? Border(
                          bottom: BorderSide(
                            color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 20,
                      color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.groups_rounded,
                        size: 16,
                        color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _trackBadge(track),
                              if (level.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                _yearBadge(level),
                              ],
                            ],
                          ),
                          if (project.isNotEmpty && project != name) ...[
                            const SizedBox(height: 2),
                            Text(
                              project,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        '${teamEntries.length} ${teamEntries.length == 1 ? 'file' : 'files'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) ...[
              if (track == 'pit')
                _buildPitGroupedPanel(
                  teamEntries,
                  compactColumns: true,
                  showTeamBadge: false,
                )
              else
                _buildCapstoneGroupedPanel(
                  state,
                  entries: teamEntries,
                  compactColumns: true,
                  showTeamBadge: false,
                ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        expandCollapseBar(),
        if (showCapstone && capstoneTeams.isNotEmpty) ...[
          _trackSectionTitle('CAPSTONE TEAMS & DELIVERABLES', AppColors.maroon),
          ...capstoneTeams.map(teamCardGroup),
          const SizedBox(height: 16),
        ],
        if (showPit && pitTeams.isNotEmpty) ...[
          _trackSectionTitle(
              'PIT TEAMS & DELIVERABLES', const Color(0xFF475569)),
          ...pitTeams.map(teamCardGroup),
        ],
      ],
    );
  }

  Widget _buildAllTeamsBrowsePanel(RepositoryAuditState state) {
    if (_mainViewMode == 'team') {
      return _buildTeamCentricGroupedPanel(state);
    }
    if (state.type == 'capstone') {
      return _buildCapstoneGroupedPanel(
        state,
        entries: state.entries.where(_isCapstoneEntry).toList(),
      );
    }
    final capstoneEntries = state.entries.where(_isCapstoneEntry).toList();
    final pitEntries = state.entries.where(_isPitEntry).toList();
    if (capstoneEntries.isEmpty && pitEntries.isEmpty) {
      return _emptyRepositoryTable();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (capstoneEntries.isNotEmpty) ...[
          _trackSectionTitle('CAPSTONE', AppColors.maroon),
          _buildCapstoneGroupedPanel(state, entries: capstoneEntries),
          const SizedBox(height: 20),
        ],
        if (pitEntries.isNotEmpty) ...[
          _trackSectionTitle('PIT', const Color(0xFF475569)),
          _buildPitGroupedPanel(pitEntries),
        ],
      ],
    );
  }

  Widget _trackSectionTitle(String label, Color accentColor) {
    final effectiveAccent = _isDark && accentColor == AppColors.maroon
        ? const Color(0xFFF87171)
        : (_isDark && accentColor == const Color(0xFF475569)
            ? const Color(0xFFA1A1AA)
            : accentColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 16,
            decoration: BoxDecoration(
              color: effectiveAccent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapstoneGroupedPanel(
    RepositoryAuditState state, {
    required List<Map<String, dynamic>> entries,
    bool compactColumns = false,
    bool showTeamBadge = true,
  }) {
    final groups = state.teamId.isNotEmpty && state.groupedByStage.isNotEmpty
        ? state.groupedByStage
        : _clientGroupByStage(entries, capstoneOnly: true);
    if (groups.isEmpty) {
      if (entries.isNotEmpty) {
        return _wrapWithHorizontalScroll(
          minWidth: compactColumns ? 880.0 : _kRepoMinTableWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _repositoryHeaderData(compactColumns: compactColumns),
              ...entries.map(
                (entry) => _repositoryRowData(
                  entry,
                  compactColumns: compactColumns,
                  showTeamBadge: showTeamBadge,
                ),
              ),
            ],
          ),
        );
      }
      return _wrapGroupedTable(
        dataChildren: [
          _repositoryHeaderData(compactColumns: compactColumns),
          if (entries.isEmpty)
            Container(
              height: 72,
              alignment: Alignment.center,
              child: Text(
                'No Capstone files found.',
                style: TextStyle(
                  color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF98A2B3),
                  fontSize: 13,
                ),
              ),
            ),
        ],
        compactColumns: compactColumns,
      );
    }
    return _buildCapstoneGroupsContent(
      groups,
      compactColumns: compactColumns,
      showTeamBadge: showTeamBadge,
    );
  }

  Widget _buildCapstoneGroupsContent(
    List<Map<String, dynamic>> groups, {
    bool compactColumns = false,
    bool showTeamBadge = true,
  }) {
    final dataChildren = <Widget>[
      _repositoryHeaderData(compactColumns: compactColumns),
    ];
    var totalValidRows = 0;

    for (final group in groups) {
      final stage = group['stage']?.toString() ?? '';
      final preRows = _mapList(group['pre_defense'])
          .where((r) => r['has_file'] == true && r['is_missing'] != true)
          .toList();
      final postRows = _mapList(group['post'] ?? group['vault'])
          .where((r) => r['has_file'] == true && r['is_missing'] != true)
          .toList();
      if (preRows.isEmpty && postRows.isEmpty) {
        continue;
      }
      totalValidRows += preRows.length + postRows.length;

      dataChildren.add(_stageTitle(stage));

      void addSubsection(
        String title,
        List<Map<String, dynamic>> rows,
      ) {
        if (rows.isEmpty) return;
        dataChildren.add(_subsectionHeader(title));
        for (final row in rows) {
          dataChildren.add(
            _repositoryRowData(
              row,
              compactColumns: compactColumns,
              showTeamBadge: showTeamBadge,
            ),
          );
        }
      }

      addSubsection('Pre-defense deliverables', preRows);
      addSubsection('Post-defense deliverables', postRows);
      dataChildren.add(const SizedBox(height: 8));
    }

    if (totalValidRows == 0) {
      return _wrapGroupedTable(
        dataChildren: [
          _repositoryHeaderData(compactColumns: compactColumns),
          Container(
            height: 72,
            alignment: Alignment.center,
            child: Text(
              'No Capstone files found.',
              style: TextStyle(
                color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF98A2B3),
                fontSize: 13,
              ),
            ),
          ),
        ],
        compactColumns: compactColumns,
      );
    }

    return _wrapGroupedTable(
      dataChildren: dataChildren,
      compactColumns: compactColumns,
    );
  }

  Widget _buildPitGroupedPanel(
    List<Map<String, dynamic>> entries, {
    bool compactColumns = false,
    bool showTeamBadge = true,
  }) {
    final groups = _clientGroupByPitCourse(entries);
    final dataChildren = <Widget>[
      _repositoryHeaderData(compactColumns: compactColumns),
    ];

    if (groups.isEmpty) {
      dataChildren.add(
        Container(
          height: 72,
          alignment: Alignment.center,
          child: Text(
            'No PIT archive files found.',
            style: TextStyle(
              color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF98A2B3),
              fontSize: 13,
            ),
          ),
        ),
      );
      return _wrapGroupedTable(
        dataChildren: dataChildren,
        compactColumns: compactColumns,
      );
    }

    for (final group in groups) {
      final course = group['stage']?.toString() ?? 'PIT';
      final rows = _mapList(group['pit_post']);
      if (rows.isEmpty) continue;

      dataChildren.add(_stageTitle(course, color: const Color(0xFF475569)));

      final preRows =
          rows.where((row) => row['submission_kind'] == 'pre').toList();
      final postRows = rows
          .where((row) =>
              row['submission_kind'] == 'post' || row['submission_kind'] == 'pit')
          .toList();

      void addSubsection(
        String title,
        List<Map<String, dynamic>> subRows,
      ) {
        if (subRows.isEmpty) return;
        dataChildren.add(_subsectionHeader(title));
        for (final row in subRows) {
          dataChildren.add(
            _repositoryRowData(
              row,
              compactColumns: compactColumns,
              showTeamBadge: showTeamBadge,
            ),
          );
        }
      }

      addSubsection('Pre-defense deliverables', preRows);
      addSubsection('Post-defense deliverables', postRows);

      dataChildren.add(const SizedBox(height: 8));
    }

    return _wrapGroupedTable(
      dataChildren: dataChildren,
      compactColumns: compactColumns,
    );
  }

  Widget _wrapGroupedTable({
    required List<Widget> dataChildren,
    bool compactColumns = false,
  }) {
    return _wrapWithHorizontalScroll(
      minWidth: compactColumns ? 880.0 : _kRepoMinTableWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: dataChildren,
      ),
    );
  }

  Widget _stageTitle(String stage, {Color color = AppColors.maroon}) {
    final effectiveColor = _isDark && color == AppColors.maroon
        ? const Color(0xFFF87171)
        : (_isDark && color == const Color(0xFF475569)
            ? const Color(0xFFA1A1AA)
            : color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 12, left: 14),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 14,
            decoration: BoxDecoration(
              color: effectiveColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            stage.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _clientGroupByStage(
    List<Map<String, dynamic>> entries, {
    bool capstoneOnly = false,
  }) {
    final scoped =
        capstoneOnly ? entries.where(_isCapstoneEntry).toList() : entries;
    final stages = <String>{};
    for (final entry in scoped) {
      final stage = entry['stage']?.toString() ?? '';
      if (stage.isNotEmpty) stages.add(stage);
    }
    return stages.map((stage) {
      final stageEntries =
          scoped.where((entry) => entry['stage'] == stage).toList();
      return {
        'stage': stage,
        'pre_defense': stageEntries
            .where((entry) => entry['submission_kind'] == 'pre')
            .toList(),
        'vault': stageEntries
            .where((entry) => entry['submission_kind'] == 'post')
            .toList(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _clientGroupByPitCourse(
    List<Map<String, dynamic>> entries,
  ) {
    final pitEntries = entries.where(_isPitEntry).toList();
    final courses = <String>{};
    for (final entry in pitEntries) {
      final course =
          entry['stage']?.toString() ?? entry['course_code']?.toString() ?? '';
      if (course.isNotEmpty) courses.add(course);
    }
    return courses.map((course) {
      final courseEntries = pitEntries.where((entry) {
        final stage = entry['stage']?.toString() ?? '';
        final code = entry['course_code']?.toString() ?? '';
        return stage == course || code == course;
      }).toList();
      return {'stage': course, 'pit_post': courseEntries};
    }).toList();
  }

  Widget _subsectionHeader(String title) {
    final isPre = title.toLowerCase().contains('pre-defense');
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8, left: 14, right: 14),
      child: Row(
        children: [
          Icon(
            isPre ? Icons.file_present_rounded : Icons.inventory_2_outlined,
            size: 14,
            color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
          ),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _repositoryDeliverableTable(RepositoryAuditState state) {
    final entries = state.entries;
    return _wrapWithHorizontalScroll(
      minWidth: _kDeliverableMinTableWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _deliverableFocusHeader(state),
          const SizedBox(height: 12),
          _deliverableTableHeaderData(),
          ...entries.map(_repositoryDeliverableRowData),
        ],
      ),
    );
  }

  Widget _deliverableFocusHeader(RepositoryAuditState state) {
    final summary = state.deliverableSummary;
    final label = summary['label']?.toString() ?? state.deliverableId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: _isDark ? const Color(0xFFF87171) : AppColors.maroon,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'One row per Capstone team for this deliverable. Use Stage to narrow by defense phase.',
            style: TextStyle(
              color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
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
          _tableHeaderCell('Actions', flex: 1.1, alignment: Alignment.centerRight),
        ],
      ),
    );
  }

  Widget _repositoryDeliverableRowData(Map<String, dynamic> entry) {
    final hasFile = entry['has_file'] == true;
    return Container(
      constraints: const BoxConstraints(minHeight: DefensysTableTokens.rowHeightStandard),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistPanel : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: DefensysTableTokens.rowBorderOf(context),
          ),
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
            _bodyText(hasFile ? (entry['file_name']?.toString() ?? '') : '—'),
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
