import 'team_workflow_status.dart';

/// A single lifecycle status; scheduling alone never starts a hearing.
class DefenseSummaryStatus {
  const DefenseSummaryStatus(this.label, this.tone);
  final String label;
  final WorkflowStatusTone tone;

  static DefenseSummaryStatus resolve({
    String? verdict,
    String? progress,
    bool scheduled = false,
    bool presenting = false,
    bool concept = false,
    Map? titleReview,
    bool titleAccepted = false,
  }) {
    if (verdict == 'approved') {
      return DefenseSummaryStatus(
        concept ? 'Concept approved' : 'Approved',
        WorkflowStatusTone.success,
      );
    }
    if (verdict == 'approved_with_revisions') {
      return const DefenseSummaryStatus(
        'Approved with revisions',
        WorkflowStatusTone.attention,
      );
    }
    if (verdict == 'for_redefense') {
      return const DefenseSummaryStatus(
        'Re-defense required',
        WorkflowStatusTone.attention,
      );
    }
    if (verdict == 'failed' || verdict == 'project_rejected') {
      return const DefenseSummaryStatus(
        'Not approved',
        WorkflowStatusTone.destructive,
      );
    }
    if (const {
      'cancelled',
      'postponed',
      'paused',
      'no_show',
      'archived',
    }.contains(progress)) {
      return DefenseSummaryStatus(switch (progress) {
        'cancelled' => 'Hearing cancelled',
        'postponed' => 'Hearing postponed',
        'paused' => 'Hearing interrupted',
        'no_show' => 'Not attended',
        _ => 'Archived',
      }, WorkflowStatusTone.neutral);
    }
    if (const {
      'awaiting_verdict',
      'awaiting_concept_selection',
      'assessed',
      'done',
    }.contains(progress)) {
      return const DefenseSummaryStatus(
        'Awaiting decision',
        WorkflowStatusTone.neutral,
      );
    }
    if (presenting || progress == 'evaluating' || progress == 'ongoing') {
      return const DefenseSummaryStatus(
        'Hearing in progress',
        WorkflowStatusTone.neutral,
      );
    }
    if (scheduled ||
        progress == 'scheduled' ||
        progress == 'awaiting_evaluation') {
      return const DefenseSummaryStatus(
        'Hearing scheduled',
        WorkflowStatusTone.neutral,
      );
    }
    if (progress == 'completed') {
      return const DefenseSummaryStatus(
        'Stage completed',
        WorkflowStatusTone.success,
      );
    }
    if (progress == 'failed' || progress == 'project_rejected') {
      return const DefenseSummaryStatus(
        'Not approved',
        WorkflowStatusTone.destructive,
      );
    }
    if (progress != null && progress.isNotEmpty) {
      return const DefenseSummaryStatus(
        'Awaiting completion',
        WorkflowStatusTone.neutral,
      );
    }
    if (titleReview?['state'] == 'accepted' ||
        ((titleReview == null || titleReview.isEmpty) && titleAccepted)) {
      return const DefenseSummaryStatus(
        'Title accepted',
        WorkflowStatusTone.success,
      );
    }
    if (titleReview?['state'] == 'changes_requested') {
      return const DefenseSummaryStatus(
        'Title changes requested',
        WorkflowStatusTone.attention,
      );
    }
    if (titleReview?['state'] == 'submitted') {
      return const DefenseSummaryStatus(
        'Title submitted',
        WorkflowStatusTone.neutral,
      );
    }
    return const DefenseSummaryStatus(
      'Title pending',
      WorkflowStatusTone.neutral,
    );
  }
}
