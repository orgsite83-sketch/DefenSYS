import 'package:flutter/material.dart';
import 'package:defensys/services/admin/system_audit_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class AuditStatusTabs extends StatelessWidget {
  final SystemAuditState state;
  final ValueChanged<String> onStatusSelected;

  const AuditStatusTabs({
    super.key,
    required this.state,
    required this.onStatusSelected,
  });

  int _count(dynamic val, {int fallback = 0}) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? fallback;
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final total = _count(state.counts['filtered'], fallback: state.logs.length);
    final needsReview = _count(state.counts['needs_review']);
    final reviewed = _count(state.counts['reviewed']);

    final currentStatus = state.reviewStatus;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTab(
            context,
            label: 'All Events',
            count: total.toString(),
            isSelected: currentStatus.isEmpty,
            onTap: () => onStatusSelected(''),
            badgeBg: currentStatus.isEmpty
                ? DefensysTokens.maroonOf(context).withValues(alpha: 0.1)
                : const Color(0xFFF1F5F9),
            badgeDarkBg: currentStatus.isEmpty
                ? DefensysTokens.maroonOf(context).withValues(alpha: 0.2)
                : const Color(0xFF1E293B),
            badgeColor: currentStatus.isEmpty
                ? DefensysTokens.maroonOf(context)
                : const Color(0xFF64748B),
          ),
          const SizedBox(width: 8),
          _buildTab(
            context,
            label: 'Needs Review',
            count: needsReview.toString(),
            isSelected: currentStatus == 'needs_review',
            onTap: () => onStatusSelected('needs_review'),
            badgeBg: const Color(0xFFFEF3C7),
            badgeDarkBg: const Color(0xFF451A03),
            badgeColor: const Color(0xFFD97706),
          ),
          const SizedBox(width: 8),
          _buildTab(
            context,
            label: 'Reviewed',
            count: reviewed.toString(),
            isSelected: currentStatus == 'reviewed',
            onTap: () => onStatusSelected('reviewed'),
            badgeBg: const Color(0xFFDCFCE7),
            badgeDarkBg: const Color(0xFF064E3B),
            badgeColor: const Color(0xFF059669),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(
    BuildContext context, {
    required String label,
    required String count,
    required bool isSelected,
    required VoidCallback onTap,
    required Color badgeBg,
    required Color badgeDarkBg,
    required Color badgeColor,
  }) {
    final isDark = DefensysTokens.isDark(context);

    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? DefensysTokens.maroonOf(context) : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? DefensysTokens.textPrimaryOf(context)
                    : (isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? badgeDarkBg : badgeBg,
                borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
              ),
              child: Text(
                count,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: badgeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
