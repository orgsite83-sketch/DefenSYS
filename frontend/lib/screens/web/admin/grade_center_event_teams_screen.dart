import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/grade_center_provider.dart';
import 'grade_center_shared.dart';
import 'widgets/defensys_admin_shell.dart';

class GradeCenterEventTeamsScreen extends ConsumerWidget {
  const GradeCenterEventTeamsScreen({
    super.key,
    required this.groupKey,
    required this.scope,
    required this.stageLabel,
    required this.title,
    required this.onBack,
    required this.onOpenTeamDetail,
  });

  final String groupKey;
  final String scope;
  final String stageLabel;
  final String title;
  final VoidCallback onBack;
  final void Function(int gradeId, bool isLocked) onOpenTeamDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gradeCenterProvider);
    final settings = groupSettingsForKey(state, groupKey);
    final isComplete = settings['is_officially_complete'] == true;
    final peerOpen = settings['peer_grading_enabled'] == true;
    final grades = gradesForGroup(state, scope, stageLabel);
    final showAdviser = scope != 'pit';

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.star_rounded,
            title: title,
            subtitle:
                '${grades.length} team${grades.length == 1 ? '' : 's'} · tap a row to view or edit scores',
            actions: OutlinedButton.icon(
              onPressed: onBack,
              icon: Icon(
                Icons.arrow_back_rounded,
                size: 16,
                color: DefensysUi.primaryMaroon,
              ),
              label: Text(
                'Back to Grade Center',
                style: TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: DefensysUi.primaryMaroon,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: DefensysUi.primaryMaroon,
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    color: gradeScopeAccentColor(scope),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: gradeGroupStageControlsSection(
                        state: state,
                        scope: scope,
                        isOfficiallyComplete: isComplete,
                        peerGradingEnabled: peerOpen,
                        showCapstonePeerTermBadge: scope == 'capstone',
                        onOfficiallyCompleteChanged: (value) {
                          ref
                              .read(gradeCenterProvider.notifier)
                              .updateGroupSettings(
                                scope: scope,
                                stageLabel: stageLabel,
                                isOfficiallyComplete: value,
                                peerGradingEnabled: value ? false : null,
                              );
                        },
                        onPeerGradingChanged: (value) {
                          ref
                              .read(gradeCenterProvider.notifier)
                              .updateGroupSettings(
                                scope: scope,
                                stageLabel: stageLabel,
                                peerGradingEnabled: value,
                              );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            Text(state.error!, style: const TextStyle(color: Color(0xFFDC2626))),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            Text(
              state.message!,
              style: const TextStyle(color: Color(0xFF10B981)),
            ),
          ],
          const SizedBox(height: 18),
          if (state.isLoading && grades.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(
                  color: DefensysUi.primaryMaroon,
                ),
              ),
            )
          else if (grades.isEmpty)
            const DefensysCard(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No teams found for this event.',
                  style: TextStyle(color: Color(0xFF98A2B3)),
                ),
              ),
            )
          else
            DefensysCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _teamsTableHeader(showAdviser: showAdviser),
                  ...grades.map(
                    (grade) => _teamRow(
                      grade,
                      showAdviser: showAdviser,
                      isLocked: isComplete,
                      onTap: () {
                        final gradeId = asInt(grade['id']);
                        if (gradeId != null) {
                          onOpenTeamDetail(gradeId, isComplete);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _teamsTableHeader({required bool showAdviser}) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F1F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text(
              'Team',
              style: TextStyle(
                color: Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Panel',
              style: TextStyle(
                color: Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (showAdviser)
            const Expanded(
              child: Text(
                'Adviser',
                style: TextStyle(
                  color: Color(0xFF5D6678),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const Expanded(
            child: Text(
              'Peer',
              style: TextStyle(
                color: Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Final',
              style: TextStyle(
                color: Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              'Status',
              style: TextStyle(
                color: Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _teamRow(
    Map<String, dynamic> grade, {
    required bool showAdviser,
    required bool isLocked,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      child: InkWell(
        hoverColor: const Color(0xFFF9FAFB),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              Expanded(flex: 3, child: teamDetailsWidget(grade)),
              Expanded(child: scoreTextWidget(grade['panel_score'])),
              if (showAdviser)
                Expanded(child: scoreTextWidget(grade['adviser_score'])),
              Expanded(child: scoreTextWidget(grade['peer_score'])),
              Expanded(child: finalGradeTextWidget(grade)),
              Expanded(
                flex: 2,
                child: gradeStatusChipWidget(grade),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF98A2B3),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
