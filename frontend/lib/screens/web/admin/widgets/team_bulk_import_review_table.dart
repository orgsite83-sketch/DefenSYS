import 'package:flutter/material.dart';

import '../widgets/defensys_admin_shell.dart';

class TeamBulkImportReviewTable extends StatelessWidget {
  const TeamBulkImportReviewTable({
    super.key,
    required this.rows,
    required this.previewRows,
    required this.isCapstoneAdmin,
    required this.pitLeadYear,
    required this.showIssuesOnly,
    required this.onRowChanged,
    required this.onDeleteRow,
    required this.onAddRow,
  });

  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> previewRows;
  final bool isCapstoneAdmin;
  final String? pitLeadYear;
  final bool showIssuesOnly;
  final void Function(int index) onRowChanged;
  final void Function(int index) onDeleteRow;
  final VoidCallback onAddRow;

  static const _ink = DefensysUi.textDark;
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFDC2626);
  static const _amber = Color(0xFFD97706);
  @override
  Widget build(BuildContext context) {
    final indexed = <MapEntry<int, Map<String, dynamic>>>[];
    for (var i = 0; i < rows.length; i++) {
      indexed.add(MapEntry(i, rows[i]));
    }

    final visible = indexed.where((entry) {
      if (!showIssuesOnly) return true;
      final preview = _previewForRow(entry.key + 1);
      return preview == null || preview['ready'] != true;
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No rows to review.',
              style: TextStyle(color: Color(0xFF667085), fontSize: 13),
            ),
          )
        else
          ...visible.map((entry) => _rowCard(context, entry.key, entry.value)),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onAddRow,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add row'),
        ),
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
    final borderColor = ready ? _green : (issues.isEmpty ? const Color(0xFFE5E7EB) : _amber);
    final members = (row['member_ids'] as List? ?? const [])
        .map((item) => item.toString())
        .join(' | ');
    final programLabel = preview?['program_label']?.toString().trim() ?? '';
    final capstoneProgram = programLabel.isNotEmpty
        ? programLabel
        : 'Capstone · ${row['year_level']?.toString() ?? '3rd Year'}';

    return Container(
      key: ValueKey('bulk_import_row_$index'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: ready || issues.isNotEmpty ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Row $rowNumber · ${row['team_name']?.toString().isNotEmpty == true ? row['team_name'] : 'Untitled team'}',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sheet row ${rowNumber + 1}',
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _statusChip(ready, issues.length),
              IconButton(
                tooltip: 'Delete row',
                onPressed: () => onDeleteRow(index),
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: _red),
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...issues.map(
              (issue) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 14, color: _red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        issue,
                        style: const TextStyle(color: _red, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 900;
              final fields = <Widget>[
                _field('Team name', row['team_name']?.toString() ?? '', (v) {
                  row['team_name'] = v;
                  onRowChanged(index);
                }),
                _field('Project title', row['project_title']?.toString() ?? '', (v) {
                  row['project_title'] = v;
                  onRowChanged(index);
                }),
                if (isCapstoneAdmin)
                  _readOnlyChip('Program', capstoneProgram)
                else if (pitLeadYear != null && pitLeadYear!.isNotEmpty)
                  _readOnlyChip('Program', programLabel.isNotEmpty ? programLabel : '$pitLeadYear PIT'),
                _field('Members (| separated)', members, (v) {
                  row['member_ids'] = v
                      .split('|')
                      .map((item) => item.trim())
                      .where((item) => item.isNotEmpty)
                      .toList();
                  onRowChanged(index);
                }),
                _field('Leader', row['leader_id']?.toString() ?? '', (v) {
                  row['leader_id'] = v;
                  onRowChanged(index);
                }),
                if (isCapstoneAdmin)
                  _field('Adviser (optional)', row['adviser_id']?.toString() ?? '', (v) {
                    row['adviser_id'] = v;
                    onRowChanged(index);
                  }),
              ];

              if (narrow) {
                return Column(children: fields.map((w) => Padding(padding: const EdgeInsets.only(bottom: 10), child: w)).toList());
              }
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: fields
                    .map((w) => SizedBox(width: (constraints.maxWidth - 24) / 2, child: w))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _readOnlyChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(bool ready, int issueCount) {
    final color = ready ? _green : (issueCount > 0 ? _amber : const Color(0xFF98A2B3));
    final label = ready ? 'Ready' : (issueCount > 0 ? '$issueCount issue${issueCount == 1 ? '' : 's'}' : 'Pending');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _field(String label, String value, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: value,
          style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
