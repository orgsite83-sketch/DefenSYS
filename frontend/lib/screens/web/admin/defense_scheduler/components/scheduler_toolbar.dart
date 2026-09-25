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
  const SchedulerToolbar({
    super.key,
    required this.state,
    this.onBack,
  });

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
              const Row(
                children: [
                  Icon(
                    Icons.auto_awesome_mosaic_rounded,
                    color: AppColors.maroon,
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Defense Scheduler',
                    style: TextStyle(
                      color: AppColors.maroon,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                semesterLabel,
                style: TextStyle(
                  color: isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
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
              foregroundColor: isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF334155),
              side: BorderSide(color: isDark ? DefensysTokens.mistBorder : const Color(0xFFCBD5E1)),
              backgroundColor: isDark ? DefensysTokens.mistInputFill : Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: Icon(
              Icons.arrow_back_rounded,
              size: 16,
              color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
            ),
            label: Text(
              'Back to Operations',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SchedulerStepProgress extends StatelessWidget {
  const SchedulerStepProgress({
    super.key,
    required this.currentStep,
  });

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: DefensysTokens.mistBorder) : null,
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _stepProgressTile(
              context: context,
              number: 1,
              title: 'Set Up Defense Schedule',
              subtitle: 'Choose the shared inputs for this batch.',
              isActive: currentStep == 1,
              isDone: currentStep > 1,
              isFirst: true,
            ),
          ),
          Expanded(
            child: _stepProgressTile(
              context: context,
              number: 2,
              title: 'Review & Arrange Teams',
              subtitle: 'Waiting for Step 1 plan generation.',
              isActive: currentStep == 2,
              isDone: currentStep > 2,
            ),
          ),
          Expanded(
            child: _stepProgressTile(
              context: context,
              number: 3,
              title: 'Final Schedule Preview',
              subtitle: 'Shown after the schedule plan is generated.',
              isActive: currentStep == 3,
              isDone: false,
              isLast: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepProgressTile({
    required BuildContext context,
    required int number,
    required String title,
    required String subtitle,
    required bool isActive,
    required bool isDone,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = isActive
        ? AppColors.maroon
        : (isDone ? AppColors.success : const Color(0xFFD0D5DD));

    final Color bg = isActive
        ? (isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.25) : const Color(0xFFFDF2F2))
        : (isDone
            ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.25) : const Color(0xFFF0FDF4))
            : (isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC)));

    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isFirst ? 14 : 0),
          bottomLeft: Radius.circular(isFirst ? 14 : 0),
          topRight: Radius.circular(isLast ? 14 : 0),
          bottomRight: Radius.circular(isLast ? 14 : 0),
        ),
        border: Border(
          bottom: BorderSide(
            color: accent,
            width: isActive || isDone ? 3 : 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive || isDone
                        ? (isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary)
                        : (isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SchedulerNoticeBanner extends StatelessWidget {
  const SchedulerNoticeBanner({
    super.key,
    required this.message,
  });

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
