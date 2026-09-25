import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:flutter/material.dart';

typedef AuditSummaryCards = ProjectArchiveSummaryCards;

class ProjectArchiveSummaryCards extends StatelessWidget {
  final ProjectArchiveState state;
  final VoidCallback? onExportCsv;
  final Widget? typeTabs;
  final Widget? deliverableFilterChip;
  final VoidCallback? onManageProgramStageAccess;

  const ProjectArchiveSummaryCards({
    super.key,
    required this.state,
    required this.onExportCsv,
    this.typeTabs,
    this.deliverableFilterChip,
    this.onManageProgramStageAccess,
  });

  String _scopeKey(RepositoryAuditState state) =>
      state.scope['scope']?.toString() ?? 'admin';

  String _headerSubtitle(RepositoryAuditState state) {
    final scope = _scopeKey(state);
    final year = state.scope['pit_year_level']?.toString() ?? '';
    switch (scope) {
      case 'pit_lead':
        return 'Archive passed PIT projects for $year after the event is officially complete in Evaluation & Grades.';
      default:
        return 'Browse pre-defense uploads and archive items by team or deliverable (e.g. D1 across all teams).';
    }
  }

  int _count(RepositoryAuditState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: AppColors.gold),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.maroon,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _metricCard({
    required BuildContext context,
    required String title,
    required int value,
    required Color valueColor,
    required IconData icon,
    required Color iconTint,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveValueColor = isDark
        ? (valueColor == const Color(0xFF0F172A)
            ? DefensysTokens.textPrimaryDark
            : (valueColor == const Color(0xFFB45309)
                ? const Color(0xFFFBBF24)
                : valueColor))
        : valueColor;
    final effectiveIconTint = isDark && iconTint == const Color(0xFF475569)
        ? const Color(0xFFA1A1AA)
        : (isDark && iconTint == AppColors.maroon ? const Color(0xFFF87171) : iconTint);

    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: effectiveValueColor,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: effectiveIconTint.withValues(alpha: isDark ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: effectiveIconTint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(RepositoryAuditState state, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project Archive',
                style: TextStyle(
                  color: isDark ? const Color(0xFFF87171) : AppColors.maroon,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _headerSubtitle(state),
                style: TextStyle(
                  color: isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (onManageProgramStageAccess != null) ...[
          OutlinedButton.icon(
            onPressed: onManageProgramStageAccess,
            icon: const Icon(Icons.tune_rounded, size: 15),
            label: const Text('Program Stage Access ▾'),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? const Color(0xFFF87171) : AppColors.maroon,
              side: BorderSide(color: isDark ? const Color(0xFFF87171) : AppColors.maroon),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        _primaryButton(
          icon: state.isExporting
              ? Icons.hourglass_top_rounded
              : Icons.file_download_rounded,
          label: state.isExporting ? 'Exporting...' : 'Export Archive Records',
          onTap: (state.isSaving || state.isExporting) ? null : onExportCsv,
        ),
      ],
    );
  }

  Widget _buildStats(RepositoryAuditState state, BuildContext context) {
    final missingCount = _count(state, 'missing_required');
    if (_scopeKey(state) == 'admin' &&
        (state.type.isEmpty || state.type == 'capstone')) {
      return Row(
        children: [
          Expanded(
            child: _metricCard(
              context: context,
              title: state.deliverableId.isNotEmpty
                  ? 'Matching records'
                  : 'Total records',
              value: _count(state, 'total'),
              valueColor: const Color(0xFF0F172A),
              icon: Icons.folder_open_rounded,
              iconTint: const Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              context: context,
              title: 'Pre-defense',
              value: _count(state, 'pre_defense'),
              valueColor: const Color(0xFF0F172A),
              icon: Icons.upload_file_rounded,
              iconTint: const Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              context: context,
              title: 'Post-defense',
              value: _count(state, 'archive_submissions'),
              valueColor: const Color(0xFF0F172A),
              icon: Icons.inventory_2_outlined,
              iconTint: AppColors.maroon,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              context: context,
              title: 'Missing required',
              value: missingCount,
              valueColor: missingCount > 0
                  ? const Color(0xFFB45309)
                  : const Color(0xFF0F172A),
              icon: Icons.error_outline_rounded,
              iconTint: const Color(0xFFD97706),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            context: context,
            title: 'Total Managed Records',
            value: _count(state, 'total'),
            valueColor: const Color(0xFF0F172A),
            icon: Icons.folder_open_rounded,
            iconTint: const Color(0xFF475569),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _metricCard(
            context: context,
            title: 'Needs Revision',
            value: _count(state, 'needs_revision'),
            valueColor: const Color(0xFFB45309),
            icon: Icons.description_outlined,
            iconTint: const Color(0xFFD97706),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _metricCard(
            context: context,
            title: 'Approved Archive Entries',
            value: _count(state, 'approved'),
            valueColor: const Color(0xFF0F172A),
            icon: Icons.task_alt_rounded,
            iconTint: const Color(0xFF059669),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showDeliverableChip =
        state.deliverableId.isNotEmpty && deliverableFilterChip != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(state, context),
        const SizedBox(height: 18),
        _buildStats(state, context),
        if (_scopeKey(state) == 'admin') ...[
          if (typeTabs != null || showDeliverableChip) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                if (typeTabs != null) typeTabs!,
                if (showDeliverableChip) deliverableFilterChip!,
              ],
            ),
          ],
        ],
      ],
    );
  }
}
