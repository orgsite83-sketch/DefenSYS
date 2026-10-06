import 'package:flutter/material.dart';
import 'package:defensys/services/admin/system_audit_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class AuditKpiMetrics extends StatelessWidget {
  final SystemAuditState state;

  const AuditKpiMetrics({super.key, required this.state});

  int _count(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final total = _count(state.counts['filtered'], fallback: state.logs.length);
    final needsReview = _count(state.counts['needs_review']);
    final reviewed = _count(state.counts['reviewed']);

    final progressPct = total == 0 ? 0 : ((reviewed / total) * 100).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= 900) {
          // 4 columns in single row
          return Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context,
                  icon: Icons.description_outlined,
                  iconColor: const Color(0xFF475569),
                  iconBg: const Color(0xFFF1F5F9),
                  darkIconBg: const Color(0xFF1E293B),
                  value: total.toString(),
                  label: 'Total Events',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricCard(
                  context,
                  icon: Icons.access_time_rounded,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFEF3C7),
                  darkIconBg: const Color(0xFF451A03),
                  value: needsReview.toString(),
                  label: 'Needs Review',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricCard(
                  context,
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: const Color(0xFF059669),
                  iconBg: const Color(0xFFDCFCE7),
                  darkIconBg: const Color(0xFF064E3B),
                  value: reviewed.toString(),
                  label: 'Reviewed',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildProgressCard(
                  context,
                  icon: Icons.bar_chart_rounded,
                  iconColor: const Color(0xFF2563EB),
                  iconBg: const Color(0xFFDBEAFE),
                  darkIconBg: const Color(0xFF1E3A8A),
                  value: '$progressPct%',
                  label: 'Review Progress',
                  progress: progressPct / 100.0,
                ),
              ),
            ],
          );
        } else if (width >= 560) {
          // 2x2 grid
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      icon: Icons.description_outlined,
                      iconColor: const Color(0xFF475569),
                      iconBg: const Color(0xFFF1F5F9),
                      darkIconBg: const Color(0xFF1E293B),
                      value: total.toString(),
                      label: 'Total Events',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      icon: Icons.access_time_rounded,
                      iconColor: const Color(0xFFD97706),
                      iconBg: const Color(0xFFFEF3C7),
                      darkIconBg: const Color(0xFF451A03),
                      value: needsReview.toString(),
                      label: 'Needs Review',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      icon: Icons.check_circle_outline_rounded,
                      iconColor: const Color(0xFF059669),
                      iconBg: const Color(0xFFDCFCE7),
                      darkIconBg: const Color(0xFF064E3B),
                      value: reviewed.toString(),
                      label: 'Reviewed',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildProgressCard(
                      context,
                      icon: Icons.bar_chart_rounded,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFDBEAFE),
                      darkIconBg: const Color(0xFF1E3A8A),
                      value: '$progressPct%',
                      label: 'Review Progress',
                      progress: progressPct / 100.0,
                    ),
                  ),
                ],
              ),
            ],
          );
        } else {
          // 1 column stack
          return Column(
            children: [
              _buildMetricCard(
                context,
                icon: Icons.description_outlined,
                iconColor: const Color(0xFF475569),
                iconBg: const Color(0xFFF1F5F9),
                darkIconBg: const Color(0xFF1E293B),
                value: total.toString(),
                label: 'Total Events',
              ),
              const SizedBox(height: 10),
              _buildMetricCard(
                context,
                icon: Icons.access_time_rounded,
                iconColor: const Color(0xFFD97706),
                iconBg: const Color(0xFFFEF3C7),
                darkIconBg: const Color(0xFF451A03),
                value: needsReview.toString(),
                label: 'Needs Review',
              ),
              const SizedBox(height: 10),
              _buildMetricCard(
                context,
                icon: Icons.check_circle_outline_rounded,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFDCFCE7),
                darkIconBg: const Color(0xFF064E3B),
                value: reviewed.toString(),
                label: 'Reviewed',
              ),
              const SizedBox(height: 10),
              _buildProgressCard(
                context,
                icon: Icons.bar_chart_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFDBEAFE),
                darkIconBg: const Color(0xFF1E3A8A),
                value: '$progressPct%',
                label: 'Review Progress',
                progress: progressPct / 100.0,
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required Color darkIconBg,
    required String value,
    required String label,
  }) {
    final isDark = DefensysTokens.isDark(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? darkIconBg : iconBg,
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: DefensysTokens.textPrimaryOf(context),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required Color darkIconBg,
    required String value,
    required String label,
    required double progress,
  }) {
    final isDark = DefensysTokens.isDark(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? darkIconBg : iconBg,
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: DefensysTokens.textPrimaryOf(context),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(DefensysTokens.maroonOf(context)),
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
