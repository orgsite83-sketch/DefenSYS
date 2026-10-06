import 'package:flutter/material.dart';
import 'package:defensys/services/admin/system_audit_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'audit_format_utils.dart';

class AuditTrailTable extends StatelessWidget {
  final SystemAuditState state;
  final ValueChanged<Map<String, dynamic>> onSelectLog;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSizeChanged;
  final Function(Map<String, dynamic> log, String status)? onQuickReviewStatus;

  const AuditTrailTable({
    super.key,
    required this.state,
    required this.onSelectLog,
    required this.onPageChanged,
    required this.onPageSizeChanged,
    this.onQuickReviewStatus,
  });

  String _formatDateTime(dynamic value) {
    if (value == null) return '';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    final local = parsed.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final logs = state.logs;
    final selectedLog = state.selectedLog ?? (logs.isNotEmpty ? logs.first : null);
    final selectedId = selectedLog?['id'];

    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Audit Trail Register + entries badge (matching original design)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroonOf(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: DefensysTokens.maroonOf(context),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Audit Trail Register',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2A2932) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  ),
                  child: Text(
                    '${state.totalCount} entries',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Table Content or Empty/Loading State
          if (state.isLoading && logs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 40,
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No audit records found',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try adjusting your search query, process area, or date filter.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                    ),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                // Calculate dynamic column spacing so the 5 columns fit edge-to-edge
                // without overflow or empty right space.
                const contentWidth = 580.0;
                const margin = 12.0;
                final extra = availableWidth - contentWidth - (margin * 2);
                final dynamicSpacing = (extra / 4).clamp(8.0, 36.0);

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: availableWidth),
                    child: DataTable(
                      showCheckboxColumn: false,
                      horizontalMargin: margin,
                      columnSpacing: dynamicSpacing,
                      headingRowHeight: 42,
                      dataRowMinHeight: 48,
                      dataRowMaxHeight: 52,
                      headingRowColor: WidgetStateProperty.all(
                        isDark ? const Color(0xFF1E1D24) : const Color(0xFFF8FAFC),
                      ),
                      columns: [
                        _buildColumnHeader(context, 'DATE / TIME'),
                        _buildColumnHeader(context, 'PROCESS AREA'),
                        _buildColumnHeader(context, 'CONTROL ACTIVITY'),
                        _buildColumnHeader(context, 'RESPONSIBLE USER'),
                        _buildColumnHeader(context, 'REVIEW STATUS'),
                      ],
                      rows: logs.map((log) {
                        final id = log['id'];
                        final isSelected = selectedId == id;
                        return _buildDataRow(
                          context,
                          log: log,
                          isSelected: isSelected,
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),

          // Pagination footer
          _buildPaginationFooter(context),
        ],
      ),
    );
  }

  DataColumn _buildColumnHeader(BuildContext context, String text) {
    return DataColumn(
      label: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  DataRow _buildDataRow(
    BuildContext context, {
    required Map<String, dynamic> log,
    required bool isSelected,
  }) {
    final isDark = DefensysTokens.isDark(context);
    final rawAction = log['action']?.toString() ?? '';
    final processArea = AuditFormatUtils.formatProcessArea(log);
    final actor = log['actor_name']?.toString() ?? 'System';
    final status = log['review_status']?.toString() ?? 'needs_review';
    final timestamp = _formatDateTime(log['created_at']);
    final isDelete = AuditFormatUtils.isDeleteAction(rawAction);

    final selectedBg = isDark
        ? const Color(0x22800000)
        : const Color(0xFFFDF2F2); // Subtle maroon tint
    final hoverBg = isDark ? const Color(0xFF222129) : const Color(0xFFF8FAFC);

    return DataRow(
      selected: false,
      onSelectChanged: (_) => onSelectLog(log),
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        if (isSelected) return selectedBg;
        if (states.contains(WidgetState.hovered)) return hoverBg;
        return Colors.transparent;
      }),
      cells: [
        // 1. DATE / TIME: Red indicator bar (if selected) + clock icon + timestamp
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? DefensysTokens.maroonOf(context) : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.schedule,
                size: 14,
                color: isSelected
                    ? DefensysTokens.maroonOf(context)
                    : (isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
              ),
              const SizedBox(width: 6),
              Text(
                timestamp,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? DefensysTokens.maroonOf(context)
                      : DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),

        // 2. PROCESS AREA: Star icon + category name
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.star_outline_rounded,
                size: 15,
                color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  processArea,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // 3. CONTROL ACTIVITY: Technical code pill (e.g. rubric.create)
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2932) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
              border: Border.all(
                color: isDark ? const Color(0xFF383742) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Text(
              rawAction,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: isDelete
                    ? const Color(0xFFDC2626)
                    : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),

        // 4. RESPONSIBLE USER: Avatar circle + username
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  actor.isNotEmpty ? actor[0].toUpperCase() : 'U',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: DefensysTokens.maroonOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(
                  actor,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // 5. REVIEW STATUS: Pill badge (Needs Review, Reviewed, or Deleted)
        DataCell(
          _buildStatusBadge(context, status, isDelete: isDelete),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context, String status, {bool isDelete = false}) {
    final isDark = DefensysTokens.isDark(context);

    if (isDelete) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0x33DC2626) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
          border: Border.all(
            color: isDark ? const Color(0x66EF4444) : const Color(0xFFFECACA),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close_rounded, size: 12, color: Color(0xFFDC2626)),
            SizedBox(width: 4),
            Text(
              'Deleted',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'reviewed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
          border: Border.all(
            color: isDark ? const Color(0xFF065F46) : const Color(0xFFBBF7D0),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: Color(0xFF059669)),
            SizedBox(width: 4),
            Text(
              'Reviewed',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF059669),
              ),
            ),
          ],
        ),
      );
    }

    // Default: Needs review
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(
          color: isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded, size: 12, color: Color(0xFFD97706)),
          SizedBox(width: 4),
          Text(
            'Needs Review',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFD97706),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final total = state.totalCount;
    final page = state.currentPage;
    final totalPages = state.totalPages;
    final pageSize = state.pageSize;

    final start = total == 0 ? 0 : ((page - 1) * pageSize) + 1;
    final end = (page * pageSize).clamp(0, total);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: DefensysTokens.borderOf(context))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Rows per page + Showing X-Y of Z
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rows: ',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                DropdownButton<int>(
                  value: pageSize,
                  underline: const SizedBox(),
                  isDense: true,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                  dropdownColor: DefensysTokens.surfaceOf(context),
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('10')),
                    DropdownMenuItem(value: 25, child: Text('25')),
                    DropdownMenuItem(value: 50, child: Text('50')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      onPageSizeChanged(val);
                    }
                  },
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Showing $start–$end of $total',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Right: Chevrons + page count
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 16,
                onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
              ),
              const SizedBox(width: 4),
              Text(
                '$page / ${totalPages > 0 ? totalPages : 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 16,
                onPressed: page < totalPages ? () => onPageChanged(page + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
