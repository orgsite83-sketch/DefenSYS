import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/utils/clipboard_copy.dart';
import 'package:defensys/toasts/feedback_toast.dart';

/// Card component displaying guest panelist codes table and status.
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
    if (raw.isEmpty) return '—';
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
    final active = _guestCount(state, 'active');
    final total = _guestCount(state, 'total');

    return SizedBox(
      width: double.infinity,
      child: DefensysCard(
        padding: const EdgeInsets.fromLTRB(25, 28, 25, 28),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: DefensysUi.warningBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.key_rounded,
                    color: DefensysUi.primaryMaroon,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guest Panelist Codes',
                        style: TextStyle(
                          color: DefensysUi.textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Temporary access codes for external evaluators',
                        style: TextStyle(color: DefensysUi.steelGrey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: DefensysUi.warningBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$active active / $total total',
                    style: const TextStyle(
                      color: DefensysUi.warningText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _tableHeader(const [
              _ColumnSpec('Code', 1.2),
              _ColumnSpec('Guest Name', 1.8),
              _ColumnSpec('Defense Schedule', 2.7),
              _ColumnSpec('Created', 1.6),
              _ColumnSpec('Status', 1.4),
              _ColumnSpec('Action', 1.4),
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

  Widget _tableHeader(List<_ColumnSpec> columns) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Row(
        children: columns.map((col) => _tableHeaderCell(col)).toList(),
      ),
    );
  }

  Widget _tableHeaderCell(_ColumnSpec column) {
    return Expanded(
      flex: (column.flex * 10).toInt(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Text(
          column.title.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _guestCodeEmptyRow() {
    return Container(
      height: 58,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: const Text(
        'No guest panelist codes generated yet.',
        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
      ),
    );
  }

  Widget _guestCodeRow(
    BuildContext context,
    UserManagementState state,
    Map<String, dynamic> guestCode,
  ) {
    final code = guestCode['code']?.toString() ?? '';
    final isActive = guestCode['is_active'] == true;
    final id = _asInt(guestCode['id']);

    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _tableCell(_codePill(code), flex: 1.2),
          _tableCell(
            _bodyText(guestCode['guest_name']?.toString() ?? ''),
            flex: 1.8,
          ),
          _tableCell(
            _bodyText(guestCode['defense_schedule_label']?.toString() ?? ''),
            flex: 2.7,
          ),
          _tableCell(
            _bodyText(_formatTimestamp(guestCode['created_at'])),
            flex: 1.6,
          ),
          _tableCell(
            isActive
                ? const DefensysStatusBadge.success(label: 'Active')
                : const DefensysStatusBadge.inactive(label: 'Revoked'),
            flex: 1.4,
          ),
          _tableCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _compactActionButton(
                  icon: Icons.content_copy_rounded,
                  label: 'Copy',
                  onTap: code.isEmpty ? null : () => _copyGuestCode(context, code),
                ),
                const SizedBox(width: 8),
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
            flex: 1.4,
          ),
        ],
      ),
    );
  }

  Widget _codePill(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(5),
      ),
      child: SelectableText(
        code.isEmpty ? '—' : code,
        style: const TextStyle(
          color: DefensysUi.textDark,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 10).toInt(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '—' : value,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF374151),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _compactActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final fg = danger ? const Color(0xFFDC2626) : DefensysUi.primaryMaroon;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: onTap == null ? const Color(0xFF9CA3AF) : fg),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: onTap == null ? const Color(0xFF9CA3AF) : fg,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        side: BorderSide(
          color: onTap == null
              ? const Color(0xFFE5E7EB)
              : (danger ? const Color(0xFFFCA5A5) : const Color(0xFFF3C5C5)),
        ),
      ),
    );
  }
}

class _ColumnSpec {
  const _ColumnSpec(this.title, this.flex);
  final String title;
  final double flex;
}
