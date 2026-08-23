import 'package:flutter/material.dart';

import '../widgets/defensys_admin_shell.dart';

/// Elevated Preflight Review Table for Student Teams Bulk Import.
/// Provides rich, interactive cards for validating, editing, and resolving
/// team rosters, leadership designation, and advisor assignments.
class TeamBulkImportReviewTable extends StatelessWidget {
  const TeamBulkImportReviewTable({
    super.key,
    required this.rows,
    required this.previewRows,
    required this.isCapstoneAdmin,
    required this.pitLeadYear,
    required this.showIssuesOnly,
    this.searchQuery,
    required this.onRowChanged,
    required this.onDeleteRow,
    required this.onAddRow,
  });

  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> previewRows;
  final bool isCapstoneAdmin;
  final String? pitLeadYear;
  final bool showIssuesOnly;
  final String? searchQuery;
  final void Function(int index) onRowChanged;
  final void Function(int index) onDeleteRow;
  final VoidCallback onAddRow;

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

  @override
  Widget build(BuildContext context) {
    final indexed = <MapEntry<int, Map<String, dynamic>>>[];
    for (var i = 0; i < rows.length; i++) {
      indexed.add(MapEntry(i, rows[i]));
    }

    final query = (searchQuery ?? '').trim().toLowerCase();
    final visible = indexed.where((entry) {
      if (showIssuesOnly) {
        final preview = _previewForRow(entry.key + 1);
        if (preview != null && preview['ready'] == true) return false;
      }
      if (query.isNotEmpty) {
        final row = entry.value;
        final teamName = (row['team_name'] ?? '').toString().toLowerCase();
        final project = (row['project_title'] ?? '').toString().toLowerCase();
        final adviser =
            (row['adviser_name'] ?? row['adviser_id'] ?? '').toString().toLowerCase();
        final members = (row['member_ids'] is List)
            ? (row['member_ids'] as List).join(' ').toLowerCase()
            : (row['member_ids'] ?? '').toString().toLowerCase();
        final matches = teamName.contains(query) ||
            project.contains(query) ||
            adviser.contains(query) ||
            members.contains(query);
        if (!matches) return false;
      }
      return true;
    }).toList();

    visible.sort((a, b) {
      final aReady = _previewForRow(a.key + 1)?['ready'] == true;
      final bReady = _previewForRow(b.key + 1)?['ready'] == true;
      if (aReady == bReady) return a.key.compareTo(b.key);
      return aReady ? 1 : -1;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (visible.isEmpty)
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
                  showIssuesOnly
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
                  'Try clearing the search box or toggle off "Issues only".',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          )
        else
          ...visible.map((entry) => _rowCard(context, entry.key, entry.value)),
        const SizedBox(height: 16),
        _buildAddRowButton(),
      ],
    );
  }

  Map<String, dynamic>? _previewForRow(int rowNumber) {
    for (final item in previewRows) {
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

    final membersText = membersList.join(' | ');
    final leaderId = (row['leader_id']?.toString() ?? '').trim();

    final programLabel = preview?['program_label']?.toString().trim() ?? '';
    final capstoneProgram = programLabel.isNotEmpty
        ? programLabel
        : (row['level']?.toString().isNotEmpty == true
            ? row['level'].toString()
            : (row['year_level']?.toString().isNotEmpty == true
                ? row['year_level'].toString()
                : ''));

    final currentProgram = isCapstoneAdmin
        ? (capstoneProgram.isNotEmpty ? capstoneProgram : 'Capstone')
        : (pitLeadYear != null && pitLeadYear!.isNotEmpty
            ? (programLabel.isNotEmpty ? programLabel : '$pitLeadYear PIT')
            : 'PIT');

    final teamTitle = row['team_name']?.toString().trim() ?? '';
    final projectTitle = row['project_title']?.toString().trim() ?? '';
    final rowHash = '${teamTitle}_${projectTitle}_${leaderId}_$membersText';

    // Accent colors based on state
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
          // 1. Header Bar
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
                  onPressed: () => onDeleteRow(index),
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
                    // Row 1: Core Identification
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: _field(
                              label: 'Team Name',
                              icon: Icons.groups_2_outlined,
                              isRequired: true,
                              value: row['team_name']?.toString() ?? '',
                              hintText: 'e.g. Team NovaPath',
                              onChanged: (v) {
                                row['team_name'] = v;
                                onRowChanged(index);
                              },
                              key: ValueKey('field_name_${rowNumber}_${row['team_name']}'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 5,
                            child: _field(
                              label: isCapstoneAdmin ? 'Capstone Project Title' : 'PIT Project Title',
                              icon: Icons.lightbulb_outline_rounded,
                              isRequired: true,
                              value: row['project_title']?.toString() ?? '',
                              hintText: 'e.g. Campus Wayfinder Mobile App',
                              onChanged: (v) {
                                row['project_title'] = v;
                                onRowChanged(index);
                              },
                              key: ValueKey('field_proj_${rowNumber}_${row['project_title']}'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: _readOnlyField(
                              label: 'Program / Term',
                              icon: Icons.school_outlined,
                              value: currentProgram,
                            ),
                          ),
                          if (isCapstoneAdmin) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 4,
                              child: _field(
                                label: 'Adviser (Optional)',
                                icon: Icons.supervisor_account_outlined,
                                isRequired: false,
                                value: row['adviser_name']?.toString() ??
                                    row['adviser_id']?.toString() ??
                                    '',
                                hintText: 'Faculty adviser name or ID',
                                onChanged: (v) {
                                  row['adviser_name'] = v;
                                  onRowChanged(index);
                                },
                                key: ValueKey(
                                  'field_adviser_${rowNumber}_${row['adviser_name']}_${row['adviser_id']}',
                                ),
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
                            hintText: 'e.g. Team NovaPath',
                            onChanged: (v) {
                              row['team_name'] = v;
                              onRowChanged(index);
                            },
                            key: ValueKey('field_name_${rowNumber}_${row['team_name']}'),
                          ),
                          const SizedBox(height: 12),
                          _field(
                            label: isCapstoneAdmin ? 'Capstone Project Title' : 'PIT Project Title',
                            icon: Icons.lightbulb_outline_rounded,
                            isRequired: true,
                            value: row['project_title']?.toString() ?? '',
                            hintText: 'e.g. Campus Wayfinder Mobile App',
                            onChanged: (v) {
                              row['project_title'] = v;
                              onRowChanged(index);
                            },
                            key: ValueKey('field_proj_${rowNumber}_${row['project_title']}'),
                          ),
                          const SizedBox(height: 12),
                          _readOnlyField(
                            label: 'Program / Term',
                            icon: Icons.school_outlined,
                            value: currentProgram,
                          ),
                          if (isCapstoneAdmin) ...[
                            const SizedBox(height: 12),
                            _field(
                              label: 'Adviser (Optional)',
                              icon: Icons.supervisor_account_outlined,
                              isRequired: false,
                              value: row['adviser_name']?.toString() ??
                                  row['adviser_id']?.toString() ??
                                  '',
                              hintText: 'Faculty adviser name or ID',
                              onChanged: (v) {
                                row['adviser_name'] = v;
                                onRowChanged(index);
                              },
                              key: ValueKey(
                                'field_adviser_${rowNumber}_${row['adviser_name']}_${row['adviser_id']}',
                              ),
                            ),
                          ],
                        ],
                      ),

                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 14),

                    // Row 2: Members Roster & Leader
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _field(
                                  label: 'Team Members (Pipe "|" Separated)',
                                  icon: Icons.person_add_alt_1_outlined,
                                  isRequired: true,
                                  value: membersText,
                                  hintText: 'Member 1 | Member 2 | Member 3 | Member 4',
                                  onChanged: (v) {
                                    final split = v
                                        .split('|')
                                        .map((e) => e.trim())
                                        .where((e) => e.isNotEmpty)
                                        .toList();
                                    row['member_ids'] = split;
                                    onRowChanged(index);
                                  },
                                  key: ValueKey('field_members_${rowNumber}_$membersText'),
                                ),
                                if (membersList.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _buildMembersChipPreview(
                                    members: membersList,
                                    leaderId: leaderId,
                                    onSelectLeader: (name) {
                                      row['leader_id'] = name;
                                      onRowChanged(index);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _field(
                                  label: 'Designated Team Leader',
                                  icon: Icons.star_border_rounded,
                                  isRequired: true,
                                  value: leaderId,
                                  hintText: 'Must match one of the team members',
                                  onChanged: (v) {
                                    row['leader_id'] = v;
                                    onRowChanged(index);
                                  },
                                  key: ValueKey('field_leader_${rowNumber}_$leaderId'),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  membersList.isNotEmpty
                                      ? 'Tip: Tap any member chip on the left to set as leader.'
                                      : 'Leader is automatically verified against the members roster.',
                                  style: const TextStyle(fontSize: 11, color: _muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _field(
                            label: 'Team Members (Pipe "|" Separated)',
                            icon: Icons.person_add_alt_1_outlined,
                            isRequired: true,
                            value: membersText,
                            hintText: 'Member 1 | Member 2 | Member 3 | Member 4',
                            onChanged: (v) {
                              final split = v
                                  .split('|')
                                  .map((e) => e.trim())
                                  .where((e) => e.isNotEmpty)
                                  .toList();
                              row['member_ids'] = split;
                              onRowChanged(index);
                            },
                            key: ValueKey('field_members_${rowNumber}_$membersText'),
                          ),
                          if (membersList.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildMembersChipPreview(
                              members: membersList,
                              leaderId: leaderId,
                              onSelectLeader: (name) {
                                row['leader_id'] = name;
                                onRowChanged(index);
                              },
                            ),
                          ],
                          const SizedBox(height: 12),
                          _field(
                            label: 'Designated Team Leader',
                            icon: Icons.star_border_rounded,
                            isRequired: true,
                            value: leaderId,
                            hintText: 'Must match one of the team members',
                            onChanged: (v) {
                              row['leader_id'] = v;
                              onRowChanged(index);
                            },
                            key: ValueKey('field_leader_${rowNumber}_$leaderId'),
                          ),
                        ],
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

  Widget _buildMembersChipPreview({
    required List<String> members,
    required String leaderId,
    required ValueChanged<String> onSelectLeader,
  }) {
    final cleanLeader = leaderId.trim().toLowerCase();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: members.map((member) {
        final isLeader = cleanLeader.isNotEmpty &&
            member.trim().toLowerCase() == cleanLeader;

        return Tooltip(
          message: isLeader ? 'Current Team Leader' : 'Click to designate as Team Leader',
          child: InkWell(
            onTap: isLeader ? null : () => onSelectLeader(member),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isLeader ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isLeader ? const Color(0xFFFECACA) : const Color(0xFFCBD5E1),
                  width: isLeader ? 1.2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLeader ? Icons.star_rounded : Icons.person_rounded,
                    size: 13,
                    color: isLeader ? _maroon : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    member,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isLeader ? FontWeight.w800 : FontWeight.w600,
                      color: isLeader ? _maroon : _ink,
                    ),
                  ),
                  if (isLeader) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _maroon,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'LEADER',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
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
            const SizedBox(width: 5),
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
            const SizedBox(width: 5),
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

  Widget _readOnlyField({
    required String label,
    required IconData icon,
    required String value,
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
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _line),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddRowButton() {
    return InkWell(
      onTap: onAddRow,
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
