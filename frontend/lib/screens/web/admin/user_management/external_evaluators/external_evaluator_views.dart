import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/utils/clipboard_copy.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/guest_invitation.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import '../../defense_scheduler/components/scheduler_people_picker.dart';
import 'external_assignment_dialog.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/table/defensys_data_table.dart';
import 'package:defensys/widgets/table/defensys_table_column.dart';

String _date(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? '—'
      : DateFormat('MMM d, y · h:mm a').format(date.toLocal());
}

Future<DateTime?> pickGuestExpiry(
  BuildContext context,
  DateTime initial,
) async {
  final now = DateTime.now();
  final value = initial.isBefore(now)
      ? now.add(const Duration(hours: 8))
      : initial;
  final day = await showDatePicker(
    context: context,
    initialDate: value,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 730)),
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(value),
  );
  return time == null
      ? null
      : DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

class ExternalEvaluatorCreateDialog extends ConsumerStatefulWidget {
  const ExternalEvaluatorCreateDialog({super.key, this.evaluator});
  final Map<String, dynamic>? evaluator;
  static Future<bool?> show(
    BuildContext context, {
    Map<String, dynamic>? evaluator,
  }) => showDialog<bool>(
    context: context,
    builder: (_) => ExternalEvaluatorCreateDialog(evaluator: evaluator),
  );
  @override
  ConsumerState<ExternalEvaluatorCreateDialog> createState() =>
      _ExternalEvaluatorCreateDialogState();
}

class _ExternalEvaluatorCreateDialogState
    extends ConsumerState<ExternalEvaluatorCreateDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _institution = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name.text = widget.evaluator?['name']?.toString() ?? '';
    _email.text = widget.evaluator?['email']?.toString() ?? '';
    _institution.text = widget.evaluator?['institution']?.toString() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _institution.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'institution': _institution.text.trim(),
    };
    final notifier = ref.read(externalEvaluatorProvider.notifier);
    final ok = widget.evaluator == null
        ? await notifier.register(data)
        : await notifier.review(widget.evaluator!['id'] as int, data);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = ref.read(externalEvaluatorProvider).error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final admin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    return AlertDialog(
      title: Text(
        widget.evaluator != null
            ? 'Edit external evaluator'
            : admin
            ? 'Add external evaluator'
            : 'Nominate external evaluator',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  admin
                      ? 'Approve this evaluator once, then reuse their record for future PIT or Capstone defenses.'
                      : 'The admin reviews this evaluator once. After approval, you can assign them to defenses in your PIT year.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  maxLength: 150,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Full name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter the evaluator’s name.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v != null &&
                          v.trim().isNotEmpty &&
                          !RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(v.trim())
                      ? 'Enter a valid email address.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _institution,
                  maxLength: 150,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Institution / organization (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'An invitation is created when they are assigned to confirmed defenses. You can copy and share it yourself.',
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? 'Saving…'
                : widget.evaluator != null
                ? 'Save changes'
                : admin
                ? 'Save & approve'
                : 'Request approval',
          ),
        ),
      ],
    );
  }
}

class GuestInvitationDialog extends StatelessWidget {
  const GuestInvitationDialog({super.key, required this.invitations});
  final List<Map<String, dynamic>> invitations;

  static Future<void> show(
    BuildContext context,
    List<Map<String, dynamic>> invitations,
  ) async {
    if (invitations.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => GuestInvitationDialog(invitations: invitations),
    );
  }

