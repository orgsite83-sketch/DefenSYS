import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class FacultyRequirementActions extends StatefulWidget {
  const FacultyRequirementActions({
    super.key,
    required this.onDetails,
    this.onReview,
    this.onViewFile,
    this.onRequestRevision,
    this.multipleFiles = false,
    this.enabled = true,
  });
  final VoidCallback onDetails;
  final VoidCallback? onReview, onViewFile, onRequestRevision;
  final bool multipleFiles, enabled;

  @override
  State<FacultyRequirementActions> createState() =>
      _FacultyRequirementActionsState();
}

class _FacultyRequirementActionsState extends State<FacultyRequirementActions> {
  final controller = ShadPopoverController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget action(String label, IconData icon, VoidCallback callback) =>
      ShadButton.ghost(
        size: ShadButtonSize.sm,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        mainAxisAlignment: MainAxisAlignment.start,
        leading: Icon(icon, size: 16),
        onPressed: () {
          controller.hide();
          callback();
        },
        child: Text(label, style: const TextStyle(fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) => ShadPopover(
    controller: controller,
    padding: const EdgeInsets.all(4),
    popover: (_) => SizedBox(
      width: 168,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onReview != null)
            action('Review', Icons.rate_review_outlined, widget.onReview!),
          if (widget.onViewFile != null)
            action(
              widget.multipleFiles ? 'View files' : 'View file',
              Icons.visibility_outlined,
              widget.onViewFile!,
            ),
          action('Details', Icons.info_outline, widget.onDetails),
          if (widget.onRequestRevision != null)
            action(
              'Request revision',
              Icons.edit_note_outlined,
              widget.onRequestRevision!,
            ),
        ],
      ),
    ),
    child: Semantics(
      button: true,
      label: 'Deliverable actions',
      child: Tooltip(
        message: 'Deliverable actions',
        child: ShadButton.outline(
          width: 32,
          height: 32,
          size: ShadButtonSize.sm,
          enabled: widget.enabled,
          padding: EdgeInsets.zero,
          onPressed: widget.enabled ? controller.toggle : null,
          child: const Icon(Icons.more_horiz, size: 18),
        ),
      ),
    ),
  );
}
