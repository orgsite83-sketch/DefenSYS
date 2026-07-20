import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';

/// Card component displaying the search bar, role filters, users table, badges, and pagination controls.
class UserManagementTable extends StatelessWidget {
  const UserManagementTable({
    super.key,
    required this.state,
    required this.visibleUsers,
    required this.searchController,
    required this.currentPage,
    required this.rowsPerPage,
    required this.rowsPerPageOptions,
    required this.onSearchSubmitted,
    required this.onClearFilters,
    required this.onRoleFilterChanged,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
    required this.onEditUser,
    required this.onOpenAccessControl,
    required this.onResetPassword,
    required this.onDeleteUser,
  });

  final UserManagementState state;
  final List<Map<String, dynamic>> visibleUsers;
  final TextEditingController searchController;
  final int currentPage;
  final int rowsPerPage;
  final List<int> rowsPerPageOptions;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearFilters;
  final ValueChanged<String> onRoleFilterChanged;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;
  final ValueChanged<Map<String, dynamic>> onEditUser;
  final ValueChanged<Map<String, dynamic>> onOpenAccessControl;
  final ValueChanged<Map<String, dynamic>> onResetPassword;
  final ValueChanged<Map<String, dynamic>> onDeleteUser;

  static const List<_ColumnSpec> _columns = [
    _ColumnSpec('User Info', 2.8),
    _ColumnSpec('Base Role', 1.4),
    _ColumnSpec('System Scope Roles', 3.8),
    _ColumnSpec('Status', 1.2),
    _ColumnSpec('Actions', 1.6),
  ];

