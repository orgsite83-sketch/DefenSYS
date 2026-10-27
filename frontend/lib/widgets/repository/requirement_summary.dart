import '../../models/team_workflow_status.dart';
import 'deliverable_file_widgets.dart';

/// Read-only presentation of the current files; never changes workflow readiness.
class RequirementSummary {
  RequirementSummary(Map<String, dynamic> item) {
    final policy = item['file_policy'] as Map? ?? {};
    final submission = item['submission'] as Map? ?? {};
    final files = (submission['files'] as List? ?? [])
        .whereType<Map>()
        .where((file) => file['is_current'] != false)
        .toList();
    final slots = (item['document_slots'] as List? ?? [])
        .whereType<Map>()
        .where((slot) => slot['required'] != false)
        .toList();
    final grouped = usesGroupedDocumentCard(item);
    final multiple = policy['mode'] == 'multiple';
    required = multiple
        ? (policy['min_files'] as num? ?? 1).toInt()
        : grouped
        ? slots.map((slot) => slot['key']).toSet().length
        : item['required'] == false
        ? 0
        : 1;
    uploaded = multiple
        ? files.length
        : grouped
        ? slots
              .map((slot) => slot['key'])
              .toSet()
              .where((key) => files.any((file) => file['slot_key'] == key))
              .length
        : hasSubmittedDeliverable(item)
        ? 1
        : 0;
    acceptedFiles = grouped
        ? multiple
              ? files.where((file) => file['status'] == 'accepted').length
              : slots
                    .map((slot) => slot['key'])
                    .toSet()
                    .where(
                      (key) => files.any(
                        (file) =>
                            file['slot_key'] == key &&
                            file['status'] == 'accepted',
                      ),
                    )
                    .length
        : uploaded > 0 && submission['status'] == 'accepted'
        ? 1
        : 0;
    fileCount = grouped ? files.length : uploaded;
    missing = (required - uploaded).clamp(0, required);
    pending = fileCount == 0
        ? 0
        : TeamWorkflowStatus.pendingFileReviewCount(item);
    corrections = files.isNotEmpty
        ? files.where((file) => _rejected(file['status'])).length
        : !grouped &&
              hasSubmittedDeliverable(item) &&
              _rejected(submission['status'])
        ? 1
        : 0;
    final accepted = files.isNotEmpty
        ? files.every((file) => file['status'] == 'accepted')
        : !grouped && uploaded > 0 && submission['status'] == 'accepted';
    final post = item['type'] == 'post' || item['deliverable_type'] == 'post';
    final defense = !post && item['requirement_timing'] == 'defense';
    if (item['is_waived'] == true) {
      status = 'Waived';
      tone = WorkflowStatusTone.neutral;
      pending = 0;
      missing = 0;
      corrections = 0;
    } else if (missing > 0) {
      status = '$uploaded/$required Uploaded';
      tone = WorkflowStatusTone.neutral;
    } else if (accepted && (required > 0 || fileCount > 0)) {
      status = post ? 'Archived' : 'Accepted';
      tone = WorkflowStatusTone.success;
    } else if (corrections > 0) {
      status = 'Corrections requested';
      tone = WorkflowStatusTone.attention;
    } else if (defense && fileCount > 0) {
      status = 'Uploaded';
      tone = WorkflowStatusTone.success;
    } else if (pending > 0) {
      status = 'Under Review';
      tone = WorkflowStatusTone.attention;
    } else {
      status = required == 0 ? 'Optional' : 'Awaiting upload';
      tone = WorkflowStatusTone.neutral;
    }
  }

  late final int required;
  late final int uploaded;
  late final int acceptedFiles;
  late final int fileCount;
  late int missing;
  late int pending;
  late int corrections;
  late final String status;
  late final WorkflowStatusTone tone;

  bool get needsAttention => missing > 0 || pending > 0 || corrections > 0;
  String get progress => required == 0
      ? '$fileCount optional'
      : uploaded > required
      ? '$uploaded uploaded · $required required'
      : '$uploaded/$required';
  String get detail => [
    if (pending > 0) '$pending awaiting review',
    if (corrections > 0) '$corrections corrections requested',
    if (missing > 0) '$missing missing',
  ].join(' · ');

  static bool _rejected(dynamic status) =>
      status == 'rejected' ||
      status == 'Needs Revision' ||
      status == 'needs_revision';
}

/// Review membership follows configuration, never labels or extensions.
/// Defense-timed materials retain their upload/correction workflow in By team.
bool isConceptRequirement(Map item) {
  final policy = item['file_policy'] as Map? ?? {};
  return policy['mode'] == 'concepts' &&
      item['requirement_timing'] != 'defense' &&
      item['type'] != 'post' &&
      item['deliverable_type'] != 'post';
}

/// All configured slots for one proposal, including briefs/decks and history.
Map<String, dynamic> conceptRequirementForKey(
  Map<String, dynamic> item,
  String key,
) {
  final submission = item['submission'] as Map? ?? {};
  bool belongs(dynamic value) => '$value'.startsWith('$key:');
  return {
    ...item,
    'document_slots': (item['document_slots'] as List? ?? [])
        .whereType<Map>()
        .where((slot) => belongs(slot['key']))
        .map(
          (slot) => <String, dynamic>{
            ...slot,
            'label': '${slot['label']}'.split('·').last.trim(),
          },
        )
        .toList(),
    'submission': {
      ...submission,
      'files': (submission['files'] as List? ?? [])
          .whereType<Map>()
          .where((f) => belongs(f['slot_key']))
          .toList(),
      'file_history': (submission['file_history'] as List? ?? [])
          .whereType<Map>()
          .where((f) => belongs(f['slot_key']))
          .toList(),
    },
  };
}
