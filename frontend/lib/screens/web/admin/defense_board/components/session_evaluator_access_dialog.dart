import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/admin/external_evaluator_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../user_management/external_evaluators/external_evaluator_views.dart';

/// Reads existing invitations without issuing or renewing access codes.
class SessionEvaluatorAccessDialog extends ConsumerStatefulWidget {
  const SessionEvaluatorAccessDialog({super.key, required this.scheduleIds});
  final Set<int> scheduleIds;

  static Future<void> show(BuildContext context, Set<int> scheduleIds) =>
      showDialog<void>(
        context: context,
        builder: (_) => SessionEvaluatorAccessDialog(scheduleIds: scheduleIds),
      );

  @override
  ConsumerState<SessionEvaluatorAccessDialog> createState() =>
      _SessionEvaluatorAccessDialogState();
}

class _SessionEvaluatorAccessDialogState
    extends ConsumerState<SessionEvaluatorAccessDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _invitations = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await ref.read(externalEvaluatorProvider.notifier).fetch();
    if (!mounted) return;
    final state = ref.read(externalEvaluatorProvider);
    setState(() {
      _loading = false;
      _error = ok ? null : state.error ?? 'Could not load evaluator access.';
      _invitations = ok
          ? state.invitations.where((invitation) {
              final ids =
                  invitation['schedule_ids'] as List? ??
                  (invitation['schedules'] as List? ?? [])
                      .whereType<Map>()
                      .map((s) => s['id'])
                      .toList();
              return ids.any(
                (id) => widget.scheduleIds.contains(int.tryParse('$id')),
              );
            }).toList()
          : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _error == null && _invitations.isNotEmpty) {
      return GuestInvitationDialog(invitations: _invitations);
    }
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Evaluator access',
                  style: DefensysTokens.dialogTitle.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Expanded(child: Text('Loading evaluator invitations…')),
                    ],
                  )
                else
                  Text(
                    _error ??
                        'No evaluator invitations are available for this session.',
                    style: DefensysTokens.body.copyWith(
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_error != null)
                      ShadButton.outline(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ShadButton.outline(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
