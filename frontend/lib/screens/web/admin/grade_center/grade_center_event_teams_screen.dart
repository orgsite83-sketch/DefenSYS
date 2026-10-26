import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/grade_center_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../widgets/defensys_admin_shell.dart';
import 'grade_center_shared.dart';
import 'grade_masterlist.dart';

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

  final String groupKey, scope, stageLabel, title;
  final VoidCallback onBack;
  // Kept for existing embedded callers; the masterlist carries full row context.
  final void Function(int gradeId, bool isLocked) onOpenTeamDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gradeCenterProvider);
    ref.listen<GradeCenterState>(gradeCenterProvider, (_, next) {
      if (next.incompleteTeams.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showIncompleteGradingTeamsDialog(context, teams: next.incompleteTeams);
        ref.read(gradeCenterProvider.notifier).clearIncompleteTeams();
      });
    });
    final settings = groupSettingsForKey(state, groupKey);
    final grades = gradesForGroup(state, scope, stageLabel);
    final complete = settings['is_officially_complete'] == true;
    final initialYear =
        settings['year_level']?.toString() ??
        (grades.isNotEmpty ? grades.first['year_level']?.toString() : null) ??
        state.pitEvents
            .where((event) => event['event_name'] == stageLabel)
            .firstOrNull?['year_level']
            ?.toString() ??
        '';
    final termId = (state.activeSemester?['id'] as num?)?.toInt();
    final neutral = DefensysTokens.isDark(context)
        ? const Color(0xFF2B2B30)
        : const Color(0xFFF4F4F5);
    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: neutral,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: DefensysTokens.maroonOf(context),
          primaryContainer: neutral,
          secondary: DefensysTokens.saveActionBg,
          secondaryContainer: neutral,
        ),
      ),
      child: DefensysShadcnScope(
        child: SingleChildScrollView(
          key: PageStorageKey('grade-masterlist-$groupKey'),
          padding: DefensysUi.contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GradeMasterlist(
                key: ValueKey('masterlist-$groupKey'),
                groupKey: groupKey,
                scope: scope,
                stageLabel: stageLabel,
                initialYear: initialYear,
                initialSemesterId: termId,
                onBack: onBack,
                assessmentControls: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceOf(context),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                    borderRadius: BorderRadius.circular(
                      DefensysTokens.radiusMd,
                    ),
                  ),
                  child: gradeGroupStageControlsSection(
                    state: state,
                    scope: scope,
                    stageLabel: stageLabel,
                    isOfficiallyComplete: complete,
                    peerGradingEnabled:
                        settings['peer_grading_enabled'] == true,
                    showCapstonePeerTermBadge: false,
                    groupSettings: settings,
                    grades: grades,
                    checkCompletion: () => ref
                        .read(gradeCenterProvider.notifier)
                        .checkGroupCompletion(
                          scope: scope,
                          stageLabel: stageLabel,
                        ),
                    onOfficiallyCompleteChanged: (value) => ref
                        .read(gradeCenterProvider.notifier)
                        .updateGroupSettings(
                          scope: scope,
                          stageLabel: stageLabel,
                          isOfficiallyComplete: value,
                          peerGradingEnabled: value ? false : null,
                        ),
                    onPeerGradingChanged: (value) => ref
                        .read(gradeCenterProvider.notifier)
                        .updateGroupSettings(
                          scope: scope,
                          stageLabel: stageLabel,
                          peerGradingEnabled: value,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