  @override
  Widget build(BuildContext context) {
    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField()),
              const SizedBox(width: 16),
              _clearButton(),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [const Spacer(), _roleFilter()]),
          const SizedBox(height: 20),
          if (state.isLoading && state.users.isEmpty)
            DefensysSkeleton.list(count: 6, rowHeight: 52)
          else
            _usersTable(),
          const SizedBox(height: 19),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 15),
          _pagination(),
        ],
      ),
    );
  }

  Widget _searchField() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: DefensysUi.steelGrey,
            size: 19,
          ),
          hintText: 'Search users by ID, name, email, or team...',
          hintStyle: const TextStyle(color: DefensysUi.steelGrey, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: DefensysUi.primaryMaroon),
          ),
        ),
        onSubmitted: onSearchSubmitted,
      ),
    );
  }

  Widget _clearButton() {
    final hasSearch = searchController.text.trim().isNotEmpty;
    final hasRole = state.role.isNotEmpty;

    return OutlinedButton.icon(
      onPressed: (!hasSearch && !hasRole) || state.isSaving
          ? null
          : onClearFilters,
      icon: const Icon(Icons.close_rounded, size: 16),
      label: const Text('Clear Filters'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        foregroundColor: const Color(0xFF374151),
        side: const BorderSide(color: Color(0xFFD1D5DB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _roleFilter() {
    return SizedBox(
      height: 40,
      child: DropdownButtonFormField<String>(
        value: state.role,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.white,
        ),
        style: const TextStyle(fontSize: 13, color: DefensysUi.textDark),
        items: const [
          DropdownMenuItem(value: '', child: Text('All Roles')),
          DropdownMenuItem(value: 'admin', child: Text('Admin')),
          DropdownMenuItem(value: 'faculty', child: Text('Faculty')),
          DropdownMenuItem(value: 'student', child: Text('Student')),
        ],
        onChanged: (v) {
          if (v != null) onRoleFilterChanged(v);
        },
      ),
    );
  }

  Widget _usersTable() {
    return Column(
      children: [
        _tableHeader(_columns),
        if (visibleUsers.isEmpty)
          _emptyRows()
        else
          ...visibleUsers.map((user) => _userRow(user)),
      ],
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

  Widget _userRow(Map<String, dynamic> user) {
    final name =
        '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
    final displayName = name.isEmpty ? (user['username']?.toString() ?? '') : name;
    final isActive = user['is_active'] != false;

    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _tableCell(
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DefensysUi.textDark,
                  ),
                ),
                Text(
                  user['email']?.toString() ?? '',
                  style: const TextStyle(fontSize: 12, color: DefensysUi.steelGrey),
                ),
              ],
            ),
            flex: 2.8,
          ),
          _tableCell(_roleBadge(user), flex: 1.4),
          _tableCell(_systemScopeRolesBadges(user), flex: 3.8),
          _tableCell(
            isActive
                ? const DefensysStatusBadge.success(label: 'Active')
                : const DefensysStatusBadge.inactive(label: 'Inactive'),
            flex: 1.2,
          ),
          _tableCell(_rowActions(user), flex: 1.6),
        ],
      ),
    );
  }

  Widget _roleBadge(Map<String, dynamic> user) {
    final role = user['role']?.toString().toLowerCase() ?? 'student';
    Color bg = const Color(0xFFEFF6FF);
    Color fg = const Color(0xFF1D4ED8);
    String label = 'Student';

    if (role == 'admin') {
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFB91C1C);
      label = 'Admin';
    } else if (role == 'faculty') {
      bg = const Color(0xFFF0FDF4);
      fg = const Color(0xFF15803D);
      label = 'Faculty';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _systemScopeRolesBadges(Map<String, dynamic> user) {
    final badges = <Widget>[];
    if (user['is_panelist'] == true) {
      badges.add(_singleBadge('Panelist', 'purple'));
    }
    if (user['is_pit_lead'] == true) {
      final year = user['pit_lead_year']?.toString();
      final label = (year != null && year.isNotEmpty) ? 'PIT Lead ($year)' : 'PIT Lead';
      badges.add(_singleBadge(label, 'gold'));
    }
    if (user['is_adviser'] == true) {
      badges.add(_singleBadge('Adviser', 'blue'));
    }
    if (user['is_documenter'] == true) {
      badges.add(_singleBadge('Documenter', 'teal'));
    }

    if (badges.isEmpty) {
      return const Text('—', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13));
    }

    return Wrap(spacing: 6, runSpacing: 4, children: badges);
  }

  Widget _singleBadge(String label, String tone) {
    Color bg = const Color(0xFFF3F4F6);
    Color fg = const Color(0xFF374151);

    if (tone == 'purple') {
      bg = const Color(0xFFF3E8FF);
      fg = const Color(0xFF7E22CE);
    } else if (tone == 'gold') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
    } else if (tone == 'blue') {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0369A1);
    } else if (tone == 'teal') {
      bg = const Color(0xFFCCFBF1);
      fg = const Color(0xFF0F766E);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _rowActions(Map<String, dynamic> user) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit details & roles',
          icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF4B5563)),
          onPressed: () => onEditUser(user),
        ),
        IconButton(
          tooltip: 'Access Control & History',
          icon: const Icon(Icons.shield_outlined, size: 18, color: DefensysUi.primaryMaroon),
          onPressed: () => onOpenAccessControl(user),
        ),
        IconButton(
          tooltip: 'Reset Password',
          icon: const Icon(Icons.lock_reset_rounded, size: 18, color: Color(0xFFD97706)),
          onPressed: () => onResetPassword(user),
        ),
        IconButton(
          tooltip: 'Delete User',
          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFDC2626)),
          onPressed: () => onDeleteUser(user),
        ),
      ],
    );
  }

  Widget _emptyRows() {
    return Container(
      height: 60,
      alignment: Alignment.center,
      child: const Text(
        'No matching users found.',
        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
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

  Widget _pagination() {
    final totalCount = state.users.length;
    final totalPages = (totalCount / rowsPerPage).ceil();

    return Row(
      children: [
        Text(
          'Showing ${visibleUsers.isEmpty ? 0 : (currentPage * rowsPerPage) + 1} to '
          '${(currentPage * rowsPerPage) + visibleUsers.length} of $totalCount users',
          style: const TextStyle(fontSize: 13, color: DefensysUi.steelGrey),
        ),
        const Spacer(),
        Row(
          children: [
            const Text('Rows per page: ', style: TextStyle(fontSize: 13, color: DefensysUi.steelGrey)),
            DropdownButton<int>(
              value: rowsPerPage,
              underline: const SizedBox.shrink(),
              items: rowsPerPageOptions.map((opt) {
                return DropdownMenuItem(value: opt, child: Text('$opt'));
              }).toList(),
              onChanged: (v) {
                if (v != null) onRowsPerPageChanged(v);
              },
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
            ),
            Text('${currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}'),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: currentPage < totalPages - 1
                  ? () => onPageChanged(currentPage + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _ColumnSpec {
  const _ColumnSpec(this.title, this.flex);
  final String title;
  final double flex;
}
