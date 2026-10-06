import 'package:flutter/material.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import '../dialogs/audit_raw_json_dialog.dart';
import 'audit_format_utils.dart';

class EventDetailsPanel extends StatelessWidget {
  final Map<String, dynamic>? log;
  final Function(Map<String, dynamic> log, String status)? onUpdateReviewStatus;
  final Function(Map<String, dynamic> log)? onExportPdf;
  final Function(String route)? onNavigateToResource;

  const EventDetailsPanel({
    super.key,
    required this.log,
    this.onUpdateReviewStatus,
    this.onExportPdf,
    this.onNavigateToResource,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);

    if (log == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
          border: Border.all(color: DefensysTokens.borderOf(context)),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 36,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              'Select an event to view details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      );
    }

    final item = log!;
    final rawAction = item['action']?.toString() ?? '';
    final actionLabel = AuditFormatUtils.formatAction(rawAction, item);
    final resourceSubtitle = AuditFormatUtils.extractResourceSubtitle(item);
    final processArea = AuditFormatUtils.formatProcessArea(item);
    final actor = item['actor_name']?.toString() ?? 'System';
    final status = item['review_status']?.toString() ?? 'needs_review';
    final timestamp = AuditFormatUtils.formatTimestamp(item['created_at']?.toString());
    final targetType = item['target_type']?.toString() ?? 'Resource';
    final targetId = item['target_id']?.toString() ?? '';
    final targetLabel = targetId.isNotEmpty ? '$targetType #$targetId' : targetType;

    final oldVals = item['old_values'] is Map ? Map<String, dynamic>.from(item['old_values']) : <String, dynamic>{};
    final newVals = item['new_values'] is Map ? Map<String, dynamic>.from(item['new_values']) : <String, dynamic>{};

    final isDelete = AuditFormatUtils.isDeleteAction(rawAction);
    final isUpdate = AuditFormatUtils.isUpdateAction(rawAction, oldVals, newVals);

    final diffEntries = isUpdate ? AuditFormatUtils.computeDiff(oldVals, newVals) : <AuditDiffEntry>[];
    final activeAttributes = isDelete
        ? AuditFormatUtils.extractAttributes(oldVals.isNotEmpty ? oldVals : newVals)
        : AuditFormatUtils.extractAttributes(newVals.isNotEmpty ? newVals : oldVals);

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
          // 1. Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 17,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Event Details',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: DefensysTokens.textPrimaryOf(context),
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                _buildStatusBadge(context, status, isDelete: isDelete),
                const SizedBox(width: 4),
                _buildHeaderMenu(context, item, status, isDelete: isDelete),
              ],
            ),
          ),
          const Divider(height: 1),

          // 2. Title & Subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDelete) ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x33DC2626) : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 20),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        actionLabel,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: isDelete
                              ? (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
                              : DefensysTokens.textPrimaryOf(context),
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        resourceSubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. Metadata Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _buildMetaRow(
                  context,
                  icon: Icons.person_outline_rounded,
                  label: 'Actor',
                  value: actor,
                ),
                const SizedBox(height: 8),
                _buildMetaRow(
                  context,
                  icon: Icons.calendar_today_outlined,
                  label: 'Date & Time',
                  value: timestamp,
                ),
                const SizedBox(height: 8),
                _buildMetaRow(
                  context,
                  icon: Icons.folder_outlined,
                  label: 'Process Area',
                  value: processArea,
                ),
                const SizedBox(height: 8),
                _buildMetaRow(
                  context,
                  icon: Icons.code_rounded,
                  label: 'Action Type',
                  value: isUpdate ? 'Updated' : (isDelete ? rawAction : rawAction),
                  isPill: isUpdate,
                ),
                const SizedBox(height: 8),
                _buildMetaRow(
                  context,
                  icon: Icons.gps_fixed_rounded,
                  label: 'Target Resource',
                  value: targetId.isNotEmpty ? '$targetLabel ($resourceSubtitle)' : targetLabel,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),

          // 4. Dynamic Content Body (Created vs Updated vs Deleted)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDelete)
                  _buildDeleteSection(context, item, activeAttributes)
                else if (isUpdate)
                  _buildUpdateDiffSection(context, item, diffEntries, oldVals, newVals)
                else
                  _buildCreateSection(context, item, activeAttributes),
              ],
            ),
          ),

          const Divider(height: 1),

          // 5. Footer Actions (Primary Review Workflow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1D24) : const Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: DefensysTokens.borderOf(context))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Review Status Context Hint
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        status == 'reviewed'
                            ? Icons.verified_outlined
                            : Icons.pending_actions_outlined,
                        size: 16,
                        color: status == 'reviewed'
                            ? const Color(0xFF059669)
                            : (isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          status == 'reviewed'
                              ? 'Audit entry is marked as reviewed'
                              : 'Pending administrative compliance review',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: status == 'reviewed'
                                ? const Color(0xFF059669)
                                : (isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Primary Review Action: "Mark as reviewed" or "Reopen review"
                if (status != 'reviewed')
                  FilledButton.icon(
                    onPressed: onUpdateReviewStatus != null
                        ? () => onUpdateReviewStatus!(item, 'reviewed')
                        : null,
                    icon: const Icon(Icons.check_rounded, size: 15),
                    label: const Text('Mark as reviewed'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      ),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: onUpdateReviewStatus != null
                        ? () => onUpdateReviewStatus!(item, 'needs_review')
                        : null,
                    icon: const Icon(Icons.replay_rounded, size: 15),
                    label: const Text('Reopen review'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD97706),
                      side: const BorderSide(color: Color(0xFFF59E0B)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool isPill = false,
  }) {
    final isDark = DefensysTokens.isDark(context);

    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Row(
            children: [
              Icon(icon, size: 15, color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: isPill
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2932) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }

  // --- DELETE STATE ---
  Widget _buildDeleteSection(
    BuildContext context,
    Map<String, dynamic> item,
    List<MapEntry<String, String>> attributes,
  ) {
    final isDark = DefensysTokens.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Red Callout Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x2EDB1414) : const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            border: Border.all(
              color: isDark ? const Color(0x44EF4444) : const Color(0xFFFECACA),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This resource has been deleted',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'The item has been removed from the portal and is no longer available for active defense use.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Last Known State Table
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 15, color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Last Known State',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => AuditRawJsonDialog.show(
                context,
                title: 'Last Known State JSON',
                data: item['old_values'] is Map ? item['old_values'] : item,
              ),
              icon: const Icon(Icons.code_rounded, size: 12),
              label: const Text('View as JSON', style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        _buildKeyValueTable(context, attributes),
      ],
    );
  }

  // --- UPDATE DIFF STATE ---
  Widget _buildUpdateDiffSection(
    BuildContext context,
    Map<String, dynamic> item,
    List<AuditDiffEntry> diffs,
    Map<String, dynamic> oldVals,
    Map<String, dynamic> newVals,
  ) {
    final isDark = DefensysTokens.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Change Diff Header
        Row(
          children: [
            Icon(Icons.compare_arrows_rounded, size: 16, color: DefensysTokens.maroonOf(context)),
            const SizedBox(width: 8),
            Text(
              'Change Diff',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (diffs.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1D24) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            child: Text(
              'No individual field values modified in payload snapshot.',
              style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: DefensysTokens.borderOf(context)),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Table Header
                Container(
                  color: isDark ? const Color(0xFF1E1D24) : const Color(0xFFF8FAFC),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: const Row(
                    children: [
                      Expanded(flex: 3, child: Text('Field', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                      Expanded(flex: 4, child: Text('Before', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                      SizedBox(width: 24, child: Center(child: Text('→', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))))),
                      Expanded(flex: 4, child: Text('After', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Rows
                ...diffs.map((diff) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context))),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            diff.field,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            diff.before,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 24,
                          child: Center(
                            child: Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF94A3B8)),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                            ),
                            child: Text(
                              diff.after,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

        const SizedBox(height: 18),

        // Other Details
        Row(
          children: [
            Icon(Icons.tune_rounded, size: 15, color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
            const SizedBox(width: 6),
            Text(
              'Other Details',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        _buildKeyValueTable(
          context,
          AuditFormatUtils.extractAttributes(newVals.isNotEmpty ? newVals : oldVals)
              .where((a) => !diffs.any((d) => d.field == a.key))
              .toList(),
        ),
      ],
    );
  }

  // --- CREATE STATE ---
  Widget _buildCreateSection(
    BuildContext context,
    Map<String, dynamic> item,
    List<MapEntry<String, String>> attributes,
  ) {
    final isDark = DefensysTokens.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Resource Details Header
        Row(
          children: [
            Icon(Icons.inventory_2_outlined, size: 16, color: DefensysTokens.maroonOf(context)),
            const SizedBox(width: 8),
            Text(
              'Resource Details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Initial State Table
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 15, color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Initial State (${attributes.length} attributes)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => AuditRawJsonDialog.show(
                context,
                title: 'Initial State JSON',
                data: item['new_values'] is Map ? item['new_values'] : item,
              ),
              icon: const Icon(Icons.code_rounded, size: 12),
              label: const Text('View as JSON', style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        _buildKeyValueTable(context, attributes),
      ],
    );
  }

  Widget _buildKeyValueTable(
    BuildContext context,
    List<MapEntry<String, String>> rows,
  ) {
    final isDark = DefensysTokens.isDark(context);

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1D24) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        ),
        child: Text(
          'No additional attributes recorded.',
          style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: isDark ? const Color(0xFF1E1D24) : const Color(0xFFF8FAFC),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Field', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                Expanded(flex: 3, child: Text('Value', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
              ],
            ),
          ),
          const Divider(height: 1),
          ...rows.map((entry) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context))),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, String status, {bool isDelete = false}) {
    final isDark = DefensysTokens.isDark(context);

    if (isDelete) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0x33DC2626) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close_rounded, size: 12, color: Color(0xFFDC2626)),
            SizedBox(width: 4),
            Text(
              'Deleted',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
            ),
          ],
        ),
      );
    }

    if (status == 'reviewed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: Color(0xFF059669)),
            SizedBox(width: 4),
            Text(
              'Reviewed',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded, size: 12, color: Color(0xFFD97706)),
          SizedBox(width: 4),
          Text(
            'Needs review',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMenu(
    BuildContext context,
    Map<String, dynamic> item,
    String status, {
    bool isDelete = false,
  }) {
    final isDark = DefensysTokens.isDark(context);
    final navRoute = _resolveNavigationRoute(item);

    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
      ),
      splashRadius: 18,
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        side: BorderSide(color: DefensysTokens.borderOf(context)),
      ),
      color: DefensysTokens.surfaceOf(context),
      onSelected: (val) {
        if (val == 'open_resource') {
          if (navRoute != null && onNavigateToResource != null) {
            onNavigateToResource!(navRoute);
          }
        } else if (val == 'json') {
          AuditRawJsonDialog.show(
            context,
            title: 'Raw Audit Log Payload',
            data: item,
          );
        } else if (val == 'pdf') {
          if (onExportPdf != null) {
            onExportPdf!(item);
          }
        } else if (val == 'reviewed' || val == 'needs_review') {
          if (onUpdateReviewStatus != null) {
            onUpdateReviewStatus!(item, val);
          }
        }
      },
      itemBuilder: (context) => [
        if (!isDelete && navRoute != null)
          PopupMenuItem(
            value: 'open_resource',
            child: Row(
              children: [
                const Icon(Icons.open_in_new_rounded, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _resolveActionText(item),
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'json',
          child: Row(
            children: [
              Icon(Icons.code_rounded, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'View Raw JSON',
                  style: TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'pdf',
          child: Row(
            children: [
              Icon(Icons.picture_as_pdf_outlined, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Export Evidence PDF',
                  style: TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        if (status != 'reviewed')
          const PopupMenuItem(
            value: 'reviewed',
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF059669)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mark as reviewed',
                    style: TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else
          const PopupMenuItem(
            value: 'needs_review',
            child: Row(
              children: [
                Icon(Icons.replay_rounded, size: 16, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reopen review',
                    style: TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String? _resolveNavigationRoute(Map<String, dynamic> item) {
    final category = item['category']?.toString() ?? '';
    final action = item['action']?.toString() ?? '';
    final targetType = item['target_type']?.toString() ?? '';

    if (action.startsWith('rubric.') || category == 'rubrics' || targetType == 'Rubric') {
      return AdminRoutes.rubrics;
    }
    if (category == 'user_management' || action.startsWith('user.')) {
      return AdminRoutes.users;
    }
    if (category == 'defense' || action.contains('stage')) {
      return AdminRoutes.defenseStages;
    }
    if (category == 'grade_center' || action.contains('grade')) {
      return AdminRoutes.gradeCenter;
    }
    if (category == 'repository' || action.contains('archive')) {
      return AdminRoutes.projectArchive;
    }
    return null;
  }

  String _resolveActionText(Map<String, dynamic> item) {
    final category = item['category']?.toString() ?? '';
    final action = item['action']?.toString() ?? '';
    final targetType = item['target_type']?.toString() ?? '';

    if (action.startsWith('rubric.') || category == 'rubrics' || targetType == 'Rubric') {
      return 'Open Rubric';
    }
    if (category == 'user_management' || action.startsWith('user.')) {
      return 'Open Users';
    }
    if (category == 'defense' || action.contains('stage')) {
      return 'Open Defense Stages';
    }
    if (category == 'grade_center' || action.contains('grade')) {
      return 'Open Grade Center';
    }
    if (category == 'repository' || action.contains('archive')) {
      return 'Open Archive';
    }
    return 'Open Resource';
  }
}
