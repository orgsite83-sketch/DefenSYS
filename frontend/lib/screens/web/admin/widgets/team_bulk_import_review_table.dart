import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../widgets/defensys_admin_shell.dart';

class _AdviserCandidate {
  final String name;
  final String? id;
  final String subtitle;

  const _AdviserCandidate({
    required this.name,
    this.id,
    this.subtitle = '',
  });
}

class _StudentCandidate {
  final String name;
  final String? id;
  final String subtitle;

  const _StudentCandidate({
    required this.name,
    this.id,
    this.subtitle = '',
  });
}

/// Elevated Preflight Review Table for Student Teams Bulk Import.
/// Clean, professional review cards with searchable faculty adviser picker,
/// 4-member capacity safety, and deliberate leader designation.
class TeamBulkImportReviewTable extends StatefulWidget {
  const TeamBulkImportReviewTable({
    super.key,
    required this.rows,
    required this.previewRows,
    required this.isCapstoneAdmin,
    required this.pitLeadYear,
    required this.showIssuesOnly,
    this.searchQuery,
    this.sectionFilter,
    this.adviserFilter,
    this.groupBy = 'none',
    required this.onRowChanged,
    required this.onDeleteRow,
    required this.onAddRow,
    this.adviserOptions,
    this.sectionOptions,
    this.studentOptions,
    this.onSectionAdded,
  });

  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> previewRows;
  final bool isCapstoneAdmin;
  final String? pitLeadYear;
  final bool showIssuesOnly;
  final String? searchQuery;
  final String? sectionFilter;
  final String? adviserFilter;
  final String groupBy; // 'none' | 'section' | 'adviser'
  final void Function(int index) onRowChanged;
  final void Function(int index) onDeleteRow;
  final VoidCallback onAddRow;
  final List<dynamic>? adviserOptions;
  final List<String>? sectionOptions;
  final List<dynamic>? studentOptions;
  final void Function(String newSection)? onSectionAdded;

  @override
  State<TeamBulkImportReviewTable> createState() => _TeamBulkImportReviewTableState();
}

class _TeamBulkImportReviewTableState extends State<TeamBulkImportReviewTable> {
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _line = Color(0xFFE2E8F0);
  static const _green = Color(0xFF15803D);
  static const _greenBg = Color(0xFFECFDF5);
  static const _greenBorder = Color(0xFFA7F3D0);
  static const _red = Color(0xFFB91C1C);
  static const _redBg = Color(0xFFFEF2F2);
  static const _redBorder = Color(0xFFFECACA);
  static const _amber = Color(0xFFB45309);
  static const _amberBg = Color(0xFFFFFBEB);
  static const _amberBorder = Color(0xFFFDE68A);

  int _pageSize = 5; // Default limit 5 teams per page to prevent long vertical scrolling
  int _currentPage = 0;
  final Set<String> _customSections = {};

  @override
  Widget build(BuildContext context) {
    final indexed = <MapEntry<int, Map<String, dynamic>>>[];
    for (var i = 0; i < widget.rows.length; i++) {
      indexed.add(MapEntry(i, widget.rows[i]));
    }

    final query = (widget.searchQuery ?? '').trim().toLowerCase();
    final visible = indexed.where((entry) {
      final row = entry.value;
      final preview = _previewForRow(entry.key + 1);

      if (widget.showIssuesOnly) {
        if (preview != null && preview['ready'] == true) return false;
      }

      // Section filter
      if (widget.sectionFilter != null && widget.sectionFilter!.isNotEmpty && widget.sectionFilter != 'all') {
        final sec = (row['section'] ?? preview?['section'] ?? '').toString().trim();
        if (widget.sectionFilter == '_none_') {
          if (sec.isNotEmpty) return false;
        } else if (sec.toLowerCase() != widget.sectionFilter!.toLowerCase()) {
          return false;
        }
      }

      // Adviser filter
      if (widget.adviserFilter != null && widget.adviserFilter!.isNotEmpty && widget.adviserFilter != 'all') {
        final adv = (row['adviser_name'] ?? row['adviser_id'] ?? preview?['adviser_name'] ?? '').toString().trim();
        if (widget.adviserFilter == 'with_adviser') {
          if (adv.isEmpty) return false;
        } else if (widget.adviserFilter == 'without_adviser') {
          if (adv.isNotEmpty) return false;
        } else {
          if (adv.toLowerCase() != widget.adviserFilter!.toLowerCase()) return false;
        }
      }

      if (query.isNotEmpty) {
        final teamName = (row['team_name'] ?? '').toString().toLowerCase();
        final project = (row['project_title'] ?? '').toString().toLowerCase();
        final section = (row['section'] ?? preview?['section'] ?? '').toString().toLowerCase();
        final adviser =
            (row['adviser_name'] ?? row['adviser_id'] ?? preview?['adviser_name'] ?? '').toString().toLowerCase();
        final members = (row['member_ids'] is List)
            ? (row['member_ids'] as List).join(' ').toLowerCase()
            : (row['member_ids'] ?? '').toString().toLowerCase();
        final matches = teamName.contains(query) ||
            project.contains(query) ||
            section.contains(query) ||
            adviser.contains(query) ||
            members.contains(query);
        if (!matches) return false;
      }
      return true;
    }).toList();

    final totalItems = visible.length;
    final totalPages = _pageSize > 0 ? (totalItems / _pageSize).ceil() : 1;
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }
    if (_currentPage < 0) _currentPage = 0;

