import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/widgets/feedback_toast.dart';

import 'access_control/access_control_view.dart';
import 'bulk_import/bulk_import_view.dart';
import 'components/guest_codes_card.dart';
import 'components/user_management_table.dart';
import 'components/user_stat_cards.dart';
import 'dialogs/download_sample_csv_dialog.dart';
import 'dialogs/guest_code_dialog.dart';
import 'dialogs/user_create_edit_dialog.dart';

enum _Tab { main, bulkImport, accessControl }

/// Main User Management Screen Orchestrator (< 250 lines).
class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key, this.initialBulkImport = false});

  final bool initialBulkImport;

  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  late _Tab _activeTab;
  final TextEditingController _searchController = TextEditingController();

  int _page = 0;
  int _rowsPerPage = 10;
  final List<int> _rowsPerPageOptions = const [10, 25, 50, 100];

  Map<String, dynamic>? _accessControlUser;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialBulkImport ? _Tab.bulkImport : _Tab.main;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userManagementProvider.notifier).fetchUsers();
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAccessControl(Map<String, dynamic> user) {
    setState(() {
      _accessControlUser = Map<String, dynamic>.from(user);
      _activeTab = _Tab.accessControl;
    });
  }

  void _closeTab() {
    setState(() {
      _activeTab = _Tab.main;
      _accessControlUser = null;
    });
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
        await notifier.updateUser(id is int ? id : int.parse(id.toString()), payload);
      } else {
        await notifier.addUser(payload);
      }
      if (mounted) {
        showSuccessToast(context, user != null ? 'User updated successfully.' : 'User created successfully.');
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

  Future<void> _confirmRevokeGuestCode(int codeId) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Revoke Guest Code?',
      message: 'This will deactivate access for this external guest panelist.',
      confirmLabel: 'Revoke Code',
      destructive: true,
    );
    if (confirmed == true && mounted) {
      await ref.read(userManagementProvider.notifier).revokeGuestCode(codeId);
      if (mounted) {
        showSuccessToast(context, 'Guest code revoked.');
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

  List<Map<String, dynamic>> _visibleUsers(List<Map<String, dynamic>> users) {
    final query = _searchController.text.trim().toLowerCase();
    var list = users;
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userManagementProvider);
    final academicState = ref.watch(academicPeriodProvider);

    if (_activeTab == _Tab.bulkImport) {
      return BulkImportView(
        state: state,
        academicState: academicState,
        onBack: _closeTab,
        onPickFile: () {},
        onDownloadSample: () => DownloadSampleCsvDialog.show(context),
        onConfirmUpload: (students) async {
          final success = await ref.read(userManagementProvider.notifier).bulkImport(students);
          if (success && context.mounted) {
            showSuccessToast(context, '${students.length} students imported successfully!');
            _closeTab();
          }
        },
      );
    }

    if (_activeTab == _Tab.accessControl && _accessControlUser != null) {
      return AccessControlView(
        user: _accessControlUser!,
        state: state,
        onBack: _closeTab,
        onEditProfile: () => _showUserDialog(_accessControlUser),
        onResetPassword: () => _confirmResetPassword(_accessControlUser!),
        onSaveRoles: (payload) async {
          final id = _accessControlUser!['id'];
          final success = await ref.read(userManagementProvider.notifier).updateUser(
                id is int ? id : int.parse(id.toString()),
                payload,
              );
          if (success && context.mounted) {
            showSuccessToast(context, 'Role permissions saved.');
            _closeTab();
          }
        },
      );
    }

    final visibleUsers = _visibleUsers(state.users);

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            title: 'User & Team Management',
            subtitle: 'Manage system access, assign faculty roles, and configure student capstone teams.',
            actions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: state.isSaving ? null : () => setState(() => _activeTab = _Tab.bulkImport),
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('Bulk Import CSV'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: state.isSaving ? null : _showGuestCodeDialog,
                  icon: const Icon(Icons.key_rounded, size: 16),
                  label: const Text('Generate Guest Code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DefensysUi.warningText,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: state.isSaving ? null : () => _showUserDialog(),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: const Text('Add Single User'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DefensysUi.primaryMaroon,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          UserStatCards(
            state: state,
            onSelectRoleFilter: (role) {
              setState(() => _page = 0);
              ref.read(userManagementProvider.notifier).fetchUsers(role: role);
            },
          ),
          const SizedBox(height: 24),
          UserManagementTable(
            state: state,
            visibleUsers: visibleUsers,
            searchController: _searchController,
            currentPage: _page,
            rowsPerPage: _rowsPerPage,
            rowsPerPageOptions: _rowsPerPageOptions,
            onSearchSubmitted: (val) => setState(() => _page = 0),
            onClearFilters: () {
              _searchController.clear();
              setState(() => _page = 0);
              ref.read(userManagementProvider.notifier).fetchUsers(role: '', search: '');
            },
            onRoleFilterChanged: (v) {
              setState(() => _page = 0);
              ref.read(userManagementProvider.notifier).fetchUsers(role: v);
            },
            onPageChanged: (newPage) => setState(() => _page = newPage),
            onRowsPerPageChanged: (newRows) {
              setState(() {
                _rowsPerPage = newRows;
                _page = 0;
              });
            },
            onEditUser: (user) => _showUserDialog(user),
            onOpenAccessControl: (user) => _openAccessControl(user),
            onResetPassword: (user) => _confirmResetPassword(user),
            onDeleteUser: (user) => _showUserDialog(user),
          ),
          const SizedBox(height: 36),
          GuestCodesCard(
            state: state,
            onRevokeGuestCode: _confirmRevokeGuestCode,
          ),
        ],
      ),
    );
  }
}
