import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/user_management_provider.dart';

/// Top summary metric cards for User Management screen.
class UserStatCards extends StatelessWidget {
  const UserStatCards({
    super.key,
    required this.state,
    required this.onSelectRoleFilter,
  });

  final UserManagementState state;
  final ValueChanged<String> onSelectRoleFilter;

  int _count(UserManagementState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value != null) {
      final parsed = int.tryParse(value.toString());
      if (parsed != null) return parsed;
    }

    if (key == 'all') {
      return state.users.length;
    }
    if (key == 'faculty') {
      return state.users.where((u) {
        final r = u['role']?.toString().toLowerCase() ?? '';
        return r == 'faculty' || r == 'admin';
      }).length;
    }
    if (key == 'students') {
      return state.users.where((u) {
        final r = u['role']?.toString().toLowerCase() ?? '';
        return r == 'student';
      }).length;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final canTap = !state.isSaving;
    return Row(
      children: [
        Expanded(
          child: _SummaryCardItem(
            title: 'All Users',
            subtitle: '${_count(state, 'all')} Total',
            icon: Icons.groups_2_rounded,
            selected: state.role.isEmpty,
            onTap: canTap ? () => onSelectRoleFilter('') : null,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _SummaryCardItem(
            title: 'Faculty',
            subtitle: '${_count(state, 'faculty')} Active',
            icon: Icons.co_present_rounded,
            selected: state.role == 'faculty',
            onTap: canTap ? () => onSelectRoleFilter('faculty') : null,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _SummaryCardItem(
            title: 'Students',
            subtitle: '${_count(state, 'students')} Active',
            icon: Icons.school_rounded,
            iconColor: const Color(0xFF2563EB),
            selected: state.role == 'student',
            onTap: canTap ? () => onSelectRoleFilter('student') : null,
          ),
        ),
      ],
    );
  }
}

class _SummaryCardItem extends StatelessWidget {
  const _SummaryCardItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.selected = false,
    this.iconColor = DefensysUi.steelGrey,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? DefensysUi.primaryMaroon : const Color(0xFFE5E7EB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F2F4),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 25),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: DefensysUi.textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        mouseCursor: SystemMouseCursors.click,
        child: card,
      ),
    );
  }
}
