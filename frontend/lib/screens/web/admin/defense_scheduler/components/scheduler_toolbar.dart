import 'package:flutter/material.dart';

import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';

class SchedulerToolbar extends StatelessWidget {
  const SchedulerToolbar({
    super.key,
    required this.state,
    this.onBack,
  });

  final DefenseSchedulerState state;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
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
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (onBack != null || Navigator.canPop(context)) ...[
          const SizedBox(width: 16),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: () {
                if (onBack != null) {
                  onBack!();
                } else {
                  Navigator.pop(context);
                }
              },
              style: OutlinedButton.styleFrom(
                elevation: 0,
                foregroundColor: const Color(0xFF334155),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                backgroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(
                Icons.arrow_back_rounded,
                size: 16,
                color: Color(0xFF64748B),
              ),
              label: const Text(
                'Back to Defense Operations',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ),
        ],
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _stepProgressTile(
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
              number: 2,
              title: 'Review & Arrange Teams',
              subtitle: 'Waiting for Step 1 plan generation.',
              isActive: currentStep == 2,
              isDone: currentStep > 2,
            ),
          ),
          Expanded(
            child: _stepProgressTile(
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
    required int number,
    required String title,
    required String subtitle,
    required bool isActive,
    required bool isDone,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final Color accent = isActive
        ? AppColors.maroon
        : (isDone ? AppColors.success : const Color(0xFFD0D5DD));

    final Color bg = isActive
        ? const Color(0xFFFDF2F2)
        : (isDone ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC));

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
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
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
