import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/table/defensys_data_table.dart';
import 'package:defensys/widgets/table/defensys_table_column.dart';

class PanelistEligibilityView extends StatelessWidget {
  const PanelistEligibilityView({super.key, required this.onBack});
  final VoidCallback onBack;

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
              child: const PanelistEligibilityDirectory(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The same RBAC duty editor is used by scheduling and Faculty & Staff.
class PanelistEligibilityDirectory extends ConsumerStatefulWidget {
  const PanelistEligibilityDirectory({super.key, this.onClose});
  final VoidCallback? onClose;
  @override
  ConsumerState<PanelistEligibilityDirectory> createState() =>
      _PanelistEligibilityDirectoryState();
}

class _PanelistEligibilityDirectoryState
    extends ConsumerState<PanelistEligibilityDirectory> {
  String _search = '';
  String _tab = 'faculty';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() => _mutate(() async {
    await ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
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

  Future<void> _review(Map<String, dynamic> request, bool approve) async {
    var note = '';
    if (!approve) {
      final result = await _noteDialog(
        title: 'Decline eligibility request',
        description: 'You can include a reason for the PIT lead.',
        action: 'Decline request',
      );
      if (result == null || !mounted) return;
      note = result;
    }
    await _mutate(
      () => ref
          .read(defenseSchedulerProvider.notifier)
          .reviewPanelistEligibility(
            (request['id'] as num).toInt(),
            approve: approve,
            note: note,
          ),
    );
  }

  Future<void> _setEligibility(
    Map<String, dynamic> person,
    bool eligible,
  ) async {
    if (!eligible) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => DefensysShadcnScope(
          child: ShadDialog(
            title: const Text('Remove panelist eligibility?'),
            description: Text(
              '${person['name']} will be removed from the eligible panelist pool. This also updates their role access.',
            ),
            constraints: const BoxConstraints(maxWidth: 460),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ShadButton.destructive(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove eligibility'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _mutate(
      () => ref
          .read(defenseSchedulerProvider.notifier)
          .setPanelistEligibility(
            (person['id'] as num).toInt(),
            eligible: eligible,
          ),
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
        onPressed: _busy ? null : () => _setEligibility(person, !eligible),
        leading: Icon(
          eligible ? LucideIcons.minus : LucideIcons.plus,
          size: 14,
        ),
        child: Flexible(
          child: Text(
            eligible ? 'Remove eligibility' : 'Grant eligibility',
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

  Widget _requestList(List<Map<String, dynamic>> requests) => Column(
    children: requests
        .map(
          (request) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request['faculty_name']?.toString() ?? 'Faculty member',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Requested by ${request['requested_by_name']} · ${request['pit_year']}',
                  style: TextStyle(
                    color: DefensysTokens.textSecondaryOf(context),
                    fontSize: 12,
                  ),
                ),
                if ((request['reason'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(request['reason'].toString()),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShadButton(
                      size: ShadButtonSize.sm,
                      onPressed: _busy ? null : () => _review(request, true),
                      child: const Text('Approve eligibility'),
                    ),
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: _busy ? null : () => _review(request, false),
                      child: const Text('Decline'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
        .toList(),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
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
    final requests = pending
        .where(
          (r) =>
              '${r['faculty_name']} ${r['requested_by_name']} ${r['pit_year']}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    final showRequests = state.canApprovePanelists && _tab == 'requests';
    final eligibleCount = pool
        .where((p) => state.isEligiblePanelist((p['id'] as num).toInt()))
        .length;
    return DefensysShadcnScope(
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
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
                        'Panelist eligibility',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state.canApprovePanelists
                            ? 'Manage the reusable panelist pool and review eligibility requests.'
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
                  width: constraints.maxWidth < 400
                      ? constraints.maxWidth - 52
                      : 290,
                  child: ShadTabs<String>(
                    scrollable: false,
                    gap: 0,
                    value: _tab,
                    onChanged: (tab) => setState(() => _tab = tab),
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
                      if (state.canApprovePanelists)
                        ShadTab(
                          value: 'requests',
                          child: Flexible(
                            child: Text(
                              'Requests (${pending.length})',
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
            ShadInput(
              placeholder: Text(
                showRequests ? 'Search requests' : 'Search faculty name or ID',
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
              child: _busy && pool.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        if (showRequests && requests.isNotEmpty)
                          _requestList(requests)
                        else if (!showRequests && people.isNotEmpty)
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
