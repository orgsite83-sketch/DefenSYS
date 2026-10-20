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

/// `concepts` means a file is required per proposal; it also applies to decks.
/// The canonical paper slot is `paper` (including the server's default policy).
bool isConceptRequirement(Map item) {
  final policy = item['file_policy'] as Map? ?? {};
  if (policy['mode'] != 'concepts') return false;
  // Older per-concept decks also inherit the server's default `paper` key.
  // Preserve those definitions, but do not present them as project papers.
  final label = '${item['label'] ?? item['name'] ?? ''}'.toLowerCase();
  if (!label.contains('paper') &&
      RegExp(r'\b(deck|slides|presentation)\b').hasMatch(label)) {
    return false;
  }
  bool documentFormat(dynamic format) => const [
    '',
    'any',
    'pdf',
    'doc',
    'docx',
  ].contains('${format ?? ''}'.toLowerCase());
  final slots = (policy['slots'] as List? ?? []).whereType<Map>();
  return slots.isEmpty
      ? documentFormat(item['file_format'])
      : slots.any(
          (slot) =>
              slot['key'] == 'paper' &&
              documentFormat(slot['file_format'] ?? item['file_format']),
        );
}

/// Project context shows only paper slots, while By team keeps every file.
Map<String, dynamic> conceptPaperRequirement(Map<String, dynamic> item) {
  final slots = (item['document_slots'] as List? ?? [])
      .whereType<Map>()
      .where((slot) => '${slot['key']}'.split(':').last == 'paper')
      .toList();
  final keys = slots.map((slot) => slot['key']).toSet();
  final submission = item['submission'] as Map? ?? {};
  return {
    ...item,
    'document_slots': slots,
    'submission': {
      ...submission,
      'files': (submission['files'] as List? ?? [])
          .whereType<Map>()
          .where((file) => keys.contains(file['slot_key']))
          .toList(),
      'file_history': (submission['file_history'] as List? ?? [])
          .whereType<Map>()
          .where((file) => keys.contains(file['slot_key']))
          .toList(),
    },
  };
}
