import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/screens/web/shared/project_archive/dialogs/stage_access_management_dialog.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/widgets/status_badge.dart';
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
  static const _kRepoMinTableWidth = 1515.0;
  static const _kRepoActionColumnWidth = 140.0;
  static const _kRepoDataTableWidth =
      _kRepoMinTableWidth - _kRepoActionColumnWidth;
  static const _kDeliverableMinTableWidth = 1100.0;

  final _teamSearchController = TextEditingController();
  String _teamSearchQuery = '';
  String _selectedPitEventFilter = '';
  final Set<String> _collapsedPitEvents = {};
  String _mainViewMode = 'stage';

  @override
  void dispose() {
    _teamSearchController.dispose();
    super.dispose();
  }

  String _scopeKey(RepositoryAuditState state) =>
      state.scope['scope']?.toString() ?? 'admin';

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
                    color: AppColors.maroon,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Project Archive Records',
                  style: TextStyle(
                    color: AppColors.maroon,
                    fontSize: 15.5,
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
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              state.deliverableId.isNotEmpty
                  ? 'Showing ${state.entries.length} teams for ${state.deliverableSummary['label'] ?? state.deliverableId}'
                  : 'Showing ${state.entries.length} records',
              style: const TextStyle(
                color: Color(0xFF5D6678),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
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
                color: selected ? AppColors.maroon : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.maroon : const Color(0xFF64748B),
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
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          modeBtn('By Stage', Icons.style_rounded, 'stage'),
          const SizedBox(width: 2),
          modeBtn('By Team', Icons.groups_rounded, 'team'),
        ],
      ),
    );
  }

  Widget _teamBadge(String teamName) {
    if (teamName.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.maroon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.maroon.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups_rounded, size: 11, color: AppColors.maroon),
          const SizedBox(width: 4),
          Text(
            teamName,
            style: const TextStyle(
              color: AppColors.maroon,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _advancedFiltersButton() {
    return SizedBox(
      height: 43,
      child: OutlinedButton.icon(
        onPressed: widget.onToggleAdvancedFilters,
        icon: Icon(
          widget.showAdvancedFilters
              ? Icons.filter_alt_off_rounded
              : Icons.filter_alt_rounded,
          size: 16,
          color: widget.showAdvancedFilters
              ? AppColors.maroon
              : AppColors.textPrimary,
        ),
        label: Text(widget.showAdvancedFilters ? 'Hide Filters' : 'Filters'),
        style: OutlinedButton.styleFrom(
          foregroundColor: widget.showAdvancedFilters
              ? AppColors.maroon
              : AppColors.textPrimary,
          side: BorderSide(
            color: widget.showAdvancedFilters
                ? AppColors.maroon
                : const Color(0xFFD1D5DB),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _searchField(RepositoryAuditState state) {
    return SizedBox(
      height: 43,
      child: TextField(
        controller: widget.searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textSecondary,
            size: 19,
          ),
          hintText: 'Search by file name, course, or semester...',
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
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
            borderSide: const BorderSide(color: AppColors.maroon),
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
      height: 43,
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
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('Clear Filters'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
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
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: AppColors.textPrimary,
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
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
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
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: AppColors.textPrimary,
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
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
          color: AppColors.textSecondary.withValues(alpha: 0.85),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _wrapWithHorizontalScroll({
    required double minDataWidth,
    required Widget dataPane,
    required Widget? actionColumn,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth =
            actionColumn == null ? 0.0 : _kRepoActionColumnWidth;
        final dataAreaWidth = (constraints.maxWidth - actionWidth).clamp(
          0.0,
          double.infinity,
        );
        final needsHorizontalScroll = dataAreaWidth < minDataWidth;

        Widget pane = dataPane;
        if (needsHorizontalScroll) {
          pane = Scrollbar(
            controller: widget.tableHScrollController,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: widget.tableHScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minDataWidth, child: dataPane),
            ),
          );
        }

        if (actionColumn == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [pane, _tableScrollHint()],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: pane),
                actionColumn,
              ],
            ),
            _tableScrollHint(),
          ],
        );
      },
    );
  }

  Widget _repositoryTable(RepositoryAuditState state) {
    final compact = state.teamId.isNotEmpty;
    final entries = state.entries;
    return _wrapWithHorizontalScroll(
      minDataWidth: _kRepoDataTableWidth,
      dataPane: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _repositoryHeaderData(compactColumns: compact),
          ...entries.map(
            (entry) => _repositoryRowData(entry, compactColumns: compact),
          ),
        ],
      ),
      actionColumn: _repositoryActionColumn(
        entries.map(_repositoryRowAction).toList(),
      ),
    );
  }

  Widget _repositoryHeaderData({bool compactColumns = false}) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _tableHeaderCell('File Name', flex: 3.45),
          if (!compactColumns) ...[
            _tableHeaderCell('Year Level', flex: 0.74),
            _tableHeaderCell('Academic Year', flex: 0.94),
            _tableHeaderCell('Course', flex: 0.62),
          ],
          _tableHeaderCell('Semester', flex: 0.78),
          _tableHeaderCell('Status', flex: 0.95),
          _tableHeaderCell('Uploaded', flex: 0.74),
        ],
      ),
    );
  }

  Widget _repositoryActionColumn(
    List<Widget> actionRows, {
    double headerHeight = 44,
  }) {
    return SizedBox(
      width: _kRepoActionColumnWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _repositoryActionHeader(height: headerHeight),
          ...actionRows,
        ],
      ),
    );
  }

  Widget _repositoryActionHeader({double height = 44}) {
    return Container(
      height: height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Text(
        'Actions',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _repositoryActionSpacer({double height = 40}) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Color(0xFFE2E8F0)),
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );
  }

  Widget _emptyRepositoryTable() {
    return _wrapWithHorizontalScroll(
      minDataWidth: _kRepoDataTableWidth,
      dataPane: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _repositoryHeaderData(),
          Container(
            height: 220,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.folder_open_outlined,
                    size: 32,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'No archive records found',
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Try searching or adjusting your filter settings',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionColumn: _repositoryActionColumn([
        _repositoryActionSpacer(height: 220),
      ]),
    );
  }

  Widget _repositoryRowData(
    Map<String, dynamic> entry, {
    bool compactColumns = false,
  }) {
    final isPit = entry['type'] == 'pit';
    final isMissing = entry['is_missing'] == true;
    final title = isPit
        ? entry['file_name']?.toString() ?? ''
        : entry['deliverable_label']?.toString() ??
            entry['file_name']?.toString() ??
            '';
    final uploadedBy = entry['uploaded_by']?.toString() ?? 'System';
    final deliverableId = entry['deliverable_id']?.toString() ?? '';
    final teamName = entry['team_name']?.toString() ?? entry['team']?.toString() ?? '';

    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _tableCell(
            Row(
              children: [
                const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.state.teamId.isEmpty && teamName.isNotEmpty) ...[
                        _teamBadge(teamName),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        deliverableId.isNotEmpty
                            ? '$deliverableId · ${title.isEmpty ? '—' : title}'
                            : (title.isEmpty ? '-' : title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
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
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            flex: 3.45,
          ),
          if (!compactColumns) ...[
            _tableCell(
              _yearBadge(entry['year_level']?.toString() ?? ''),
              flex: 0.74,
            ),
            _tableCell(
              _bodyText(entry['academic_year']?.toString() ?? ''),
              flex: 0.94,
            ),
            _tableCell(
              _bodyText(entry['course']?.toString() ?? ''),
              flex: 0.62,
            ),
          ],
          _tableCell(
            _bodyText(entry['semester']?.toString() ?? ''),
            flex: 0.78,
          ),
          _tableCell(
            Row(
              children: [
                _kindBadge(entry['submission_kind']?.toString()),
                const SizedBox(width: 6),
                Flexible(
                  child: _statusBadge(entry['status']?.toString() ?? ''),
                ),
              ],
            ),
            flex: 0.95,
          ),
          _tableCell(_bodyText(_prettyDate(entry['uploaded_at'])), flex: 0.74),
        ],
      ),
    );
  }

  Widget _repositoryRowAction(Map<String, dynamic> entry) {
    final isMissing = entry['is_missing'] == true;
    final hasFile = entry['has_file'] == true && !isMissing;
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: hasFile ? _rowActions(entry) : const SizedBox.shrink(),
    );
  }

  Widget _tableHeaderCell(String label, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _yearBadge(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value.isEmpty ? '-' : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF2563EB),
          fontSize: 11,
          fontWeight: FontWeight.w900,
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

  Widget _kindBadge(String? kind) {
    final label = switch (kind) {
      'pre' => 'Pre-defense',
      'post' => 'Post-defense',
      'pit' => 'Post-defense',
      _ => 'File',
    };
    final color = switch (kind) {
      'pre' => const Color(0xFF2563EB),
      'post' => AppColors.maroon,
      'pit' => AppColors.maroon,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
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
        : (isReplacementUnlocked ? const Color(0xFF0D9488) : const Color(0xFF2563EB));

    final actionTooltip = isPendingResubmission
        ? 'Student Re-upload Pending (Needs Revision)'
        : (isReplacementUnlocked
            ? 'File Replacement Unlocked for Team (Click to manage)'
            : 'Request team resubmission / replace file');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actionIcon(
          tooltip: 'View PDF',
          icon: Icons.visibility_outlined,
          color: const Color(0xFF2563EB),
          onTap: () => widget.onViewPdf(fileUrl, fileName),
        ),
        const SizedBox(width: 3),
        _actionIcon(
          tooltip: 'Download',
          icon: Icons.download_rounded,
          color: const Color(0xFF059669),
          onTap: () => widget.onDownloadFile(fileUrl, fileName),
        ),
        if (entry['can_override'] == true) ...[
          const SizedBox(width: 3),
          _actionIcon(
            tooltip: actionTooltip,
            icon: actionIconData,
            color: actionIconColor,
            onTap: () => widget.onOverrideStatus(entry),
          ),
        ],
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
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: 16),
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
        'Pick a deliverable to compare all teams. Pick a team to see that team\'s full file list.',
        style: TextStyle(
          color: AppColors.textSecondary.withValues(alpha: 0.9),
          fontSize: 11.5,
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
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 260, child: _buildTeamSidebar(state)),
          const SizedBox(width: 18),
          Expanded(child: _buildTeamDetailPanel(state)),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 260, child: _buildTeamSidebar(state)),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _browseModeTip(state),
              _buildAllTeamsBrowsePanel(state)
            ],
          ),
        ),
      ],
    );
  }

  List<String> _teamStagesFromEntries(RepositoryAuditState state, String teamId) {
    final stages = <String>{};
    for (final entry in state.entries) {
      if (entry['team_id']?.toString() == teamId && entry['has_file'] == true) {
        final stage = entry['stage']?.toString() ?? '';
        if (stage.isNotEmpty) stages.add(stage);
      }
    }
    return stages.toList();
  }

  Map<String, List<Map<String, dynamic>>> _groupPitTeamsByEvent(
    List<Map<String, dynamic>> pitTeams,
    RepositoryAuditState state,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final team in pitTeams) {
      final level = team['level']?.toString() ?? '';
      final course = team['course_code']?.toString() ?? '';
      String eventKey = 'PIT Event';
      if (level.isNotEmpty && course.isNotEmpty) {
        eventKey = '$level ($course)';
      } else if (level.isNotEmpty) {
        eventKey = level;
      } else if (course.isNotEmpty) {
        eventKey = course;
      }
      grouped.putIfAbsent(eventKey, () => []).add(team);
    }
    return grouped;
  }

  Widget _buildPitEventFilterChips(List<String> eventKeys) {
    if (eventKeys.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () => setState(() => _selectedPitEventFilter = ''),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _selectedPitEventFilter.isEmpty
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF2563EB).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _selectedPitEventFilter.isEmpty
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF2563EB).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  'All Events',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: _selectedPitEventFilter.isEmpty
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: _selectedPitEventFilter.isEmpty
                        ? Colors.white
                        : const Color(0xFF2563EB),
                  ),
                ),
              ),
            ),
            ...eventKeys.map((evt) {
              final selected = _selectedPitEventFilter == evt;
              return Padding(
                padding: const EdgeInsets.only(left: 4),
                child: InkWell(
                  onTap: () => setState(() {
                    _selectedPitEventFilter = selected ? '' : evt;
                  }),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF2563EB).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF2563EB).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      evt,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? Colors.white : const Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamSidebar(RepositoryAuditState state) {
    final allTeams = _mapList(state.options['team_counts']);
    
    final teams = _teamSearchQuery.isEmpty
        ? allTeams
        : allTeams.where((team) {
            final name = (team['name']?.toString() ?? '').toLowerCase();
            final level = (team['level']?.toString() ?? '').toLowerCase();
            final project = (_teamProjectFromEntries(state, team['id']?.toString() ?? '') ?? '').toLowerCase();
            return name.contains(_teamSearchQuery) ||
                level.contains(_teamSearchQuery) ||
                project.contains(_teamSearchQuery);
          }).toList();

    final capstoneTeams =
        teams.where((team) => _teamTrack(team) == 'capstone').toList();
    final pitTeams = teams.where((team) => _teamTrack(team) == 'pit').toList();
    final showCapstone = state.type.isEmpty || state.type == 'capstone';
    final showPit = state.type.isEmpty || state.type == 'pit';

    Widget capstoneSection() {
      if (capstoneTeams.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CAPSTONE TEAMS',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF64748B),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.maroon.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${capstoneTeams.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.maroon,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...capstoneTeams.map((team) {
            final id = team['id']?.toString() ?? '';
            final name = team['name']?.toString() ?? 'Team';
            final level = team['level']?.toString() ?? '';
            final project = _teamProjectFromEntries(state, id) ?? '';
            final track = _teamTrack(team);
            final pre = _asInt(team['pre']);
            final vault = _asInt(team['post']);
            final stages = _teamStagesFromEntries(state, id);
            return _sidebarTeamTile(
              state,
              id: id,
              name: name,
              level: level,
              projectTitle: project,
              preCount: pre,
              vaultCount: vault,
              track: track,
              stages: stages,
            );
          }),
        ],
      );
    }

    Widget pitSection() {
      if (pitTeams.isEmpty) return const SizedBox.shrink();
      final pitGroups = _groupPitTeamsByEvent(pitTeams, state);
      final eventKeys = pitGroups.keys.toList();

      final filteredGroups = _selectedPitEventFilter.isEmpty
          ? pitGroups
          : Map.fromEntries(
              pitGroups.entries.where((e) => e.key == _selectedPitEventFilter),
            );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PIT TEAMS (BY EVENT)',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF64748B),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${pitTeams.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildPitEventFilterChips(eventKeys),
          const SizedBox(height: 4),
          ...filteredGroups.entries.map((group) {
            final eventTitle = group.key;
            final eventTeams = group.value;
            final isCollapsed = _collapsedPitEvents.contains(eventTitle);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isCollapsed) {
                        _collapsedPitEvents.remove(eventTitle);
                      } else {
                        _collapsedPitEvents.add(eventTitle);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          isCollapsed
                              ? Icons.keyboard_arrow_right_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: const Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.event_note_rounded,
                          size: 13,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            eventTitle,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF2563EB).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${eventTeams.length}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isCollapsed) ...[
                  ...eventTeams.map((team) {
                    final id = team['id']?.toString() ?? '';
                    final name = team['name']?.toString() ?? 'Team';
                    final level = team['level']?.toString() ?? '';
                    final project = _teamProjectFromEntries(state, id) ?? '';
                    final track = _teamTrack(team);
                    final vault = _asInt(team['post']);
                    return _sidebarTeamTile(
                      state,
                      id: id,
                      name: name,
                      level: level,
                      projectTitle: project,
                      preCount: 0,
                      vaultCount: vault,
                      track: track,
                    );
                  }),
                ],
              ],
            );
          }),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_outlined,
                size: 18,
                color: AppColors.maroon,
              ),
              const SizedBox(width: 8),
              const Text(
                'TEAMS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${allTeams.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.maroon,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: TextField(
              controller: _teamSearchController,
              onChanged: (val) {
                setState(() {
                  _teamSearchQuery = val.toLowerCase().trim();
                });
              },
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Filter teams...',
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
                suffixIcon: _teamSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 14),
                        onPressed: () {
                          _teamSearchController.clear();
                          setState(() => _teamSearchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _sidebarTeamTile(
            state,
            id: null,
            name: 'All teams',
            level: '',
            projectTitle: '',
            preCount: 0,
            vaultCount: 0,
            track: '',
          ),
          if (showCapstone) capstoneSection(),
          if (showPit) pitSection(),
        ],
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

  Widget _sidebarTeamTile(
    RepositoryAuditState state, {
    required String? id,
    required String name,
    required String level,
    required String projectTitle,
    required int preCount,
    required int vaultCount,
    required String track,
    List<String> stages = const [],
  }) {
    final selected = (id ?? '') == state.teamId;
    final isAllTeams = id == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? AppColors.maroon.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: state.isSaving
              ? null
              : () {
                  if (id == null) {
                    ref
                        .read(repositoryAuditProvider.notifier)
                        .fetchEntries(clearTeam: true);
                  } else {
                    ref
                        .read(repositoryAuditProvider.notifier)
                        .fetchEntries(teamId: id, clearDeliverable: true);
                  }
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? AppColors.maroon.withValues(alpha: 0.35)
                    : const Color(0xFFE2E8F0),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.maroon.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: isAllTeams ? 16 : 36,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.maroon : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isAllTeams
                                ? Icons.folder_special_rounded
                                : Icons.folder_outlined,
                            size: 15,
                            color: selected
                                ? AppColors.maroon
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight:
                                    selected ? FontWeight.w800 : FontWeight.w700,
                                fontSize: 12.5,
                                color: selected
                                    ? AppColors.maroon
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (track.isNotEmpty) _trackBadge(track),
                        ],
                      ),
                      if (!isAllTeams) ...[
                        const SizedBox(height: 3),
                        if (projectTitle.isNotEmpty && projectTitle != name)
                          Text(
                            projectTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (stages.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 3,
                            runSpacing: 2,
                            children: stages.map((stg) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppColors.maroon.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.maroon.withValues(alpha: 0.15)),
                                ),
                                child: Text(
                                  stg,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.maroon,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (level.isNotEmpty) ...[
                              Text(
                                level,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            const Spacer(),
                            if (track != 'pit' && preCount > 0)
                              _microCountPill('$preCount pre', const Color(0xFF2563EB)),
                            if (vaultCount > 0) ...[
                              if (track != 'pit' && preCount > 0)
                                const SizedBox(width: 4),
                              _microCountPill('$vaultCount post', AppColors.maroon),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _microCountPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _trackBadge(String track) {
    final isPit = track == 'pit';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isPit ? const Color(0xFF2563EB) : AppColors.maroon).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isPit ? 'PIT' : 'Capstone',
        style: TextStyle(
          color: isPit ? const Color(0xFF2563EB) : AppColors.maroon,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
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
        gradient: LinearGradient(
          colors: [
            AppColors.maroon.withValues(alpha: 0.03),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.maroon.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
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
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.maroon.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.business_center_rounded,
                    color: AppColors.maroon,
                    size: 22,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: AppColors.maroon,
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
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      const Text(
                        'Showing files for this team only.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
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
                icon: const Icon(Icons.lock_open_rounded, size: 15),
                label: const Text('Manage Team Access ▾'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.maroon,
                  side: const BorderSide(color: AppColors.maroon),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
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
          )
        else
          _buildCapstoneGroupedPanel(
            state,
            entries: _entriesForTeam(state, track: 'capstone'),
            compactColumns: true,
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

      final accentColor = track == 'pit' ? const Color(0xFF2563EB) : AppColors.maroon;

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.05),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.groups_rounded,
                    size: 16,
                    color: accentColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _trackBadge(track),
                  if (level.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _yearBadge(level),
                  ],
                  if (project.isNotEmpty && project != name) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '· $project',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (track == 'pit')
              _buildPitGroupedPanel(teamEntries, compactColumns: true)
            else
              _buildCapstoneGroupedPanel(state, entries: teamEntries, compactColumns: true),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showCapstone && capstoneTeams.isNotEmpty) ...[
          _trackSectionTitle('CAPSTONE TEAMS & DELIVERABLES', AppColors.maroon),
          ...capstoneTeams.map(teamCardGroup),
          const SizedBox(height: 16),
        ],
        if (showPit && pitTeams.isNotEmpty) ...[
          _trackSectionTitle('PIT TEAMS & DELIVERABLES', const Color(0xFF2563EB)),
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
          _trackSectionTitle('PIT', const Color(0xFF2563EB)),
          _buildPitGroupedPanel(pitEntries),
        ],
      ],
    );
  }

  Widget _trackSectionTitle(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Container(width: 4, height: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.5,
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
  }) {
    final groups = state.teamId.isNotEmpty && state.groupedByStage.isNotEmpty
        ? state.groupedByStage
        : _clientGroupByStage(entries, capstoneOnly: true);
    if (groups.isEmpty) {
      if (entries.isNotEmpty) {
        return _wrapWithHorizontalScroll(
          minDataWidth: _kRepoDataTableWidth,
          dataPane: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _repositoryHeaderData(compactColumns: compactColumns),
              ...entries.map(
                (entry) =>
                    _repositoryRowData(entry, compactColumns: compactColumns),
              ),
            ],
          ),
          actionColumn: _repositoryActionColumn(
            entries.map(_repositoryRowAction).toList(),
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
              child: const Text(
                'No Capstone files found.',
                style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
              ),
            ),
        ],
        actionChildren:
            entries.isEmpty ? [_repositoryActionSpacer(height: 72)] : [],
      );
    }
    return _buildCapstoneGroupsContent(groups, compactColumns: compactColumns);
  }

  Widget _buildCapstoneGroupsContent(
    List<Map<String, dynamic>> groups, {
    bool compactColumns = false,
  }) {
    final dataChildren = <Widget>[
      _repositoryHeaderData(compactColumns: compactColumns),
    ];
    final actionChildren = <Widget>[];
    const subsectionHeight = 40.0;
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
      actionChildren.add(_repositoryActionSpacer(height: 32));

      void addSubsection(
        String title,
        Color color,
        List<Map<String, dynamic>> rows,
      ) {
        if (rows.isEmpty) return;
        dataChildren.add(_subsectionHeader(title, color));
        actionChildren.add(_repositoryActionSpacer(height: subsectionHeight));
        for (final row in rows) {
          dataChildren.add(
            _repositoryRowData(row, compactColumns: compactColumns),
          );
          actionChildren.add(_repositoryRowAction(row));
        }
      }

      addSubsection(
        'Pre-defense deliverables',
        const Color(0xFFEFF6FF),
        preRows,
      );
      addSubsection(
        'Post-defense deliverables',
        const Color(0xFFFFF1F2),
        postRows,
      );
      dataChildren.add(const SizedBox(height: 12));
      actionChildren.add(_repositoryActionSpacer(height: 12));
    }

    if (totalValidRows == 0) {
      return _wrapGroupedTable(
        dataChildren: [
          _repositoryHeaderData(compactColumns: compactColumns),
          Container(
            height: 72,
            alignment: Alignment.center,
            child: const Text(
              'No Capstone files found.',
              style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
            ),
          ),
        ],
        actionChildren: [_repositoryActionSpacer(height: 72)],
      );
    }

    return _wrapGroupedTable(
      dataChildren: dataChildren,
      actionChildren: actionChildren,
    );
  }

  Widget _buildPitGroupedPanel(
    List<Map<String, dynamic>> entries, {
    bool compactColumns = false,
  }) {
    final groups = _clientGroupByPitCourse(entries);
    final dataChildren = <Widget>[
      _repositoryHeaderData(compactColumns: compactColumns),
    ];
    final actionChildren = <Widget>[];
    const subsectionHeight = 40.0;

    if (groups.isEmpty) {
      dataChildren.add(
        Container(
          height: 72,
          alignment: Alignment.center,
          child: const Text(
            'No PIT archive files found.',
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
          ),
        ),
      );
      actionChildren.add(_repositoryActionSpacer(height: 72));
      return _wrapGroupedTable(
        dataChildren: dataChildren,
        actionChildren: actionChildren,
      );
    }

    for (final group in groups) {
      final course = group['stage']?.toString() ?? 'PIT';
      final rows = _mapList(group['pit_post']);
      if (rows.isEmpty) continue;

      dataChildren.add(_stageTitle(course, color: const Color(0xFF2563EB)));
      actionChildren.add(_repositoryActionSpacer(height: 32));

      final preRows =
          rows.where((row) => row['submission_kind'] == 'pre').toList();
      final postRows = rows
          .where((row) =>
              row['submission_kind'] == 'post' || row['submission_kind'] == 'pit')
          .toList();

      void addSubsection(
        String title,
        Color color,
        List<Map<String, dynamic>> subRows,
      ) {
        if (subRows.isEmpty) return;
        dataChildren.add(_subsectionHeader(title, color));
        actionChildren.add(_repositoryActionSpacer(height: subsectionHeight));
        for (final row in subRows) {
          dataChildren.add(
            _repositoryRowData(row, compactColumns: compactColumns),
          );
          actionChildren.add(_repositoryRowAction(row));
        }
      }

      addSubsection(
        'Pre-defense deliverables',
        const Color(0xFFEFF6FF),
        preRows,
      );
      addSubsection(
        'Post-defense deliverables',
        const Color(0xFFFFF1F2),
        postRows,
      );

      dataChildren.add(const SizedBox(height: 12));
      actionChildren.add(_repositoryActionSpacer(height: 12));
    }

    return _wrapGroupedTable(
      dataChildren: dataChildren,
      actionChildren: actionChildren,
    );
  }

  Widget _wrapGroupedTable({
    required List<Widget> dataChildren,
    required List<Widget> actionChildren,
  }) {
    return _wrapWithHorizontalScroll(
      minDataWidth: _kRepoDataTableWidth,
      dataPane: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: dataChildren,
      ),
      actionColumn: _repositoryActionColumn(actionChildren),
    );
  }

  Widget _stageTitle(String stage, {Color color = AppColors.maroon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            stage.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 0.6,
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

  Widget _subsectionHeader(String title, Color background) {
    final isPre = title.toLowerCase().contains('pre-defense');
    final icon = isPre ? Icons.folder_open_rounded : Icons.inventory_2_rounded;
    final iconColor = isPre ? const Color(0xFF2563EB) : AppColors.maroon;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8, top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: iconColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _repositoryDeliverableTable(RepositoryAuditState state) {
    final entries = state.entries;
    return _wrapWithHorizontalScroll(
      minDataWidth: _kDeliverableMinTableWidth,
      dataPane: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _deliverableFocusHeader(state),
          const SizedBox(height: 12),
          _deliverableTableHeaderData(),
          ...entries.map(_repositoryDeliverableRowData),
        ],
      ),
      actionColumn: _repositoryActionColumn(
        entries.map(_repositoryDeliverableRowAction).toList(),
        headerHeight: 44,
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.maroon,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'One row per Capstone team for this deliverable. Use Stage to narrow by defense phase.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _deliverableTableHeaderData() {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F1F4),
        borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
      ),
      child: Row(
        children: [
          _tableHeaderCell('Team', flex: 1.2),
          _tableHeaderCell('Project', flex: 1.4),
          _tableHeaderCell('Stage', flex: 0.9),
          _tableHeaderCell('File', flex: 1.6),
          _tableHeaderCell('Status', flex: 0.8),
          _tableHeaderCell('Uploaded', flex: 0.7),
        ],
      ),
    );
  }

  Widget _repositoryDeliverableRowData(Map<String, dynamic> entry) {
    final hasFile = entry['has_file'] == true;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
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
            flex: 0.8,
          ),
          _tableCell(_bodyText(_prettyDate(entry['uploaded_at'])), flex: 0.7),
        ],
      ),
    );
  }

  Widget _repositoryDeliverableRowAction(Map<String, dynamic> entry) {
    final hasFile = entry['has_file'] == true;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: hasFile ? _rowActions(entry) : const SizedBox.shrink(),
    );
  }
}
