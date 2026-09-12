import 'package:flutter/material.dart';
import '../../../../../theme/app_theme.dart';

/// Clean, executive horizontal progression funnel tracking cohorts from:
/// 1st Year PIT -> 2nd Year PIT -> 3rd Year PIT -> 4th Year Capstone.
class CurriculumCohortProgressionCard extends StatelessWidget {
  final List<Map<String, dynamic>> cohortProgression;

  const CurriculumCohortProgressionCard({
    super.key,
    required this.cohortProgression,
  });

  @override
  Widget build(BuildContext context) {
    final items = cohortProgression.isNotEmpty
        ? cohortProgression
        : _fallbackProgression();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.timeline_rounded,
                  color: AppColors.maroon,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '4-Year Longitudinal Cohort Progression Funnel',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Retention, stage advancement, and milestone completion pacing from 1st Year PIT to Capstone',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 13, color: Color(0xFF475569)),
                    SizedBox(width: 5),
                    Text(
                      'Cohort Health: 94.8% Retained',
                      style: TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Horizontal Pipeline Steps
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 800;

              if (isNarrow) {
                return Column(
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      _buildStepCard(items[i], i, items.length),
                      if (i < items.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            size: 18,
                            color: Colors.grey.shade400,
                          ),
                        ),
                    ],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    Expanded(
                      child: _buildStepCard(items[i], i, items.length),
                    ),
                    if (i < items.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 48, left: 6, right: 6),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(Map<String, dynamic> item, int index, int total) {
    final title = item['title']?.toString() ?? 'Year ${index + 1}';
    final phase = item['phase']?.toString() ?? '';
    final focus = item['focus']?.toString() ?? '';
    final studentCount = item['student_count']?.toString() ?? '0';
    final teamCount = item['team_count']?.toString() ?? '0';
    final onTimeRate = (item['on_time_rate'] != null)
        ? double.tryParse(item['on_time_rate'].toString()) ?? 90.0
        : 90.0;

    final isCapstone = index == total - 1;
    final color = isCapstone ? AppColors.maroon : const Color(0xFF0284C7);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCapstone
            ? AppColors.maroon.withValues(alpha: 0.03)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCapstone
              ? AppColors.maroon.withValues(alpha: 0.25)
              : const Color(0xFFE2E8F0),
          width: isCapstone ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step pill & stage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'Step ${index + 1}/$total',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Phase Name
          Text(
            phase,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),

          // Focus details
          Text(
            focus,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),

          // Counts & Rate
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ENROLLED',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$studentCount Stud. · $teamCount Teams',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: onTimeRate >= 80.0
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: onTimeRate >= 80.0
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Text(
                  '${onTimeRate.toStringAsFixed(1)}% Adv.',
                  style: TextStyle(
                    color: onTimeRate >= 80.0
                        ? const Color(0xFF047857)
                        : const Color(0xFFB45309),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _fallbackProgression() {
    return [
      {
        'title': '1st Year PIT',
        'phase': 'Foundational Ideation',
        'focus': 'Core Algorithms, Basic UI & Agile Teamwork',
        'student_count': 120,
        'team_count': 24,
        'on_time_rate': 96.5,
      },
      {
        'title': '2nd Year PIT',
        'phase': 'Systems Architecture',
        'focus': 'Database Design, REST APIs & Backend Services',
        'student_count': 114,
        'team_count': 23,
        'on_time_rate': 94.8,
      },
      {
        'title': '3rd Year PIT',
        'phase': 'Advanced Integration',
        'focus': 'Cloud Architecture, Microservices & Hardware/IoT',
        'student_count': 108,
        'team_count': 22,
        'on_time_rate': 92.0,
      },
      {
        'title': '4th Year Capstone',
        'phase': 'Defense & Production',
        'focus': 'Research Methodology, Novelty & Real-World Clearance',
        'student_count': 102,
        'team_count': 21,
        'on_time_rate': 85.0,
      },
    ];
  }
}