    final startIndex = _pageSize > 0 ? _currentPage * _pageSize : 0;
    final endIndex = _pageSize > 0
        ? math.min(startIndex + _pageSize, totalItems)
        : totalItems;

    final List<Widget> bodyContent = [];

    if (visible.isEmpty) {
      bodyContent.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 32, color: _muted),
              const SizedBox(height: 10),
              Text(
                widget.showIssuesOnly
                    ? 'No teams currently have validation issues.'
                    : 'No staged teams match the current filter.',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try clearing the search box or choosing "All Sections" / "All Advisers".',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    } else if (widget.groupBy == 'section') {
      final pagedVisible = _pageSize > 0 && totalItems > 0
          ? visible.sublist(startIndex, endIndex)
          : visible;
      final groups = <String, List<MapEntry<int, Map<String, dynamic>>>>{};
      for (final item in pagedVisible) {
        final sec = (item.value['section'] ?? _previewForRow(item.key + 1)?['section'] ?? '')
            .toString()
            .trim();
        final groupKey = sec.isNotEmpty ? 'Section $sec' : 'Unassigned Section';
        groups.putIfAbsent(groupKey, () => []).add(item);
      }
      for (final grp in groups.entries) {
        final readyInGroup = grp.value.where((e) => _previewForRow(e.key + 1)?['ready'] == true).length;
        bodyContent.add(
          _buildGroupHeader(
            icon: Icons.meeting_room_outlined,
            title: grp.key,
            count: grp.value.length,
            readyCount: readyInGroup,
            color: const Color(0xFF0284C7),
          ),
        );
        bodyContent.addAll(grp.value.map((entry) => _rowCard(context, entry.key, entry.value)));
      }
    } else if (widget.groupBy == 'adviser') {
      final pagedVisible = _pageSize > 0 && totalItems > 0
          ? visible.sublist(startIndex, endIndex)
          : visible;
      final groups = <String, List<MapEntry<int, Map<String, dynamic>>>>{};
      for (final item in pagedVisible) {
        final adv = (item.value['adviser_name'] ?? item.value['adviser_id'] ?? _previewForRow(item.key + 1)?['adviser_name'] ?? '')
            .toString()
            .trim();
        final groupKey = adv.isNotEmpty ? 'Adviser: $adv' : 'No Adviser Assigned';
        groups.putIfAbsent(groupKey, () => []).add(item);
      }
      for (final grp in groups.entries) {
        final readyInGroup = grp.value.where((e) => _previewForRow(e.key + 1)?['ready'] == true).length;
        bodyContent.add(
          _buildGroupHeader(
            icon: Icons.supervisor_account_outlined,
            title: grp.key,
            count: grp.value.length,
            readyCount: readyInGroup,
            color: const Color(0xFF7C3AED),
          ),
        );
        bodyContent.addAll(grp.value.map((entry) => _rowCard(context, entry.key, entry.value)));
      }
    } else {
      visible.sort((a, b) {
        final aReady = _previewForRow(a.key + 1)?['ready'] == true;
        final bReady = _previewForRow(b.key + 1)?['ready'] == true;
        if (aReady == bReady) return a.key.compareTo(b.key);
        return aReady ? 1 : -1;
      });
      final pagedVisible = _pageSize > 0 && totalItems > 0
          ? visible.sublist(startIndex, endIndex)
          : visible;
      bodyContent.addAll(pagedVisible.map((entry) => _rowCard(context, entry.key, entry.value)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (totalItems > 0)
          _buildPaginationBar(
            totalItems: totalItems,
            totalPages: totalPages,
            startIndex: startIndex,
            endIndex: endIndex,
            isTop: true,
          ),
        ...bodyContent,
        if (totalItems > 0)
          _buildPaginationBar(
            totalItems: totalItems,
            totalPages: totalPages,
            startIndex: startIndex,
            endIndex: endIndex,
            isTop: false,
          ),
        const SizedBox(height: 12),
        _buildAddRowButton(),
      ],
    );
  }

