import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/grade_center_provider.dart';
import 'grade_center_shared.dart';
import 'widgets/defensys_admin_shell.dart';

class GradeCenterTeamDetailScreen extends ConsumerStatefulWidget {
  const GradeCenterTeamDetailScreen({
    super.key,
    required this.gradeId,
    required this.isLocked,
    required this.onBack,
  });

  final int gradeId;
  final bool isLocked;
  final VoidCallback onBack;

  @override
  ConsumerState<GradeCenterTeamDetailScreen> createState() =>
      _GradeCenterTeamDetailScreenState();
}

class _GradeCenterTeamDetailScreenState
    extends ConsumerState<GradeCenterTeamDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gradeCenterProvider.notifier).refreshGrade(widget.gradeId);
    });
  }

  Future<void> _reloadGrade() async {
    await ref.read(gradeCenterProvider.notifier).refreshGrade(widget.gradeId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gradeCenterProvider);
    final grade = gradeById(state, widget.gradeId);

    if (grade == null && state.isRefreshingGrade) {
      return SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailHeader(
              title: 'Team grades',
              subtitle: 'Loading…',
              onBack: widget.onBack,
            ),
            const SizedBox(height: 40),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    if (grade == null) {
      return SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailHeader(
              title: 'Team grades',
              subtitle: '',
              onBack: widget.onBack,
            ),
            const SizedBox(height: 24),
            const Text('Grade record not found.'),
          ],
        ),
      );
    }

    final isPit = grade['scope'] == 'pit';
    final breakdowns = parseBreakdowns(grade);
    final peers = parsePeerPerStudent(grade);
    final gradeIdValue = asInt(grade['id']);
    final canPublish = !isPit &&
        !widget.isLocked &&
        gradeIdValue != null &&
        grade['status'] != 'published' &&
        asDouble(grade['final_grade']) != null;
    final canEdit =
        !widget.isLocked && !state.isSaving && gradeIdValue != null;

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grade['team_name']?.toString() ?? 'Team',
                      style: DefensysUi.pageTitle,
                    ),
                    Text(
                      grade['project_title']?.toString() ?? '',
                      style: DefensysUi.subtitle,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh grades',
                onPressed: state.isRefreshingGrade ? null : _reloadGrade,
                icon: state.isRefreshingGrade
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              if (canEdit)
                OutlinedButton.icon(
                  onPressed: () => GradeCenterActions.showEditScoresDialog(
                    context: context,
                    ref: ref,
                    grade: grade,
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit scores'),
                ),
              if (canEdit) const SizedBox(width: 8),
              if (canPublish)
                ElevatedButton.icon(
                  onPressed: state.isSaving
                      ? null
                      : () => GradeCenterActions.confirmPublish(
                            context: context,
                            ref: ref,
                            gradeId: gradeIdValue,
                            teamName: grade['team_name']?.toString() ?? 'team',
                          ),
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: const Text('Publish'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DefensysUi.primaryMaroon,
                    foregroundColor: DefensysUi.accentGold,
                  ),
                ),
            ],
          ),
            if (widget.isLocked) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Text(
                  'This event is officially complete. Grades cannot be edited.',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            gradeScoreSummaryCard(
              title: 'Panel scores',
              headlineScore: grade['panel_score'],
              child: _breakdownForType(breakdowns, 'panel'),
            ),
            if (!isPit) ...[
              const SizedBox(height: 14),
              gradeScoreSummaryCard(
                title: 'Adviser scores',
                headlineScore: grade['adviser_score'],
                child: _breakdownForType(breakdowns, 'adviser'),
              ),
            ],
            const SizedBox(height: 14),
            gradeScoreSummaryCard(
              title: 'Peer scores (per member)',
              headlineScore: grade['peer_score'],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Each member receives a distinct peer average from teammate evaluations.',
                    style: TextStyle(
                      color: Color(0xFF5D6678),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (peers.isEmpty)
                    const Text(
                      'No peer scores recorded yet.',
                      style: TextStyle(color: Color(0xFF98A2B3)),
                    )
                  else
                    ...peers.map(_peerMemberTile),
                  if (breakdowns.any((r) => r['evaluation_type'] == 'peer')) ...[
                    const SizedBox(height: 12),
                    breakdownSectionWidget(
                      'peer',
                      breakdowns
                          .where((r) => r['evaluation_type'] == 'peer')
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            DefensysCard(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Overall',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: DefensysUi.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  gradeFormulaLine(grade),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Final grade',
                            style: TextStyle(
                              color: Color(0xFF5D6678),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          finalGradeTextWidget(grade),
                        ],
                      ),
                      const SizedBox(width: 32),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'System status',
                            style: TextStyle(
                              color: Color(0xFF5D6678),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          gradeStatusChipWidget(grade),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _detailHeader({
    required String title,
    required String subtitle,
    required VoidCallback onBack,
  }) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DefensysUi.pageTitle),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: DefensysUi.subtitle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _breakdownForType(
    List<Map<String, dynamic>> breakdowns,
    String type,
  ) {
    final rows =
        breakdowns.where((item) => item['evaluation_type'] == type).toList();
    if (rows.isEmpty) {
      return const Text(
        'No criterion breakdown posted yet.',
        style: TextStyle(color: Color(0xFF98A2B3)),
      );
    }
    return breakdownSectionWidget(type, rows);
  }

  Widget _peerMemberTile(Map<String, dynamic> peer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              peer['student_name']?.toString() ?? 'Student',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: DefensysUi.textDark,
              ),
            ),
          ),
          Text(
            '${peer['average_score']} / ${peer['max_score']}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Text(
            '(${peer['normalized_score']}%)',
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
