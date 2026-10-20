import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../services/pit_instructor_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import '../dialogs/confirm_dialog.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Actions affect this section assignment, while the faculty account stays intact.
class InstructorAssignmentActions extends ConsumerStatefulWidget {
  const InstructorAssignmentActions({
    super.key,
    required this.assignment,
    required this.onChange,
    this.onUpdated,
  });

  final Map<String, dynamic> assignment;
  final VoidCallback onChange;
  final VoidCallback? onUpdated;

  @override
  ConsumerState<InstructorAssignmentActions> createState() =>
      _InstructorAssignmentActionsState();
}

class _InstructorAssignmentActionsState
    extends ConsumerState<InstructorAssignmentActions> {
  final _controller = ShadContextMenuController();
  Map<String, dynamic> get assignment => widget.assignment;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(assignment['id']?.toString() ?? '');
    final active = assignment['is_active'] == true;
    final name = assignment['faculty_name']?.toString() ?? 'Instructor';
    final saving = ref.watch(pitInstructorProvider.select((s) => s.isSaving));
    ShadContextMenuItem item(
      String action,
      String label,
      IconData icon, {
      bool destructive = false,
    }) => ShadContextMenuItem(
      height: DefensysTokens.buttonHeightSm,
      onPressed: () {
        _controller.hide();
        _handleAction(action);
      },
      textStyle: DefensysTokens.tableCell.copyWith(
        color: destructive
            ? Theme.of(context).colorScheme.error
            : DefensysTokens.textPrimaryOf(context),
      ),
      leading: Icon(
        icon,
        size: 16,
        color: destructive
            ? Theme.of(context).colorScheme.error
            : DefensysTokens.textSecondaryOf(context),
      ),
      child: Text(label),
    );
    return DefensysShadcnScope(
      child: TapRegion(
        groupId: _controller,
        onTapOutside: (_) => _controller.hide(),
        child: ShadContextMenu(
          controller: _controller,
          groupId: widget.key ?? _controller,
          anchor: const ShadAnchorAuto(
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: Offset(0, 4),
            fallback: ShadAnchorAuto(
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.bottomRight,
              offset: Offset(0, -4),
            ),
          ),
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
          items: [
            for (final entry in [
              item('details', 'Details', Icons.info_outline_rounded),
              if (active) item('change', 'Change', Icons.swap_horiz_rounded),
              active
                  ? item(
                      'remove',
                      'Remove',
                      Icons.person_remove_outlined,
                      destructive: true,
                    )
                  : item('restore', 'Restore', Icons.restore_rounded),
            ])
              TapRegion(groupId: _controller, child: entry),
          ],
          child: Tooltip(
            message: 'Instructor actions for $name',
            child: ShadButton.ghost(
              key: ValueKey('instructor-actions-$id'),
              enabled: !saving && id != null,
              width: 32,
              height: 32,
              padding: EdgeInsets.zero,
              onPressed: !saving && id != null ? _controller.toggle : null,
              child: const Icon(Icons.more_horiz_rounded, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(String action) async {
    final id = int.tryParse(assignment['id']?.toString() ?? '');
    final name = assignment['faculty_name']?.toString() ?? 'Instructor';
    if (action == 'details') {
      await _showDetails(context);
      return;
    }
    if (action == 'change') {
      widget.onChange();
      return;
    }
    if (action == 'remove') {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Remove instructor?',
        message:
            'Remove $name from ${assignment['section']} for ${assignment['semester_label']}? '
            'Their account and existing review records will be kept.',
        confirmLabel: 'Remove',
        destructive: true,
        icon: Icons.person_remove_outlined,
      );
      if (!confirmed || !mounted) return;
    }
    if (!mounted || id == null) return;
    final restored = action == 'restore';
    final success = await ref
        .read(pitInstructorProvider.notifier)
        .setAssignmentActive(id, restored);
    if (!mounted) return;
    if (success) {
      showSuccessToast(
        context,
        restored
            ? 'Instructor restored.'
            : 'Instructor removed from this section.',
      );
      widget.onUpdated?.call();
    } else {
      showErrorToast(
        context,
        ref.read(pitInstructorProvider).error ??
            'Failed to update the assignment.',
      );
    }
  }

  Future<void> _showDetails(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) {
      Widget field(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                (value?.toString().trim().isNotEmpty ?? false)
                    ? value.toString()
                    : '—',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
      return AlertDialog(
        title: const Text('Instructor details'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  assignment['faculty_name']?.toString() ?? 'Instructor',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                field('ID number', assignment['faculty_username']),
                field('Email', assignment['faculty_email']),
                Divider(color: DefensysTokens.borderOf(context)),
                field('Section', assignment['section']),
                field('Year level', assignment['year_level']),
                field('Academic period', assignment['semester_label']),
                field(
                  'Status',
                  assignment['is_active'] == true ? 'Active' : 'Inactive',
                ),
                field('Assigned by', assignment['assigned_by_name']),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
