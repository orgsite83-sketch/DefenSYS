import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/table/defensys_data_table.dart';
import 'package:defensys/widgets/table/defensys_table_column.dart';
import 'package:go_router/go_router.dart';
import 'package:defensys/notifications/notification_request_screen.dart';
import 'package:defensys/services/admin/panelist_requests_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'panelist_requests_view.dart';

class PanelistEligibilityView extends StatelessWidget {
  const PanelistEligibilityView({
    super.key,
    required this.onBack,
    this.initialTab = 'faculty',
    this.initialRequestId,
    this.onEditRoles,
    this.onSelectRequest,
    this.onRequestClosed,
    this.onTabChanged,
  });
  final VoidCallback onBack;
  final String initialTab;
  final int? initialRequestId;
  final ValueChanged<int>? onEditRoles, onSelectRequest;
  final VoidCallback? onRequestClosed;
  final ValueChanged<String>? onTabChanged;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.ghost(
              onPressed: onBack,
              leading: const Icon(LucideIcons.arrowLeft, size: 16),
              child: const Text('Faculty & Staff'),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceOf(context),
                border: Border.all(color: DefensysTokens.borderOf(context)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: PanelistEligibilityDirectory(
                centralized: true,
                initialTab: initialTab,
                initialRequestId: initialRequestId,
                onEditRoles: onEditRoles,
                onSelectRequest: onSelectRequest,
                onRequestClosed: onRequestClosed,
                onTabChanged: onTabChanged,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The same RBAC duty editor is used by scheduling and Faculty & Staff.
class PanelistEligibilityDirectory extends ConsumerStatefulWidget {
  const PanelistEligibilityDirectory({
    super.key,
    this.onClose,
    this.centralized = false,
    this.initialTab = 'faculty',
    this.initialRequestId,
    this.onEditRoles,
    this.onSelectRequest,
    this.onRequestClosed,
    this.onTabChanged,
  });
  final VoidCallback? onClose;
  final bool centralized;
  final String initialTab;
  final int? initialRequestId;
  final ValueChanged<int>? onEditRoles, onSelectRequest;
  final VoidCallback? onRequestClosed;
  final ValueChanged<String>? onTabChanged;
  @override
  ConsumerState<PanelistEligibilityDirectory> createState() =>
      _PanelistEligibilityDirectoryState();
}

class _PanelistEligibilityDirectoryState
    extends ConsumerState<PanelistEligibilityDirectory> {
  String _search = '';
  late String _tab =
      widget.initialRequestId != null && widget.initialTab == 'faculty'
      ? 'requests'
      : widget.initialTab;
  final _contentKey = GlobalKey();
  BuildContext? _activeSheet;
  bool _sheetOpen = false, _openingRoles = false;
  bool _busy = false;
  String? _error;
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (_router == router) return;
    _router?.routerDelegate.removeListener(_reopenDestination);
    _router = router;
    _router?.routerDelegate.addListener(_reopenDestination);
  }

  void _reopenDestination() {
    final uri = _router?.routerDelegate.currentConfiguration.uri;
    final id = widget.initialRequestId;
    if (id == null || uri == null || _sheetOpen) return;
    final requestedId = int.tryParse(
      uri.queryParameters[widget.centralized ? 'request' : 'panelistRequest'] ??
          '',
    );
    final expectedPath = widget.centralized
        ? '/admin/users'
        : '/faculty/defense-board';
    if (uri.path != expectedPath || requestedId != id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRequest(id);
    });
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_reopenDestination);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
      if (mounted && widget.initialRequestId != null) {
        _showRequest(widget.initialRequestId!);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PanelistEligibilityDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) _tab = widget.initialTab;
    if (oldWidget.initialRequestId != widget.initialRequestId) {
      if (widget.initialRequestId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showRequest(widget.initialRequestId!);
        });
      } else if (_sheetOpen && _activeSheet?.mounted == true) {
        Navigator.of(_activeSheet!).pop();
      }
    }
  }

  void _editRoles(int id) {
    if (widget.onEditRoles != null) {
      widget.onEditRoles!(id);
      return;
    }
    final router = GoRouter.maybeOf(context);
    widget.onClose?.call();
    router?.go('/admin/users?tab=faculty&view=roles&user=$id');
  }

  void _openRequest(int id) {
    if (widget.onSelectRequest != null) {
      widget.onSelectRequest!(id);
    } else {
      _showRequest(id);
    }
  }

  Future<void> _showRequest(int id) async {
    if (_sheetOpen || !mounted) return;
    final sheetHost = _contentKey.currentContext;
    if (sheetHost == null) return;
    final canEditRoles =
        ref.read(defenseSchedulerProvider).canApprovePanelists ||
        ref.read(authProvider).user?['role'] == 'admin';
    final router = GoRouter.maybeOf(context);
    final openingUri = router?.routeInformationProvider.value.uri;
    NavigatorState? sheetNavigator;
    ModalRoute<void>? sheetRoute;
    var leftDestination = false;
    void closeOnNavigation() {
      if (router?.routeInformationProvider.value.uri == openingUri) return;
      leftDestination = true;
      if (sheetRoute?.isActive == true && sheetNavigator?.mounted == true) {
        sheetNavigator!.removeRoute(sheetRoute!);
      }
    }

    router?.routeInformationProvider.addListener(closeOnNavigation);
    _sheetOpen = true;
    _openingRoles = false;
    await showShadSheet<void>(
      context: sheetHost,
      side: ShadSheetSide.right,
      barrierColor: Colors.black.withValues(alpha: .18),
      builder: (sheetContext) {
        _activeSheet = sheetContext;
        sheetNavigator = Navigator.of(sheetContext);
        sheetRoute = ModalRoute.of<void>(sheetContext);
        return DefensysShadcnScope(
          child: ShadSheet(
            key: const ValueKey('panelist-request-sheet'),
            title: Text('Request #$id'),
            isScrollControlled: true,
            scrollable: true,
            expandCrossSide: true,
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(sheetContext).width.clamp(0, 540),
            ),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Close request'),
              ),
            ],
            child: NotificationRequestScreen(
              kind: 'panelist',
              requestId: id,
              embedded: true,
              onBack: () => Navigator.pop(sheetContext),
              onOpenRoles: !canEditRoles
                  ? null
                  : (facultyId) {
                      _openingRoles = true;
                      Navigator.pop(sheetContext);
                      _editRoles(facultyId);
                    },
            ),
          ),
        );
      },
    );
    router?.routeInformationProvider.removeListener(closeOnNavigation);
    _sheetOpen = false;
    _activeSheet = null;
    if (mounted && !_openingRoles && !leftDestination) {
      widget.onRequestClosed?.call();
    }
  }

  Future<void> _refresh() => _mutate(() async {
    if (widget.centralized || _tab != 'faculty') {
      await ref.read(panelistRequestsProvider('pending').notifier).fetch();
      if (!mounted) return false;
      if (_tab == 'history') {
        await ref.read(panelistRequestsProvider('reviewed').notifier).fetch();
        if (!mounted) return false;
      }
    }
    await ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
    if (!mounted) return false;
    return ref.read(defenseSchedulerProvider).error == null;
  });

  Future<void> _mutate(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _error =
            ref.read(defenseSchedulerProvider).error ??
            'Unable to update panelist eligibility.';
      }
    });
  }

  Future<String?> _noteDialog({
    required String title,
    required String description,
    required String action,
  }) async {
    var note = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => DefensysShadcnScope(
        child: ShadDialog(
          title: Text(title),
          description: Text(description),
          constraints: const BoxConstraints(maxWidth: 460),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(dialogContext, note.trim()),
              child: Text(action),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ShadInput(
              placeholder: const Text('Reason (optional)'),
              maxLength: 1000,
              minLines: 2,
              maxLines: 4,
              onChanged: (value) => note = value,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _request(Map<String, dynamic> faculty) async {
    final note = await _noteDialog(
      title: 'Request eligibility',
      description:
          'Ask an admin to add ${faculty['name']} to the reusable panelist pool.',
      action: 'Submit request',
    );
    if (note == null || !mounted) return;
    await _mutate(
      () => ref
          .read(defenseSchedulerProvider.notifier)
          .requestPanelistEligibility((faculty['id'] as num).toInt(), note),
    );
  }

  List<Map<String, dynamic>> _requestsFor(int id) => ref
      .read(defenseSchedulerProvider)
      .panelistRequests
      .where((request) => request['faculty_id'] == id)
      .toList();

  Widget _identity(Map<String, dynamic> person) {
    final id = (person['id'] as num).toInt();
    final declined = ref.read(defenseSchedulerProvider).isEligiblePanelist(id)
        ? null
        : _requestsFor(
            id,
          ).where((request) => request['status'] == 'declined').firstOrNull;
    final note = (declined?['review_note'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          person['name']?.toString() ?? person['username'].toString(),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          'ID: ${person['username'] ?? person['id']}',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        if (note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Tooltip(
              message: note,
              child: Text(
                'Previous decision: $note',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _status(Map<String, dynamic> person, DefenseSchedulerState state) {
    final id = (person['id'] as num).toInt();
    final eligible = state.isEligiblePanelist(id);
    final pending = _requestsFor(id).any((r) => r['status'] == 'pending');
    return ShadBadge.outline(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            eligible
                ? LucideIcons.circleCheck
                : pending
                ? LucideIcons.clock
                : LucideIcons.circleMinus,
            size: 13,
            color: eligible
                ? (DefensysTokens.isDark(context)
                      ? Colors.tealAccent
                      : DefensysTokens.successText)
                : DefensysTokens.textSecondaryOf(context),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              eligible
                  ? 'Eligible panelist'
                  : pending
                  ? 'Approval pending'
                  : 'Not eligible',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(Map<String, dynamic> person, DefenseSchedulerState state) {
    final id = (person['id'] as num).toInt();
    final eligible = state.isEligiblePanelist(id);
    final pending = _requestsFor(id).any((r) => r['status'] == 'pending');
    if (state.canApprovePanelists) {
      return ShadButton.outline(
        key: ValueKey('panelist-eligibility-$id'),
        size: ShadButtonSize.sm,
        onPressed: _busy ? null : () => _editRoles(id),
        leading: Icon(LucideIcons.shieldCheck, size: 14),
        child: Flexible(
          child: Text(
            'Edit roles',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (eligible) return const SizedBox.shrink();
    return ShadButton.outline(
      size: ShadButtonSize.sm,
      onPressed: _busy || pending ? null : () => _request(person),
      child: Flexible(
        child: Text(
          pending ? 'Request pending' : 'Request eligibility',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _facultyList(
    List<Map<String, dynamic>> people,
    DefenseSchedulerState state,
    bool narrow,
  ) {
    if (!narrow) {
      return DefensysDataTable<Map<String, dynamic>>(
        items: people,
        columns: [
          DefensysTableColumn(
            title: 'Faculty member',
            minWidth: 180,
            flex: 2,
            cellBuilder: (_, person, index) => _identity(person),
          ),
          DefensysTableColumn(
            title: 'Eligibility',
            minWidth: 175,
            flex: 1.7,
            cellBuilder: (_, person, index) => _status(person, state),
          ),
          DefensysTableColumn(
            title: 'Role access',
            minWidth: 195,
            flex: 2,
            cellBuilder: (_, person, index) => _actions(person, state),
          ),
        ],
      );
    }
    return Column(
      children: people.map((person) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: DefensysTokens.borderOf(context)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _identity(person),
              const SizedBox(height: 10),
              _status(person, state),
              const SizedBox(height: 10),
              _actions(person, state),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
    final queue = widget.centralized || _tab != 'faculty'
        ? ref.watch(panelistRequestsProvider('pending'))
        : null;
    final pool = state.faculty.isNotEmpty ? state.faculty : state.panelists;
    final query = _search.trim().toLowerCase();
    final people = pool
        .where(
          (p) => '${p['name']} ${p['username']}'.toLowerCase().contains(query),
        )
        .toList();
    final pending = state.panelistRequests
        .where((r) => r['status'] == 'pending')
        .toList();
    final showRequests = _tab == 'requests' || _tab == 'history';
    final eligibleCount = pool
        .where((p) => state.isEligiblePanelist((p['id'] as num).toInt()))
        .length;
    return DefensysShadcnScope(
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          key: _contentKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.centralized
                            ? 'Panelist access'
                            : 'Panelist pool',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state.canApprovePanelists
                            ? 'Panelist eligibility follows the assigned RBAC role. Review nominations and past decisions here.'
                            : 'Browse eligible faculty or request approval for a new panelist.',
                        style: TextStyle(
                          color: DefensysTokens.textSecondaryOf(context),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onClose != null)
                  Tooltip(
                    message: 'Close',
                    child: ShadButton.ghost(
                      size: ShadButtonSize.sm,
                      onPressed: widget.onClose,
                      child: const Icon(LucideIcons.x, size: 18),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: constraints.maxWidth < 600
                      ? constraints.maxWidth - 44
                      : 440,
                  child: ShadTabs<String>(
                    scrollable: false,
                    gap: 0,
                    value: _tab,
                    onChanged: (tab) {
                      setState(() => _tab = tab);
                      widget.onTabChanged?.call(tab);
                    },
                    tabs: [
                      ShadTab(
                        value: 'faculty',
                        child: Flexible(
                          child: Text(
                            'Faculty (${pool.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      ShadTab(
                        value: 'requests',
                        child: Flexible(
                          child: Text(
                            'Requests (${queue?.pending ?? pending.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      ShadTab(
                        value: 'history',
                        child: Flexible(
                          child: Text(
                            'History',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Refresh pool',
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: _busy ? null : _refresh,
                    leading: constraints.maxWidth < 400
                        ? null
                        : const Icon(LucideIcons.refreshCw, size: 15),
                    child: constraints.maxWidth < 400
                        ? const Icon(LucideIcons.refreshCw, size: 16)
                        : const Text('Refresh pool'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!showRequests)
              ShadInput(
                placeholder: Text(
                  showRequests
                      ? 'Search requests'
                      : 'Search faculty name or ID',
                ),
                leading: const Icon(LucideIcons.search, size: 16),
                onChanged: (value) => setState(() => _search = value),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: showRequests
                  ? PanelistRequestsView(
                      key: ValueKey(_tab),
                      reviewed: _tab == 'history',
                      onOpen: _openRequest,
                    )
                  : _busy && pool.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        if (people.isNotEmpty)
                          _facultyList(
                            people,
                            state,
                            constraints.maxWidth < 640,
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Column(
                              children: [
                                Icon(
                                  showRequests
                                      ? LucideIcons.inbox
                                      : LucideIcons.users,
                                  size: 28,
                                  color: DefensysTokens.textSecondaryOf(
                                    context,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  showRequests
                                      ? (query.isEmpty
                                            ? 'All requests reviewed'
                                            : 'No matching requests')
                                      : 'No matching faculty members.',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              '$eligibleCount of ${pool.length} faculty eligible${_busy ? ' · Updating…' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
