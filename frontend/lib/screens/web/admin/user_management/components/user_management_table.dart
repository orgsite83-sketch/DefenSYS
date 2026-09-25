import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';
import 'package:defensys/widgets/table/table.dart';

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

  @override
  Widget build(BuildContext context) {
    return DefensysTableCard(
      searchController: searchController,
      searchHint: 'Search users by ID, name, email...',
      isSearchEnabled: !state.isSaving,
      onSearchSubmitted: onSearchSubmitted,
      onSearchCleared: onClearFilters,
      filterControls: [
        _roleFilter(),
        _clearButton(),
      ],
      pagination: DefensysTablePagination(
        currentPage: currentPage,
        totalItems: state.users.length,
        rowsPerPage: rowsPerPage,
        rowsPerPageOptions: rowsPerPageOptions,
        itemLabel: 'users',
        onPageChanged: onPageChanged,
        onRowsPerPageChanged: onRowsPerPageChanged,
      ),
      child: DefensysDataTable<Map<String, dynamic>>(
        items: visibleUsers,
        isLoading: state.isLoading && state.users.isEmpty,
        emptyState: _emptyRows(),
        columns: [
          DefensysTableColumn(
            title: 'User ID',
            flex: 1.25,
            minWidth: 120,
            cellBuilder: (context, user, _) => Text(
              user['username']?.toString() ?? '',
              style: const TextStyle(
                color: DefensysUi.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          DefensysTableColumn(
            title: 'Full Name',
            flex: 2.45,
            minWidth: 180,
            cellBuilder: (context, user, _) {
              final name = (user['name']?.toString() ??
                      '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}')
                  .trim();
              final displayName = name.isEmpty ? (user['username']?.toString() ?? '') : name;
              return _bodyText(displayName);
            },
          ),
          DefensysTableColumn(
            title: 'Email Address',
            flex: 2.35,
            minWidth: 180,
            cellBuilder: (context, user, _) => _bodyText(user['email']?.toString() ?? ''),
          ),
          DefensysTableColumn(
            title: 'System Role',
            flex: 2.35,
            minWidth: 180,
            cellBuilder: (context, user, _) => _roleBadge(user),
          ),
          DefensysTableColumn(
            title: 'Status',
            flex: 1.55,
            minWidth: 120,
            cellBuilder: (context, user, _) {
              final isActive = user['is_active'] != false;
              return DefensysStatusBadge.success(
                label: isActive ? 'Active' : 'Inactive',
                showDot: isActive,
              );
            },
          ),
          DefensysTableColumn(
            title: 'Action',
            flex: 1.1,
            minWidth: 100,
            cellBuilder: (context, user, _) => _rowActions(user),
          ),
        ],
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
      icon: const Icon(Icons.clear_rounded, size: 16),
      label: const Text('Clear'),
      style: OutlinedButton.styleFrom(
        foregroundColor: DefensysUi.steelGrey,
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _roleFilter() {
    final activeRole = state.role;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: activeRole,
          style: const TextStyle(
            fontSize: 13,
            color: DefensysUi.textDark,
            fontFamily: DefensysUi.fontFamily,
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('All Faculty Roles')),
            DropdownMenuItem(value: 'faculty', child: Text('Faculty Member')),
            DropdownMenuItem(value: 'adviser', child: Text('Adviser')),
            DropdownMenuItem(value: 'pit_lead', child: Text('PIT Lead')),
            DropdownMenuItem(value: 'panelist', child: Text('Panelist')),
            DropdownMenuItem(value: 'documenter', child: Text('Documenter')),
            DropdownMenuItem(value: 'admin', child: Text('System Admin')),
          ],
          onChanged: (v) {
            if (v != null) onRoleFilterChanged(v);
          },
        ),
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
    final role = user['role']?.toString().toLowerCase() ?? 'student';
    final isFacultyOrAdmin = role == 'faculty' || role == 'admin';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Edit Profile',
          waitDuration: const Duration(milliseconds: 300),
          child: InkWell(
            onTap: state.isSaving ? null : () => onEditUser(user),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.edit_square, color: DefensysUi.techBlue, size: 18),
            ),
          ),
        ),
        if (isFacultyOrAdmin) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'Role & Access Control',
            waitDuration: const Duration(milliseconds: 300),
            child: InkWell(
              onTap: state.isSaving ? null : () => onOpenAccessControl(user),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.shield_rounded, color: DefensysUi.techBlue, size: 18),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _emptyRows() {
    final query = searchController.text.trim();
    return DefensysEmptyState.search(
      query: query.isNotEmpty ? query : null,
      title: query.isNotEmpty
          ? 'No Matching Users Found'
          : 'No Users in this Category',
      description: query.isNotEmpty
          ? 'No user records matched "$query". Try adjusting your search query or role filter.'
          : 'No user accounts found matching the active role criteria.',
      onReset: onClearFilters,
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
}

