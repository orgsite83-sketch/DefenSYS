import 'package:defensys/services/repository_audit_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AuditSummaryCards extends StatelessWidget {
  final RepositoryAuditState state;
  final VoidCallback? onExportCsv;
  final ValueChanged<String?> onCopySuggestedFileName;
  final Widget? typeTabs;
  final Widget? deliverableFilterChip;

  const AuditSummaryCards({
    super.key,
    required this.state,
    required this.onExportCsv,
    required this.onCopySuggestedFileName,
    this.typeTabs,
    this.deliverableFilterChip,
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
        return 'Browse pre-defense uploads and repository items by team or deliverable (e.g. D1 across all teams).';
    }
  }

  int _count(RepositoryAuditState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Widget _notice(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.maroon,
          foregroundColor: AppColors.gold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.maroon,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required int value,
    required Color valueColor,
    required IconData icon,
    required Color iconTint,
  }) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: valueColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF5D6678),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconTint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: iconTint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(RepositoryAuditState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project Archive',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.maroon,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _headerSubtitle(state),
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _primaryButton(
              icon: Icons.file_download_rounded,
              label: 'Export Archive Records',
              onTap: state.isSaving ? null : onExportCsv,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStats(RepositoryAuditState state) {
    if (_scopeKey(state) == 'admin' &&
        (state.type.isEmpty || state.type == 'capstone')) {
      return Row(
        children: [
          Expanded(
            child: _metricCard(
              title: state.deliverableId.isNotEmpty
                  ? 'Matching records'
                  : 'Total records',
              value: _count(state, 'total'),
              valueColor: const Color(0xFF0F2743),
              icon: Icons.folder_copy_outlined,
              iconTint: const Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              title: 'Pre-defense',
              value: _count(state, 'pre_defense'),
              valueColor: const Color(0xFF2563EB),
              icon: Icons.upload_file_outlined,
              iconTint: const Color(0xFFBFDBFE),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              title: 'Archive items',
              value: _count(state, 'archive_submissions'),
              valueColor: const Color(0xFF7C3AED),
              icon: Icons.lock_outline_rounded,
              iconTint: const Color(0xFFDDD6FE),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _metricCard(
              title: 'Missing required',
              value: _count(state, 'missing_required'),
              valueColor: const Color(0xFFD97706),
              icon: Icons.error_outline_rounded,
              iconTint: const Color(0xFFFDE68A),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            title: 'Total Managed Records',
            value: _count(state, 'total'),
            valueColor: const Color(0xFF0F2743),
            icon: Icons.folder_copy_outlined,
            iconTint: const Color(0xFFCBD5E1),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _metricCard(
            title: 'Needs Revision',
            value: _count(state, 'needs_revision'),
            valueColor: const Color(0xFFD97706),
            icon: Icons.description_outlined,
            iconTint: const Color(0xFFFDE68A),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _metricCard(
            title: 'Approved Archive Entries',
            value: _count(state, 'approved'),
            valueColor: const Color(0xFF059669),
            icon: Icons.description_outlined,
            iconTint: const Color(0xFFA7F3D0),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyQueueBanner(RepositoryAuditState state) {
    final scope = _scopeKey(state);
    if (scope != 'pit_lead') {
      return const SizedBox.shrink();
    }
    final open = state.uploadWindow['open'] == true;
    final queue = state.uploadWindow['queue'];
    final hasQueue = queue is List && queue.isNotEmpty;
    if (!open || hasQueue) {
      return const SizedBox.shrink();
    }

    final diagnostics = state.uploadWindow['diagnostics'];
    if (diagnostics is! Map) {
      return _notice(
        Icons.info_outline_rounded,
        'No teams are ready to upload to vault yet. Mark the PIT event officially complete in Evaluation & Grades so passed teams become ready to upload to vault.',
        const Color(0xFFD97706),
      );
    }

    final diag = Map<String, dynamic>.from(diagnostics);
    final parts = <String>[
      'No teams are ready to upload to vault for your year level.',
    ];
    final forYear = diag['completed_events_for_year'];
    if (forYear is List && forYear.isNotEmpty) {
      parts.add('Completed events for your year: ${forYear.join(', ')}.');
    } else {
      parts.add('No officially complete PIT event matches your year yet.');
    }
    final other = diag['completed_events_other_years'];
    if (other is List && other.isNotEmpty) {
      parts.add('Other completed events: ${other.join(', ')}.');
    }
    final stages = diag['pit_stage_labels'];
    if (stages is List && stages.isNotEmpty) {
      parts.add('Grade event names in use: ${stages.join(', ')}.');
    }
    final unpublished = diag['unpublished_passed_count'];
    if (unpublished is int && unpublished > 0) {
      parts.add(
        '$unpublished team(s) passed but are not published — mark their PIT event officially complete.',
      );
    }
    return _notice(
      Icons.warning_amber_rounded,
      parts.join(' '),
      const Color(0xFFD97706),
    );
  }

  Widget _buildUploadWindowBanner(RepositoryAuditState state) {
    final scope = _scopeKey(state);
    if (scope == 'admin') {
      return const SizedBox.shrink();
    }
    final open = state.uploadWindow['open'] == true;
    final queue = state.uploadWindow['queue'];
    final hasQueue = queue is List && queue.isNotEmpty;
    if (open || hasQueue) {
      return const SizedBox.shrink();
    }
    const message =
        'Mark your year\'s PIT event officially complete in Evaluation & Grades. Upload PDFs here while teams are ready to upload; Evaluation & Grades shows Published after archive_save.';
    return _notice(
      Icons.info_outline_rounded,
      message,
      const Color(0xFF2563EB),
    );
  }

  Widget _buildUploadQueuePanel(RepositoryAuditState state) {
    final queue = (state.uploadWindow['queue'] as List?) ?? [];
    final events =
        (state.uploadWindow['completed_events'] as List?)
            ?.map((e) => e.toString())
            .join(', ') ??
        '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to archive${events.isNotEmpty ? ' · $events' : ''}',
            style: const TextStyle(
              color: AppColors.maroon,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Awaiting PDF means the team passed and still needs a correctly named upload—not that Evaluation & Grades is incomplete.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...queue.map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            final pending = row['archive_status'] == 'pending';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['team_name']?.toString() ?? 'Team',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${row['event_name'] ?? ''} · ${row['project_title'] ?? ''}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        SelectableText(
                          row['suggested_file_name']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    pending ? 'Awaiting PDF' : 'In archive',
                    style: TextStyle(
                      color: pending
                          ? const Color(0xFFD97706)
                          : const Color(0xFF059669),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  if (pending &&
                      (row['suggested_file_name']?.toString() ?? '')
                          .isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Copy filename',
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: () => onCopySuggestedFileName(
                        row['suggested_file_name']?.toString(),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(state),
        const SizedBox(height: 22),
        _sectionHeader(
          'Project Archive Summary',
          'Current archive status and record counts for your scope.',
        ),
        const SizedBox(height: 12),
        _buildStats(state),
        if (_scopeKey(state) == 'admin') ...[
          if (typeTabs != null) ...[
            const SizedBox(height: 18),
            typeTabs!,
          ],
          if (state.deliverableId.isNotEmpty && deliverableFilterChip != null) ...[
            const SizedBox(height: 10),
            deliverableFilterChip!,
          ],
        ],
        if (_scopeKey(state) != 'admin') ...[
          const SizedBox(height: 18),
          _buildUploadWindowBanner(state),
          _buildEmptyQueueBanner(state),
          if (state.uploadWindow['queue'] is List &&
              (state.uploadWindow['queue'] as List).isNotEmpty &&
              _scopeKey(state) == 'pit_lead') ...[
            const SizedBox(height: 16),
            _buildUploadQueuePanel(state),
          ],
        ],
      ],
    );
  }
}
