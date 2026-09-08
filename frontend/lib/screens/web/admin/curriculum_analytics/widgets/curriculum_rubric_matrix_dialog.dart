import 'package:flutter/material.dart';
import '../../../../../theme/app_theme.dart';

/// Modal dialog providing the granular rubric criteria table for accreditation and syllabus review.
class CurriculumRubricMatrixDialog extends StatefulWidget {
  final List<Map<String, dynamic>> criteria;
  final String stageTitle;

  const CurriculumRubricMatrixDialog({
    super.key,
    required this.criteria,
    required this.stageTitle,
  });

  @override
  State<CurriculumRubricMatrixDialog> createState() => _CurriculumRubricMatrixDialogState();
}

class _CurriculumRubricMatrixDialogState extends State<CurriculumRubricMatrixDialog> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.criteria.where((c) {
      if (_searchQuery.isEmpty) return true;
      final name = c['name']?.toString().toLowerCase() ?? '';
      final stage = c['stage_name']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || stage.contains(query);
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.maroon.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.table_chart_rounded, color: AppColors.maroon, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Granular Rubric Criteria Matrix',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Individual scoring breakdown across Panelists, Advisers, and Peers (${widget.stageTitle})',
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search Bar
              TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search criteria name, defense stage, or syllabus topic...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                ),
              ),
              const SizedBox(height: 14),

              // Table Content
              Expanded(
                child: filtered.isEmpty
                    ? Container(
                        alignment: Alignment.center,
                        child: const Text(
                          'No criteria matching search.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                columnSpacing: 24,
                                horizontalMargin: 16,
                                dataRowMinHeight: 48,
                                dataRowMaxHeight: 56,
                                columns: const [
                                  DataColumn(label: Text('Criterion Name', style: TextStyle(fontWeight: FontWeight.w700))),
                                  DataColumn(label: Text('Stage', style: TextStyle(fontWeight: FontWeight.w700))),
                                  DataColumn(label: Text('Panelist', style: TextStyle(fontWeight: FontWeight.w700))),
                                  DataColumn(label: Text('Adviser', style: TextStyle(fontWeight: FontWeight.w700))),
                                  DataColumn(label: Text('Peer', style: TextStyle(fontWeight: FontWeight.w700))),
                                  DataColumn(label: Text('Average', style: TextStyle(fontWeight: FontWeight.w700))),
                                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w700))),
                                ],
                                rows: filtered.map((c) {
                                  final name = c['name']?.toString() ?? 'Criterion';
                                  final stage = c['stage_name']?.toString() ?? 'General';
                                  final evalBreakdown = c['evaluator_breakdown'] as Map<String, dynamic>?;

                                  String fmtScore(dynamic val) {
                                    if (val == null) return '—';
                                    final numVal = double.tryParse(val.toString());
                                    if (numVal == null) return '—';
                                    return '${numVal.toStringAsFixed(1)}%';
                                  }

                                  final panelStr = fmtScore(evalBreakdown?['panel']?['score']);
                                  final adviserStr = fmtScore(evalBreakdown?['adviser']?['score']);
                                  final peerStr = fmtScore(evalBreakdown?['peer']?['score']);

                                  final avgRaw = c['average_score'] ?? c['score'];
                                  final avgStr = fmtScore(avgRaw);
                                  final avgNum = double.tryParse(avgRaw?.toString() ?? '');

                                  final bool isProficient = avgNum != null && avgNum >= 75.0;

                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: 220,
                                          child: Text(
                                            name,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(stage, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
                                      DataCell(Text(panelStr, style: const TextStyle(fontSize: 12, color: Color(0xFF0EA5E9), fontWeight: FontWeight.w700))),
                                      DataCell(Text(adviserStr, style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w700))),
                                      DataCell(Text(peerStr, style: const TextStyle(fontSize: 12, color: Color(0xFF8B5CF6), fontWeight: FontWeight.w700))),
                                      DataCell(
                                        Text(
                                          avgStr,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                            color: avgNum != null
                                                ? (isProficient ? const Color(0xFF059669) : const Color(0xFFDC2626))
                                                : const Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isProficient
                                                ? const Color(0xFFECFDF5)
                                                : (avgNum != null ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9)),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            avgNum != null ? (isProficient ? 'Proficient' : 'Remediation') : 'Pending',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isProficient
                                                  ? const Color(0xFF047857)
                                                  : (avgNum != null ? const Color(0xFFB91C1C) : const Color(0xFF64748B)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 16),

              // Footer Action
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.maroon,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
