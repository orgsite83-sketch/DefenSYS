import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/services/admin/system_audit_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'audit_format_utils.dart';

class AuditTrailTable extends StatelessWidget {
  final SystemAuditState state;
  final ValueChanged<Map<String, dynamic>> onSelectLog;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSizeChanged;

  const AuditTrailTable({
    super.key,
    required this.state,
    required this.onSelectLog,
    required this.onPageChanged,
    required this.onPageSizeChanged,
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
    final selectedLog = state.selectedLog;
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
          // Activity register and matching entry count.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroonOf(
                      context,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      DefensysTokens.radiusSm,
                    ),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: DefensysTokens.maroonOf(context),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Activity register',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2A2932)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(
                      DefensysTokens.radiusPill,
                    ),
                  ),
                  child: Text(
                    '${state.totalCount} entries',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : DefensysTokens.steelGrey,
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
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
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
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No logs found',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try adjusting your search query, process area, or date filter.',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : DefensysTokens.steelGrey,
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
                      dataRowMinHeight: 60,
                      dataRowMaxHeight: 64,
                      headingRowColor: WidgetStateProperty.all(
                        isDark
                            ? const Color(0xFF1E1D24)
                            : const Color(0xFFF8FAFC),
                      ),
                      columns: [
                        _buildColumnHeader(context, 'Date / time'),
                        _buildColumnHeader(context, 'Process area'),
                        _buildColumnHeader(context, 'Activity'),
                        _buildColumnHeader(context, 'Actor'),
                        _buildColumnHeader(context, 'Details'),
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
          fontFamily: DefensysTokens.fontFamilyInter,
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
    final actionLabel = AuditFormatUtils.formatAction(rawAction, log);
    final processArea = AuditFormatUtils.formatProcessArea(log);
    final actor = log['actor_name']?.toString() ?? 'System';
    final timestamp = _formatDateTime(log['created_at']);
    final isDelete = AuditFormatUtils.isDeleteAction(rawAction);

    final selectedBg = isDark
        ? const Color(0xFF2B2A30)
        : const Color(0xFFF4F4F5);
    final hoverBg = isDark ? const Color(0xFF28272D) : const Color(0xFFFAFAFA);
    final selectionMarker = isDark
        ? const Color(0xFFD4D4D8)
        : const Color(0xFF475569);

    return DataRow(
      selected: isSelected,
      onSelectChanged: (_) => onSelectLog(log),
      color: WidgetStateProperty.resolveWith<Color?>((states) {
        if (isSelected) return selectedBg;
        if (states.contains(WidgetState.hovered)) return hoverBg;
        return Colors.transparent;
      }),
      cells: [
        // 1. DATE / TIME: Quiet selection marker and neutral text.
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 2,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? selectionMarker : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.schedule,
                size: 14,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : DefensysTokens.steelGrey,
              ),
              const SizedBox(width: 6),
              Text(
                timestamp,
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: DefensysTokens.textPrimaryOf(context),
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
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : DefensysTokens.steelGrey,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  processArea,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
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

        // 3. CONTROL ACTIVITY: Readable label; raw code remains in the details.
        DataCell(
          Tooltip(
            message: rawAction,
            child: SizedBox(
              width: 260,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actionLabel,
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDelete
                          ? Theme.of(context).colorScheme.error
                          : DefensysTokens.textPrimaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    log['target_label']?.toString() ??
                        AuditFormatUtils.extractResourceSubtitle(log),
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
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
                  color: DefensysTokens.maroonOf(
                    context,
                  ).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  actor.isNotEmpty ? actor[0].toUpperCase() : 'U',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
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
                    fontFamily: DefensysTokens.fontFamilyInter,
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

        DataCell(
          DefensysShadcnScope(
            child: ShadButton.ghost(
              onPressed: () => onSelectLog(log),
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: const Text('Details'),
            ),
          ),
        ),
      ],
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
        border: Border(
          top: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
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
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : DefensysTokens.steelGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                DropdownButton<int>(
                  value: pageSize,
                  underline: const SizedBox(),
                  isDense: true,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
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
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 12,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : DefensysTokens.steelGrey,
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
                  fontFamily: DefensysTokens.fontFamilyInter,
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
                onPressed: page < totalPages
                    ? () => onPageChanged(page + 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
