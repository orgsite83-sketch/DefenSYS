import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../services/grade_center_provider.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/grading/grade_masterlist_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/dialogs/confirm_dialog.dart';
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
    final settings = groupSettingsForKey(state, groupKey);
    final grades = gradesForGroup(state, scope, stageLabel);
    final complete = settings['is_officially_complete'] == true;
    final total = groupGradingTeamCount(settings, grades: grades);
    final ready = groupGradingReadyTeamCount(settings, grades: grades);
    final initialYear = scope == 'capstone'
        ? state.yearLevel
        : settings['year_level']?.toString() ??
              (grades.isNotEmpty
                  ? grades.first['year_level']?.toString()
                  : null) ??
              state.pitEvents
                  .where((event) => event['event_name'] == stageLabel)
                  .firstOrNull?['year_level']
                  ?.toString() ??
              '';
    final termId = (state.activeSemester?['id'] as num?)?.toInt();
    final assessmentId = asInt(
      settings[scope == 'pit' ? 'pit_event_config_id' : 'defense_stage_id'],
    );
    final user = ref.watch(authProvider).user;
    final canManage =
        user?['role'] == 'admin' ||
        user?['is_superuser'] == true ||
        (scope == 'pit' &&
            user?['is_pit_lead'] == true &&
            initialYear.isNotEmpty &&
            user?['pit_lead_year'] == initialYear);
    final busy =
        state.isSaving || state.isLoading || state.isCheckingCompletion;
    Future<void> saveSettings({
      bool? officiallyComplete,
      bool? peerEnabled,
    }) async {
      final saved = await ref
          .read(gradeCenterProvider.notifier)
          .updateGroupSettings(
            scope: scope,
            stageLabel: stageLabel,
            isOfficiallyComplete: officiallyComplete,
            peerGradingEnabled: peerEnabled,
          );
      if (!context.mounted) return;
      if (saved) {
        ref.invalidate(gradeMasterlistDataProvider);
      } else {
        showErrorToast(
          context,
          ref.read(gradeCenterProvider).error ??
              'Unable to update evaluation settings.',
        );
      }
    }

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
                key: ValueKey('masterlist-$groupKey-$termId-$assessmentId'),
                groupKey: groupKey,
                scope: scope,
                stageLabel: stageLabel,
                initialYear: initialYear,
                initialSemesterId: termId,
                initialAssessmentId: assessmentId,
                onBack: onBack,
                headerActions: [
                  if (canManage && scope == 'pit')
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Peer grading open',
                          style: TextStyle(
                            fontSize: 12,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          label: 'Peer grading open',
                          child: ShadSwitch(
                            value: settings['peer_grading_enabled'] == true,
                            enabled: !busy && !complete,
                            checkedTrackColor: DefensysTokens.successText,
                            onChanged: (value) =>
                                saveSettings(peerEnabled: value),
                          ),
                        ),
                      ],
                    ),
                  if (canManage && scope == 'capstone')
                    Tooltip(
                      message:
                          'Peer evaluation follows this semester’s grading settings.',
                      child: Text(
                        'Peer evaluation · ${capstoneTermPeerEvalEnabled(state) ? 'Enabled' : 'Disabled'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ),
                  if (canManage)
                    Builder(
                      builder: (actionContext) {
                        Future<void> changeCompletion() async {
                          if (!actionContext.mounted) return;
                          final confirmation = complete
                              ? showConfirmDialog(
                                  actionContext,
                                  title: 'Reopen $stageLabel?',
                                  message:
                                      'Allow grading again for this ${scope == 'pit' ? 'event' : 'stage'}? $total teams will be affected.',
                                  confirmLabel: scope == 'pit'
                                      ? 'Reopen Event'
                                      : 'Reopen Stage',
                                  icon: Icons.lock_open_rounded,
                                  iconBgColor: DefensysTokens.surfaceHigherOf(
                                    actionContext,
                                  ),
                                )
                              : reviewGradeGroupCompletion(
                                  actionContext,
                                  stageLabel: stageLabel,
                                  isPit: scope == 'pit',
                                  checkCompletion: () => ref
                                      .read(gradeCenterProvider.notifier)
                                      .checkGroupCompletion(
                                        scope: scope,
                                        stageLabel: stageLabel,
                                      ),
                                );
                          final confirmed = await confirmation;
                          if (confirmed && actionContext.mounted) {
                            await saveSettings(
                              officiallyComplete: !complete,
                              peerEnabled: complete ? null : false,
                            );
                          }
                        }

                        return complete
                            ? ShadButton.outline(
                                onPressed: busy ? null : changeCompletion,
                                child: Text(
                                  scope == 'pit'
                                      ? 'Reopen Event'
                                      : 'Reopen Stage',
                                ),
                              )
                            : ShadButton(
                                onPressed: busy ? null : changeCompletion,
                                backgroundColor: DefensysTokens.successText,
                                hoverBackgroundColor: const Color(0xFF065F46),
                                foregroundColor: Colors.white,
                                leading: const Icon(
                                  Icons.verified_outlined,
                                  size: 16,
                                ),
                                child: const Text('Mark Complete'),
                              );
                      },
                    ),
                ],
                readinessSummary: state.isLoading && total == 0
                    ? 'Loading event status…'
                    : '${complete ? 'Officially complete' : 'In progress'} · ${total == 0 ? 'No teams assigned' : '$ready of $total teams ready'}',
                onRefresh: () =>
                    ref.read(gradeCenterProvider.notifier).fetchGrades(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
