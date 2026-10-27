import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../theme/defensys_tokens.dart';
import 'concept_review_section.dart';
import 'concept_revision_dialog.dart';

/// Student-owned title submission and adviser review share the same state.
class TitleReviewCard extends StatefulWidget {
  const TitleReviewCard({
    super.key,
    required this.concept,
    required this.onAction,
    this.system = false,
    this.readOnly = false,
  });
  final Map<String, dynamic> concept;
  final bool system;
  final bool readOnly;
  final Future<bool> Function(String action, String? title, String? reason)
  onAction;
  @override
  State<TitleReviewCard> createState() => _TitleReviewCardState();
}

class _TitleReviewCardState extends State<TitleReviewCard> {
  late final controller = TextEditingController(
    text: '${widget.concept['title'] ?? ''}',
  );
  bool busy = false;
  String? error;
  Future<bool> Function(String, String?, String?)? editAction;
  @override
  void didUpdateWidget(covariant TitleReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (editAction == null &&
        oldWidget.concept['title'] != widget.concept['title']) {
      controller.text = '${widget.concept['title'] ?? ''}';
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> act(
    String action, {
    String? reason,
    Future<bool> Function(String, String?, String?)? snapshot,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final submitting = action == 'submit_title' || action == 'draft_title';
      final ok =
          await (snapshot ??
              (submitting ? editAction : null) ??
              widget.onAction)(
            action,
            action == 'submit_title' || action == 'draft_title'
                ? controller.text.trim()
                : null,
            reason,
          );
      if (ok) editAction = null;
      if (mounted && !ok) {
        setState(
          () => error = 'The action was not saved. Refresh and try again.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.concept['title_review'] as Map? ?? {};
    final state = '${review['state'] ?? 'draft'}';
    final request = review['revision_request'] as Map?;
    final kind = widget.system
        ? 'system'
        : '${widget.concept['system_title'] ?? ''}'.isNotEmpty
        ? 'module'
        : 'concept';
    final secondary = DefensysTokens.textSecondaryOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TitleReviewHeader(
            label: 'Proposed $kind title',
            statusLabel:
                '${review['status_label'] ?? 'Awaiting student submission'}',
            accepted: state == 'accepted',
          ),
          const SizedBox(height: 12),
          if (review['can_edit'] == true && !widget.readOnly)
            ShadInput(
              controller: controller,
              onChanged: (_) => editAction ??= widget.onAction,
              minLines: 1,
              maxLines: 3,
              enabled: !busy,
              placeholder: Text('Enter the proposed $kind title'),
            )
          else
            Text(
              '${widget.concept['title'] ?? ''}'.isEmpty
                  ? 'No proposed title yet'
                  : '${widget.concept['title']}',
              style: DefensysTokens.body.copyWith(
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          if ('${widget.concept['system_title'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Linked to ${widget.concept['system_title']}',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
          if (request != null && state == 'changes_requested') ...[
            const SizedBox(height: 12),
            Text(
              'Revision requested: ${request['feedback']}',
              style: DefensysTokens.body.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            if (request['scope'] == 'title_and_paper')
              const Text('After title acceptance, upload the updated paper.'),
          ],
          if ('${review['blocker'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${review['blocker']}',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
          if ('${review['edit_reason'] ?? ''}'.isNotEmpty &&
              review['can_submit'] == true) ...[
            const SizedBox(height: 8),
            Text(
              '${review['edit_reason']}',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
          if (!widget.readOnly) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (review['can_request_revision'] == true)
                  ShadButton.outline(
                    height: 40,
                    enabled: !busy,
                    onPressed: () async {
                      final snapshot = widget.onAction;
                      final result = await showConceptRevisionDialog(
                        context,
                        titleOnly: true,
                        description: '${widget.concept['title']}',
                      );
                      if (result != null && mounted) {
                        await act(
                          'request_title_revision',
                          reason: result.feedback,
                          snapshot: snapshot,
                        );
                      }
                    },
                    child: const Text('Request title revision'),
                  ),
                if (review['can_submit'] == true) ...[
                  if (review['can_edit'] == true)
                    ShadButton.outline(
                      height: 40,
                      enabled: !busy,
                      onPressed: () => act('draft_title'),
                      child: const Text('Save draft'),
                    ),
                  ShadButton(
                    height: 40,
                    backgroundColor: DefensysTokens.maroonOf(context),
                    foregroundColor: Colors.white,
                    enabled: !busy,
                    onPressed: () => act('submit_title'),
                    child: Text('Submit $kind title'),
                  ),
                ],
                if (review['can_accept'] == true)
                  ShadButton(
                    height: 40,
                    backgroundColor: DefensysTokens.maroonOf(context),
                    foregroundColor: Colors.white,
                    enabled: !busy,
                    onPressed: () => act('accept_title'),
                    child: Text('Accept $kind title'),
                  ),
              ],
            ),
          ],
          if (busy)
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
