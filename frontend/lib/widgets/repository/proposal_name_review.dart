import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import 'concept_review_section.dart';

/// One title confirmation, next to the documents that support that proposal.
class ProposalNameReview extends StatefulWidget {
  const ProposalNameReview({
    super.key,
    required this.title,
    required this.confirmed,
    required this.system,
    this.canConfirm = false,
    this.onConfirm,
    this.linkedSystem,
  });

  final String title;
  final bool confirmed;
  final bool system;
  final bool canConfirm;
  final String? linkedSystem;
  final Future<bool> Function(String? title)? onConfirm;

  @override
  State<ProposalNameReview> createState() => _ProposalNameReviewState();
}

class _ProposalNameReviewState extends State<ProposalNameReview> {
  late final controller = TextEditingController(text: widget.title);
  bool editing = false;
  bool saving = false;
  String? error;
  Future<bool> Function(String? title)? reviewAction;

  @override
  void didUpdateWidget(covariant ProposalNameReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!editing && oldWidget.title != widget.title) {
      controller.text = widget.title;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> confirm({bool edited = false}) async {
    if (saving || widget.onConfirm == null) return;
    final title = controller.text.trim();
    if (edited && (title.isEmpty || title.length > 255)) {
      setState(() => error = 'Enter a name of up to 255 characters.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final ok = await (edited
          ? reviewAction ?? widget.onConfirm!
          : widget.onConfirm!)(edited ? title : null);
      if (mounted) {
        setState(() {
          if (ok) editing = false;
          if (!ok) {
            error =
                'The name was not confirmed. Review the error and try again.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'The name could not be confirmed. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = DefensysTokens.textSecondaryOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TitleReviewHeader(
            label: 'Proposed ${widget.system ? 'system' : 'module'} name',
            statusLabel: widget.confirmed
                ? 'Name confirmed'
                : 'Needs name confirmation',
            accepted: widget.confirmed,
          ),
          const SizedBox(height: 8),
          if (editing) ...[
            ShadInput(
              controller: controller,
              minLines: 1,
              maxLines: 3,
              enabled: !saving,
              placeholder: const Text('Proposed name'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ShadButton(
                  size: ShadButtonSize.sm,
                  enabled: !saving,
                  onPressed: () => confirm(edited: true),
                  child: const Text('Save and confirm name'),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  enabled: !saving,
                  onPressed: () => setState(() {
                    editing = false;
                    error = null;
                  }),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ] else ...[
            Text(
              widget.title.trim().isEmpty ? 'Name needed' : widget.title,
              style: DefensysTokens.body.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            if (widget.linkedSystem?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                'Linked to ${widget.linkedSystem}',
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ],
            if (widget.canConfirm && widget.onConfirm != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!widget.confirmed && widget.title.trim().isNotEmpty)
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      enabled: !saving,
                      onPressed: () => confirm(),
                      child: Text(
                        'Confirm ${widget.system ? 'system' : 'module'} name',
                      ),
                    ),
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    enabled: !saving,
                    onPressed: () => setState(() {
                      controller.text = widget.title;
                      reviewAction = widget.onConfirm;
                      editing = true;
                      error = null;
                    }),
                    child: const Text('Edit name'),
                  ),
                ],
              ),
            ],
          ],
          if (saving)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