  Future<void> _copy(BuildContext context, String value, String success) async {
    final ok = await copyTextToClipboard(value);
    if (!context.mounted) return;
    if (ok) {
      showSuccessToast(context, success);
    } else {
      showErrorToast(context, 'Copy failed. Select and copy the access code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final portal = guestPortalUrl();
    final local =
        portal.isNotEmpty &&
        ['localhost', '127.0.0.1', '0.0.0.0'].contains(Uri.parse(portal).host);
    return DefensysShadcnScope(
      child: Dialog(
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: DefensysTokens.surfaceOf(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
        child: SizedBox(
          width: 680,
          height: (MediaQuery.sizeOf(context).height * .82).clamp(0, 660),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Evaluator invitations',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '${invitations.length} access links. Share each stage or event invitation with its evaluator.',
                  style: TextStyle(
                    color: DefensysTokens.textSecondaryOf(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      if (local)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'For remote evaluators, use the deployed DefenSYS address instead of localhost.',
                            style: TextStyle(
                              fontSize: 12,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      for (final invitation in invitations)
                        _invitationCard(context, invitation, portal),
                      if (portal.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Portal address',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          portal,
                          style: TextStyle(
                            fontSize: 12,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Evaluators open the link in a browser. If needed, they can enter the access code on the portal.',
                        style: TextStyle(
                          fontSize: 12,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ShadButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _invitationCard(
    BuildContext context,
    Map<String, dynamic> invitation,
    String portal,
  ) {
    final schedules = invitation['schedules'] as List? ?? [];
    final sessions = schedules.map((s) => s['stage_label']).toSet().join(', ');
    final teams = schedules
        .map((s) => s['team_name'].toString())
        .toSet()
        .toList();
    final code = invitation['code']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            invitation['guest_name']?.toString() ?? 'Evaluator',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 5),
          Text(
            '$sessions · ${(invitation['schedule_ids'] as List? ?? []).length} defense${(invitation['schedule_ids'] as List? ?? []).length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          if (teams.isNotEmpty) ...[
            const SizedBox(height: 6),
            Tooltip(
              message: teams.join(', '),
              child: Text(
                '${teams.take(3).join(', ')}${teams.length > 3 ? ' + ${teams.length - 3} more' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: DefensysTokens.panelOf(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    code,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Copy access code',
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: () =>
                        _copy(context, code, 'Access code copied.'),
                    child: const Icon(LucideIcons.copy, size: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Access until ${_date(invitation['expires_at'])}',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton(
                size: ShadButtonSize.sm,
                onPressed: () => _copy(
                  context,
                  guestInvitationText(invitation),
                  'Invitation copied.',
                ),
                leading: const Icon(LucideIcons.copy, size: 14),
                child: const Text('Copy invitation'),
              ),
              if (portal.isNotEmpty)
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () => _copy(
                    context,
                    guestInvitationUrl(code),
                    'Login link copied.',
                  ),
                  child: const Text('Copy login link'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ExternalEvaluatorDirectory extends ConsumerStatefulWidget {
  const ExternalEvaluatorDirectory({super.key});
  @override
  ConsumerState<ExternalEvaluatorDirectory> createState() =>
      _ExternalEvaluatorDirectoryState();
}

class _ExternalEvaluatorDirectoryState
    extends ConsumerState<ExternalEvaluatorDirectory> {
  bool _invitations = false;
  String _search = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(externalEvaluatorProvider.notifier).fetch();
    });
  }

  Future<void> _mutate(Future<bool> Function() action) async {
    final ok = await action();
    if (!mounted) return;
    if (!ok) {
      showErrorToast(
        context,
        ref.read(externalEvaluatorProvider).error ??
            'Could not save the change.',
      );
    }
  }

  Future<void> _revoke(Map<String, dynamic> invitation) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Revoke evaluator access?'),
        content: Text(
          '${invitation['guest_name']} will lose access immediately. Submitted grades and drafts are retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _mutate(
        () => ref
            .read(externalEvaluatorProvider.notifier)
            .revoke(invitation['id'] as int),
      );
    }
  }

  Future<void> _renew(Map<String, dynamic> invitation) async {
    final expiry = await pickGuestExpiry(
      context,
      DateTime.now().add(const Duration(hours: 8)),
    );
    if (expiry == null || !mounted) return;
    final ok = await ref
        .read(externalEvaluatorProvider.notifier)
        .renew(invitation['id'] as int, expiry);
    if (!mounted) return;
    if (ok) {
      await GuestInvitationDialog.show(
        context,
        ref.read(externalEvaluatorProvider).createdInvitations,
      );
    } else {
      showErrorToast(
        context,
        ref.read(externalEvaluatorProvider).error ?? 'Could not renew access.',
      );
    }
  }

  Widget _status(String value, bool active) {
    final status = active ? value.toLowerCase() : 'inactive';
    final color = switch (status) {
      'approved' || 'active' =>
        DefensysTokens.isDark(context)
            ? Colors.tealAccent
            : DefensysTokens.successText,
      'pending' =>
        DefensysTokens.isDark(context)
            ? Colors.amberAccent
            : DefensysTokens.warningText,
      'declined' ||
      'revoked' ||
      'expired' => Theme.of(context).colorScheme.error,
      _ => DefensysTokens.textSecondaryOf(context),
    };
    return ShadBadge.outline(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${status[0].toUpperCase()}${status.substring(1)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _review(
    Map<String, dynamic> evaluator,
    ExternalEvaluatorState state,
  ) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      if (evaluator['status'] == 'approved' && evaluator['is_active'] == true)
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: state.saving
              ? null
              : () => ExternalInvitationCreateDialog.show(
                  context,
                  evaluatorId: evaluator['id'] as int,
                ),
          child: const Text('Assign'),
        ),
      if (state.canApprove)
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: state.saving
              ? null
              : () => ExternalEvaluatorCreateDialog.show(
                  context,
                  evaluator: evaluator,
                ),
          child: const Text('Edit'),
        ),
      if (state.canApprove && evaluator['status'] == 'pending') ...[
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: state.saving
              ? null
              : () => _mutate(
                  () => ref.read(externalEvaluatorProvider.notifier).review(
                    evaluator['id'],
                    {'status': 'approved'},
                  ),
                ),
          child: const Text('Approve'),
        ),
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: state.saving
              ? null
              : () => _mutate(
                  () => ref.read(externalEvaluatorProvider.notifier).review(
                    evaluator['id'],
                    {'status': 'declined'},
                  ),
                ),
          child: const Text('Decline'),
        ),
      ] else if (state.canApprove)
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: state.saving
              ? null
              : () => _mutate(
                  () => ref
                      .read(externalEvaluatorProvider.notifier)
                      .review(
                        evaluator['id'],
                        evaluator['status'] == 'declined'
                            ? {'status': 'approved', 'is_active': true}
                            : {'is_active': evaluator['is_active'] != true},
                      ),
                ),
          child: Text(
            evaluator['status'] == 'declined'
                ? 'Approve'
                : evaluator['is_active'] == true
                ? 'Deactivate'
                : 'Reactivate',
          ),
        ),
    ],
  );
  Widget _accessActions(
    Map<String, dynamic> item,
    ExternalEvaluatorState state,
  ) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      ShadButton.ghost(
        size: ShadButtonSize.sm,
        onPressed: () => GuestInvitationDialog.show(context, [item]),
        child: const Text('View / copy'),
      ),
      if (item['status'] == 'Active')
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: state.saving ? null : () => _revoke(item),
          child: const Text('Revoke'),
        ),
      ShadButton.ghost(
        size: ShadButtonSize.sm,
        onPressed: state.saving ? null : () => _renew(item),
        child: const Text('Renew'),
      ),
    ],
  );
  Widget _identity(Map<String, dynamic> item) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        (item['name'] ?? item['guest_name']).toString(),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      if ((item['email'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          item['email'],
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    ],
  );

  String _sessions(
    Map<String, dynamic> item,
  ) => (item['schedules'] as List? ?? [])
      .map(
        (s) =>
            '${s['scope'].toString().toUpperCase()} · ${s['stage_label']}\n${s['date']}',
      )
      .toSet()
      .join('\n');

  Widget _table(
    List<Map<String, dynamic>> items,
    ExternalEvaluatorState state,
  ) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefensysDataTable<Map<String, dynamic>>(
        key: ValueKey(
          _invitations
              ? 'evaluator-invitations-table'
              : 'evaluator-directory-table',
        ),
        items: items,
        columns: [
          DefensysTableColumn(
            title: 'Evaluator',
            minWidth: 200,
            flex: 2,
            cellBuilder: (_, e, index) => _identity(e),
          ),
          if (_invitations) ...[
            DefensysTableColumn(
              title: 'Defense session',
              minWidth: 180,
              flex: 1.6,
              cellBuilder: (_, e, index) => Text(_sessions(e)),
            ),
            DefensysTableColumn(
              title: 'Progress',
              minWidth: 120,
              cellBuilder: (_, e, index) => Text(
                '${e['submitted_count']} / ${(e['schedule_ids'] as List).length} submitted',
              ),
            ),
            DefensysTableColumn(
              title: 'Access expires',
              minWidth: 150,
              flex: 1.2,
              cellBuilder: (_, e, index) => Text(_date(e['expires_at'])),
            ),
            DefensysTableColumn(
              title: 'Last access',
              minWidth: 150,
              flex: 1.2,
              cellBuilder: (_, e, index) =>
                  Text(_date(e['last_access_at'] ?? e['used_at'])),
            ),
            DefensysTableColumn(
              title: 'Status',
              minWidth: 110,
              cellBuilder: (_, e, index) => _status(e['status'], true),
            ),
            DefensysTableColumn(
              title: 'Actions',
              minWidth: 225,
              flex: 2,
              cellBuilder: (_, e, index) => _accessActions(e, state),
            ),
          ] else ...[
            DefensysTableColumn(
              title: 'Institution',
              minWidth: 180,
              flex: 2,
              cellBuilder: (_, e, index) => Text(
                (e['institution'] ?? '').toString().isEmpty
                    ? '—'
                    : e['institution'],
              ),
            ),
            DefensysTableColumn(
              title: 'Approval',
              minWidth: 125,
              cellBuilder: (_, e, index) =>
                  _status(e['status'], e['is_active'] == true),
            ),
            DefensysTableColumn(
              title: 'Actions',
              minWidth: 275,
              flex: 2.2,
              cellBuilder: (_, e, index) => _review(e, state),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _mobileRows(
    List<Map<String, dynamic>> items,
    ExternalEvaluatorState state,
  ) => Column(
    children: items
        .map(
          (e) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: DefensysTokens.borderOf(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _identity(e),
                const SizedBox(height: 12),
                if (_invitations) ...[
                  _status(e['status'], true),
                  const SizedBox(height: 12),
                  Text(
                    '${e['submitted_count']} / ${(e['schedule_ids'] as List).length} defenses submitted',
                  ),
                  const SizedBox(height: 4),
                  Text(_sessions(e)),
                  const SizedBox(height: 8),
                  Text(
                    'Expires ${_date(e['expires_at'])}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'Last access ${_date(e['last_access_at'] ?? e['used_at'])}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  _accessActions(e, state),
                ] else ...[
                  if ((e['institution'] ?? '').toString().isNotEmpty) ...[
                    Text(
                      e['institution'],
                      style: TextStyle(
                        color: DefensysTokens.textSecondaryOf(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _status(e['status'], e['is_active'] == true),
                  if (state.canApprove) ...[
                    const SizedBox(height: 12),
                    _review(e, state),
                  ],
                ],
              ],
            ),
          ),
        )
        .toList(),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(externalEvaluatorProvider);
    final source = _invitations ? state.invitations : state.evaluators;
    final query = _search.trim().toLowerCase();
    final items = source
        .where(
          (e) =>
              '${e['name'] ?? e['guest_name']} ${e['email']} ${e['institution'] ?? ''}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return DefensysShadcnScope(
      child: Container(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
        ),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          border: Border.all(color: DefensysTokens.borderOf(context)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'External evaluators',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Approve evaluators, assign defenses, then share access.',
                        style: TextStyle(
                          fontSize: 13,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: state.loading || state.saving
                            ? null
                            : () => ref
                                  .read(externalEvaluatorProvider.notifier)
                                  .fetch(),
                        leading: const Icon(LucideIcons.refreshCw, size: 15),
                        child: const Text('Refresh'),
                      ),
                      ShadButton(
                        size: ShadButtonSize.sm,
                        onPressed: state.saving
                            ? null
                            : () =>
                                  ExternalInvitationCreateDialog.show(context),
                        leading: const Icon(LucideIcons.plus, size: 15),
                        child: const Text('Assign evaluators'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: constraints.maxWidth.clamp(0, 390),
                    child: ShadTabs<String>(
                      value: _invitations ? 'invitations' : 'directory',
                      scrollable: false,
                      gap: 0,
                      onChanged: (value) =>
                          setState(() => _invitations = value == 'invitations'),
                      tabs: [
                        ShadTab(
                          value: 'directory',
                          child: Flexible(
                            child: Text(
                              'Directory (${state.evaluators.length})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        ShadTab(
                          value: 'invitations',
                          child: Flexible(
                            child: Text(
                              'Invitations (${state.invitations.length})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth.clamp(0, 360),
                    child: ShadInput(
                      placeholder: const Text(
                        'Search evaluator or institution',
                      ),
                      leading: const Icon(LucideIcons.search, size: 16),
                      onChanged: (value) => setState(() => _search = value),
                    ),
                  ),
                ],
              ),
              if (state.loading || state.saving)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              if (items.isEmpty && !state.loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(
                        _invitations ? LucideIcons.mail : LucideIcons.users,
                        size: 28,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        query.isNotEmpty
                            ? 'No matching evaluators'
                            : _invitations
                            ? 'No evaluator invitations yet'
                            : 'No external evaluators yet',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        query.isNotEmpty
                            ? 'Try another name, email or institution.'
                            : _invitations
                            ? 'Invite approved evaluators to confirmed defenses.'
                            : 'Add an evaluator to build your reusable directory.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              if (items.isNotEmpty)
                constraints.maxWidth < 760
                    ? _mobileRows(items, state)
                    : _table(items, state),
              const SizedBox(height: 16),
              Text(
                '${items.length} of ${source.length} ${_invitations ? 'invitations' : 'evaluators'}',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExternalEvaluatorManagementButton extends StatelessWidget {
  const ExternalEvaluatorManagementButton({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => compact
      ? SchedulerShadcnScope(
          child: ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => show(context),
            child: const Text('Manage pool'),
          ),
        )
      : TextButton.icon(
          icon: const Icon(Icons.public, size: 18),
          label: const Text('External evaluators'),
          onPressed: () => show(context),
        );

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => ExternalEvaluatorCreateDialog.show(c),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add external evaluator'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: ExternalEvaluatorDirectory(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ExternalEvaluatorSelector extends ConsumerStatefulWidget {
  const ExternalEvaluatorSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.expiry,
    required this.onExpiryChanged,
    this.enabled = true,
    this.compact = false,
  });
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final DateTime? expiry;
  final ValueChanged<DateTime?> onExpiryChanged;
  final bool enabled;
  final bool compact;
  @override
  ConsumerState<ExternalEvaluatorSelector> createState() =>
      _ExternalEvaluatorSelectorState();
}

class _ExternalEvaluatorSelectorState
    extends ConsumerState<ExternalEvaluatorSelector> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(externalEvaluatorProvider.notifier).fetch();
    });
  }

  Widget _buildCompact(ExternalEvaluatorState state) {
    final primary = DefensysTokens.textPrimaryOf(context);
    final secondary = DefensysTokens.textSecondaryOf(context);
    return SchedulerShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1, color: DefensysTokens.borderOf(context)),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'External evaluators',
                  style: TextStyle(
                    color: primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const ExternalEvaluatorManagementButton(compact: true),
            ],
          ),
          Text(
            'Optional. Invitations are created when you confirm.',
            style: TextStyle(color: secondary, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (state.loading) const LinearProgressIndicator(minHeight: 2),
          SchedulerPeoplePicker(
            key: const ValueKey('external-evaluator-picker'),
            people: state.approved,
            selected: widget.selected,
            onChanged: widget.onChanged,
            placeholder: 'Choose external evaluators',
            searchPlaceholder: 'Search by name or institution',
            detailBuilder: (person) => person['institution']?.toString(),
            enabled: widget.enabled && !state.loading,
            emptyMessage: 'No approved external evaluators available.',
          ),
          if (state.error != null)
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: () =>
                  ref.read(externalEvaluatorProvider.notifier).fetch(),
              leading: const Icon(LucideIcons.refreshCw, size: 14),
              child: const Text('Could not load evaluators. Retry'),
            )
          else if (state.approved.isEmpty && !state.loading) ...[
            const SizedBox(height: 6),
            Text(
              'Add or request an evaluator in the pool.',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
          ],
          if (widget.selected.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Keep a faculty panel chair assigned.',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                padding: EdgeInsets.zero,
                enabled: widget.enabled,
                leading: const Icon(LucideIcons.clock, size: 14),
                onPressed: () async {
                  final expiry = await pickGuestExpiry(
                    context,
                    widget.expiry ??
                        DateTime.now().add(const Duration(hours: 8)),
                  );
                  if (expiry != null) widget.onExpiryChanged(expiry);
                },
                child: Text(
                  widget.expiry == null
                      ? 'Access: end of defense day'
                      : 'Expires ${_date(widget.expiry!.toIso8601String())}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            if (widget.expiry != null)
              Align(
                alignment: Alignment.centerLeft,
                child: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  enabled: widget.enabled,
                  onPressed: () => widget.onExpiryChanged(null),
                  child: const Text('Use default expiry'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(externalEvaluatorProvider);
    if (widget.compact) return _buildCompact(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text(
          'External evaluators (optional)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        const Text(
          'Select approved evaluators. Browser invitations are created after this schedule is confirmed.',
        ),
        if (state.loading) const LinearProgressIndicator(),
        if (state.error != null)
          TextButton.icon(
            onPressed: () =>
                ref.read(externalEvaluatorProvider.notifier).fetch(),
            icon: const Icon(Icons.refresh),
            label: const Text('Could not load evaluators · Retry'),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in state.approved)
              FilterChip(
                label: Text(e['name']),
                selected: widget.selected.contains(e['id']),
                onSelected: widget.enabled
                    ? (on) {
                        final ids = {...widget.selected};
                        on ? ids.add(e['id'] as int) : ids.remove(e['id']);
                        widget.onChanged(ids);
                      }
                    : null,
              ),
          ],
        ),
        if (state.approved.isEmpty && !state.loading)
          const Text('No approved external evaluators available.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: state.loading || state.saving
                ? null
                : () => ref.read(externalEvaluatorProvider.notifier).fetch(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(
              state.evaluators.any((e) => e['status'] == 'pending')
                  ? 'Refresh pool · Approval pending'
                  : 'Refresh evaluator pool',
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.enabled
                ? () => ExternalEvaluatorCreateDialog.show(context)
                : null,
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: Text(
              state.canApprove
                  ? 'Add external evaluator'
                  : 'Request evaluator approval',
            ),
          ),
        ),
        if (widget.selected.isNotEmpty) ...[
          const Text(
            'Keep a faculty panel chair assigned. External evaluators can grade only their invited defenses.',
          ),
          TextButton.icon(
            onPressed: widget.enabled
                ? () async {
                    final expiry = await pickGuestExpiry(
                      context,
                      widget.expiry ??
                          DateTime.now().add(const Duration(hours: 8)),
                    );
                    if (expiry != null) widget.onExpiryChanged(expiry);
                  }
                : null,
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(
              widget.expiry == null
                  ? 'Access expires at the end of defense day · Change'
                  : 'Expires ${_date(widget.expiry!.toIso8601String())} · Change',
            ),
          ),
          if (widget.expiry != null)
            TextButton(
              onPressed: () => widget.onExpiryChanged(null),
              child: const Text('Use default expiry'),
            ),
        ],
      ],
    );
  }
}

class ExternalInvitationCreateDialog extends StatelessWidget {
  const ExternalInvitationCreateDialog({super.key, this.evaluatorId});
  final int? evaluatorId;

  static Future<void> show(BuildContext context, {int? evaluatorId}) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            ExternalInvitationCreateDialog(evaluatorId: evaluatorId),
      );

  @override
  Widget build(BuildContext context) => ExternalAssignmentDialog(
    initialEvaluatorIds: {if (evaluatorId != null) evaluatorId!},
    onAddEvaluator: (context) async {
      await ExternalEvaluatorCreateDialog.show(context);
    },
    onCreated: GuestInvitationDialog.show,
    pickExpiry: pickGuestExpiry,
  );
}
