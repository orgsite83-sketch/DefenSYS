import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/academic_period_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../services/user_management_provider.dart';
import '../../../utils/clipboard_copy.dart';
import '../../../utils/csv_file_io.dart';
import '../../../utils/student_bulk_import_csv.dart';
import '../../../utils/user_bulk_import_draft.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../widgets/defensys_skeleton.dart';
import '../../../widgets/feedback_toast.dart';
import '../../../widgets/confirm_dialog.dart';
import 'widgets/defensys_admin_shell.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key, this.initialBulkImport = false});

  final bool initialBulkImport;

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

enum _BulkImportExitChoice { save, discard, stay }

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _gold = DefensysUi.accentGold;
  static const _blue = DefensysUi.techBlue;
  static const _line = Color(0xFFE5E7EB);
  static const List<int> _rowsPerPageOptions = [10, 25, 50, 100, 200, 500];
  static const List<int> _bulkReviewRowsPerPageOptions = [10, 25, 50];

  /// Canonical labels stored in `pit_lead_year` (matches team year_level usage).
  static const List<String> _pitLeadYearOptions = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
  ];

  static String? _normalizePitLeadYear(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    for (final y in _pitLeadYearOptions) {
      if (y.toLowerCase() == s.toLowerCase()) return y;
    }
    return null;
  }

  final _searchController = TextEditingController();
  final _bulkReviewSearchController = TextEditingController();
  int _rowsPerPage = 10;
  int _page = 0;
  int _bulkReviewRowsPerPage = 10;
  int _bulkReviewPage = 0;
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

  Map<String, dynamic>? _accessControlUser;
  String _acRole = 'student';
  bool _acActive = true;
  bool _acPanelist = false;
  bool _acPitLead = false;
  bool _acAdviser = false;
  bool _acDocumenter = false;
  String? _acPitLeadYear;
  List<Map<String, dynamic>> _roleAssignments = [];
  bool _roleAssignmentsLoading = false;
  Timer? _successNoticeTimer;
  Timer? _bulkDraftSaveTimer;
  UserBulkImportDraft? _savedBulkDraft;
  String? _bulkImportSessionBaseline;
  String? _bulkImportPersistedSnapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBulkDraft();
      ref.read(userManagementProvider.notifier).fetchUsers();
      ref.read(userManagementProvider.notifier).fetchGuestCodes();
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
      if (widget.initialBulkImport && mounted) {
        _openBulkImport();
      }
    });
  }

  @override
  void dispose() {
    _successNoticeTimer?.cancel();
    _bulkDraftSaveTimer?.cancel();
    _searchController.dispose();
    _bulkReviewSearchController.dispose();
    super.dispose();
  }

  void _dismissNotice() {
    _successNoticeTimer?.cancel();
    ref.read(userManagementProvider.notifier).clearNotice();
  }

  void _dismissError() {
    ref.read(userManagementProvider.notifier).clearError();
  }

  void _scheduleSuccessNoticeAutoDismiss(String message) {
    _successNoticeTimer?.cancel();
    _successNoticeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      final current = ref.read(userManagementProvider).message;
      if (current == message) {
        ref.read(userManagementProvider.notifier).clearNotice();
      }
    });
  }

  Future<void> _loadBulkDraft() async {
    final draft = await loadUserBulkImportDraft();
    if (!mounted || draft == null) {
      return;
    }
    setState(() => _savedBulkDraft = draft);
  }

  int _bulkImportWarningCount() {
    if (_csvDraft.trim().isEmpty) {
      return 0;
    }
    final rows = _parseCsv(_csvDraft);
    final official = _selectedBulkImportType == 'student'
        ? _parseOfficialClassListCsv(_csvDraft)
        : const _AdminOfficialClassListParseResult(metadata: {}, students: []);
    return _bulkImportBlockingIssues(rows).length +
        _bulkImportWarnings(rows, official).length;
  }

  Future<void> _persistBulkDraft() async {
    final csv = _csvDraft;
    if (csv.trim().isEmpty) {
      await clearUserBulkImportDraft();
      if (mounted) {
        setState(() => _savedBulkDraft = null);
      }
      return;
    }

    final draft = UserBulkImportDraft(
      csv: csv,
      importType: _selectedBulkImportType,
      studentPeriodSource: _selectedStudentPeriodSource,
      targetSemesterId: _selectedTargetSemesterId,
      batchYearLevel: _selectedBatchYearLevel,
      savedAt: DateTime.now(),
      rowCount: _parseCsv(csv).length,
      warningCount: _bulkImportWarningCount(),
    );
    await saveUserBulkImportDraft(draft);
    if (mounted) {
      setState(() => _savedBulkDraft = draft);
      _bulkImportPersistedSnapshot = _bulkImportSnapshot();
    }
  }

  void _scheduleBulkDraftSave() {
    if (_csvDraft.trim().isEmpty) {
      return;
    }
    _bulkDraftSaveTimer?.cancel();
    _bulkDraftSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _persistBulkDraft();
    });
  }

  String _bulkImportSnapshot() {
    return jsonEncode({
      'csv': _csvDraft,
      'import_type': _selectedBulkImportType,
      'student_period_source': _selectedStudentPeriodSource,
      'target_semester_id': _selectedTargetSemesterId,
      'batch_year_level': _selectedBatchYearLevel,
    });
  }

  void _captureBulkImportBaseline({bool persisted = false}) {
    final snap = _bulkImportSnapshot();
    _bulkImportSessionBaseline ??= snap;
    if (persisted) {
      _bulkImportPersistedSnapshot = snap;
    }
  }

  bool get _isBulkImportDirty {
    if (!_isBulkImportVisible || _csvDraft.trim().isEmpty) return false;
    if (_bulkDraftSaveTimer?.isActive ?? false) return true;
    final current = _bulkImportSnapshot();
    final baseline = _bulkImportPersistedSnapshot ?? _bulkImportSessionBaseline;
    return baseline != null && current != baseline;
  }

  Future<_BulkImportExitChoice> _confirmBulkImportExit() async {
    final choice = await showDialog<_BulkImportExitChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: Text(context.l10n.leaveBulkImportTitle),
        content: Text(context.l10n.leaveBulkImportMessage),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _BulkImportExitChoice.discard),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _BulkImportExitChoice.stay),
            child: Text(context.l10n.stay),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: Colors.white,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, _BulkImportExitChoice.save),
            child: Text(context.l10n.saveAndLeave),
          ),
        ],
      ),
    );
    return choice ?? _BulkImportExitChoice.stay;
  }

  Future<void> _requestCloseBulkImport() async {
    if (_isBulkImportDirty) {
      final choice = await _confirmBulkImportExit();
      if (!mounted || choice == _BulkImportExitChoice.stay) {
        return;
      }
      _bulkDraftSaveTimer?.cancel();
      if (choice == _BulkImportExitChoice.save) {
        await _persistBulkDraft();
        _bulkImportPersistedSnapshot = _bulkImportSnapshot();
      } else {
        await _discardBulkDraftConfirmed(clearCurrent: true);
      }
    } else {
      if (_csvDraft.trim().isNotEmpty) {
        _scheduleBulkDraftSave();
      }
    }
    if (!mounted) return;
    setState(() => _showBulkImport = false);
  }

  Future<void> _discardBulkDraftConfirmed({bool clearCurrent = false}) async {
    await clearUserBulkImportDraft();
    if (!mounted) {
      return;
    }
    setState(() {
      _savedBulkDraft = null;
      if (clearCurrent) {
        _bulkCsv = '';
        _bulkImportType = 'student';
        _studentPeriodSource = 'explicit';
        _targetSemesterId = '';
        _batchYearLevel = '';
        _bulkReviewSearchController.clear();
        _resetBulkReviewPaging();
      }
    });
  }

  Future<void> _discardBulkDraft() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Discard draft?',
      message: 'Your saved user import draft will be permanently deleted.',
      confirmLabel: 'Discard',
    );
    if (!confirmed || !mounted) return;
    await _discardBulkDraftConfirmed();
  }

  void _openBulkImport({bool resumeDraft = false}) {
    _bulkImportSessionBaseline = null;
    _bulkImportPersistedSnapshot = null;
    if (resumeDraft && _savedBulkDraft != null) {
      final draft = _savedBulkDraft!;
      setState(() {
        _showBulkImport = true;
        _bulkCsv = draft.csv;
        _bulkImportType = draft.importType;
        _studentPeriodSource = draft.studentPeriodSource;
        _targetSemesterId = draft.targetSemesterId;
        _batchYearLevel = draft.batchYearLevel;
        _bulkReviewSearchController.clear();
        _resetBulkReviewPaging();
      });
      _captureBulkImportBaseline(persisted: true);
      return;
    }

    setState(() {
      _showBulkImport = true;
      _resetBulkReviewPaging();
    });
    _captureBulkImportBaseline();
  }

  Widget _draftResumeBanner() {
    final draft = _savedBulkDraft!;
    final savedLabel = MaterialLocalizations.of(
      context,
    ).formatShortDate(draft.savedAt);
    final rowCount = draft.rowCount;
    final warningText = draft.warningCount > 0
        ? ' - ${draft.warningCount} warning${draft.warningCount == 1 ? '' : 's'}'
        : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pending_actions_rounded, color: _blue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Unfinished user import draft - $rowCount row${rowCount == 1 ? '' : 's'}$warningText - Saved $savedLabel',
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _secondaryButton(
            icon: Icons.play_arrow_rounded,
            label: 'Resume',
            onTap: () => _openBulkImport(resumeDraft: true),
          ),
          const SizedBox(width: 8),
          _secondaryButton(
            icon: Icons.delete_outline_rounded,
            label: 'Discard',
            onTap: _discardBulkDraft,
          ),
        ],
      ),
    );
  }

  Widget? _errorNotice(String? error) {
    if (error == null) {
      return null;
    }
    return _notice(error, warning: true, onDismiss: _dismissError);
  }

  Widget? _successNotice(String? message) {
    if (message == null) {
      return null;
    }
    return _notice(message, onDismiss: _dismissNotice);
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
    ref.listen<String?>(userManagementProvider.select((s) => s.message), (
      previous,
      next,
    ) {
      if (next != null && next.isNotEmpty) {
        _scheduleSuccessNoticeAutoDismiss(next);
        if (next != previous) {
          showSuccessToast(context, next);
        }
      } else {
        _successNoticeTimer?.cancel();
      }
    });
    ref.listen<String?>(userManagementProvider.select((s) => s.error), (
      previous,
      next,
    ) {
      if (next != null && next.isNotEmpty && next != previous) {
        showErrorToast(context, next);
      }
    });

    final state = ref.watch(userManagementProvider);
    _ensurePageInRange(state.users.length);
    final academicState = ref.watch(academicPeriodProvider);
    final visibleUsers = _pageUsers(state.users);

    if (_isBulkImportVisible) {
      return _bulkImportPage(state, academicState);
    }

    if (_accessControlUser != null) {
      return _accessControlPage(state);
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
          if (_errorNotice(state.error) != null) ...[
            const SizedBox(height: 14),
            _errorNotice(state.error)!,
          ],
          if (_successNotice(state.message) != null) ...[
            const SizedBox(height: 14),
            _successNotice(state.message)!,
          ],
          if (_savedBulkDraft != null) ...[
            const SizedBox(height: 14),
            _draftResumeBanner(),
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
          icon: Icons.file_upload_outlined,
          label: 'Bulk Import CSV',
          onTap: state.isSaving ? null : () => _openBulkImport(),
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

  void _applySummaryRoleFilter(String role) {
    setState(() => _page = 0);
    ref.read(userManagementProvider.notifier).fetchUsers(role: role);
  }

  Widget _summaryCards(UserManagementState state) {
    final canTap = !state.isSaving;
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            title: 'All Users',
            subtitle: '${_count(state, 'all')} Total',
            icon: Icons.groups_2_rounded,
            selected: state.role.isEmpty,
            onTap: canTap ? () => _applySummaryRoleFilter('') : null,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _summaryCard(
            title: 'Faculty',
            subtitle: '${_count(state, 'faculty')} Active',
            icon: Icons.co_present_rounded,
            selected: state.role == 'faculty',
            onTap: canTap ? () => _applySummaryRoleFilter('faculty') : null,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _summaryCard(
            title: 'Students',
            subtitle: '${_count(state, 'students')} Active',
            icon: Icons.school_rounded,
            iconColor: const Color(0xFF2563EB),
            selected: state.role == 'student',
            onTap: canTap ? () => _applySummaryRoleFilter('student') : null,
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
    VoidCallback? onTap,
  }) {
    final card = Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? _maroon : const Color(0xFFE5E7EB)),
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
          if (state.isLoading && state.users.isEmpty)
            DefensysSkeleton.list(count: 6, rowHeight: 52)
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
      width: 168,
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
            DropdownMenuItem(value: 'panelist', child: Text('Panelist')),
            DropdownMenuItem(value: 'pit_lead', child: Text('PIT Lead')),
            DropdownMenuItem(value: 'adviser', child: Text('Adviser')),
            DropdownMenuItem(
              value: 'documenter',
              child: Text('Documenter'),
            ),
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
              if (state.users.isEmpty)
                _emptyRows()
              else
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
    final displayRole = user['displayRole'];
    final tone = displayRole is Map ? displayRole['tone']?.toString() : null;
    final role = user['role']?.toString() ?? 'student';
    final label = displayRole is Map && displayRole['label'] != null
        ? displayRole['label'].toString()
        : switch (role) {
            'admin' => 'Administrator',
            'faculty' => 'Faculty',
            _ => 'Student',
          };
    final effectiveTone = tone ?? role;
    final background = switch (effectiveTone) {
      'admin' => const Color(0xFFFDE8E8),
      'adviser' => const Color(0xFFECFDF5),
      'panelist' => const Color(0xFFF3E8FF),
      'pit_lead' => const Color(0xFFEFF6FF),
      'documenter' => const Color(0xFFFFEDD5),
      'faculty' => const Color(0xFFFFEDD5),
      _ => const Color(0xFFEFF6FF),
    };
    final textColor = switch (effectiveTone) {
      'admin' => const Color(0xFF9B1C1C),
      'adviser' => const Color(0xFF047857),
      'panelist' => const Color(0xFF7E22CE),
      'pit_lead' => const Color(0xFF1D4ED8),
      'documenter' => const Color(0xFFEA580C),
      'faculty' => const Color(0xFFEA580C),
      _ => const Color(0xFF1E40AF),
    };
    final icon = switch (effectiveTone) {
      'admin' => Icons.admin_panel_settings_rounded,
      'adviser' => Icons.school_outlined,
      'panelist' => Icons.groups_2_outlined,
      'pit_lead' => Icons.flag_outlined,
      'documenter' => Icons.assignment_outlined,
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
          onTap: state.isSaving ? null : () => _showProfileEditor(user),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.edit_square, color: _blue, size: 18),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: state.isSaving ? null : () => _openAccessControl(user),
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
                    (n) => DropdownMenuItem<int>(value: n, child: Text('$n')),
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
    return PopScope(
      canPop: !_isBulkImportDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestCloseBulkImport();
      },
      child: SingleChildScrollView(
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
                onTap: state.isSaving ? null : _requestCloseBulkImport,
              ),
            ),
            if (_errorNotice(state.error) != null) ...[
              const SizedBox(height: 14),
              _errorNotice(state.error)!,
            ],
            if (_successNotice(state.message) != null) ...[
              const SizedBox(height: 14),
              _successNotice(state.message)!,
            ],
            const SizedBox(height: 28),
            _csvFormatCard(),
            const SizedBox(height: 20),
            _uploadCsvCard(state, academicState),
          ],
        ),
      ),
    );
  }

  Widget _csvFormatCard() {
    final studentBatch = _selectedBulkImportType == 'student';
    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CSV Format',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  studentBatch
                      ? 'Student Batch uses the official class list template, including section and year-level metadata.'
                      : 'Faculty / General Users uses the account-import template. Column order matters.',
                  style: const TextStyle(
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
                  message: studentBatch
                      ? 'Use the official class list template for student cohorts. The importer detects Class Section and Year Level from the file, while semester remains controlled by the Student Batch settings.'
                      : 'Use Faculty / General Users for non-student imports so student-only academic setup does not interfere.',
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
    final studentBatch = _selectedBulkImportType == 'student';
    final columns = studentBatch
        ? const ['Template area', 'Example value']
        : const ['id_number', 'first_name', 'last_name', 'email', 'role'];
    final values = studentBatch
        ? const [
            'Class Section / Year Level / Student Number',
            'BSIT-3A / 3rd Year / 4081',
          ]
        : const [
            'FAC-0001',
            'Ada',
            'Lovelace',
            'ada@ustp.edu.ph',
            'faculty',
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
    final reviewRows = _parseCsv(_csvDraft);
    final importBlockers = _bulkImportBlockingIssues(reviewRows);
    final canConfirmImport =
        _csvDraft.trim().isNotEmpty &&
        reviewRows.isNotEmpty &&
        importBlockers.isEmpty;

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
                            _resetBulkReviewPaging();
                          });
                          _scheduleBulkDraftSave();
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
                Text(
                  _selectedBulkImportType == 'student'
                      ? 'Student Batch accepts the official class list CSV template.'
                      : 'Columns: id_number, first_name, last_name, email, role',
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_csvDraft.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _bulkImportReview(),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    _primaryButton(
                      icon: Icons.system_update_alt_rounded,
                      label: state.isSaving
                          ? 'Importing...'
                          : _csvDraft.trim().isEmpty
                          ? 'Import Users'
                          : 'Confirm Import',
                      onTap: state.isSaving
                          ? null
                          : canConfirmImport
                          ? () => _importBulkUsers(academicState)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    _secondaryButton(
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      onTap: state.isSaving ? null : _requestCloseBulkImport,
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
                                _resetBulkReviewPaging();
                              });
                              _scheduleBulkDraftSave();
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
                              setState(() {
                                _targetSemesterId = value ?? '';
                                _resetBulkReviewPaging();
                              });
                              _scheduleBulkDraftSave();
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
                : (value) {
                    setState(() {
                      _batchYearLevel = value ?? '';
                      _resetBulkReviewPaging();
                    });
                    _scheduleBulkDraftSave();
                  },
            items: const [
              DropdownMenuItem(value: '1st Year', child: Text('1st Year')),
              DropdownMenuItem(value: '2nd Year', child: Text('2nd Year')),
              DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
              DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
            ],
          ),
          const SizedBox(height: 6),
          _helper(
            'Optional when the official class list includes Year Level. If selected, it must match the file.',
          ),
        ],
      ),
    );
  }

  Widget _preflightReview(
    AcademicPeriodState academicState,
    List<_SemesterOption> semesterOptions,
  ) {
    final officialContext = _parseOfficialClassListCsv(_csvDraft).metadata;
    final detectedYear = officialContext['year_level']?.toString() ?? '';
    final detectedSection = officialContext['section']?.toString() ?? '';
    final resolvedYear = _selectedBatchYearLevel.isNotEmpty
        ? _selectedBatchYearLevel
        : detectedYear;

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
          Row(
            children: [
              Expanded(
                child: _preflightMetric(
                  'BATCH YEAR LEVEL',
                  _selectedBulkImportType == 'student' &&
                          resolvedYear.isNotEmpty
                      ? resolvedYear
                      : '-',
                ),
              ),
              Expanded(
                child: _preflightMetric(
                  'CLASS SECTION',
                  _selectedBulkImportType == 'student' &&
                          detectedSection.isNotEmpty
                      ? detectedSection
                      : '-',
                ),
              ),
            ],
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
                  ? 'Imported Student rows will create Initial Student Academic Records using the selected semester plus the official class list section/year. Split mixed student cohorts into separate imports so the shared academic context stays correct.'
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

  Widget _bulkImportReview() {
    final rows = _parseCsv(_csvDraft);
    final official = _selectedBulkImportType == 'student'
        ? _parseOfficialClassListCsv(_csvDraft)
        : const _AdminOfficialClassListParseResult(metadata: {}, students: []);
    final blockers = _bulkImportBlockingIssues(rows);
    final warnings = _bulkImportWarnings(rows, official);
    final filteredRows = _filteredBulkReviewRows(rows);
    final previewRows = _pageBulkReviewRows(filteredRows);
    final detectedYear = official.metadata['year_level']?.toString() ?? '';
    final detectedSection = official.metadata['section']?.toString() ?? '';
    final detectedFaculty = official.metadata['faculty']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: _maroon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Review Import',
                  style: DefensysUi.sectionTitle.copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Check the detected context and parsed rows before committing this import.',
            style: TextStyle(
              color: Color(0xFF536079),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _reviewMetric('Rows', rows.length.toString()),
              _reviewMetric(
                'Mode',
                _selectedBulkImportType == 'student'
                    ? 'Student Batch'
                    : 'Faculty / General',
              ),
              if (_selectedBulkImportType == 'student')
                _reviewMetric(
                  'Year Level',
                  _selectedBatchYearLevel.isNotEmpty
                      ? _selectedBatchYearLevel
                      : (detectedYear.isEmpty ? '-' : detectedYear),
                ),
              if (_selectedBulkImportType == 'student')
                _reviewMetric(
                  'Section',
                  detectedSection.isEmpty ? '-' : detectedSection,
                ),
              if (_selectedBulkImportType == 'student')
                _reviewMetric(
                  'Instructor',
                  detectedFaculty.isEmpty ? '-' : detectedFaculty,
                ),
              if (blockers.isNotEmpty)
                _reviewMetric('Blocked', blockers.length.toString()),
            ],
          ),
          if (blockers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _reviewBlockingIssues(blockers),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _reviewWarnings(warnings),
          ],
          const SizedBox(height: 16),
          _bulkReviewControls(rows.length, filteredRows.length),
          const SizedBox(height: 12),
          _reviewRowsTable(previewRows),
          const SizedBox(height: 12),
          _bulkReviewPagination(filteredRows.length),
        ],
      ),
    );
  }

  Widget _reviewMetric(String label, String value) {
    return Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewWarnings(List<String> warnings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DefensysUi.warningBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: DefensysUi.warningBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: warnings
            .map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: DefensysUi.warningText,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style: const TextStyle(
                          color: DefensysUi.warningText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _reviewBlockingIssues(List<String> issues) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: issues
            .map(
              (issue) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFDC2626),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue,
                        style: const TextStyle(
                          color: Color(0xFF991B1B),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _bulkReviewControls(int totalRows, int filteredRows) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _bulkReviewSearchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _muted,
                  size: 19,
                ),
                hintText: 'Search parsed rows...',
                hintStyle: const TextStyle(color: _muted, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE2EA)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE2EA)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _maroon),
                ),
                suffixIcon: _bulkReviewSearchController.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          setState(() {
                            _bulkReviewSearchController.clear();
                            _resetBulkReviewPaging();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (_) {
                setState(_resetBulkReviewPaging);
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          filteredRows == totalRows
              ? '$totalRows row${totalRows == 1 ? '' : 's'}'
              : '$filteredRows of $totalRows rows',
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _bulkReviewPagination(int filteredRows) {
    final total = filteredRows;
    final pages = total == 0 ? 1 : (total / _bulkReviewRowsPerPage).ceil();
    final safePage = _bulkReviewPage.clamp(0, pages - 1);
    final start = total == 0 ? 0 : safePage * _bulkReviewRowsPerPage + 1;
    final end = total == 0
        ? 0
        : ((safePage + 1) * _bulkReviewRowsPerPage).clamp(0, total);

    return Row(
      children: [
        Text(
          'Showing $start-$end of $total rows',
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 16),
        const Text(
          'Rows per page',
          style: TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFDDE2EA)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _bulkReviewRowsPerPage,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: DefensysUi.fontFamily,
              ),
              items: _bulkReviewRowsPerPageOptions
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _bulkReviewRowsPerPage = value;
                  _resetBulkReviewPaging();
                });
              },
            ),
          ),
        ),
        const Spacer(),
        _bulkReviewPageButton(
          Icons.chevron_left_rounded,
          safePage > 0,
          () => setState(() => _bulkReviewPage = safePage - 1),
        ),
        const SizedBox(width: 8),
        Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 36),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _maroon),
          ),
          child: Text(
            '${safePage + 1}',
            style: const TextStyle(
              color: _maroon,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _bulkReviewPageButton(
          Icons.chevron_right_rounded,
          safePage < pages - 1,
          () => setState(() => _bulkReviewPage = safePage + 1),
        ),
      ],
    );
  }

  Widget _bulkReviewPageButton(
    IconData icon,
    bool enabled,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: 36,
      height: 36,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0xFFDDE2EA)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }

  Widget _reviewRowsTable(List<Map<String, dynamic>> rows) {
    final studentBatch = _selectedBulkImportType == 'student';
    final columns = studentBatch
        ? const [
            'Student ID',
            'Full Name',
            'Email',
            'Year Level',
            'Section',
            'Status',
          ]
        : const ['User ID', 'Full Name', 'Email', 'Role', 'Status'];

    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Text(
          'No rows could be parsed for review.',
          style: TextStyle(color: Color(0xFF667085)),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        constraints: const BoxConstraints(minWidth: 920),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Column(
          children: [
            Container(
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFF0F1F4),
                borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              ),
              child: Row(
                children: columns
                    .map((column) => _reviewCell(column, header: true))
                    .toList(),
              ),
            ),
            ...rows.map((row) {
              final blocked = _bulkImportRowBlockingIssues(row).isNotEmpty;
              final values = studentBatch
                  ? [
                      _rowText(row, 'id_number'),
                      _rowName(row),
                      _rowText(row, 'email'),
                      _rowText(row, 'year_level'),
                      _rowText(row, 'section'),
                      blocked ? 'Blocked' : 'Ready',
                    ]
                  : [
                      _rowText(row, 'id_number'),
                      _rowName(row),
                      _rowText(row, 'email'),
                      _rowText(row, 'role'),
                      blocked ? 'Blocked' : 'Ready',
                    ];
              return Container(
                height: 42,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(
                  children: values.map((value) => _reviewCell(value)).toList(),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _reviewCell(String value, {bool header = false}) {
    return SizedBox(
      width: 184,
      child: Container(
        height: double.infinity,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Text(
          value.isEmpty ? '-' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: header ? _ink : const Color(0xFF536079),
            fontSize: 12.5,
            fontWeight: header ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  List<String> _bulkImportBlockingIssues(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const ['No valid rows were detected in the selected CSV.'];
    }

    final issues = <String>[];
    if (_selectedBulkImportType == 'student') {
      final wrongModeRows = rows
          .where((row) => _bulkImportRowBlockingIssues(row).isNotEmpty)
          .length;
      if (wrongModeRows > 0) {
        issues.add(
          '$wrongModeRows row${wrongModeRows == 1 ? '' : 's'} look like Faculty / General users. Switch the import mode to Faculty / General Users or fix the role column to student before importing.',
        );
      }
      if (_selectedStudentPeriodSource == 'explicit' &&
          _selectedTargetSemesterId.isEmpty) {
        issues.add('Select the target semester for this student batch.');
      }
      final hasDetectedYear = rows.any(
        (row) => _rowText(row, 'year_level').isNotEmpty,
      );
      if (_selectedBatchYearLevel.isEmpty && !hasDetectedYear) {
        issues.add('Select the student batch year level before importing.');
      }
    }

    return issues;
  }

  List<String> _bulkImportRowBlockingIssues(Map<String, dynamic> row) {
    if (_selectedBulkImportType != 'student') {
      return const [];
    }

    final role = _rowText(row, 'role').trim().toLowerCase();
    if (role.isEmpty || role == 'student') {
      return const [];
    }

    return const ['Wrong import mode'];
  }

  List<String> _bulkImportWarnings(
    List<Map<String, dynamic>> rows,
    _AdminOfficialClassListParseResult official,
  ) {
    final warnings = <String>[];
    if (rows.isEmpty) {
      return const [];
    }

    final seen = <String>{};
    final duplicates = <String>{};
    for (final row in rows) {
      final id = _rowText(row, 'id_number');
      if (id.isEmpty) continue;
      if (!seen.add(id)) duplicates.add(id);
    }
    if (duplicates.isNotEmpty) {
      warnings.add(
        'Duplicate ID numbers in this file: ${duplicates.take(5).join(', ')}.',
      );
    }

    final missingEmailCount = rows
        .where((row) => _rowText(row, 'email').isEmpty)
        .length;
    if (missingEmailCount > 0) {
      warnings.add(
        '$missingEmailCount row${missingEmailCount == 1 ? '' : 's'} have no email address.',
      );
    }

    if (_selectedBulkImportType == 'student') {
      final detectedYear = official.metadata['year_level']?.toString() ?? '';
      final detectedSection = official.metadata['section']?.toString() ?? '';
      final detectedFaculty = official.metadata['faculty']?.toString() ?? '';
      if (_selectedBatchYearLevel.isNotEmpty &&
          detectedYear.isNotEmpty &&
          _normalizeYearLevel(_selectedBatchYearLevel) !=
              _normalizeYearLevel(detectedYear)) {
        warnings.add(
          'Selected year level does not match the official class list year.',
        );
      }
      if (detectedSection.isEmpty) {
        warnings.add(
          'No class section was detected. Academic records may be created without section context.',
        );
      }
      if (official.students.isNotEmpty && detectedFaculty.isEmpty) {
        warnings.add(
          'No instructor was detected. Official class list imports require a matching active faculty account before students can be imported.',
        );
      }

      final rowYears = rows
          .map((row) => _rowText(row, 'year_level'))
          .where((value) => value.isNotEmpty)
          .toSet();
      if (rowYears.length > 1) {
        warnings.add(
          'Multiple year levels were detected in student rows. Split mixed cohorts into separate imports.',
        );
      }

      final rowSections = rows
          .map((row) => _rowText(row, 'section'))
          .where((value) => value.isNotEmpty)
          .toSet();
      if (rowSections.length > 1) {
        warnings.add(
          'Multiple sections were detected. Import one class section per file when possible.',
        );
      }
    }

    return warnings;
  }

  String _rowText(Map<String, dynamic> row, String key) =>
      row[key]?.toString().trim() ?? '';

  String _rowName(Map<String, dynamic> row) {
    final first = _rowText(row, 'first_name');
    final last = _rowText(row, 'last_name');
    final full = _rowText(row, 'full_name');
    if (first.isNotEmpty || last.isNotEmpty) {
      return '$first $last'.trim();
    }
    return full;
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
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _notice(
    String message, {
    bool warning = false,
    VoidCallback? onDismiss,
  }) {
    final color = warning ? DefensysUi.warningText : DefensysUi.successText;
    final background = warning ? DefensysUi.warningBg : DefensysUi.successBg;
    final border = warning
        ? DefensysUi.warningBorder
        : DefensysUi.successBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                message,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss',
              icon: Icon(Icons.close_rounded, size: 18, color: color),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
        ],
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

  Future<String?> _pickStudentSampleYear() async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Download official class list sample'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Each file follows the official class list shape and includes '
                'one section plus four students for the chosen year level.',
                style: TextStyle(fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 16),
              for (final year in studentSampleYearLevels)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(year),
                    child: Text(year),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadCsvTemplate() async {
    if (_showBulkImport == true && _selectedBulkImportType == 'student') {
      final yearLevel = await _pickStudentSampleYear();
      if (yearLevel == null || !mounted) {
        return;
      }
      await downloadTextFile(
        filename: sampleStudentCsvFilenameForYear(yearLevel),
        content: sampleStudentCsvForYear(yearLevel),
      );
      return;
    }

    await downloadTextFile(
      filename: 'defensys-user-import-template.csv',
      content: sampleFacultyCsvTemplate,
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
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
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
    final copied = await copyTextToClipboard(code);
    if (!mounted) {
      return;
    }
    _snack(
      copied
          ? 'Guest code copied.'
          : 'Copy failed — select the code and copy manually.',
    );
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

  void _syncAccessFieldsFromUser(Map<String, dynamic> user) {
    _acRole = user['role']?.toString() ?? 'student';
    _acActive = user['is_active'] != false;
    _acPanelist = user['is_panelist'] == true;
    _acPitLead = user['is_pit_lead'] == true;
    _acAdviser = user['is_adviser'] == true;
    _acDocumenter = user['is_documenter'] == true;
    _acPitLeadYear = _normalizePitLeadYear(user['pit_lead_year']?.toString());
  }

  Future<void> _loadRoleAssignments(int userId) async {
    setState(() => _roleAssignmentsLoading = true);
    final rows = await ref
        .read(userManagementProvider.notifier)
        .fetchRoleAssignmentHistory(userId);
    if (!mounted) {
      return;
    }
    setState(() {
      _roleAssignments = rows;
      _roleAssignmentsLoading = false;
    });
  }

  void _openAccessControl(Map<String, dynamic> user) {
    _acPitLeadYear = _normalizePitLeadYear(user['pit_lead_year']?.toString());
    final userId = _asInt(user['id']);
    setState(() {
      _accessControlUser = Map<String, dynamic>.from(user);
      _roleAssignments = [];
      _roleAssignmentsLoading = userId != null;
      _syncAccessFieldsFromUser(user);
    });
    if (userId != null) {
      _loadRoleAssignments(userId);
    }
  }

  void _closeAccessControlPage() {
    setState(() {
      _accessControlUser = null;
      _roleAssignments = [];
      _roleAssignmentsLoading = false;
    });
  }

  Map<String, dynamic> _accessPayloadFromCurrent() {
    final u = _accessControlUser!;
    final isFaculty = _acRole == 'admin' || _acRole == 'faculty';
    return {
      'username': u['username']?.toString().trim() ?? '',
      'first_name': u['first_name']?.toString().trim() ?? '',
      'last_name': u['last_name']?.toString().trim() ?? '',
      'email': u['email']?.toString().trim() ?? '',
      'role': _acRole,
      'is_active': _acActive,
      'is_panelist': isFaculty && _acPanelist,
      'is_pit_lead': isFaculty && _acPitLead,
      'pit_lead_year': isFaculty && _acPitLead ? _acPitLeadYear : null,
      'is_adviser': isFaculty && _acAdviser,
      'is_documenter': isFaculty && _acDocumenter,
      'is_uploader': isFaculty && (u['is_uploader'] == true),
    };
  }

  Future<void> _persistAccessControl() async {
    final u = _accessControlUser;
    if (u == null) {
      return;
    }
    final id = _asInt(u['id']);
    if (id == null) {
      return;
    }
    final ok = await _updateUserAndRefreshCurrent(
      id,
      _accessPayloadFromCurrent(),
    );
    if (!mounted || !ok) {
      return;
    }
    final rows = ref.read(userManagementProvider).users;
    Map<String, dynamic>? next;
    for (final row in rows) {
      if (_asInt(row['id']) == id) {
        next = row;
        break;
      }
    }
    if (next != null) {
      setState(() {
        _accessControlUser = Map<String, dynamic>.from(next!);
        _syncAccessFieldsFromUser(_accessControlUser!);
      });
    }
    await _loadRoleAssignments(id);
  }

  Future<bool> _updateUserAndRefreshCurrent(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final ok = await ref
        .read(userManagementProvider.notifier)
        .updateUser(id, payload);
    if (!ok || !mounted) {
      return ok;
    }

    final auth = ref.read(authProvider);
    if (_asInt(auth.user?['id']) == id && auth.token != null) {
      await ref.read(authProvider.notifier).fetchCurrentUser(auth.token!);
    }
    return ok;
  }

  static const _histHead = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
    color: Color(0xFF9CA3AF),
  );

  Widget _accessControlPage(UserManagementState state) {
    final u = _accessControlUser!;
    final name = (u['name']?.toString().trim().isNotEmpty == true)
        ? u['name']!.toString().trim()
        : '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    final email = u['email']?.toString() ?? '';
    final isFaculty = _acRole == 'admin' || _acRole == 'faculty';

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.shield_outlined,
            title: 'Access Control & Role Assignment',
            subtitle:
                'Configure primary access roles and operational duties for this user account.',
            actions: _greyBorderMaroonTextButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back to Users',
              onPressed: state.isSaving
                  ? null
                  : () => _closeAccessControlPage(),
            ),
          ),
          if (_errorNotice(state.error) != null) ...[
            const SizedBox(height: 14),
            _errorNotice(state.error)!,
          ],
          if (_successNotice(state.message) != null) ...[
            const SizedBox(height: 14),
            _successNotice(state.message)!,
          ],
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: _accessControlRefCard(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: _maroon,
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name.isNotEmpty ? name : '—',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        email.isNotEmpty ? email : '—',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${u['username']?.toString() ?? '—'}',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: state.isSaving ? null : _showProfileEditor,
                          icon: const Icon(Icons.person_outline, size: 18),
                          label: const Text('Edit User Profile'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _maroon,
                            side: const BorderSide(
                              color: Color(0xFFD1D5DB),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 3,
                child: _accessControlRefCard(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, color: _maroon, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Dynamic Role Assignment',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Toggle switches to grant or revoke modular '
                                  'permissions. Users can hold multiple roles simultaneously.',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 12.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Changes apply after you save the configuration below.',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                    height: 1.4,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isFaculty) ...[
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _line),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: _line),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'ROLE',
                                        style: _histHead.copyWith(
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'ASSIGNED',
                                      style: _histHead.copyWith(fontSize: 10.5),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _accessRoleCard(
                                      accent: const Color(0xFF9333EA),
                                      icon: Icons.groups_2_outlined,
                                      title: 'Defense Panelist',
                                      subtitle:
                                          'Participates as evaluator on defense panels.',
                                      value: _acPanelist,
                                      enabled: !state.isSaving,
                                      onChanged: (v) =>
                                          setState(() => _acPanelist = v),
                                      flatInTable: true,
                                    ),
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: _line,
                                    ),
                                    _accessRoleCard(
                                      accent: const Color(0xFF2563EB),
                                      icon: Icons.flag_outlined,
                                      title: 'PIT Lead',
                                      subtitle:
                                          'Coordinates PIT activities and dependent roles.',
                                      value: _acPitLead,
                                      enabled: !state.isSaving,
                                      onChanged: (v) {
                                        setState(() {
                                          _acPitLead = v;
                                          if (!_acPitLead) {
                                            _acPitLeadYear = null;
                                          }
                                        });
                                      },
                                      below: _acPitLead
                                          ? [
                                              const Text(
                                                'PIT Lead Year',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _ink,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              DropdownButtonFormField<String?>(
                                                key: ValueKey(
                                                  'pit-year-$_acPitLeadYear',
                                                ),
                                                initialValue: _acPitLeadYear,
                                                isExpanded: true,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: _ink,
                                                ),
                                                decoration:
                                                    _accessTextFieldDecoration(),
                                                dropdownColor: Colors.white,
                                                items: [
                                                  const DropdownMenuItem<
                                                    String?
                                                  >(
                                                    value: null,
                                                    child: Text(
                                                      '— Select year level —',
                                                    ),
                                                  ),
                                                  ..._pitLeadYearOptions.map(
                                                    (y) =>
                                                        DropdownMenuItem<
                                                          String?
                                                        >(
                                                          value: y,
                                                          child: Text(y),
                                                        ),
                                                  ),
                                                ],
                                                onChanged: state.isSaving
                                                    ? null
                                                    : (v) => setState(
                                                        () =>
                                                            _acPitLeadYear = v,
                                                      ),
                                              ),
                                            ]
                                          : null,
                                      flatInTable: true,
                                    ),
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: _line,
                                    ),
                                    _accessRoleCard(
                                      accent: const Color(0xFF059669),
                                      icon: Icons.school_outlined,
                                      title: 'Project Adviser',
                                      subtitle:
                                          'Capstone advising responsibilities.',
                                      value: _acAdviser,
                                      enabled: !state.isSaving,
                                      onChanged: (v) =>
                                          setState(() => _acAdviser = v),
                                      flatInTable: true,
                                    ),
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: _line,
                                    ),
                                    _accessRoleCard(
                                      accent: const Color(0xFF0284C7),
                                      icon: Icons.assignment_outlined,
                                      title: 'Documenter',
                                      subtitle:
                                          'Records minutes of defense for capstone teams.',
                                      value: _acDocumenter,
                                      enabled: !state.isSaving,
                                      onChanged: (v) => setState(
                                        () => _acDocumenter = v,
                                      ),
                                      flatInTable: true,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: state.isSaving
                                ? null
                                : _onSaveRoleConfiguration,
                            icon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Save Role Configuration'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _maroon,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _roleAssignmentHistoryCard(),
        ],
      ),
    );
  }

  Widget _roleAssignmentHistoryCard() {
    return _accessControlRefCard(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.history_rounded, color: _maroon, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Role Assignment History',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Capability toggles: Panelist, PIT Lead, Project Adviser, etc.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_roleAssignmentsLoading)
            const SizedBox(
              height: 72,
              child: Center(
                child: CircularProgressIndicator(
                  color: DefensysUi.primaryMaroon,
                ),
              ),
            )
          else if (_roleAssignments.isEmpty)
            SizedBox(
              height: 72,
              width: double.infinity,
              child: Center(
                child: Text(
                  'No role assignments recorded yet.',
                  style: TextStyle(
                    color: _muted.withValues(alpha: 0.95),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            _roleHistoryTable(),
        ],
      ),
    );
  }

  String _formatAssignmentTimestamp(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) {
      return '—';
    }
    final dt = DateTime.tryParse(raw);
    if (dt == null) {
      return raw;
    }
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static const Map<int, TableColumnWidth> _roleHistoryColumnWidths = {
    0: FlexColumnWidth(2.1),
    1: FlexColumnWidth(2.4),
    2: FlexColumnWidth(1.1),
    3: FlexColumnWidth(1.3),
    4: FlexColumnWidth(1.1),
  };

  Widget _roleHistoryCell(
    String text, {
    FontWeight fontWeight = FontWeight.w500,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        text.isEmpty ? '—' : text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(color: _ink, fontSize: 12.5, fontWeight: fontWeight),
      ),
    );
  }

  Widget _roleHistoryHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(text, style: _histHead),
    );
  }

  Widget _roleHistoryTable() {
    return Table(
      columnWidths: _roleHistoryColumnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line)),
          ),
          children: [
            _roleHistoryHeaderCell('ROLE'),
            _roleHistoryHeaderCell('SEMESTER'),
            _roleHistoryHeaderCell('YEAR LEVEL'),
            _roleHistoryHeaderCell('CHANGED'),
            _roleHistoryHeaderCell('ACTION'),
          ],
        ),
        ..._roleAssignments.map(_roleAssignmentHistoryTableRow),
      ],
    );
  }

  String _roleHistoryLabel(Map<String, dynamic> row) {
    final label = row['role_label']?.toString() ?? '—';
    final detail = row['role_detail']?.toString();
    if (detail == null || detail.isEmpty) {
      return label;
    }
    return '$label ($detail)';
  }

  TableRow _roleAssignmentHistoryTableRow(Map<String, dynamic> row) {
    final isAssigned = row['action']?.toString() == 'assigned';
    final yearLevel = row['year_level']?.toString().trim() ?? '';

    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      children: [
        _roleHistoryCell(
          _roleHistoryLabel(row),
          fontWeight: FontWeight.w600,
          maxLines: 2,
        ),
        _roleHistoryCell(row['semester']?.toString() ?? '—'),
        _roleHistoryCell(yearLevel.isEmpty ? '—' : yearLevel),
        _roleHistoryCell(_formatAssignmentTimestamp(row['changed_at'])),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isAssigned
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                isAssigned ? 'Assigned' : 'Revoked',
                style: TextStyle(
                  color: isAssigned
                      ? const Color(0xFF047857)
                      : const Color(0xFFB91C1C),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _accessControlRefCard({
    required EdgeInsetsGeometry padding,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _accessRoleCard({
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool>? onChanged,
    List<Widget>? below,
    bool flatInTable = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
        boxShadow: flatInTable
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.38,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                DefensysUi.flatSwitch(
                  value: value,
                  onChanged: !enabled || onChanged == null
                      ? null
                      : (v) => onChanged(v),
                ),
              ],
            ),
          ),
          if (below != null && below.isNotEmpty) ...[
            const Divider(height: 1, thickness: 1, color: _line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: below,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _greyBorderMaroonTextButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: _maroon),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _maroon,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _maroon,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
    );
  }

  InputDecoration _accessTextFieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: TextStyle(color: _muted.withValues(alpha: 0.75), fontSize: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _maroon, width: 1.25),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
    );
  }

  InputDecoration _profileModalBaseRoleDecoration() {
    const r = 8.0;
    const side = BorderSide(color: _maroon, width: 1);
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: side,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: const BorderSide(color: _maroon, width: 1.25),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: side,
      ),
    );
  }

  Future<void> _onSaveRoleConfiguration() async {
    await _persistAccessControl();
  }

  Map<String, dynamic> _profilePayloadFromUser(
    Map<String, dynamic> user, {
    required String firstName,
    required String lastName,
    required String email,
    required String role,
    required bool isActive,
    String? password,
  }) {
    final isFaculty = role == 'admin' || role == 'faculty';
    if (!isFaculty) {
      return {
        'username': user['username']?.toString().trim() ?? '',
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'role': role,
        'is_active': isActive,
        'is_panelist': false,
        'is_pit_lead': false,
        'pit_lead_year': null,
        'is_adviser': false,
        'is_documenter': false,
        'is_uploader': false,
        if (password != null && password.isNotEmpty) 'password': password,
      };
    }
    return {
      'username': user['username']?.toString().trim() ?? '',
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'role': role,
      'is_active': isActive,
      'is_panelist': user['is_panelist'] == true,
      'is_pit_lead': user['is_pit_lead'] == true,
      'pit_lead_year': user['is_pit_lead'] == true
          ? _normalizePitLeadYear(user['pit_lead_year']?.toString())
          : null,
      'is_adviser': user['is_adviser'] == true,
      'is_documenter': user['is_documenter'] == true,
      'is_uploader': user['is_uploader'] == true,
      if (password != null && password.isNotEmpty) 'password': password,
    };
  }

  Future<void> _showProfileEditor([Map<String, dynamic>? user]) async {
    final u = user ?? _accessControlUser;
    if (u == null) {
      return;
    }
    final onAccessPage =
        _accessControlUser != null &&
        _asInt(_accessControlUser!['id']) == _asInt(u['id']);
    final first = TextEditingController(
      text: u['first_name']?.toString() ?? '',
    );
    final last = TextEditingController(text: u['last_name']?.toString() ?? '');
    final email = TextEditingController(text: u['email']?.toString() ?? '');
    final password = TextEditingController();

    final displayName = (u['name']?.toString().trim().isNotEmpty == true)
        ? u['name']!.toString().trim()
        : '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    final usernameStr = u['username']?.toString() ?? '—';

    Widget capsLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.85,
          color: Color(0xFF4B5563),
        ),
      ),
    );

    final roleChoice = <String>[
      onAccessPage ? _acRole : (u['role']?.toString() ?? 'student'),
    ];
    final activeChoice = <bool>[
      onAccessPage ? _acActive : (u['is_active'] != false),
    ];

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 14,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit User Profile',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _maroon,
                            fontFamily: DefensysUi.fontFamily,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Editing account: $displayName (ID $usernameStr)',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _muted,
                            height: 1.35,
                            fontFamily: DefensysUi.fontFamily,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_outlined, size: 18, color: _maroon),
                            const SizedBox(width: 8),
                            const Text(
                              'Edit Account Details',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                                fontFamily: DefensysUi.fontFamily,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Update the user's name, email, and system role.",
                          style: TextStyle(
                            fontSize: 12.5,
                            color: _muted,
                            height: 1.4,
                            fontFamily: DefensysUi.fontFamily,
                          ),
                        ),
                        const SizedBox(height: 18),
                        capsLabel('ID Number / Username'),
                        Text(
                          usernameStr,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                            fontFamily: DefensysUi.fontFamily,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  capsLabel('First Name'),
                                  TextField(
                                    controller: first,
                                    decoration: _accessTextFieldDecoration(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  capsLabel('Last Name'),
                                  TextField(
                                    controller: last,
                                    decoration: _accessTextFieldDecoration(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        capsLabel('Email Address'),
                        TextField(
                          controller: email,
                          decoration: _accessTextFieldDecoration(),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        capsLabel('System Role'),
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            'profile-role-${roleChoice[0]}',
                          ),
                          initialValue: roleChoice[0],
                          isExpanded: true,
                          decoration: _profileModalBaseRoleDecoration(),
                          icon: Icon(
                            Icons.arrow_drop_down_rounded,
                            color: _muted,
                            size: 22,
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _ink,
                            fontFamily: DefensysUi.fontFamily,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Administrator'),
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
                          onChanged: (v) {
                            setDialogState(() {
                              roleChoice[0] = v ?? 'student';
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: activeChoice[0],
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                side: const BorderSide(
                                  color: _maroon,
                                  width: 1.5,
                                ),
                                fillColor: WidgetStateProperty.resolveWith((
                                  states,
                                ) {
                                  if (states.contains(WidgetState.selected)) {
                                    return _maroon;
                                  }
                                  return Colors.white;
                                }),
                                checkColor: Colors.white,
                                onChanged: (v) {
                                  setDialogState(() {
                                    activeChoice[0] = v ?? false;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  activeChoice[0] = !activeChoice[0];
                                });
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 4,
                                ),
                                child: Text(
                                  'Account is active',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _ink,
                                    fontFamily: DefensysUi.fontFamily,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        capsLabel('New Password (optional)'),
                        TextField(
                          controller: password,
                          obscureText: true,
                          decoration: _accessTextFieldDecoration(
                            hint: 'Leave blank to keep current password',
                          ),
                        ),
                        const SizedBox(height: 26),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _ink,
                                backgroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Color(0xFFD1D5DB),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              icon: const Icon(
                                Icons.save_outlined,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: const Text('Save Changes'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _maroon,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      final id = _asInt(u['id']);
      if (id != null) {
        final dialogRole = roleChoice[0];
        final dialogActive = activeChoice[0];
        final pwd = password.text.trim();
        final Map<String, dynamic> payload;
        if (onAccessPage) {
          payload = Map<String, dynamic>.from(_accessPayloadFromCurrent());
          payload['first_name'] = first.text.trim();
          payload['last_name'] = last.text.trim();
          payload['email'] = email.text.trim();
          payload['role'] = dialogRole;
          payload['is_active'] = dialogActive;
          final isF = dialogRole == 'admin' || dialogRole == 'faculty';
          if (!isF) {
            payload['is_panelist'] = false;
            payload['is_pit_lead'] = false;
            payload['pit_lead_year'] = null;
            payload['is_adviser'] = false;
            payload['is_documenter'] = false;
            payload['is_uploader'] = false;
          } else {
            payload['is_panelist'] = _acPanelist;
            payload['is_pit_lead'] = _acPitLead;
            payload['pit_lead_year'] =
                _acPitLead &&
                    (_acPitLeadYear != null && _acPitLeadYear!.isNotEmpty)
                ? _acPitLeadYear
                : null;
            payload['is_adviser'] = _acAdviser;
            payload['is_documenter'] = _acDocumenter;
            payload['is_uploader'] = u['is_uploader'] == true;
          }
          if (pwd.isNotEmpty) {
            payload['password'] = pwd;
          }
        } else {
          payload = _profilePayloadFromUser(
            u,
            firstName: first.text.trim(),
            lastName: last.text.trim(),
            email: email.text.trim(),
            role: dialogRole,
            isActive: dialogActive,
            password: pwd.isNotEmpty ? pwd : null,
          );
        }
        final ok = await _updateUserAndRefreshCurrent(id, payload);
        if (mounted && ok && onAccessPage) {
          final rows = ref.read(userManagementProvider).users;
          for (final row in rows) {
            if (_asInt(row['id']) == id) {
              setState(() {
                _accessControlUser = Map<String, dynamic>.from(row);
                _syncAccessFieldsFromUser(_accessControlUser!);
              });
              break;
            }
          }
          await _loadRoleAssignments(id);
        }
      }
    }

    first.dispose();
    last.dispose();
    email.dispose();
    password.dispose();
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
    var role = user?['role']?.toString() ?? 'student';
    var isPanelist = user?['is_panelist'] == true;
    var isPitLead = user?['is_pit_lead'] == true;
    var isAdviser = user?['is_adviser'] == true;
    var isDocumenter = user?['is_documenter'] == true;
    var isActive = user?['is_active'] != false;
    String? pitLeadYear = _normalizePitLeadYear(
      user?['pit_lead_year']?.toString(),
    );

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
                                pitLeadYear = null;
                              }
                            });
                          },
                        ),
                        if (isPitLead) ...[
                          DropdownButtonFormField<String?>(
                            key: ValueKey('dlg-pit-$pitLeadYear'),
                            initialValue: pitLeadYear,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'PIT Lead Year',
                            ),
                            dropdownColor: Colors.white,
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('— Select year level —'),
                              ),
                              ..._pitLeadYearOptions.map(
                                (y) => DropdownMenuItem<String?>(
                                  value: y,
                                  child: Text(y),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                pitLeadYear = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
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
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Documenter'),
                          subtitle: const Text(
                            'Records minutes of defense for capstone teams.',
                          ),
                          value: isDocumenter,
                          onChanged: (value) {
                            setDialogState(() {
                              isDocumenter = value ?? false;
                            });
                          },
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
      'pit_lead_year': isPitLead ? pitLeadYear : null,
      'is_adviser': isAdviser,
      'is_documenter': isDocumenter,
      'is_uploader': user?['is_uploader'] == true,
      if (password.text.trim().isNotEmpty) 'password': password.text.trim(),
    };

    username.dispose();
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    password.dispose();

    if (!mounted) {
      return;
    }

    if (editing) {
      await _updateUserAndRefreshCurrent(_asInt(user['id'])!, payload);
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

      setState(() {
        _bulkCsv = csv;
        _bulkReviewSearchController.clear();
        _resetBulkReviewPaging();
      });
      _scheduleBulkDraftSave();
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
    final blockers = _bulkImportBlockingIssues(rows);
    if (blockers.isNotEmpty) {
      _snack(blockers.first);
      return;
    }
    if (_selectedBulkImportType == 'student') {
      final official = _parseOfficialClassListCsv(csv);
      final detectedFaculty = official.metadata['faculty']?.toString() ?? '';
      if (official.students.isNotEmpty && detectedFaculty.trim().isEmpty) {
        _snack('Official class list imports require a Faculty value.');
        return;
      }
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
      await clearUserBulkImportDraft();
      if (!mounted) {
        return;
      }
      setState(() {
        _showBulkImport = false;
        _bulkCsv = '';
        _savedBulkDraft = null;
        _bulkReviewSearchController.clear();
        _resetBulkReviewPaging();
      });
    }
  }

  void _resetBulkReviewPaging() {
    _bulkReviewPage = 0;
  }

  List<Map<String, dynamic>> _filteredBulkReviewRows(
    List<Map<String, dynamic>> rows,
  ) {
    final query = _bulkReviewSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return rows;
    }
    return rows.where((row) {
      final haystack = [
        _rowText(row, 'id_number'),
        _rowName(row),
        _rowText(row, 'email'),
        _rowText(row, 'role'),
        _rowText(row, 'year_level'),
        _rowText(row, 'section'),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> _pageBulkReviewRows(
    List<Map<String, dynamic>> rows,
  ) {
    final pages = rows.isEmpty
        ? 1
        : (rows.length / _bulkReviewRowsPerPage).ceil();
    final safePage = _bulkReviewPage.clamp(0, pages - 1);
    if (safePage != _bulkReviewPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _bulkReviewPage = safePage);
      });
    }
    final start = safePage * _bulkReviewRowsPerPage;
    final end = (start + _bulkReviewRowsPerPage).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  Map<String, dynamic>? _studentContext(AcademicPeriodState academicState) {
    if (_selectedBulkImportType != 'student') {
      return null;
    }

    final officialContext = _parseOfficialClassListCsv(_csvDraft).metadata;
    final detectedYear = officialContext['year_level']?.toString() ?? '';
    final detectedSection = officialContext['section']?.toString() ?? '';
    final detectedFaculty = officialContext['faculty']?.toString() ?? '';
    final isOfficialClassList = _parseOfficialClassListCsv(
      _csvDraft,
    ).students.isNotEmpty;
    final selectedYear = _selectedBatchYearLevel.isNotEmpty
        ? _selectedBatchYearLevel
        : detectedYear;

    if (_selectedBatchYearLevel.isNotEmpty &&
        detectedYear.isNotEmpty &&
        _normalizeYearLevel(_selectedBatchYearLevel) !=
            _normalizeYearLevel(detectedYear)) {
      _snack(
        'The selected year level does not match the official class list year.',
      );
      return null;
    }

    if (selectedYear.isEmpty) {
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
        'year_level': _normalizeYearLevel(selectedYear),
        if (detectedSection.isNotEmpty) 'section': detectedSection,
        if (detectedFaculty.isNotEmpty) 'instructor_name': detectedFaculty,
        if (isOfficialClassList) 'require_faculty_match': true,
      };
    }

    final semesterId = int.tryParse(_selectedTargetSemesterId);
    if (semesterId == null) {
      _snack('Select the target semester first.');
      return null;
    }

    return {
      'semester_id': semesterId,
      'year_level': _normalizeYearLevel(selectedYear),
      if (detectedSection.isNotEmpty) 'section': detectedSection,
      if (detectedFaculty.isNotEmpty) 'instructor_name': detectedFaculty,
      if (isOfficialClassList) 'require_faculty_match': true,
    };
  }

  List<Map<String, dynamic>> _parseCsv(String csv) {
    if (_selectedBulkImportType == 'student') {
      final official = _parseOfficialClassListCsv(csv);
      if (official.students.isNotEmpty) {
        return official.students;
      }
    }

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

  _AdminOfficialClassListParseResult _parseOfficialClassListCsv(String csv) {
    final rows = csv
        .split(RegExp(r'\r?\n'))
        .map(_splitCsvLine)
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) {
      return const _AdminOfficialClassListParseResult(
        metadata: {},
        students: [],
      );
    }

    String? csvSchoolYear;
    String? csvSemester;
    final schoolYearRegex = RegExp(r'\b(\d{4}-\d{4})\b');
    final semesterRegex = RegExp(r'\b(1st|2nd|Summer)\s*(?:Semester|sem)?\b', caseSensitive: false);

    final limit = rows.length < 10 ? rows.length : 10;
    for (var i = 0; i < limit; i++) {
      for (final cell in rows[i]) {
        final trimmed = cell.trim();
        if (trimmed.isEmpty) continue;

        if (csvSchoolYear == null) {
          final syMatch = schoolYearRegex.firstMatch(trimmed);
          if (syMatch != null) {
            csvSchoolYear = syMatch.group(1);
          }
        }

        if (csvSemester == null) {
          final semMatch = semesterRegex.firstMatch(trimmed);
          if (semMatch != null) {
            final rawSem = semMatch.group(1)!.toLowerCase();
            if (rawSem.contains('1st')) {
              csvSemester = '1st Semester';
            } else if (rawSem.contains('2nd')) {
              csvSemester = '2nd Semester';
            } else if (rawSem.contains('summer')) {
              csvSemester = 'Summer';
            }
          }
        }
      }
      if (csvSchoolYear != null && csvSemester != null) break;
    }

    final metadata = <String, dynamic>{
      if (csvSchoolYear != null) 'school_year': csvSchoolYear,
      if (csvSemester != null) 'semester': csvSemester,
    };
    var headerIndex = -1;

    for (var i = 0; i < rows.length; i++) {
      final normalized = rows[i].map(_normalizeHeader).toList();

      void readMeta(String key, List<String> labels) {
        if (metadata[key]?.toString().trim().isNotEmpty == true) return;
        for (final label in labels) {
          final index = normalized.indexWhere((cell) => cell == label);
          if (index == -1) continue;
          final value = _nextCell(rows[i], index);
          if (value.isNotEmpty) metadata[key] = value;
          return;
        }
      }

      readMeta('faculty', ['faculty', 'instructor']);
      readMeta('section', ['class section', 'section']);
      readMeta('year_level', ['year level', 'level']);

      final hasStudentNumber = normalized.any(
        (cell) =>
            cell.contains('student') &&
            (cell.contains('number') ||
                cell.contains('no') ||
                cell == 'student n'),
      );
      final hasFullName = normalized.contains('full name');
      if (hasStudentNumber && hasFullName) {
        headerIndex = i;
        break;
      }
    }

    if (metadata['year_level'] != null) {
      metadata['year_level'] = _normalizeYearLevel(
        metadata['year_level'].toString(),
      );
    }
    if (headerIndex == -1) {
      return _AdminOfficialClassListParseResult(
        metadata: metadata,
        students: const [],
      );
    }

    final headers = rows[headerIndex].map(_normalizeHeader).toList();
    int findHeader(bool Function(String value) matches) =>
        headers.indexWhere(matches);
    final idIndex = findHeader(
      (value) =>
          value.contains('student') &&
          (value.contains('number') ||
              value.contains('no') ||
              value == 'student n'),
    );
    final nameIndex = findHeader((value) => value == 'full name');
    final levelIndex = findHeader((value) => value == 'level');
    final emailIndex = findHeader((value) => value == 'email');
    final section = metadata['section']?.toString() ?? '';
    final yearLevel = metadata['year_level']?.toString() ?? '';
    final students = <Map<String, dynamic>>[];

    for (final row in rows.skip(headerIndex + 1)) {
      String read(int index) =>
          index >= 0 && index < row.length ? row[index].trim() : '';
      final id = read(idIndex);
      final name = read(nameIndex);
      if (id.isEmpty || name.isEmpty) continue;
      final splitName = _splitOfficialFullName(name);
      final rowYear = levelIndex != -1
          ? _normalizeYearLevel(read(levelIndex))
          : yearLevel;
      students.add({
        'id_number': id,
        'first_name': splitName.firstName,
        'last_name': splitName.lastName,
        'email': emailIndex == -1 ? '' : read(emailIndex),
        'role': 'student',
        if (rowYear.isNotEmpty) 'year_level': rowYear,
        if (section.isNotEmpty) 'section': section,
      });
    }

    return _AdminOfficialClassListParseResult(
      metadata: metadata,
      students: students,
    );
  }

  List<String> _splitCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        values.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString().trim());
    return values;
  }

  String _nextCell(List<String> row, int index) {
    for (var i = index + 1; i < row.length; i++) {
      final value = row[i].trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _normalizeHeader(String value) => value
      .trim()
      .replaceFirst('\ufeff', '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  String _normalizeYearLevel(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('1')) return '1st Year';
    if (lower.contains('2')) return '2nd Year';
    if (lower.contains('3')) return '3rd Year';
    if (lower.contains('4')) return '4th Year';
    return value.trim();
  }

  _OfficialNameParts _splitOfficialFullName(String value) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.contains(',')) {
      final parts = clean.split(',');
      final lastName = parts.first.trim();
      final firstName = parts.skip(1).join(',').trim();
      return _OfficialNameParts(firstName: firstName, lastName: lastName);
    }
    final parts = clean.split(' ');
    if (parts.length == 1) {
      return _OfficialNameParts(firstName: clean, lastName: '');
    }
    return _OfficialNameParts(
      firstName: parts.first,
      lastName: parts.skip(1).join(' '),
    );
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

    showInfoToast(context, message);
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

class _AdminOfficialClassListParseResult {
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> students;

  const _AdminOfficialClassListParseResult({
    required this.metadata,
    required this.students,
  });
}

class _OfficialNameParts {
  final String firstName;
  final String lastName;

  const _OfficialNameParts({required this.firstName, required this.lastName});
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