  Widget _buildGroupHeader({
    required IconData icon,
    required String title,
    required int count,
    required int readyCount,
    required Color color,
  }) {
    final issuesCount = count - readyCount;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: DefensysUi.textDark,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Text(
              '$count team${count == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
              ),
            ),
          ),
          const Spacer(),
          Text(
            readyCount == count
                ? 'All $count ready'
                : '$readyCount ready${issuesCount > 0 ? ' · $issuesCount need fix' : ''}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: readyCount == count ? const Color(0xFF16A34A) : const Color(0xFFD97706),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _previewForRow(int rowNumber) {
    for (final item in widget.previewRows) {
      if (item['row'] == rowNumber) {
        return item;
      }
    }
    return null;
  }

  Widget _rowCard(BuildContext context, int index, Map<String, dynamic> row) {
    final rowNumber = index + 1;
    final preview = _previewForRow(rowNumber);
    final ready = preview?['ready'] == true;
    final issues = (preview?['issues'] as List? ?? const [])
        .map((item) => item.toString())
        .toList();
    final warnings = (preview?['warnings'] as List? ?? const [])
        .map((item) => item.toString())
        .toList();

    final membersList = (row['member_ids'] is List)
        ? (row['member_ids'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : (row['member_ids']?.toString() ?? '')
            .split('|')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    final leaderId = (row['leader_id']?.toString() ?? '').trim();

    final programLabel = preview?['program_label']?.toString().trim() ?? '';
    final capstoneProgram = programLabel.isNotEmpty
        ? programLabel
        : (row['level']?.toString().isNotEmpty == true
            ? row['level'].toString()
            : (row['year_level']?.toString().isNotEmpty == true
                ? row['year_level'].toString()
                : ''));

    final currentProgram = widget.isCapstoneAdmin
        ? (capstoneProgram.isNotEmpty ? capstoneProgram : 'Capstone')
        : (widget.pitLeadYear != null && widget.pitLeadYear!.isNotEmpty
            ? (programLabel.isNotEmpty ? programLabel : '${widget.pitLeadYear} PIT')
            : 'PIT');

    final teamTitle = row['team_name']?.toString().trim() ?? '';
    final projectTitle = row['project_title']?.toString().trim() ?? '';
    final sectionValue = (row['section'] ?? preview?['section'] ?? '').toString().trim();
    final adviserValue = (row['adviser_name'] ?? row['adviser_id'] ?? preview?['adviser_name'] ?? '').toString().trim();
    final rowHash = '${teamTitle}_${projectTitle}_${sectionValue}_${adviserValue}_${leaderId}_${membersList.join(',')}';

    final borderColor = ready
        ? const Color(0xFF10B981)
        : (issues.isNotEmpty ? const Color(0xFFEF4444) : const Color(0xFFCBD5E1));

    return Container(
      key: ValueKey('bulk_import_row_${index}_$rowHash'),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: ready || issues.isNotEmpty ? 1.4 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Bar: Row, Context Badges, Title, Status, and Delete
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: ready
                  ? const Color(0xFFF0FDF4)
                  : (issues.isNotEmpty
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFF8FAFC)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(
                bottom: BorderSide(
                  color: ready
                      ? _greenBorder
                      : (issues.isNotEmpty ? _redBorder : _line),
                ),
              ),
            ),
            child: Row(
              children: [
                // Team Index Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: ready
                        ? _green.withValues(alpha: 0.12)
                        : (issues.isNotEmpty
                            ? _red.withValues(alpha: 0.12)
                            : _maroon.withValues(alpha: 0.08)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Row $rowNumber',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: ready ? _green : (issues.isNotEmpty ? _red : _maroon),
                    ),
                  ),
                ),
                // Section Badge
                if (sectionValue.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.meeting_room_outlined, size: 12, color: Color(0xFF1D4ED8)),
                        const SizedBox(width: 4),
                        Text(
                          'Sec: $sectionValue',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Adviser Badge
                if (adviserValue.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.supervisor_account_outlined, size: 12, color: Color(0xFF6D28D9)),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            adviserValue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5B21B6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Program / Term Badge (promoted to header to keep inputs uncluttered)
                if (currentProgram.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school_outlined, size: 12, color: Color(0xFF475569)),
                        const SizedBox(width: 4),
                        Text(
                          currentProgram,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          teamTitle.isNotEmpty ? teamTitle : 'Untitled Team',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• Sheet row ${rowNumber + 1}',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _statusBadge(ready, issues.length, warnings.length),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Delete team row',
                  onPressed: () => widget.onDeleteRow(index),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFDC2626)),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

          // 2. Validation Issues / Warnings Alerts (if any)
          if (issues.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _redBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _redBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 15, color: _red),
                      const SizedBox(width: 8),
                      Text(
                        '${issues.length} issue${issues.length == 1 ? '' : 's'} require correction:',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...issues.map(
                    (issue) => Padding(
                      padding: const EdgeInsets.only(left: 23, bottom: 2),
                      child: Text(
                        '• $issue',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF7F1D1D),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (warnings.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _amberBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _amberBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 15, color: _amber),
                      const SizedBox(width: 8),
                      Text(
                        '${warnings.length} warning${warnings.length == 1 ? '' : 's'}:',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...warnings.map(
                    (warn) => Padding(
                      padding: const EdgeInsets.only(left: 23, bottom: 2),
                      child: Text(
                        '• $warn',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF78350F),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 3. Form Fields Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 840;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Core Identification & Academic Assignments
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _field(
                              label: 'Team Name',
                              icon: Icons.groups_2_outlined,
                              isRequired: true,
                              value: row['team_name']?.toString() ?? '',
                              hintText: 'e.g. Team SkyLedger',
                              onChanged: (v) {
                                row['team_name'] = v;
                                widget.onRowChanged(index);
                              },
                              key: ValueKey('field_name_${rowNumber}_${row['team_name']}'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 4,
                            child: _field(
                              label: widget.isCapstoneAdmin ? 'Capstone Project Title' : 'PIT Project Title',
                              icon: Icons.lightbulb_outline_rounded,
                              isRequired: true,
                              value: row['project_title']?.toString() ?? '',
                              hintText: 'e.g. Alumni Career Tracker',
                              onChanged: (v) {
                                row['project_title'] = v;
                                widget.onRowChanged(index);
                              },
                              key: ValueKey('field_proj_${rowNumber}_${row['project_title']}'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: _buildSectionSelector(
                              index: index,
                              rowNumber: rowNumber,
                              row: row,
                              sectionValue: sectionValue,
                            ),
                          ),
                          if (widget.isCapstoneAdmin) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: _buildAdviserField(
                                context: context,
                                index: index,
                                rowNumber: rowNumber,
                                adviserValue: adviserValue,
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      Column(
                        children: [
                          _field(
                            label: 'Team Name',
                            icon: Icons.groups_2_outlined,
                            isRequired: true,
                            value: row['team_name']?.toString() ?? '',
                            hintText: 'e.g. Team SkyLedger',
                            onChanged: (v) {
                              row['team_name'] = v;
                              widget.onRowChanged(index);
                            },
                            key: ValueKey('field_name_${rowNumber}_${row['team_name']}'),
                          ),
                          const SizedBox(height: 12),
                          _field(
                            label: widget.isCapstoneAdmin ? 'Capstone Project Title' : 'PIT Project Title',
                            icon: Icons.lightbulb_outline_rounded,
                            isRequired: true,
                            value: row['project_title']?.toString() ?? '',
                            hintText: 'e.g. Alumni Career Tracker',
                            onChanged: (v) {
                              row['project_title'] = v;
                              widget.onRowChanged(index);
                            },
                            key: ValueKey('field_proj_${rowNumber}_${row['project_title']}'),
                          ),
                          const SizedBox(height: 12),
                          _buildSectionSelector(
                            index: index,
                            rowNumber: rowNumber,
                            row: row,
                            sectionValue: sectionValue,
                          ),
                          if (widget.isCapstoneAdmin) ...[
                            const SizedBox(height: 12),
                            _buildAdviserField(
                              context: context,
                              index: index,
                              rowNumber: rowNumber,
                              adviserValue: adviserValue,
                            ),
                          ],
                        ],
                      ),

                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 16),

                    // Row 2: Interactive Team Roster & Leader Studio (Max 4 limit)
                    _buildRosterStudio(
                      context: context,
                      index: index,
                      rowNumber: rowNumber,
                      row: row,
                      membersList: membersList,
                      leaderId: leaderId,
                      teamTitle: teamTitle,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Interactive Team Roster Studio with max-4 member capacity enforcement,
  /// 1-click leader designation, and safe, deliberate member management.
  Widget _buildRosterStudio({
    required BuildContext context,
    required int index,
    required int rowNumber,
    required Map<String, dynamic> row,
    required List<String> membersList,
    required String leaderId,
    required String teamTitle,
  }) {
    final cleanLeader = leaderId.trim().toLowerCase();
    final hasLeader = cleanLeader.isNotEmpty &&
        membersList.any((m) => m.trim().toLowerCase() == cleanLeader);
    final isMaxCapacity = membersList.length >= 4;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Studio Bar Header
          Row(
            children: [
              const Icon(Icons.people_alt_outlined, size: 15, color: DefensysUi.textDark),
              const SizedBox(width: 7),
              const Text(
                'Team Members',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: DefensysUi.textDark,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(width: 8),
              // Capacity Indicator: 4/4 (Max) or count
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isMaxCapacity ? const Color(0xFFEFF6FF) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMaxCapacity ? const Color(0xFFBFDBFE) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Text(
                  isMaxCapacity ? '4/4 (Max)' : '${membersList.length}/4',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isMaxCapacity ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Leadership designation status pill
              if (hasLeader) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars_rounded, size: 13, color: _maroon),
                      const SizedBox(width: 4),
                      Text(
                        'Leader: $leaderId',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _maroon,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFFD97706)),
                    const SizedBox(width: 4),
                    Text(
                      membersList.isEmpty
                          ? 'No members added yet'
                          : 'Tap star on any member to designate as Leader',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Member Cards + Add Member Picker (if under capacity)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...membersList.map((member) {
                final isLeader = cleanLeader.isNotEmpty &&
                    member.trim().toLowerCase() == cleanLeader;

                return _buildMemberCard(
                  context: context,
                  member: member,
                  isLeader: isLeader,
                  onDesignateLeader: () {
                    setState(() {
                      row['leader_id'] = member;
                    });
                    widget.onRowChanged(index);
                  },
                  onRemove: () => _showRemoveMemberConfirmDialog(
                    context: context,
                    index: index,
                    member: member,
                    currentMembers: membersList,
                    teamName: teamTitle,
                  ),
                );
              }),

              // Add Member button ONLY if under 4 members
              if (!isMaxCapacity)
                InkWell(
                  onTap: () => _showAddMemberSearchDialog(
                    context: context,
                    index: index,
                    currentMembers: membersList,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add_alt_rounded, size: 14, color: _maroon),
                        SizedBox(width: 5),
                        Text(
                          'Add Member',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _maroon,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Individual member card featuring 1-click leader designation and deliberate safe remove
  Widget _buildMemberCard({
    required BuildContext context,
    required String member,
    required bool isLeader,
    required VoidCallback onDesignateLeader,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
      decoration: BoxDecoration(
        color: isLeader ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLeader ? const Color(0xFFF87171) : const Color(0xFFCBD5E1),
          width: isLeader ? 1.4 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: isLeader ? 'Current Team Leader' : 'Click star to designate as Leader',
            child: InkWell(
              onTap: isLeader ? null : onDesignateLeader,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  isLeader ? Icons.stars_rounded : Icons.star_border_rounded,
                  size: 16,
                  color: isLeader ? _maroon : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            member,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isLeader ? FontWeight.w800 : FontWeight.w600,
              color: isLeader ? const Color(0xFF7F1D1D) : DefensysUi.textDark,
            ),
          ),
          if (isLeader) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: _maroon,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'LEADER',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
          const SizedBox(width: 6),
          Tooltip(
            message: 'Remove member',
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Safe Confirmation Dialog to prevent accidental misclick deletions
  Future<void> _showRemoveMemberConfirmDialog({
    required BuildContext context,
    required int index,
    required String member,
    required List<String> currentMembers,
    required String teamName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.person_remove_outlined, color: Color(0xFFDC2626), size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Remove Team Member',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: DefensysUi.textDark),
              ),
            ),
          ],
        ),
        content: Text.rich(
          TextSpan(
            text: 'Are you sure you want to remove ',
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
            children: [
              TextSpan(
                text: member,
                style: const TextStyle(fontWeight: FontWeight.w800, color: DefensysUi.textDark),
              ),
              TextSpan(
                text: ' from ${teamName.isNotEmpty ? teamName : 'this team'}?',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Remove Member', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        final updated = List<String>.from(currentMembers)..remove(member);
        widget.rows[index]['member_ids'] = updated;
        final currentLeader = (widget.rows[index]['leader_id']?.toString() ?? '').trim().toLowerCase();
        if (currentLeader == member.trim().toLowerCase()) {
          widget.rows[index]['leader_id'] = updated.isNotEmpty ? updated.first : '';
        }
      });
      widget.onRowChanged(index);
    }
  }

  /// Searchable Student Picker Dialog when adding a team member (< 4 members)
  Future<void> _showAddMemberSearchDialog({
    required BuildContext context,
    required int index,
    required List<String> currentMembers,
  }) async {
    // 1. Collect student candidates from import rows and loaded studentOptions
    final Map<String, _StudentCandidate> candidatesMap = {};

    if (widget.studentOptions != null) {
      for (final st in widget.studentOptions!) {
        if (st is Map<String, dynamic>) {
          final name = (st['name'] ?? st['full_name'] ?? '').toString().trim();
          final id = (st['student_id'] ?? st['username'] ?? '').toString().trim();
          final sec = (st['section'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            candidatesMap[name.toLowerCase()] = _StudentCandidate(
              name: name,
              id: id.isNotEmpty ? id : null,
              subtitle: sec.isNotEmpty ? 'Sec: $sec · $id' : id,
            );
          }
        }
      }
    }

    // Also include students from current import batch
    for (final r in widget.rows) {
      final list = (r['member_ids'] is List)
          ? (r['member_ids'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
          : (r['member_ids']?.toString() ?? '').split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      for (final m in list) {
        if (!candidatesMap.containsKey(m.toLowerCase())) {
          candidatesMap[m.toLowerCase()] = _StudentCandidate(
            name: m,
            subtitle: 'From imported sheet',
          );
        }
      }
    }

    // Exclude students already on this team
    final existingLower = currentMembers.map((e) => e.trim().toLowerCase()).toSet();
    final available = candidatesMap.values
        .where((c) => !existingLower.contains(c.name.toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    String filter = '';

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final q = filter.trim().toLowerCase();
            final filtered = available.where((c) {
              return c.name.toLowerCase().contains(q) ||
                  (c.id != null && c.id!.toLowerCase().contains(q)) ||
                  c.subtitle.toLowerCase().contains(q);
            }).toList();

            final hasExactMatch = available.any((c) => c.name.toLowerCase() == q);

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              surfaceTintColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_add_alt_1_rounded, color: _maroon, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Add Member (${currentMembers.length}/4)',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: _muted),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search imported students by name...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _muted),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _line)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _line)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _maroon, width: 1.5)),
                        ),
                        onChanged: (val) => setModalState(() => filter = val),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView(
                          children: [
                            if (q.isNotEmpty && !hasExactMatch)
                              ListTile(
                                dense: true,
                                leading: const CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Color(0xFFFEF2F2),
                                  child: Icon(Icons.add_rounded, size: 16, color: _maroon),
                                ),
                                title: Text(
                                  'Add "$filter"',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _maroon),
                                ),
                                subtitle: const Text('Add as new member name', style: TextStyle(fontSize: 11, color: _muted)),
                                onTap: () {
                                  _addStudentToTeam(index, currentMembers, filter.trim());
                                  Navigator.of(dialogCtx).pop();
                                },
                              ),
                            if (filtered.isEmpty && (q.isEmpty || hasExactMatch))
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Text('No available students found.', style: TextStyle(fontSize: 12.5, color: _muted)),
                                ),
                              ),
                            ...filtered.map((st) {
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  child: Text(
                                    st.name.isNotEmpty ? st.name[0].toUpperCase() : '?',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                                  ),
                                ),
                                title: Text(st.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                                subtitle: st.subtitle.isNotEmpty
                                    ? Text(st.subtitle, style: const TextStyle(fontSize: 11, color: _muted))
                                    : null,
                                trailing: const Icon(Icons.add_circle_outline_rounded, size: 18, color: _maroon),
                                onTap: () {
                                  _addStudentToTeam(index, currentMembers, st.name);
                                  Navigator.of(dialogCtx).pop();
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _addStudentToTeam(int index, List<String> currentMembers, String studentName) {
    if (studentName.isEmpty) return;
    if (currentMembers.length >= 4) return;

    final lower = studentName.toLowerCase();
    if (!currentMembers.any((m) => m.trim().toLowerCase() == lower)) {
      final updated = List<String>.from(currentMembers)..add(studentName);
      setState(() {
        widget.rows[index]['member_ids'] = updated;
        final currentLeader = (widget.rows[index]['leader_id']?.toString() ?? '').trim();
        if (currentLeader.isEmpty) {
          widget.rows[index]['leader_id'] = studentName;
        }
      });
      widget.onRowChanged(index);
    }
  }

  /// Clean, professional Adviser Selector that opens a Searchable Faculty Dialog
  /// (Strictly registered faculty users who will evaluate the team)
  Widget _buildAdviserField({
    required BuildContext context,
    required int index,
    required int rowNumber,
    required String adviserValue,
  }) {
    final hasAdviser = adviserValue.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.supervisor_account_outlined, size: 13, color: Color(0xFF64748B)),
            SizedBox(width: 5),
            Text(
              'Adviser (Optional)',
              style: TextStyle(
                color: Color(0xFF334155),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          key: ValueKey('adviser_selector_$rowNumber'),
          onTap: () => _showAdviserSearchDialog(context, index, adviserValue),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9.5),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasAdviser ? adviserValue : 'Select Faculty Adviser...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasAdviser ? _ink : const Color(0xFF94A3B8),
                      fontSize: 13,
                      fontWeight: hasAdviser ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down_rounded, size: 20, color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Searchable Faculty Adviser Dialog (includes a clean search bar)
  Future<void> _showAdviserSearchDialog(
    BuildContext context,
    int index,
    String currentAdviser,
  ) async {
    final Map<String, _AdviserCandidate> candidatesMap = {};

    if (widget.adviserOptions != null) {
      for (final adv in widget.adviserOptions!) {
        if (adv is Map<String, dynamic>) {
          final name = (adv['name'] ?? adv['full_name'] ?? '').toString().trim();
          final username = (adv['username'] ?? '').toString().trim();
          final id = adv['id']?.toString();
          if (name.isNotEmpty) {
            candidatesMap[name.toLowerCase()] = _AdviserCandidate(
              name: name,
              id: id,
              subtitle: username.isNotEmpty ? '@$username' : '',
            );
          }
        } else if (adv is String && adv.trim().isNotEmpty) {
          candidatesMap[adv.trim().toLowerCase()] = _AdviserCandidate(
            name: adv.trim(),
          );
        }
      }
    }

    for (final r in widget.rows) {
      final a = (r['adviser_name'] ?? r['adviser_id'] ?? '').toString().trim();
      if (a.isNotEmpty && !candidatesMap.containsKey(a.toLowerCase())) {
        candidatesMap[a.toLowerCase()] = _AdviserCandidate(
          name: a,
          subtitle: 'From imported sheet',
        );
      }
    }

    final sortedAdvisers = candidatesMap.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    String filter = '';

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final q = filter.trim().toLowerCase();
            final filtered = sortedAdvisers.where((c) {
              return c.name.toLowerCase().contains(q) ||
                  c.subtitle.toLowerCase().contains(q);
            }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              surfaceTintColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.supervisor_account_outlined, color: _maroon, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Assign Faculty Adviser',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: _muted),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search faculty adviser name...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _muted),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _line)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _line)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _maroon, width: 1.5)),
                        ),
                        onChanged: (val) => setModalState(() => filter = val),
                      ),
                      const SizedBox(height: 8),
                      // Clear / Unassigned Option
                      ListTile(
                        dense: true,
                        leading: const CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(0xFFF1F5F9),
                          child: Icon(Icons.person_off_outlined, size: 15, color: _muted),
                        ),
                        title: const Text('Unassigned / No Adviser', style: TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w600)),
                        trailing: currentAdviser.isEmpty ? const Icon(Icons.check_rounded, color: _green, size: 18) : null,
                        onTap: () {
                          setState(() {
                            widget.rows[index]['adviser_name'] = '';
                            widget.rows[index]['adviser_id'] = '';
                          });
                          widget.onRowChanged(index);
                          Navigator.of(dialogCtx).pop();
                        },
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      const SizedBox(height: 4),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Text('No faculty advisers match the search.', style: TextStyle(fontSize: 12.5, color: _muted)),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (ctx, i) {
                                  final adv = filtered[i];
                                  final isSelected = adv.name.toLowerCase() == currentAdviser.trim().toLowerCase();

                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: isSelected ? _maroon.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
                                      child: Icon(Icons.person_outline_rounded, size: 16, color: isSelected ? _maroon : const Color(0xFF64748B)),
                                    ),
                                    title: Text(
                                      adv.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                        color: isSelected ? _maroon : _ink,
                                      ),
                                    ),
                                    subtitle: adv.subtitle.isNotEmpty
                                        ? Text(adv.subtitle, style: const TextStyle(fontSize: 11, color: _muted))
                                        : null,
                                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: _maroon, size: 18) : null,
                                    onTap: () {
                                      setState(() {
                                        widget.rows[index]['adviser_name'] = adv.name;
                                        widget.rows[index]['adviser_id'] = adv.id ?? adv.name;
                                      });
                                      widget.onRowChanged(index);
                                      Navigator.of(dialogCtx).pop();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Clean, professional Section Dropdown
  Widget _buildSectionSelector({
    required int index,
    required int rowNumber,
    required Map<String, dynamic> row,
    required String sectionValue,
  }) {
    final Set<String> distinctSections = {};
    if (widget.sectionOptions != null) {
      for (final s in widget.sectionOptions!) {
        final t = s.trim();
        if (t.isNotEmpty && t != 'all' && t != '_none_') distinctSections.add(t);
      }
    }
    for (final r in widget.rows) {
      final s = (r['section'] ?? '').toString().trim();
      if (s.isNotEmpty) distinctSections.add(s);
    }
    if (sectionValue.isNotEmpty) distinctSections.add(sectionValue);
    distinctSections.addAll(_customSections);

    final sortedSections = distinctSections.toList()..sort();

    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: '',
        child: Text('Unassigned', style: TextStyle(color: _muted, fontWeight: FontWeight.normal)),
      ),
      ...sortedSections.map(
        (sec) => DropdownMenuItem(
          value: sec,
          child: Text(sec, overflow: TextOverflow.ellipsis),
        ),
      ),
      const DropdownMenuItem(
        value: '__ADD_NEW__',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 14, color: _maroon),
            SizedBox(width: 6),
            Text('+ Add Section...', style: TextStyle(color: _maroon, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ];

    final selectedValue = distinctSections.contains(sectionValue)
        ? sectionValue
        : (sectionValue.isEmpty ? '' : sectionValue);

    return _dropdownField<String>(
      label: 'Section',
      icon: Icons.meeting_room_outlined,
      isRequired: false,
      value: selectedValue,
      items: items,
      labelTrailing: InkWell(
        key: ValueKey('add_section_btn_$rowNumber'),
        onTap: () => _showAddNewSectionDialog(context, index, row),
        borderRadius: BorderRadius.circular(4),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 12, color: _maroon),
              SizedBox(width: 2),
              Text(
                'Add',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _maroon,
                ),
              ),
            ],
          ),
        ),
      ),
      onChanged: (v) {
        if (v == '__ADD_NEW__') {
          _showAddNewSectionDialog(context, index, row);
          return;
        }
        setState(() {
          row['section'] = v ?? '';
        });
        widget.onRowChanged(index);
      },
      key: ValueKey('field_sec_dropdown_${rowNumber}_$selectedValue'),
    );
  }

  /// Dialog to add a new class section dynamically
  Future<void> _showAddNewSectionDialog(
    BuildContext context,
    int index,
    Map<String, dynamic> row,
  ) async {
    final textCtrl = TextEditingController();
    String? errorText;

    final newSection = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.add_business_outlined, color: _maroon, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Add Class Section',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the section name to assign to this team and make available for all other teams.',
                  style: TextStyle(fontSize: 12.5, color: _muted, height: 1.35),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('add_section_name_input'),
                  controller: textCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Section Name',
                    hintText: 'e.g. BSIT-4C, BSIT-4D',
                    errorText: errorText,
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _maroon, width: 1.5),
                    ),
                  ),
                  onSubmitted: (val) {
                    final trimmed = val.trim();
                    if (trimmed.isEmpty) {
                      setModalState(() => errorText = 'Section name cannot be empty');
                    } else {
                      Navigator.of(dialogCtx).pop(trimmed);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ),
              FilledButton(
                key: const ValueKey('submit_add_section_btn'),
                style: FilledButton.styleFrom(
                  backgroundColor: _maroon,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final trimmed = textCtrl.text.trim();
                  if (trimmed.isEmpty) {
                    setModalState(() => errorText = 'Section name cannot be empty');
                  } else {
                    Navigator.of(dialogCtx).pop(trimmed);
                  }
                },
                child: const Text('Add & Assign', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );

    if (newSection != null && newSection.isNotEmpty) {
      setState(() {
        _customSections.add(newSection);
        row['section'] = newSection;
      });
      widget.onSectionAdded?.call(newSection);
      widget.onRowChanged(index);
    }
  }

  Widget _statusBadge(bool ready, int issueCount, int warningCount) {
    if (ready) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _greenBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _greenBorder),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 13, color: _green),
            SizedBox(width: 5),
            Text(
              'Ready',
              style: TextStyle(
                color: _green,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    if (issueCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _redBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _redBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 13, color: _red),
            SizedBox(width: 5),
            Text(
              '$issueCount issue${issueCount == 1 ? '' : 's'}',
              style: const TextStyle(
                color: _red,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    if (warningCount > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _amberBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _amberBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 13, color: _amber),
            SizedBox(width: 5),
            Text(
              '$warningCount warning${warningCount == 1 ? '' : 's'}',
              style: const TextStyle(
                color: _amber,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: const Text(
        'Pending Review',
        style: TextStyle(
          color: _muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _dropdownField<T>({
    required String label,
    required IconData icon,
    required bool isRequired,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? hintText,
    Key? key,
    Widget? labelTrailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: const Color(0xFF64748B)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 3),
              const Text(
                '*',
                style: TextStyle(color: _maroon, fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ],
            if (labelTrailing != null) ...[
              const Spacer(),
              labelTrailing,
            ],
          ],
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          key: key,
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          style: const TextStyle(
            color: _ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _maroon, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required IconData icon,
    required bool isRequired,
    required String value,
    required String hintText,
    required ValueChanged<String> onChanged,
    Key? key,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: const Color(0xFF64748B)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 3),
              const Text(
                '*',
                style: TextStyle(color: _maroon, fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: key,
          initialValue: value,
          style: const TextStyle(
            color: _ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _maroon, width: 1.5),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildPaginationBar({
    required int totalItems,
    required int totalPages,
    required int startIndex,
    required int endIndex,
    required bool isTop,
  }) {
    return Container(
      margin: EdgeInsets.only(top: isTop ? 0 : 12, bottom: isTop ? 14 : 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 620;

          final infoWidget = Text(
            totalItems == 1
                ? 'Showing 1 team'
                : 'Showing ${startIndex + 1}–$endIndex of $totalItems staged teams',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          );

          final controlsWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Per page: ',
                style: TextStyle(fontSize: 11.5, color: _muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    key: ValueKey(isTop ? 'page_size_top' : 'page_size_bottom'),
                    value: _pageSize,
                    isDense: true,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _ink),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5')),
                      DropdownMenuItem(value: 10, child: Text('10')),
                      DropdownMenuItem(value: 20, child: Text('20')),
                      DropdownMenuItem(value: 0, child: Text('All')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _pageSize = val;
                          _currentPage = 0;
                        });
                      }
                    },
                  ),
                ),
              ),
              if (totalPages > 1) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  key: ValueKey(isTop ? 'prev_page_top' : 'prev_page_bottom'),
                  onPressed: _currentPage > 0
                      ? () => setState(() => _currentPage--)
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_left_rounded, size: 16),
                      Text('Prev', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    '${_currentPage + 1} / $totalPages',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _ink),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  key: ValueKey(isTop ? 'next_page_top' : 'next_page_bottom'),
                  onPressed: _currentPage < totalPages - 1
                      ? () => setState(() => _currentPage++)
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Next', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      Icon(Icons.chevron_right_rounded, size: 16),
                    ],
                  ),
                ),
              ],
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                infoWidget,
                const SizedBox(height: 8),
                controlsWidget,
              ],
            );
          }

          return Row(
            children: [
              infoWidget,
              const Spacer(),
              controlsWidget,
            ],
          );
        },
      ),
    );
  }

  Widget _buildAddRowButton() {
    return InkWell(
      onTap: () {
        widget.onAddRow();
        setState(() {
          if (_pageSize > 0) {
            _currentPage = (widget.rows.length / _pageSize).floor();
          }
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline_rounded, size: 16, color: _maroon),
            SizedBox(width: 8),
            Text(
              'Add New Team Row',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: _maroon,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
