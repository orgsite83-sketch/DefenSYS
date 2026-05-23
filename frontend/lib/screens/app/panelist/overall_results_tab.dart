import 'package:flutter/material.dart';

const _primaryColor = Color(0xFF7F1D1D);
const _goldColor = Color(0xFFD97706);

class OverallResultsTab extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final bool loading;

  const OverallResultsTab({
    super.key,
    required this.results,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: _primaryColor));
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No graded teams yet.',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 8),
            const Text('Post grades to see results here.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader('Overall Panel Results'),
        const SizedBox(height: 4),
        Text(
          'Your panel scores for ${results.length} team${results.length != 1 ? "s" : ""}.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        ...results.asMap().entries.map((e) => _teamCard(e.key + 1, e.value)),
      ],
    );
  }

  Widget _teamCard(int rank, Map<String, dynamic> result) {
    final pct = (result['percentage'] as num?)?.toDouble() ?? 0;
    final total = (result['total'] as num?)?.toDouble() ?? 0;
    final max = (result['max'] as num?)?.toDouble() ?? 0;
    final teamStatus = result['teamStatus'] as String? ?? 'Pending';
    final level = result['level'] as String? ?? '';
    final criteria = result['criteria'] as List? ?? [];
    final memberGrades = result['memberGrades'] as List? ?? [];
    final weights = result['weights'] as Map<String, dynamic>? ?? {};
    final panelW = (weights['panel'] as num?)?.toInt() ?? 80;
    final peerW = (weights['peer'] as num?)?.toInt() ?? 20;

    final medalColors = [
      const Color(0xFFD97706),
      const Color(0xFF6B7280),
      const Color(0xFFB45309),
    ];
    final rankColor = rank <= 3 ? medalColors[rank - 1] : _primaryColor;

    final statusColor = teamStatus == 'Approved'
        ? Colors.green
        : teamStatus == 'Failed'
            ? Colors.red
            : Colors.orange;
    final statusLabel = teamStatus == 'Approved'
        ? 'Passed'
        : teamStatus == 'Failed'
            ? 'Failed'
            : 'Pending';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: rankColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('#$rank',
                        style: TextStyle(fontWeight: FontWeight.bold,
                            fontSize: 13, color: rankColor)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result['teamName'] ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(result['projectTitle'] ?? '—',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (level.isNotEmpty)
                        Text(level,
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${pct.toStringAsFixed(1)}%',
                        style: TextStyle(fontWeight: FontWeight.bold,
                            fontSize: 16, color: rankColor)),
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withOpacity(0.4)),
                      ),
                      child: Text(statusLabel,
                          style: TextStyle(fontSize: 10, color: statusColor,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Panel Score Bar ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Panel Score ($panelW%)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('${total.toStringAsFixed(1)} / ${max.toStringAsFixed(0)} pts',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.bold, color: _primaryColor)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          pct >= 75 ? Colors.green : pct >= 60 ? _goldColor : Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Criteria Breakdown ──
          if (criteria.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _subSectionLabel('Criteria Breakdown'),
            ),
            const SizedBox(height: 6),
            ...criteria.map((c) {
              final cName = c['criteriaName'] ?? '';
              final cScore = (c['score'] as num?)?.toDouble() ?? 0;
              final cMax = (c['max'] as num?)?.toDouble() ?? 1;
              final cPct = cMax > 0 ? cScore / cMax : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(cName,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
                    ),
                    Expanded(
                      flex: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: cPct.clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              cPct >= 0.85 ? const Color(0xFF10B981)
                                  : cPct >= 0.65 ? _goldColor
                                  : const Color(0xFFEF4444)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${cScore.toStringAsFixed(0)}/${cMax.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: _primaryColor)),
                  ],
                ),
              );
            }),
          ],

          // ── Member Final Grades ──
          if (memberGrades.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _subSectionLabel('Individual Final Grades'),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(flex: 3, child: Text('Member',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                  color: Color(0xFF6B7280)))),
                          Expanded(flex: 2, child: Text('Panel ($panelW%)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                  color: Color(0xFF6B7280)))),
                          Expanded(flex: 2, child: Text('Peer ($peerW%)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                  color: Color(0xFF6B7280)))),
                          const Expanded(flex: 2, child: Text('Final',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                  color: Color(0xFF6B7280)))),
                        ],
                      ),
                    ),
                    ...memberGrades.map((m) {
                      final name = m['name'] ?? '';
                      final isLeader = m['isLeader'] == true;
                      final panelContrib = (m['panelContrib'] as num?)?.toDouble();
                      final peerScore = m['peerScore'];
                      final peerMax = m['peerMax'];
                      final finalGrade = m['finalGrade'];
                      final hasFinish = finalGrade != null;
                      final fg = hasFinish ? (finalGrade as num).toDouble() : 0.0;
                      final finalColor = hasFinish
                          ? (fg >= 75 ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                          : Colors.grey;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: isLeader ? _primaryColor : const Color(0xFFE5E7EB),
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: TextStyle(fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isLeader ? Colors.white : const Color(0xFF6B7280)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: const TextStyle(fontSize: 11,
                                                fontWeight: FontWeight.w600),
                                            maxLines: 1, overflow: TextOverflow.ellipsis),
                                        if (isLeader)
                                          Container(
                                            margin: const EdgeInsets.only(top: 1),
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEF3C7),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: const Text('Leader',
                                                style: TextStyle(fontSize: 8,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF92400E))),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                panelContrib != null ? panelContrib.toStringAsFixed(1) : '—',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                peerScore != null
                                    ? '${(peerScore as num).toStringAsFixed(1)}/${(peerMax as num).toStringAsFixed(0)}'
                                    : '—',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11,
                                    color: peerScore != null ? Colors.grey.shade600 : Colors.grey.shade400,
                                    fontStyle: peerScore != null ? FontStyle.normal : FontStyle.italic),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: hasFinish ? finalColor.withOpacity(0.1) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  hasFinish ? fg.toStringAsFixed(1) : '—',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: finalColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],

          // ── Weight Info ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Formula: Panel ($panelW%) + Peer ($peerW%) = Final Grade  ·  Pass ≥ 75',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
            width: 4, height: 20,
            decoration: BoxDecoration(
                color: _primaryColor, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
      ],
    );
  }

  Widget _subSectionLabel(String text) {
    return Row(
      children: [
        Container(
          width: 3, height: 14,
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w700, color: Color(0xFF6B7280),
                letterSpacing: 0.3)),
      ],
    );
  }
}
