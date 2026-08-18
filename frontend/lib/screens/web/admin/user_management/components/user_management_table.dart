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
    this.onResetPassword,
    this.onDeleteUser,
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
  final ValueChanged<Map<String, dynamic>>? onResetPassword;
  final ValueChanged<Map<String, dynamic>>? onDeleteUser;

  static const List<_ColumnSpec> _columns = [
    _ColumnSpec('User ID', 1.25),
    _ColumnSpec('Full Name', 2.45),
    _ColumnSpec('Email Address', 2.35),
    _ColumnSpec('System Role', 2.35),
    _ColumnSpec('Status', 1.55),
    _ColumnSpec('Action', 1.1),
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
      width: 160,
      child: DropdownButtonFormField<String>(
        initialValue: state.role,
        isExpanded: true,
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
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: columns.map((col) => _tableHeaderCell(col)).toList(),
      ),
    );
  }

  Widget _tableHeaderCell(_ColumnSpec column) {
    return Expanded(
      flex: (column.flex * 100).round(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.centerLeft,
        child: Text(
          column.title,
          style: const TextStyle(
            color: Color(0xFF5D6678),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _userRow(Map<String, dynamic> user) {
    final name = (user['name']?.toString() ??
            '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}')
        .trim();
    final displayName = name.isEmpty ? (user['username']?.toString() ?? '') : name;
    final isActive = user['is_active'] != false;

    return Container(
      height: 57,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _tableCell(
            Text(
              user['username']?.toString() ?? '',
              style: const TextStyle(
                color: DefensysUi.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            flex: 1.25,
          ),
          _tableCell(_bodyText(displayName), flex: 2.45),
          _tableCell(_bodyText(user['email']?.toString() ?? ''), flex: 2.35),
          _tableCell(_roleBadge(user), flex: 2.35),
          _tableCell(
            DefensysStatusBadge.success(
              label: isActive ? 'Active' : 'Inactive',
              showDot: isActive,
            ),
            flex: 1.55,
          ),
          _tableCell(_rowActions(user), flex: 1.1),
        ],
      ),
    );
  }

  List<Map<String, String>> _getIndividualRoles(Map<String, dynamic> user) {
    final role = user['role']?.toString() ?? 'student';
    final List<Map<String, String>> individualRoles = [];

    if (role == 'admin') {
      individualRoles.add({'tone': 'admin', 'label': 'Administrator'});
    } else if (role == 'student') {
      final displayRole = user['displayRole'];
      final label = displayRole is Map && displayRole['label'] != null
          ? displayRole['label'].toString()
          : (user['year_level']?.toString().isNotEmpty == true
              ? user['year_level'].toString()
              : 'Student');
      individualRoles.add({'tone': 'student', 'label': label});
    } else {
      // Faculty/General
      if (user['is_pit_lead'] == true) {
        final year = user['pit_lead_year'];
        final label = year != null && year.toString().isNotEmpty
            ? 'PIT Lead: $year'
            : 'PIT Lead';
        individualRoles.add({'tone': 'pit_lead', 'label': label});
      }
      if (user['is_adviser'] == true) {
        individualRoles.add({'tone': 'adviser', 'label': 'Adviser'});
      }
      if (user['is_panelist'] == true) {
        individualRoles.add({'tone': 'panelist', 'label': 'Panelist'});
      }
      if (user['is_documenter'] == true) {
        individualRoles.add({'tone': 'documenter', 'label': 'Documenter'});
      }

      final assignments = user['instructor_assignments'] as List?;
      if (assignments != null && assignments.isNotEmpty) {
        final years = assignments
            .map((a) => (a as Map)['year_level']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
        years.sort();
        if (years.isNotEmpty) {
          individualRoles.add({
            'tone': 'pit_instructor',
            'label': 'Instructor: ${years.join(', ')}',
          });
        }
      }

      if (individualRoles.isEmpty) {
        individualRoles.add({'tone': 'faculty', 'label': 'Faculty Member'});
      }
    }
    return individualRoles;
  }

  Widget _buildSingleBadge(String label, String tone) {
    final background = switch (tone) {
      'admin' => const Color(0xFFFDE8E8),
      'adviser' => const Color(0xFFECFDF5),
      'panelist' => const Color(0xFFF3E8FF),
      'pit_lead' => const Color(0xFFEFF6FF),
      'documenter' => const Color(0xFFCCFBF1),
      'faculty' => const Color(0xFFFFEDD5),
      'pit_instructor' => const Color(0xFFF0FDF4),
      _ => const Color(0xFFEFF6FF),
    };
    final textColor = switch (tone) {
      'admin' => const Color(0xFF9B1C1C),
      'adviser' => const Color(0xFF047857),
      'panelist' => const Color(0xFF7E22CE),
      'pit_lead' => const Color(0xFF1D4ED8),
      'documenter' => const Color(0xFF0F766E),
      'faculty' => const Color(0xFFEA580C),
      'pit_instructor' => const Color(0xFF15803D),
      _ => const Color(0xFF1E40AF),
    };
    final icon = switch (tone) {
      'admin' => Icons.admin_panel_settings_rounded,
      'adviser' => Icons.school_outlined,
      'panelist' => Icons.groups_2_outlined,
      'pit_lead' => Icons.flag_outlined,
      'documenter' => Icons.assignment_outlined,
      'faculty' => Icons.co_present_rounded,
      'pit_instructor' => Icons.co_present_rounded,
      _ => Icons.school_rounded,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        '+$count',
        style: const TextStyle(
          color: Color(0xFF4B5563),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _roleBadge(Map<String, dynamic> user) {
    final individualRoles = _getIndividualRoles(user);
    if (individualRoles.isEmpty) {
      return const SizedBox.shrink();
    }

    final tooltipMessage =
        individualRoles.map((r) => '• ${r['label']}').join('\n');
    final primaryRole = individualRoles[0];
    final hasMore = individualRoles.length > 1;

    Widget badgeContent;
    if (!hasMore) {
      badgeContent =
          _buildSingleBadge(primaryRole['label']!, primaryRole['tone']!);
    } else {
      badgeContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: _buildSingleBadge(
              primaryRole['label']!,
              primaryRole['tone']!,
            ),
          ),
          const SizedBox(width: 6),
          _buildCountBadge(individualRoles.length - 1),
        ],
      );
    }

    return Tooltip(
      message: 'Active Roles:\n$tooltipMessage',
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: badgeContent,
    );
  }

  Widget _rowActions(Map<String, dynamic> user) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: state.isSaving ? null : () => onEditUser(user),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.edit_square, color: DefensysUi.techBlue, size: 18),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: state.isSaving ? null : () => onOpenAccessControl(user),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.shield_rounded, color: DefensysUi.techBlue, size: 18),
          ),
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
      flex: (flex * 100).round(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: DefensysUi.textDark,
        fontSize: 13,
        fontWeight: FontWeight.w500,
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
