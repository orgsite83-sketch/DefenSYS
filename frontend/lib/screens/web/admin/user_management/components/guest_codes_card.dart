import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/clipboard_copy.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';
import '../dialogs/guest_code_dialog.dart';

/// Card component displaying guest panelist codes table and verified academic credentials.
class GuestCodesCard extends StatelessWidget {
  const GuestCodesCard({
    super.key,
    required this.state,
    required this.onRevokeGuestCode,
  });

  final UserManagementState state;
  final ValueChanged<int> onRevokeGuestCode;

  int _guestCount(UserManagementState state, String key) {
    if (key == 'total') {
      return state.guestCodes.length;
    }
    if (key == 'active') {
      return state.guestCodes.where((c) => c['is_active'] == true).length;
    }
    return 0;
  }

  Future<void> _copyGuestCode(BuildContext context, String code) async {
    final copied = await copyTextToClipboard(code);
    if (copied && context.mounted) {
      showSuccessToast(
        context,
        'Guest panelist code copied to clipboard!',
      );
    }
  }

  String _formatTimestamp(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final monthNames = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final month = monthNames[dt.month - 1];
      final day = dt.day.toString().padLeft(2, '0');
      final year = dt.year;
      return '$month $day, $year';
    } catch (_) {
      return raw.length > 10 ? raw.substring(0, 10) : raw;
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A);
    final textSecondary = isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B);
    final active = _guestCount(state, 'active');
    final total = _guestCount(state, 'total');

    return SizedBox(
      width: double.infinity,
      child: DefensysCard(
        padding: const EdgeInsets.fromLTRB(25, 24, 25, 24),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.7) : const Color(0xFFFDE68A)),
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guest Evaluator Access Codes',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Temporary evaluation passes and academic credentials for external defense panelists',
                        style: TextStyle(color: textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.7) : const Color(0xFFFDE68A)),
                  ),
                  child: Text(
                    '$active active / $total total',
                    style: TextStyle(
                      color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _tableHeader(context, const [
              _ColumnSpec('Code', 1.2),
              _ColumnSpec('Evaluator Credentials', 3.0),
              _ColumnSpec('Defense Schedule', 2.1),
              _ColumnSpec('Created', 1.2),
              _ColumnSpec('Status', 1.3),
              _ColumnSpec('Action', 2.4),
            ]),
            if (state.guestCodes.isEmpty)
              _guestCodeEmptyRow()
            else
              ...state.guestCodes.map((code) => _guestCodeRow(context, state, code)),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader(BuildContext context, List<_ColumnSpec> columns) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC);
    final borderColor = isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0);
    final textSecondary = isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B);

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          top: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor, width: 1.5),
        ),
      ),
      child: Row(
        children: columns.map((col) => _tableHeaderCell(col, textSecondary)).toList(),
      ),
    );
  }

  Widget _tableHeaderCell(_ColumnSpec column, Color textColor) {
    return Expanded(
      flex: (column.flex * 10).toInt(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(
          column.title.toUpperCase(),
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  Widget _guestCodeEmptyRow() {
    return DefensysEmptyState.table(
      icon: Icons.vpn_key_outlined,
      title: 'No Guest Passcodes Generated',
      description:
          'Generate time-bounded access passcodes for guest evaluators.',
      size: DefensysEmptyStateSize.compact,
    );
  }

  Widget _guestCodeRow(
    BuildContext context,
    UserManagementState state,
    Map<String, dynamic> guestCode,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rowBg = isDark ? DefensysTokens.mistSurface : Colors.white;
    final borderColor = isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A);
    final textSecondary = isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B);
    final subtleFill = isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC);

    final code = guestCode['code']?.toString() ?? '';
    final isActive = guestCode['is_active'] == true;
    final id = _asInt(guestCode['id']);
    final rawName = guestCode['guest_name']?.toString() ?? '';
    final email = guestCode['email']?.toString() ?? '';
    final info = GuestPanelistInfo.parse(rawName);
    final scheduleLabel = guestCode['defense_schedule_label']?.toString() ?? 'Defense Schedule';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          // Code Column
          _tableCell(_codePill(code, isDark: isDark), flex: 1.2),

          // Evaluator Identity Cell
          _tableCell(
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.7) : const Color(0xFFFDE68A)),
                  ),
                  child: Center(
                    child: Text(
                      info.initials,
                      style: TextStyle(
                        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info.displayName,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        (info.affiliation != null && info.affiliation!.isNotEmpty)
                            ? info.affiliation!
                            : (email.isNotEmpty ? email : 'External Panelist'),
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            flex: 3.0,
          ),

          // Defense Schedule Column
          _tableCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: subtleFill,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                scheduleLabel.isEmpty ? 'Scheduled Defense' : scheduleLabel,
                style: TextStyle(
                  color: isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF334155),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            flex: 2.1,
          ),

          // Created Column
          _tableCell(
            Text(
              _formatTimestamp(guestCode['created_at']),
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
            flex: 1.2,
          ),

          // Status Column
          _tableCell(
            Align(
              alignment: Alignment.centerLeft,
              child: isActive
                  ? const DefensysStatusBadge.success(label: 'Active')
                  : const DefensysStatusBadge.inactive(label: 'Revoked'),
            ),
            flex: 1.3,
          ),

          // Action Column
          _tableCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _compactActionButton(
                  icon: Icons.content_copy_rounded,
                  label: 'Copy',
                  onTap: code.isEmpty ? null : () => _copyGuestCode(context, code),
                ),
                const SizedBox(width: 6),
                _compactActionButton(
                  icon: Icons.block_rounded,
                  label: 'Revoke',
                  danger: true,
                  onTap: !isActive || id == null || state.isSaving
                      ? null
                      : () => onRevokeGuestCode(id),
                ),
              ],
            ),
            flex: 2.4,
          ),
        ],
      ),
    );
  }

  Widget _codePill(String code, {bool isDark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? DefensysTokens.mistBorder : const Color(0xFFCBD5E1)),
      ),
      child: SelectableText(
        code.isEmpty ? 'N/A' : code,
        style: TextStyle(
          color: isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 10).toInt(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  Widget _compactActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final fg = danger ? const Color(0xFFDC2626) : const Color(0xFF7A110A);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: BorderSide(
          color: onTap == null
              ? const Color(0xFFE2E8F0)
              : (danger ? const Color(0xFFFECACA) : const Color(0xFFFECDD3)),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: onTap == null ? const Color(0xFF9CA3AF) : fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: onTap == null ? const Color(0xFF9CA3AF) : fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnSpec {
  const _ColumnSpec(this.title, this.flex);
  final String title;
  final double flex;
}
