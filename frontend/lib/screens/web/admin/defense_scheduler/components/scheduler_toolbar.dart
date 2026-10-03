import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class SchedulerToolbar extends ConsumerWidget {
  const SchedulerToolbar({super.key, required this.state, this.onBack});

  final DefenseSchedulerState state;
  final VoidCallback? onBack;

  void _handleBack(BuildContext context, WidgetRef ref) {
    if (onBack != null) {
      onBack!();
      return;
    }
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    final user = ref.read(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    if (isAdmin) {
      ref
          .read(activeAdminSectionProvider.notifier)
          .setSection(DefensysAdminSection.defenseBoard);
      try {
        context.go(AdminRoutes.defenseBoard);
      } catch (_) {}
    } else {
      try {
        context.go(FacultyRoutes.defenseBoard);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final semesterLabel =
        state.activeSemester?['display_name']?.toString() ??
        'No active semester configured';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    color: DefensysTokens.textPrimaryOf(context),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Defense Scheduler',
                      style: TextStyle(
                        color: DefensysTokens.textPrimaryOf(context),
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                semesterLabel,
                style: TextStyle(
                  color: isDark
                      ? DefensysTokens.textSecondaryDark
                      : AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () => _handleBack(context, ref),
            style: OutlinedButton.styleFrom(
              elevation: 0,
              foregroundColor: isDark
                  ? DefensysTokens.textPrimaryDark
                  : const Color(0xFF334155),
              side: BorderSide(
                color: isDark
                    ? DefensysTokens.mistBorder
                    : const Color(0xFFCBD5E1),
              ),
              backgroundColor: isDark
                  ? DefensysTokens.mistInputFill
                  : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: Icon(
              Icons.arrow_back_rounded,
              size: 16,
              color: isDark
                  ? DefensysTokens.textSecondaryDark
                  : const Color(0xFF64748B),
            ),
            label: Text(
              MediaQuery.sizeOf(context).width < 640
                  ? 'Back'
                  : 'Back to Operations',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isDark
                    ? DefensysTokens.textPrimaryDark
                    : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SchedulerStepProgress extends StatelessWidget {
  const SchedulerStepProgress({super.key, required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 640;
      final labels = compact
          ? ['Setup', 'Arrange', 'Preview']
          : ['Schedule details', 'Arrange teams', 'Review & confirm'];
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 20,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
          border: Border.all(color: DefensysTokens.borderOf(context)),
        ),
        child: Row(
          children: [
            for (int i = 1; i <= 3; i++) ...[
              if (i > 1)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 16),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              Expanded(
                child: Semantics(
                  label: '${labels[i - 1]}, step $i of 3',
                  selected: currentStep == i,
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: currentStep == i
                              ? DefensysTokens.textPrimaryOf(context)
                              : null,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: currentStep == i
                                ? DefensysTokens.textPrimaryOf(context)
                                : DefensysTokens.borderOf(context),
                          ),
                        ),
                        child: i < currentStep
                            ? Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: DefensysTokens.textPrimaryOf(context),
                              )
                            : Text(
                                '$i',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: currentStep == i
                                      ? DefensysTokens.surfaceOf(context)
                                      : DefensysTokens.textSecondaryOf(context),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          labels[i - 1],
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 12 : 13,
                            fontWeight: currentStep == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: currentStep == i
                                ? DefensysTokens.textPrimaryOf(context)
                                : DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class SchedulerNoticeBanner extends StatelessWidget {
  const SchedulerNoticeBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF92400E),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
