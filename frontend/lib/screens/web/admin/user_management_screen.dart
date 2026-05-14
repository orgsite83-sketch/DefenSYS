import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../services/academic_period_provider.dart';
import '../../../services/user_management_provider.dart';
import '../../../utils/csv_file_io.dart';
import 'widgets/defensys_admin_shell.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _gold = DefensysUi.accentGold;
  static const _blue = DefensysUi.techBlue;
  static const _line = Color(0xFFE5E7EB);
  static const List<int> _rowsPerPageOptions = [10, 25, 50, 100, 200, 500];

  final _searchController = TextEditingController();
  int _rowsPerPage = 10;
  int _page = 0;
  bool? _showBulkImport = false;
  String? _bulkImportType = 'student';
  String? _studentPeriodSource = 'explicit';
  String? _targetSemesterId = '';
  String? _batchYearLevel = '';
  String? _bulkCsv = '';

  bool get _isBulkImportVisible => _showBulkImport == true;
  String get _selectedBulkImportType => _bulkImportType ?? 'student';
  String get _selectedStudentPeriodSource => _studentPeriodSource ?? 'explicit';
  String get _selectedTargetSemesterId => _targetSemesterId ?? '';
  String get _selectedBatchYearLevel => _batchYearLevel ?? '';
  String get _csvDraft => _bulkCsv ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userManagementProvider.notifier).fetchUsers();
      ref.read(userManagementProvider.notifier).fetchGuestCodes();
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _ensurePageInRange(int userCount) {
    final pages = userCount == 0 ? 1 : (userCount / _rowsPerPage).ceil();
    final maxPage = pages - 1;
    if (_page > maxPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _page = maxPage);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userManagementProvider);
    _ensurePageInRange(state.users.length);
    final academicState = ref.watch(academicPeriodProvider);
    final visibleUsers = _pageUsers(state.users);

    if (_isBulkImportVisible) {
      return _bulkImportPage(state, academicState);
    }

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            title: 'User & Team Management',
            subtitle:
                'Manage system access, assign faculty roles, and configure student capstone teams.',
            actions: _headerActions(state),
          ),
          const SizedBox(height: 28),
          _summaryCards(state),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(state.error!, warning: true),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(state.message!),
          ],
          const SizedBox(height: 30),
          _usersTableCard(state, visibleUsers),
          const SizedBox(height: 62),
          _guestCodesCard(state),
        ],
      ),
    );
  }

  Widget _headerActions(UserManagementState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _secondaryButton(
          icon: Icons.description_rounded,
          label: 'CSV Template',
          onTap: _showCsvTemplateDialog,
        ),
        const SizedBox(width: 14),
        _secondaryButton(
          icon: Icons.file_upload_outlined,
          label: 'Bulk Import CSV',
          onTap: state.isSaving
              ? null
              : () => setState(() => _showBulkImport = true),
        ),
        const SizedBox(width: 14),
        _goldButton(
          icon: Icons.key_rounded,
          label: 'Generate Guest Code',
          onTap: state.isSaving ? null : _showGuestCodeDialog,
        ),
        const SizedBox(width: 14),
        _primaryButton(
          icon: Icons.person_add_alt_1_rounded,
          label: 'Add Single User',
          onTap: state.isSaving ? null : () => _showUserDialog(),
        ),
      ],
    );
  }

  Widget _summaryCards(UserManagementState state) {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            title: 'All Users',
            subtitle: '${_count(state, 'all')} Total',
            icon: Icons.groups_2_rounded,
            selected: true,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _summaryCard(
            title: 'Faculty',
            subtitle: '${_count(state, 'faculty')} Active',
            icon: Icons.co_present_rounded,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _summaryCard(
            title: 'Students',
            subtitle: '${_count(state, 'students')} Active',
            icon: Icons.school_rounded,
            iconColor: const Color(0xFF2563EB),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    bool selected = false,
    Color iconColor = _muted,
  }) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? _maroon : Colors.transparent),
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
                  color: _ink,
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
  }

  Widget _usersTableCard(
    UserManagementState state,
    List<Map<String, dynamic>> visibleUsers,
  ) {
    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField(state)),
              const SizedBox(width: 16),
              _clearButton(state),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [const Spacer(), _roleFilter(state)]),
          const SizedBox(height: 20),
          if (state.isLoading)
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator(color: _maroon)),
            )
          else
            _usersTable(state, visibleUsers),
          const SizedBox(height: 19),
          Container(height: 1, color: _line),
          const SizedBox(height: 15),
          _pagination(state),
        ],
      ),
    );
  }

  Widget _searchField(UserManagementState state) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 19),
          hintText: 'Search users by ID, name, email, or team...',
          hintStyle: const TextStyle(color: _muted, fontSize: 13),
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
            borderSide: const BorderSide(color: _maroon),
          ),
        ),
        onSubmitted: (value) {
          setState(() => _page = 0);
          ref.read(userManagementProvider.notifier).fetchUsers(search: value);
        },
      ),
    );
  }

  Widget _clearButton(UserManagementState state) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: state.isSaving
            ? null
            : () {
                _searchController.clear();
                setState(() => _page = 0);
                ref
                    .read(userManagementProvider.notifier)
                    .fetchUsers(search: '', role: '');
              },
        icon: const Icon(Icons.refresh_rounded, size: 17),
        label: const Text('Clear'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _roleFilter(UserManagementState state) {
    return Container(
      width: 142,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.role,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: _ink,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('Filter by Role...')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
            DropdownMenuItem(value: 'faculty', child: Text('Faculty')),
            DropdownMenuItem(value: 'student', child: Text('Student')),
          ],
          onChanged: state.isSaving
              ? null
              : (value) {
                  setState(() => _page = 0);
                  ref
                      .read(userManagementProvider.notifier)
                      .fetchUsers(role: value ?? '');
                },
        ),
      ),
    );
  }

  Widget _usersTable(
    UserManagementState state,
    List<Map<String, dynamic>> visibleUsers,
  ) {
    if (state.users.isEmpty) {
      return _emptyRows();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 640),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _tableHeader(const [
                _ColumnSpec('User ID', 1.25),
                _ColumnSpec('Full Name', 2.45),
                _ColumnSpec('Email Address', 2.35),
                _ColumnSpec('System Role', 2.35),
                _ColumnSpec('Status', 1.55),
                _ColumnSpec('Action', 1.1),
              ]),
              ...visibleUsers.map((user) => _userRow(state, user)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableHeader(List<_ColumnSpec> columns) {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(children: columns.map(_tableHeaderCell).toList()),
    );
  }

  Widget _tableHeaderCell(_ColumnSpec column) {
    return Expanded(
      flex: (column.flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            column.label,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _userRow(UserManagementState state, Map<String, dynamic> user) {
    return Container(
      height: 57,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          _tableCell(
            Text(
              user['username']?.toString() ?? '',
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            flex: 1.25,
          ),
          _tableCell(_bodyText(user['name']?.toString() ?? ''), flex: 2.45),
          _tableCell(_bodyText(user['email']?.toString() ?? ''), flex: 2.35),
          _tableCell(_roleBadge(user), flex: 2.35),
          _tableCell(
            DefensysStatusBadge.success(
              label: user['is_active'] == true ? 'Active' : 'Inactive',
              showDot: user['is_active'] == true,
            ),
            flex: 1.55,
          ),
          _tableCell(_rowActions(state, user), flex: 1.1),
        ],
      ),
    );
  }

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _roleBadge(Map<String, dynamic> user) {
    final role = user['role']?.toString() ?? 'student';
    final label = switch (role) {
      'admin' => 'Administrator',
      'faculty' => 'Faculty',
      _ => 'Student',
    };
    final background = switch (role) {
      'admin' => const Color(0xFFFDE8E8),
      'faculty' => const Color(0xFFFFEDD5),
      _ => const Color(0xFFEFF6FF),
    };
    final textColor = switch (role) {
      'admin' => const Color(0xFF9B1C1C),
      'faculty' => const Color(0xFFEA580C),
      _ => const Color(0xFF1E40AF),
    };
    final icon = switch (role) {
      'admin' => Icons.admin_panel_settings_rounded,
      'faculty' => Icons.co_present_rounded,
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
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowActions(UserManagementState state, Map<String, dynamic> user) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: state.isSaving ? null : () => _showUserDialog(user),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.edit_square, color: _blue, size: 18),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: state.isSaving ? null : () => _showUserDialog(user),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.shield_rounded, color: _blue, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _emptyRows() {
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: const Text(
        'No users found.',
        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      ),
    );
  }

  Widget _pagination(UserManagementState state) {
    final total = state.users.length;
    final totalCount = _count(state, 'all');
    final pages = total == 0 ? 1 : (total / _rowsPerPage).ceil();
    final safePage = _page.clamp(0, pages - 1);
    final start = total == 0 ? 0 : safePage * _rowsPerPage + 1;
    final end = total == 0
        ? 0
        : (safePage * _rowsPerPage + _rowsPerPage).clamp(0, total);

    return Row(
      children: [
        Text(
          'Showing $start-$end of ${totalCount == 0 ? total : totalCount} users',
          style: const TextStyle(
            color: Color(0xFF5D6678),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 16),
        _rowsPerPageDropdown(),
        const Spacer(),
        _pageButton(Icons.chevron_left_rounded, safePage > 0, () {
          setState(() => _page = safePage - 1);
        }),
        const SizedBox(width: 8),
        if (pages <= 10)
          ...List.generate(pages, (index) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _numberPageButton(index + 1, safePage == index, () {
                setState(() => _page = index);
              }),
            );
          })
        else ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Page ${safePage + 1} of $pages',
              style: const TextStyle(
                color: Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        _pageButton(Icons.chevron_right_rounded, safePage < pages - 1, () {
          setState(() => _page = safePage + 1);
        }),
      ],
    );
  }

  Widget _rowsPerPageDropdown() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Rows per page',
          style: TextStyle(
            color: Color(0xFF5D6678),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _rowsPerPageOptions.contains(_rowsPerPage)
                  ? _rowsPerPage
                  : _rowsPerPageOptions.first,
              isDense: true,
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              items: _rowsPerPageOptions
                  .map(
                    (n) => DropdownMenuItem<int>(
                      value: n,
                      child: Text('$n'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _rowsPerPage = value;
                  _page = 0;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _pageButton(IconData icon, bool enabled, VoidCallback onTap) {
    return SizedBox(
      width: 30,
      height: 36,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: const BorderSide(color: _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }

  Widget _numberPageButton(int number, bool selected, VoidCallback onTap) {
    return SizedBox(
      width: 30,
      height: 36,
      child: OutlinedButton(
        onPressed: selected ? null : onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          disabledForegroundColor: _maroon,
          foregroundColor: _ink,
          side: BorderSide(color: selected ? _maroon : _line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Text(
          number.toString(),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _guestCodesCard(UserManagementState state) {
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
                    color: _maroon,
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
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Temporary access codes for external evaluators',
                        style: TextStyle(color: _muted, fontSize: 12),
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
                    style: TextStyle(
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
              ...state.guestCodes.map((code) => _guestCodeRow(state, code)),
          ],
        ),
      ),
    );
  }

  Widget _guestCodeEmptyRow() {
    return Container(
      height: 58,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: const Text(
        'No guest panelist codes generated yet.',
        style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
      ),
    );
  }

  Widget _guestCodeRow(
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
        border: Border(bottom: BorderSide(color: _line)),
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
                  onTap: code.isEmpty ? null : () => _copyGuestCode(code),
                ),
                const SizedBox(width: 8),
                _compactActionButton(
                  icon: Icons.block_rounded,
                  label: 'Revoke',
                  danger: true,
                  onTap: !isActive || id == null || state.isSaving
                      ? null
                      : () => _confirmRevokeGuestCode(id),
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
      child: Text(
        code,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _compactActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    return SizedBox(
      height: 33,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? const Color(0xFFDC2626) : _ink,
          side: BorderSide(
            color: danger ? const Color(0xFFFCA5A5) : const Color(0xFFD1D5DB),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _bulkImportPage(
    UserManagementState state,
    AcademicPeriodState academicState,
  ) {
    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.output_rounded,
            title: 'Bulk Import Users',
            subtitle:
                'Upload a CSV file to create multiple users at once. Default password is set to their ID number.',
            actions: _secondaryButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back to Users',
              onTap: state.isSaving
                  ? null
                  : () => setState(() => _showBulkImport = false),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(state.error!, warning: true),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(state.message!),
          ],
          const SizedBox(height: 28),
          _csvFormatCard(),
          const SizedBox(height: 20),
          _uploadCsvCard(state, academicState),
        ],
      ),
    );
  }

  Widget _csvFormatCard() {
    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CSV Format',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your CSV must follow this column structure exactly. Column order matters.',
                  style: TextStyle(
                    color: Color(0xFF536079),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sampleCsvTable(),
                const SizedBox(height: 14),
                _infoBanner(
                  icon: Icons.info_rounded,
                  message:
                      'The CSV template stays the same. Use Student Batch when importing a student cohort with one shared academic context. Use Faculty / General Users for non-student imports so student-only academic setup does not interfere.',
                ),
                const SizedBox(height: 16),
                _secondaryButton(
                  icon: Icons.file_download_rounded,
                  label: 'Download Sample Template',
                  onTap: _downloadCsvTemplate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleCsvTable() {
    const columns = ['id_number', 'first_name', 'last_name', 'email', 'role'];
    const values = [
      '2024-0001',
      'Juan',
      'Dela Cruz',
      'juan@ustp.edu.ph',
      'student',
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        children: [
          Container(
            height: 38,
            color: const Color(0xFFF0F1F4),
            child: Row(
              children: columns
                  .map((column) => _sampleCsvCell(column, header: true))
                  .toList(),
            ),
          ),
          Container(
            height: 38,
            color: Colors.white,
            child: Row(
              children: values.map((value) => _sampleCsvCell(value)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleCsvCell(String value, {bool header = false}) {
    return Expanded(
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFDDE2EA))),
        ),
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: header ? _ink : const Color(0xFF536079),
            fontSize: 13,
            fontWeight: header ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _uploadCsvCard(
    UserManagementState state,
    AcademicPeriodState academicState,
  ) {
    final semesterOptions = _semesterOptions(academicState);
    final semesterValues = semesterOptions.map((option) => option.id);
    final safeSemesterValue = semesterValues.contains(_selectedTargetSemesterId)
        ? _selectedTargetSemesterId
        : null;

    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upload CSV',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Choose the import type first. Student-only options below are used only when you are importing a student batch.',
                  style: TextStyle(
                    color: Color(0xFF536079),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('IMPORT BATCH TYPE'),
                const SizedBox(height: 8),
                _dropdownBox(
                  value: _selectedBulkImportType,
                  hint: 'Select import type',
                  onChanged: state.isSaving
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _bulkImportType = value;
                            if (value != 'student') {
                              _targetSemesterId = '';
                              _batchYearLevel = '';
                            }
                          });
                        },
                  items: const [
                    DropdownMenuItem(
                      value: 'student',
                      child: Text('Student Batch'),
                    ),
                    DropdownMenuItem(
                      value: 'general',
                      child: Text('Faculty / General Users'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _helper(
                  _selectedBulkImportType == 'student'
                      ? 'Student Batch: rows will receive shared academic context.'
                      : 'Faculty / General Users: imports only accounts and roles.',
                ),
                if (_selectedBulkImportType == 'student') ...[
                  const SizedBox(height: 18),
                  _studentBatchOptions(
                    state: state,
                    semesterOptions: semesterOptions,
                    safeSemesterValue: safeSemesterValue,
                  ),
                ],
                const SizedBox(height: 20),
                _preflightReview(academicState, semesterOptions),
                const SizedBox(height: 20),
                _fieldLabel('CSV FILE'),
                const SizedBox(height: 8),
                _uploadDropZone(state),
                const SizedBox(height: 8),
                const Text(
                  'Columns: id_number, first_name, last_name, email, role',
                  style: TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    _primaryButton(
                      icon: Icons.system_update_alt_rounded,
                      label: state.isSaving ? 'Importing...' : 'Import Users',
                      onTap: state.isSaving
                          ? null
                          : () => _importBulkUsers(academicState),
                    ),
                    const SizedBox(width: 12),
                    _secondaryButton(
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      onTap: state.isSaving
                          ? null
                          : () => setState(() => _showBulkImport = false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentBatchOptions({
    required UserManagementState state,
    required List<_SemesterOption> semesterOptions,
    required String? safeSemesterValue,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Student Batch Options',
            style: TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'These settings apply only to imported Student rows and reuse the current import flow safely. For best results, upload one student year-level batch per CSV.',
            style: TextStyle(
              color: Color(0xFF536079),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('STUDENT PERIOD SOURCE'),
                    const SizedBox(height: 8),
                    _dropdownBox(
                      value: _selectedStudentPeriodSource,
                      hint: 'Select source',
                      onChanged: state.isSaving
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _studentPeriodSource = value;
                                if (value == 'active') {
                                  _targetSemesterId = '';
                                }
                              });
                            },
                      items: const [
                        DropdownMenuItem(
                          value: 'explicit',
                          child: Text('Explicit Target Semester'),
                        ),
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Use Active Semester'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _helper('Only used for Student Batch imports.'),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('TARGET SEMESTER'),
                    const SizedBox(height: 8),
                    _dropdownBox(
                      value: safeSemesterValue,
                      hint: '- Select semester -',
                      onChanged:
                          state.isSaving ||
                              _selectedStudentPeriodSource == 'active'
                          ? null
                          : (value) {
                              setState(() => _targetSemesterId = value ?? '');
                            },
                      items: semesterOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option.id,
                              child: Text(option.label),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 6),
                    _helper(
                      'Required only when Student Period Source is set to Explicit Target Semester.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _fieldLabel('BATCH YEAR LEVEL'),
          const SizedBox(height: 8),
          _dropdownBox(
            value: _selectedBatchYearLevel.isEmpty
                ? null
                : _selectedBatchYearLevel,
            hint: '- Select year level -',
            onChanged: state.isSaving
                ? null
                : (value) => setState(() => _batchYearLevel = value ?? ''),
            items: const [
              DropdownMenuItem(value: '1st Year', child: Text('1st Year')),
              DropdownMenuItem(value: '2nd Year', child: Text('2nd Year')),
              DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
              DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
            ],
          ),
          const SizedBox(height: 6),
          _helper(
            'Required for Student Batch imports. Must belong to the resolved target semester.',
          ),
        ],
      ),
    );
  }

  Widget _preflightReview(
    AcademicPeriodState academicState,
    List<_SemesterOption> semesterOptions,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.search_rounded, color: _maroon, size: 16),
              SizedBox(width: 6),
              Text(
                'Preflight Review',
                style: TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Review the batch context below before importing. This helps prevent mixed student cohorts or the wrong target semester from being applied.',
            style: TextStyle(
              color: Color(0xFF536079),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _preflightMetric(
                  'IMPORT MODE',
                  _selectedBulkImportType == 'student'
                      ? 'Student Batch'
                      : 'Faculty / General Users',
                ),
              ),
              Expanded(
                child: _preflightMetric(
                  'RESOLVED SEMESTER',
                  _resolvedSemesterLabel(academicState, semesterOptions),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _preflightMetric(
            'BATCH YEAR LEVEL',
            _selectedBulkImportType == 'student' &&
                    _selectedBatchYearLevel.isNotEmpty
                ? _selectedBatchYearLevel
                : '-',
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFF93C5FD)),
            ),
            child: Text(
              _selectedBulkImportType == 'student'
                  ? 'Imported Student rows will create Initial Student Academic Records using the selected batch context. Keep one upload to one student year-level batch. Split mixed student cohorts into separate imports so the shared academic context stays correct.'
                  : 'Faculty / General imports create accounts only. Student academic records are skipped for this import mode.',
              style: const TextStyle(
                color: Color(0xFF1D4ED8),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preflightMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
            color: _ink,
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _uploadDropZone(UserManagementState state) {
    final csv = _csvDraft;
    final parsedRows = _parseCsv(csv).length;

    return InkWell(
      onTap: state.isSaving ? null : _pickCsvFile,
      borderRadius: BorderRadius.circular(8),
      child: _DashedBorder(
        color: const Color(0xFFCBD5E1),
        radius: 8,
        child: Container(
          width: double.infinity,
          height: 136,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_upload_rounded,
                color: Color(0xFF98A2B3),
                size: 34,
              ),
              const SizedBox(height: 10),
              Text(
                csv.trim().isEmpty
                    ? 'Click to choose file or drag & drop'
                    : 'CSV content ready to import',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                csv.trim().isEmpty
                    ? 'Only .csv files accepted'
                    : '$parsedRows valid row${parsedRows == 1 ? '' : 's'} detected',
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdownBox({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: onChanged == null ? const Color(0xFFF3F4F6) : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
          style: const TextStyle(
            color: _ink,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF667085),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _helper(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF667085),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _infoBanner({required IconData icon, required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAE8),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _gold),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DefensysUi.warningText, size: 15),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: DefensysUi.warningText,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _goldButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFFFFFAE8),
          foregroundColor: _maroon,
          side: const BorderSide(color: _gold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _maroon,
          foregroundColor: _gold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _notice(String message, {bool warning = false}) {
    final color = warning ? DefensysUi.warningText : DefensysUi.successText;
    final background = warning ? DefensysUi.warningBg : DefensysUi.successBg;
    final border = warning
        ? DefensysUi.warningBorder
        : DefensysUi.successBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  List<Map<String, dynamic>> _pageUsers(List<Map<String, dynamic>> users) {
    final pages = users.isEmpty ? 1 : (users.length / _rowsPerPage).ceil();
    final safePage = _page.clamp(0, pages - 1);
    final start = safePage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, users.length);
    return users.sublist(start, end);
  }

  Future<void> _showCsvTemplateDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('CSV Template'),
        content: const SizedBox(
          width: 540,
          child: SelectableText(_sampleCsvTemplate),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadCsvTemplate() async {
    await downloadTextFile(
      filename: 'defensys-user-import-template.csv',
      content: _sampleCsvTemplate,
    );
  }

  Future<void> _showGuestCodeDialog() async {
    if (ref.read(userManagementProvider).defenseSchedules.isEmpty) {
      await ref.read(userManagementProvider.notifier).fetchGuestCodes();
    }

    if (!mounted) {
      return;
    }

    final state = ref.read(userManagementProvider);
    final schedules = state.defenseSchedules;
    final guestName = TextEditingController();
    final email = TextEditingController();
    String? selectedScheduleId = schedules.isEmpty
        ? null
        : schedules.first['id']?.toString();
    String? validationError;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFFFF5F5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
              contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              title: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: DefensysUi.warningBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.key_rounded,
                      color: DefensysUi.warningText,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Generate Guest Panelist Code',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Create temporary access for an external panelist.',
                          style: TextStyle(
                            color: DefensysUi.warningText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 430,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1, color: Color(0xFFF4C57C)),
                    const SizedBox(height: 22),
                    const Text(
                      'Guest Panelist Name',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: guestName,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Engr. Juan Dela Cruz',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Guest Email (optional)',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'guest@example.com',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Assign to Defense Schedule',
                      style: TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (schedules.isEmpty)
                      _dialogWarning(
                        'No scheduled defenses are available yet. Create a defense schedule before generating a guest code.',
                      )
                    else
                      _dropdownBox(
                        value: selectedScheduleId,
                        hint: '- Select a scheduled defense -',
                        items: schedules.map((schedule) {
                          final id = schedule['id']?.toString() ?? '';
                          final label =
                              schedule['label']?.toString() ??
                              'Defense Schedule #$id';
                          return DropdownMenuItem(
                            value: id,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedScheduleId = value;
                            validationError = null;
                          });
                        },
                      ),
                    if (validationError != null) ...[
                      const SizedBox(height: 12),
                      _dialogWarning(validationError!),
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: schedules.isEmpty
                      ? null
                      : () {
                          final name = guestName.text.trim();
                          final scheduleId = int.tryParse(
                            selectedScheduleId ?? '',
                          );

                          if (name.isEmpty) {
                            setDialogState(() {
                              validationError =
                                  'Guest panelist name is required.';
                            });
                            return;
                          }
                          if (scheduleId == null) {
                            setDialogState(() {
                              validationError =
                                  'Select a defense schedule first.';
                            });
                            return;
                          }

                          Navigator.pop(dialogContext, {
                            'guest_name': name,
                            if (email.text.trim().isNotEmpty)
                              'email': email.text.trim(),
                            'defense_schedule': scheduleId,
                          });
                        },
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: const Text('Generate & Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DefensysUi.warningText,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    guestName.dispose();
    email.dispose();

    if (payload == null || !mounted) {
      return;
    }

    final guestCode = await ref
        .read(userManagementProvider.notifier)
        .generateGuestCode(payload);

    if (guestCode != null && mounted) {
      await _showGeneratedGuestCodeDialog(guestCode);
    }
  }

  Widget _dialogWarning(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DefensysUi.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DefensysUi.warningBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: DefensysUi.warningText,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _showGeneratedGuestCodeDialog(
    Map<String, dynamic> guestCode,
  ) async {
    final code = guestCode['code']?.toString() ?? '';
    final guestName = guestCode['guest_name']?.toString() ?? 'Guest panelist';
    final schedule =
        guestCode['defense_schedule_label']?.toString() ?? 'Defense schedule';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: DefensysUi.successBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: DefensysUi.successText,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Code Generated Successfully!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DefensysUi.successText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Share this code with the guest panelist.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        ),
        content: SizedBox(
          width: 390,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFCBD5E1),
                    style: BorderStyle.solid,
                  ),
                ),
                child: SelectableText(
                  code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'For: $guestName - Defense: $schedule',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton.icon(
            onPressed: code.isEmpty ? null : () => _copyGuestCode(code),
            icon: const Icon(Icons.content_copy_rounded, size: 16),
            label: const Text('Copy Code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyGuestCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    _snack('Guest code copied.');
  }

  Future<void> _confirmRevokeGuestCode(int codeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke guest code?'),
        content: const Text(
          'This will prevent the guest panelist from using this access code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(userManagementProvider.notifier).revokeGuestCode(codeId);
    }
  }

  Future<void> _showUserDialog([Map<String, dynamic>? user]) async {
    final editing = user != null;
    final username = TextEditingController(
      text: user?['username']?.toString() ?? '',
    );
    final firstName = TextEditingController(
      text: user?['first_name']?.toString() ?? '',
    );
    final lastName = TextEditingController(
      text: user?['last_name']?.toString() ?? '',
    );
    final email = TextEditingController(text: user?['email']?.toString() ?? '');
    final password = TextEditingController();
    final pitLeadYear = TextEditingController(
      text: user?['pit_lead_year']?.toString() ?? '',
    );
    final adviserPhase = TextEditingController(
      text: user?['adviser_phase']?.toString() ?? '',
    );

    var role = user?['role']?.toString() ?? 'student';
    var isPanelist = user?['is_panelist'] == true;
    var isPitLead = user?['is_pit_lead'] == true;
    var isAdviser = user?['is_adviser'] == true;
    var isRepoAssistant = user?['is_repo_assistant'] == true;
    var isUploader = user?['is_uploader'] == true;
    var isActive = user?['is_active'] != false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isFaculty = role == 'admin' || role == 'faculty';

            return AlertDialog(
              title: Text(editing ? 'Edit User' : 'Add Single User'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: username,
                        enabled: !editing,
                        decoration: const InputDecoration(
                          labelText: 'ID Number / Username',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: firstName,
                              decoration: const InputDecoration(
                                labelText: 'First Name',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: lastName,
                              decoration: const InputDecoration(
                                labelText: 'Last Name',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: email,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(
                          labelText: 'Base Role',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Admin'),
                          ),
                          DropdownMenuItem(
                            value: 'faculty',
                            child: Text('Faculty'),
                          ),
                          DropdownMenuItem(
                            value: 'student',
                            child: Text('Student'),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            role = value ?? 'student';
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: editing
                              ? 'New Password (optional)'
                              : 'Password (optional, defaults to ID)',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active account'),
                        value: isActive,
                        onChanged: (value) {
                          setDialogState(() {
                            isActive = value;
                          });
                        },
                      ),
                      if (isFaculty) ...[
                        const Divider(),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Defense Panelist'),
                          value: isPanelist,
                          onChanged: (value) {
                            setDialogState(() {
                              isPanelist = value ?? false;
                            });
                          },
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('PIT Lead'),
                          value: isPitLead,
                          onChanged: (value) {
                            setDialogState(() {
                              isPitLead = value ?? false;
                              if (!isPitLead) {
                                isRepoAssistant = false;
                              }
                            });
                          },
                        ),
                        if (isPitLead)
                          TextField(
                            controller: pitLeadYear,
                            decoration: const InputDecoration(
                              labelText: 'PIT Lead Year',
                              hintText: '4th Year',
                            ),
                          ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Project Adviser'),
                          value: isAdviser,
                          onChanged: (value) {
                            setDialogState(() {
                              isAdviser = value ?? false;
                            });
                          },
                        ),
                        if (isAdviser)
                          TextField(
                            controller: adviserPhase,
                            decoration: const InputDecoration(
                              labelText: 'Adviser Phase',
                              hintText: 'Capstone 1',
                            ),
                          ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Repository Assistant'),
                          subtitle: const Text('Requires PIT Lead'),
                          value: isRepoAssistant,
                          onChanged: isPitLead
                              ? (value) {
                                  setDialogState(() {
                                    isRepoAssistant = value ?? false;
                                  });
                                }
                              : null,
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Uploader'),
                          subtitle: const Text('Can upload project files'),
                          value: isUploader,
                          onChanged: isFaculty
                              ? (value) {
                                  setDialogState(() {
                                    isUploader = value ?? false;
                                  });
                                }
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(editing ? 'Save Changes' : 'Create User'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      username.dispose();
      firstName.dispose();
      lastName.dispose();
      email.dispose();
      password.dispose();
      pitLeadYear.dispose();
      adviserPhase.dispose();
      return;
    }

    final payload = {
      'username': username.text.trim(),
      'first_name': firstName.text.trim(),
      'last_name': lastName.text.trim(),
      'email': email.text.trim(),
      'role': role,
      'is_active': isActive,
      'is_panelist': isPanelist,
      'is_pit_lead': isPitLead,
      'pit_lead_year': isPitLead ? pitLeadYear.text.trim() : null,
      'is_adviser': isAdviser,
      'adviser_phase': isAdviser ? adviserPhase.text.trim() : null,
      'is_repo_assistant': isRepoAssistant,
      'is_uploader': isUploader,
      if (password.text.trim().isNotEmpty) 'password': password.text.trim(),
    };

    username.dispose();
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    password.dispose();
    pitLeadYear.dispose();
    adviserPhase.dispose();

    if (!mounted) {
      return;
    }

    if (editing) {
      await ref
          .read(userManagementProvider.notifier)
          .updateUser(_asInt(user['id'])!, payload);
    } else {
      await ref.read(userManagementProvider.notifier).addUser(payload);
    }
  }

  Future<void> _pickCsvFile() async {
    try {
      final csv = await pickCsvTextFile();
      if (!mounted || csv == null) {
        return;
      }

      if (_parseCsv(csv).isEmpty) {
        _snack('Selected file is not a valid DefenSYS CSV template.');
        return;
      }

      setState(() => _bulkCsv = csv);
    } catch (e) {
      _snack('Could not read CSV file: $e');
    }
  }

  Future<void> _importBulkUsers(AcademicPeriodState academicState) async {
    final csv = _csvDraft;
    if (csv.trim().isEmpty) {
      _snack('Choose or paste a CSV file first.');
      return;
    }

    final rows = _parseCsv(csv);
    if (rows.isEmpty) {
      _snack('CSV has no valid rows.');
      return;
    }

    final studentContext = _studentContext(academicState);
    if (_selectedBulkImportType == 'student' && studentContext == null) {
      return;
    }

    final imported = await ref
        .read(userManagementProvider.notifier)
        .bulkImport(rows, studentContext: studentContext);

    if (!mounted) {
      return;
    }

    if (imported) {
      setState(() {
        _showBulkImport = false;
        _bulkCsv = '';
      });
    }
  }

  Map<String, dynamic>? _studentContext(AcademicPeriodState academicState) {
    if (_selectedBulkImportType != 'student') {
      return null;
    }

    if (_selectedBatchYearLevel.isEmpty) {
      _snack('Select the student batch year level first.');
      return null;
    }

    if (_selectedStudentPeriodSource == 'active') {
      if (academicState.activeSemester == null) {
        _snack('There is no active semester to use for this import.');
        return null;
      }

      return {
        'use_active_semester': true,
        'year_level': _selectedBatchYearLevel,
      };
    }

    final semesterId = int.tryParse(_selectedTargetSemesterId);
    if (semesterId == null) {
      _snack('Select the target semester first.');
      return null;
    }

    return {'semester_id': semesterId, 'year_level': _selectedBatchYearLevel};
  }

  List<Map<String, dynamic>> _parseCsv(String csv) {
    final lines = csv
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.length < 2) {
      return [];
    }

    final headers = lines.first
        .split(',')
        .map((header) => header.trim().toLowerCase().replaceFirst('\ufeff', ''))
        .toList();
    final idIndex = headers.indexOf('id_number');
    final firstIndex = headers.indexOf('first_name');
    final lastIndex = headers.indexOf('last_name');
    final emailIndex = headers.indexOf('email');
    final roleIndex = headers.indexOf('role');
    final yearLevelIndex = headers.indexOf('year_level');

    if ([idIndex, firstIndex, lastIndex, emailIndex, roleIndex].contains(-1)) {
      return [];
    }

    return lines
        .skip(1)
        .map((line) {
          final columns = line.split(',').map((cell) => cell.trim()).toList();
          String read(int index) =>
              index < columns.length ? columns[index] : '';

          return {
            'id_number': read(idIndex),
            'first_name': read(firstIndex),
            'last_name': read(lastIndex),
            'email': read(emailIndex),
            'role': read(roleIndex).isEmpty ? 'student' : read(roleIndex),
            if (yearLevelIndex != -1 && read(yearLevelIndex).isNotEmpty)
              'year_level': read(yearLevelIndex),
          };
        })
        .where((row) => row['id_number']!.isNotEmpty)
        .toList();
  }

  List<_SemesterOption> _semesterOptions(AcademicPeriodState state) {
    final options = <_SemesterOption>[];

    for (final year in state.schoolYears) {
      final yearLabel =
          year['label']?.toString() ?? year['school_year']?.toString() ?? '';
      final semesters = year['semesters'];
      if (semesters is! List) {
        continue;
      }

      for (final rawSemester in semesters.whereType<Map>()) {
        final semester = Map<String, dynamic>.from(rawSemester);
        final id = _asInt(semester['id']);
        if (id == null) {
          continue;
        }

        options.add(
          _SemesterOption(
            id.toString(),
            _semesterOptionLabel(semester, yearLabel),
          ),
        );
      }
    }

    return options;
  }

  String _semesterOptionLabel(Map<String, dynamic> semester, String yearLabel) {
    final displayName = semester['display_name']?.toString();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final label = semester['label']?.toString() ?? 'Semester';
    return yearLabel.isEmpty ? label : '$label, A.Y. $yearLabel';
  }

  String _resolvedSemesterLabel(
    AcademicPeriodState state,
    List<_SemesterOption> semesterOptions,
  ) {
    if (_selectedBulkImportType != 'student') {
      return '-';
    }

    if (_selectedStudentPeriodSource == 'active') {
      final activeSemester = state.activeSemester;
      if (activeSemester == null) {
        return '-';
      }

      final displayName = activeSemester['display_name']?.toString();
      if (displayName != null && displayName.isNotEmpty) {
        return displayName;
      }

      final label = activeSemester['label']?.toString() ?? 'Active Semester';
      final year = activeSemester['school_year']?.toString() ?? '';
      return year.isEmpty ? label : '$label, A.Y. $year';
    }

    for (final option in semesterOptions) {
      if (option.id == _selectedTargetSemesterId) {
        return option.label;
      }
    }

    return '-';
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  int _count(UserManagementState state, String key) {
    final value = state.counts[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _guestCount(UserManagementState state, String key) {
    final value = state.guestCounts[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatTimestamp(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) {
      return '';
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }

    final local = parsed.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${months[local.month - 1]} ${local.day}, ${local.year} $hour:$minute $period';
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static const _sampleCsvTemplate =
      'id_number,first_name,last_name,email,role\n'
      '2024-0001,Juan,Dela Cruz,juan@ustp.edu.ph,student\n'
      'FAC-0001,Ada,Lovelace,ada@ustp.edu.ph,faculty\n';
}

class _ColumnSpec {
  final String label;
  final double flex;

  const _ColumnSpec(this.label, this.flex);
}

class _SemesterOption {
  final String id;
  final String label;

  const _SemesterOption(this.id, this.label);
}

class _DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;

  const _DashedBorder({
    required this.child,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect.deflate(0.7), Radius.circular(radius)),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 6;
        canvas.drawPath(
          metric.extractPath(
            distance,
            next > metric.length ? metric.length : next,
          ),
          paint,
        );
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
