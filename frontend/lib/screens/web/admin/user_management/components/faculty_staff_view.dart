import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';

import '../components/user_management_table.dart';
import '../dialogs/guest_code_dialog.dart';
import '../dialogs/user_create_edit_dialog.dart';

/// The Faculty & Staff management view within User Management.
class FacultyStaffView extends ConsumerStatefulWidget {
  const FacultyStaffView({
    super.key,
    required this.onOpenBulkImport,
    required this.onOpenAccessControl,
  });

  final VoidCallback onOpenBulkImport;
  final ValueChanged<Map<String, dynamic>> onOpenAccessControl;

  @override
  ConsumerState<FacultyStaffView> createState() => _FacultyStaffViewState();
}

class _FacultyStaffViewState extends ConsumerState<FacultyStaffView> {
  static const _maroon = DefensysUi.primaryMaroon;
  static const _muted = DefensysUi.steelGrey;
  static const _ink = DefensysUi.textDark;
  static const _line = Color(0xFFE5E7EB);
  static const _blue = DefensysUi.techBlue;

  final TextEditingController _searchController = TextEditingController();
  int _page = 0;
  int _rowsPerPage = 10;
  final List<int> _rowsPerPageOptions = const [10, 25, 50, 100];
  String _selectedRole = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userManagementProvider.notifier).fetchUsers(role: _selectedRole);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _count(UserManagementState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value != null) {
      final parsed = int.tryParse(value.toString());
      if (parsed != null) return parsed;
    }

    if (key == 'all') return state.users.length;
    if (key == 'faculty') {
      return state.users.where((u) {
        final r = u['role']?.toString().toLowerCase() ?? '';
        return r == 'faculty' || r == 'admin';
      }).length;
    }
    if (key == 'admins') {
      final v = state.counts['admins'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v != null) {
        final parsed = int.tryParse(v.toString());
        if (parsed != null) return parsed;
      }
      return state.users.where((u) {
        final r = u['role']?.toString().toLowerCase() ?? '';
        return r == 'admin';
      }).length;
    }
    return 0;
  }

  List<Map<String, dynamic>> _visibleUsers(List<Map<String, dynamic>> users) {
    final query = _searchController.text.trim().toLowerCase();
    var list = users.where((u) {
      final r = u['role']?.toString().toLowerCase() ?? '';
      return r != 'student';
    }).toList();

    if (_selectedRole.isNotEmpty) {
      list = list.where((u) {
        final r = u['role']?.toString().toLowerCase() ?? '';
        switch (_selectedRole) {
          case 'admin':
            return r == 'admin';
          case 'faculty':
            return r == 'faculty' || r == 'admin';
          case 'adviser':
            return u['is_adviser'] == true;
          case 'pit_lead':
            return u['is_pit_lead'] == true;
          case 'panelist':
            return u['is_panelist'] == true;
          case 'documenter':
            return u['is_documenter'] == true;
          default:
            return true;
        }
      }).toList();
    }
    if (query.isNotEmpty) {
      list = list.where((u) {
        final id = u['username']?.toString().toLowerCase() ?? '';
        final fn = u['first_name']?.toString().toLowerCase() ?? '';
        final ln = u['last_name']?.toString().toLowerCase() ?? '';
        final em = u['email']?.toString().toLowerCase() ?? '';
        return id.contains(query) || fn.contains(query) || ln.contains(query) || em.contains(query);
      }).toList();
    }
    final start = _page * _rowsPerPage;
    if (start >= list.length) return [];
    final end = (start + _rowsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  Future<void> _showUserDialog([Map<String, dynamic>? user]) async {
    final payload = await UserCreateEditDialog.show(
      context,
      user: user,
    );
    if (payload != null && mounted) {
      final notifier = ref.read(userManagementProvider.notifier);
      if (user != null) {
        final id = user['id'];
        final success = await notifier.updateUser(id is int ? id : int.parse(id.toString()), payload);
        if (success && mounted) {
          showSuccessToast(context, 'User updated successfully.');
        }
      } else {
        await notifier.addUser(payload);
        if (mounted) {
          showSuccessToast(context, 'User created successfully.');
        }
      }
    }
  }

  Future<void> _showGuestCodeDialog() async {
    final state = ref.read(userManagementProvider);
    final payload = await GuestCodeGenerateDialog.show(
      context,
      schedules: state.defenseSchedules,
    );
    if (payload != null && mounted) {
      final result = await ref.read(userManagementProvider.notifier).generateGuestCode(payload);
      if (result != null && mounted) {
        await GeneratedGuestCodeDialog.show(context, guestCode: result);
      }
    }
  }

  Future<void> _confirmResetPassword(Map<String, dynamic> user) async {
    final name = user['first_name'] ?? user['username'] ?? 'User';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset Password?',
      message: 'Reset password for $name to their default ID number?',
      confirmLabel: 'Reset Password',
    );
    if (confirmed == true && mounted) {
      final id = user['id'];
      await ref.read(userManagementProvider.notifier).resetUserPassword(id is int ? id : int.parse(id.toString()));
      if (mounted) {
        showSuccessToast(context, 'Password reset to default ID number.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userManagementProvider);
    final visibleUsers = _visibleUsers(state.users);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stat Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'All Users',
                value: '${_count(state, 'all')}',
                subtitle: 'Total system accounts',
                icon: Icons.groups_2_rounded,
                iconColor: _maroon,
                iconBg: const Color(0xFFFDF2F2),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'Faculty Members',
                value: '${_count(state, 'faculty')}',
                subtitle: 'Active faculty & advisers',
                icon: Icons.co_present_rounded,
                iconColor: _blue,
                iconBg: const Color(0xFFEFF6FF),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildMetricCard(
                title: 'System Administrators',
                value: '${_count(state, 'admins')}',
                subtitle: 'Full administrative access',
                icon: Icons.admin_panel_settings_rounded,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFECFDF5),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // Table Card
        UserManagementTable(
          state: state,
          visibleUsers: visibleUsers,
          searchController: _searchController,
          currentPage: _page,
          rowsPerPage: _rowsPerPage,
          rowsPerPageOptions: _rowsPerPageOptions,
          onSearchSubmitted: (_) => setState(() => _page = 0),
          onClearFilters: () {
            _searchController.clear();
            setState(() {
              _page = 0;
              _selectedRole = '';
            });
            ref.read(userManagementProvider.notifier).fetchUsers(role: '', search: '');
          },
          onRoleFilterChanged: (r) {
            setState(() {
              _page = 0;
              _selectedRole = r;
            });
            ref.read(userManagementProvider.notifier).fetchUsers(role: r);
          },
          onPageChanged: (p) => setState(() => _page = p),
          onRowsPerPageChanged: (n) {
            setState(() {
              _rowsPerPage = n;
              _page = 0;
            });
          },
          onEditUser: (user) => _showUserDialog(user),
          onOpenAccessControl: (user) => widget.onOpenAccessControl(user),
          onResetPassword: (user) => _confirmResetPassword(user),
          onDeleteUser: (user) => _showUserDialog(user),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
