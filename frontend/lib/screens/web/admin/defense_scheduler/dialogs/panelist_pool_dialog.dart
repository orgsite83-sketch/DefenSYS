import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import '../components/scheduler_people_picker.dart';
import '../../user_management/access_control/panelist_eligibility_view.dart';
import 'package:defensys/theme/defensys_tokens.dart';

/// The same pool and approval queue are available from scheduling and imports.
class PanelistPoolButton extends ConsumerWidget {
  const PanelistPoolButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(defenseSchedulerProvider);
    final pending = state.panelistRequests
        .where((r) => r['status'] == 'pending')
        .length;
    if (compact) {
      return SchedulerShadcnScope(
        child: ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: () => PanelistPoolDialog.show(context),
          child: Text(pending > 0 ? 'Manage pool ($pending)' : 'Manage pool'),
        ),
      );
    }
    return TextButton.icon(
      onPressed: () => PanelistPoolDialog.show(context),
      icon: const Icon(Icons.how_to_reg_outlined, size: 18),
      label: Text(
        state.canApprovePanelists && pending > 0
            ? 'Panelist requests ($pending)'
            : 'Panelist pool${pending > 0 ? ' ($pending pending)' : ''}',
      ),
    );
  }
}

class PanelistPoolDialog extends StatelessWidget {
  const PanelistPoolDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const PanelistPoolDialog(),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    elevation: 0,
    insetPadding: const EdgeInsets.all(20),
    backgroundColor: DefensysTokens.surfaceOf(context),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: DefensysTokens.borderOf(context)),
    ),
    child: SizedBox(
      width: 840,
      height: (MediaQuery.sizeOf(context).height * .82).clamp(0, 680),
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
        ),
        child: PanelistEligibilityDirectory(
          onClose: () => Navigator.pop(context),
        ),
      ),
    ),
  );
}
