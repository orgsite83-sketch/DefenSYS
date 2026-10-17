import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../services/auth_provider.dart';
import '../../models/team_workflow_status.dart';
import 'workflow_status_style.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../utils/universal_file_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';

class DocumentGroup extends ConsumerStatefulWidget {
  const DocumentGroup({
    super.key,
    required this.teamId,
    required this.stageLabel,
    required this.item,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic> item;
  @override
  ConsumerState<DocumentGroup> createState() => _DocumentGroupState();
}

class _DocumentGroupState extends ConsumerState<DocumentGroup> {
  bool busy = false;
  String? error;
  Future<void> perform(Future<bool> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ok = await action();
      if (mounted && !ok) {
        setState(
          () => error =
              ref.read(capstoneDeliverablesProvider).error ??
              'The action could not be saved.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not complete the action: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload(
    String slot,
    Map<String, dynamic>? file, {
    bool multiple = false,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: multiple,
      );
      if (result == null || !mounted) return;
      final selected = result.files;
      if (multiple) {
        final policy = widget.item['file_policy'] as Map? ?? {};
        final submission = widget.item['submission'] as Map? ?? {};
        final count = (submission['files'] as List? ?? []).length;
        if (count + selected.length > (policy['max_files'] as int? ?? 10)) {
          setState(
            () => error =
                'Choose fewer files. This deliverable allows up to ${policy['max_files'] ?? 10} attachments.',
          );
          return;
        }
      }
      await perform(() async {
        for (final selectedFile in selected) {
          final bytes = selectedFile.bytes;
          if (bytes == null || bytes.isEmpty) {
            throw StateError('The selected file is empty or unreadable.');
          }
          final ok = await ref
              .read(capstoneDeliverablesProvider.notifier)
              .uploadDocument(
                teamId: widget.teamId,
                stageLabel: widget.stageLabel,
                deliverableId: '${widget.item['id']}',
                slotKey: slot,
                filename: selectedFile.name,
                bytes: bytes,
                fileId: file?['id'] as int?,
              );
          if (!ok) return false;
        }
        return true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Could not read the selected file: $e');
      }
    }
  }

  Future<void> review(Map<String, dynamic> file, String status) async {
    var feedback = '';
    if (status == 'rejected') {
      final controller = TextEditingController();
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => DefensysShadcnScope(
          child: ShadDialog(
            title: const Text('Request document corrections'),
            description: Text('${file['file_name']}'),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ShadButton(
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Request corrections'),
              ),
            ],
            child: ShadInput(
              controller: controller,
              minLines: 3,
              maxLines: 6,
              placeholder: const Text(
                'Explain the changes needed before presentation.',
              ),
            ),
          ),
        ),
      );
      feedback = controller.text.trim();
      controller.dispose();
      if (saved != true || !mounted) return;
    }
    await perform(
      () => ref
          .read(capstoneDeliverablesProvider.notifier)
          .reviewDeliverable(
            teamId: widget.teamId,
            stageLabel: widget.stageLabel,
            deliverableId: '${widget.item['id']}',
            status: status,
            feedback: feedback,
            fileId: file['id'] as int,
          ),
    );
  }

  Widget documentRow(
    String label,
    String slot,
    Map<String, dynamic>? file, {
    bool required = true,
  }) {
    final item = widget.item;
    final user = ref.watch(authProvider).user ?? {};
    final faculty = user['role'] != 'student';
    final defenseTimed = item['requirement_timing'] == 'defense';
    final canReview = faculty && item['can_faculty_review'] == true;
    final canUpload = item['can_upload'] == true;
    final accepted = file?['status'] == 'accepted';
    final status = file == null
        ? (required ? 'Missing' : 'Optional')
        : defenseTimed && file['status'] != 'rejected'
        ? 'Uploaded'
        : switch (file['status']) {
            'accepted' =>
              item['type'] == 'post' ? 'Accepted' : 'Accepted for presentation',
            'rejected' => 'Corrections requested',
            _ => 'Awaiting review',
          };
    final fileStyle = WorkflowStatusStyle.of(
      context,
      file == null
          ? WorkflowStatusTone.neutral
          : file['status'] == 'rejected'
          ? WorkflowStatusTone.attention
          : accepted || defenseTimed
          ? WorkflowStatusTone.success
          : WorkflowStatusTone.active,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(LucideIcons.fileText, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      file == null
                          ? status
                          : '${file['file_name']} · Revision ${file['revision'] ?? 1}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (file != null)
                Flexible(
                  child: ShadBadge.outline(
                    backgroundColor: fileStyle.background,
                    foregroundColor: fileStyle.foreground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(color: fileStyle.border),
                    ),
                    child: Text(status),
                  ),
                ),
            ],
          ),
          if ('${file?['feedback'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${file!['feedback']}'),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (file?['file_url'] != null)
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  child: const Text('View'),
                  onPressed: () => viewFileInDialog(
                    context: context,
                    fileUrl: '${file!['file_url']}',
                    fileName: '${file['file_name']}',
                  ),
                ),
              if (canUpload && (!accepted || defenseTimed))
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  enabled: !busy,
                  child: Text(
                    file == null ? 'Upload document' : 'Upload revision',
                  ),
                  onPressed: () => upload(slot, file),
                ),
              if (canUpload && file != null && !accepted)
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  enabled: !busy,
                  onPressed: () => perform(
                    () => ref
                        .read(capstoneDeliverablesProvider.notifier)
                        .removeDeliverable({
                          'team_id': widget.teamId,
                          'stage_label': widget.stageLabel,
                          'deliverable_id': widget.item['id'],
                          'file_id': file['id'],
                        }),
                  ),
                  child: const Text('Remove'),
                ),
              if (canReview &&
                  file != null &&
                  !defenseTimed &&
                  !(item['type'] == 'post' && accepted)) ...[
                if (!accepted)
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    enabled: !busy,
                    child: const Text('Accept'),
                    onPressed: () => review(file, 'accepted'),
                  ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  enabled: !busy,
                  child: const Text('Request corrections'),
                  onPressed: () => review(file, 'rejected'),
                ),
              ],
              if (canReview && file != null && defenseTimed)
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  enabled: !busy,
                  child: const Text('Request corrections'),
                  onPressed: () => review(file, 'rejected'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final policy = Map<String, dynamic>.from(item['file_policy'] as Map? ?? {});
    final submission = Map<String, dynamic>.from(
      item['submission'] as Map? ?? {},
    );
    final files = (submission['files'] as List? ?? [])
        .whereType<Map>()
        .map((f) => Map<String, dynamic>.from(f))
        .toList();
    final history = (submission['file_history'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final slots = (item['document_slots'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final multiple = policy['mode'] == 'multiple';
    final minimum = multiple
        ? (policy['min_files'] ?? 1)
        : slots.where((s) => s['required'] != false).length;
    final user = ref.watch(authProvider).user ?? {};
    return DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ShadCard(
          width: double.infinity,
          title: Text('${item['label']}'),
          description: Text(
            '${files.length} uploaded · $minimum required${multiple ? ' · up to ${policy['max_files'] ?? 10}' : ''}',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (multiple) ...[
                for (final file in files)
                  documentRow(
                    '${file['file_name']}',
                    '${file['slot_key']}',
                    file,
                  ),
                if (item['can_upload'] == true &&
                    (user['role'] == 'student' ||
                        user['role'] == 'admin' ||
                        user['is_superuser'] == true) &&
                    files.length < (policy['max_files'] as int? ?? 10))
                  ShadButton.outline(
                    enabled: !busy,
                    child: const Text('Add attachments'),
                    onPressed: () => upload('', null, multiple: true),
                  ),
              ] else
                for (final slot in slots) ...[
                  documentRow(
                    '${slot['label']}',
                    '${slot['key']}',
                    files
                        .where((f) => f['slot_key'] == slot['key'])
                        .firstOrNull,
                    required: slot['required'] != false,
                  ),
                  if (slot != slots.last) const Divider(height: 1),
                ],
              if (history.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Earlier file revisions (${history.length})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  children: [
                    for (final file in history)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${file['file_name']}'),
                        subtitle: Text(
                          'Revision ${file['revision']} · Previous upload',
                        ),
                        trailing: ShadButton.ghost(
                          size: ShadButtonSize.sm,
                          onPressed: file['file_url'] == null
                              ? null
                              : () => viewFileInDialog(
                                  context: context,
                                  fileUrl: '${file['file_url']}',
                                  fileName: '${file['file_name']}',
                                ),
                          child: const Text('View'),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
