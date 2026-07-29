import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/widgets/feedback_toast.dart';
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Project Archive Records',
              style: const TextStyle(
                color: AppColors.maroon,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
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
      height: 51,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F1F4),
        borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
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
    double headerHeight = 51,
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

  Widget _repositoryActionHeader({double height = 51}) {
    return Container(
      height: height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F1F4),
        borderRadius: BorderRadius.horizontal(right: Radius.circular(5)),
        border: Border(left: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: const Text(
        'Action',
        style: TextStyle(
          color: Color(0xFF5D6678),
          fontSize: 12,
          fontWeight: FontWeight.w800,
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
          left: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
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
      'post' => 'Repository',
      'pit' => 'Repository',
      _ => 'File',
    };
    final color = switch (kind) {
      'pre' => const Color(0xFF2563EB),
      'post' => const Color(0xFF7C3AED),
      'pit' => const Color(0xFF7C3AED),
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
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: color, size: 18),
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

  Widget _buildTeamSidebar(RepositoryAuditState state) {
    final teams = _mapList(state.options['team_counts']);
    final capstoneTeams =
        teams.where((team) => _teamTrack(team) == 'capstone').toList();
    final pitTeams = teams.where((team) => _teamTrack(team) == 'pit').toList();
    final showCapstone = state.type.isEmpty || state.type == 'capstone';
    final showPit = state.type.isEmpty;

    Widget teamSection(String title, List<Map<String, dynamic>> sectionTeams) {
      if (sectionTeams.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 6),
          ...sectionTeams.map((team) {
            final id = team['id']?.toString() ?? '';
            final name = team['name']?.toString() ?? 'Team';
            final level = team['level']?.toString() ?? '';
            final project = _teamProjectFromEntries(state, id) ??
                team['name']?.toString() ??
                '';
            final track = _teamTrack(team);
            final pre = _asInt(team['pre']);
            final vault = _asInt(team['post']);
            final counts = track == 'pit'
                ? '$vault archive'
                : '$pre pre · $vault archive';
            final subtitle = [
              if (level.isNotEmpty) level,
              if (project.isNotEmpty && project != name) project,
              counts,
            ].join(' · ');
            return _sidebarTeamTile(state, id, name, subtitle, track: track);
          }),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TEAMS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 10),
          _sidebarTeamTile(state, null, 'All teams', null),
          if (showCapstone) teamSection('CAPSTONE TEAMS', capstoneTeams),
          if (showPit) teamSection('PIT TEAMS', pitTeams),
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
    RepositoryAuditState state,
    String? teamId,
    String label,
    String? subtitle, {
    String track = '',
  }) {
    final selected = (teamId ?? '') == state.teamId;
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: state.isSaving
            ? null
            : () {
                if (teamId == null) {
                  ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(clearTeam: true);
                } else {
                  ref
                      .read(repositoryAuditProvider.notifier)
                      .fetchEntries(teamId: teamId, clearDeliverable: true);
                }
              },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? AppColors.maroon : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color:
                        selected ? AppColors.maroon : const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color:
                            selected ? AppColors.maroon : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (track.isNotEmpty) _trackBadge(track),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.maroon,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _trackBadge(track),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (level.isNotEmpty) level,
                    if (project.isNotEmpty) 'Project: $project',
                  ].join(' · '),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Showing files for this team only.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_scopeKey(state) == 'admin' && teamId > 0) ...[
            OutlinedButton.icon(
              onPressed: state.isSaving
                  ? null
                  : () async {
                      final stage = state.stage.isNotEmpty
                          ? state.stage
                          : (state.groupedByStage.isNotEmpty
                              ? state.groupedByStage.first['stage']?.toString() ?? 'Concept Proposal'
                              : 'Concept Proposal');
                      final success = await ref
                          .read(capstoneDeliverablesProvider.notifier)
                          .unlockDeliverables(
                            teamId: teamId,
                            stageLabel: stage,
                          );
                      if (success && mounted) {
                        showInfoToast(
                          context,
                          'Deliverable unlock status updated for $name ($stage).',
                        );
                        ref.read(repositoryAuditProvider.notifier).fetchEntries();
                      }
                    },
              icon: const Icon(Icons.lock_open_outlined, size: 15),
              label: const Text('Unlock Deliverables'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.maroon,
                side: const BorderSide(color: AppColors.maroon),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                visualDensity: VisualDensity.compact,
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

  Widget _buildAllTeamsBrowsePanel(RepositoryAuditState state) {
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
        'Repository deliverables',
        const Color(0xFFF5F3FF),
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
        'Repository',
        const Color(0xFFFFF7ED),
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
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        stage.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.6,
        ),
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
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
