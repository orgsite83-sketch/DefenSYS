import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../services/auth_provider.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../models/team_workflow_status.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/universal_file_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'deliverable_file_widgets.dart';
import 'workflow_status_style.dart';

class DocumentGroup extends ConsumerStatefulWidget {
  const DocumentGroup({
    super.key,
    required this.teamId,
    required this.stageLabel,
    required this.item,
    this.programScope,
    this.focused = false,
    this.concepts = const [],
    this.projectContext = false,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic> item;
  final String? programScope;
  final bool focused;
  final bool projectContext;
  final List<Map<String, dynamic>> concepts;
  @override
  ConsumerState<DocumentGroup> createState() => _DocumentGroupState();
}

class _DocumentGroupState extends ConsumerState<DocumentGroup> {
  bool busy = false;
  String? error;
  String? selectedSlot;

  List<Map<String, dynamic>> get focusEntries {
    final item = widget.item;
    final policy = item['file_policy'] as Map? ?? {};
    final files = ((item['submission'] as Map?)?['files'] as List? ?? [])
        .whereType<Map>()
        .where((file) => file['is_current'] != false)
        .map((file) => Map<String, dynamic>.from(file))
        .toList();
    if (policy['mode'] == 'multiple') {
      final minimum = (policy['min_files'] as num? ?? 1).toInt();
      return [
        for (final (index, file) in files.indexed)
          {
            'key': '${file['slot_key'] ?? file['id']}',
            'label': 'Attachment ${index + 1}',
            'file': file,
            'required': index < minimum,
          },
        for (var i = files.length; i < minimum; i++)
          {
            'key': 'missing-$i',
            'label': 'Attachment ${i + 1}',
            'required': true,
          },
      ];
    }
    return [
      for (final slot
          in (item['document_slots'] as List? ?? []).whereType<Map>())
        {
          ...Map<String, dynamic>.from(slot),
          'file': files
              .where((file) => file['slot_key'] == slot['key'])
              .firstOrNull,
        },
    ];
  }

  bool get hasNextFile {
    final entries = focusEntries;
    final index = entries.indexWhere(
      (entry) => '${entry['key']}' == selectedSlot,
    );
    return entries.length > 1 && (index < 0 ? 0 : index) < entries.length - 1;
  }

  void nextFile() {
    final entries = focusEntries;
    final index = entries.indexWhere(
      (entry) => '${entry['key']}' == selectedSlot,
    );
    final next = (index < 0 ? 0 : index) + 1;
    if (mounted && next < entries.length) {
      setState(() => selectedSlot = '${entries[next]['key']}');
    }
  }

  Future<bool> perform(Future<bool> Function() action) async {
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
      return ok;
    } catch (e) {
      if (mounted) setState(() => error = 'Could not complete the action: $e');
      return false;
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
      final slots = (widget.item['document_slots'] as List? ?? [])
          .whereType<Map>();
      final configured = slots
          .where((entry) => entry['key'] == slot)
          .firstOrNull;
      final rawFormat =
          configured?['file_format'] ?? widget.item['file_format'];
      final format = DeliverableFormatInfo.fromFormat(rawFormat?.toString());
      final unrestricted = rawFormat == null || rawFormat == 'any';
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: multiple,
        type: unrestricted ? FileType.any : FileType.custom,
        allowedExtensions: unrestricted ? null : format.extensions,
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

  Future<bool> review(Map<String, dynamic> file, String status) async {
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
      if (saved != true || !mounted) return false;
    }
    return perform(
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
    String? fileFormat,
  }) {
    final item = widget.item;
    final user = ref.watch(authProvider).user ?? {};
    final faculty = user['role'] != 'student';
    final defenseTimed = item['requirement_timing'] == 'defense';
    final canReview = faculty && item['can_faculty_review'] == true;
    final canUpload =
        item['can_upload'] == true &&
        (user['role'] == 'student' ||
            user['role'] == 'admin' ||
            user['is_superuser'] == true);
    final accepted = file?['status'] == 'accepted';
    final rejected =
        file?['status'] == 'rejected' || file?['status'] == 'Needs Revision';
    final status = file == null
        ? (required ? 'Missing' : 'Optional')
        : defenseTimed && !rejected
        ? 'Uploaded'
        : accepted
        ? (item['type'] == 'post' ? 'Archived' : 'Accepted for presentation')
        : rejected
        ? 'Corrections requested'
        : 'Awaiting review';
    final tone = accepted || (defenseTimed && file != null && !rejected)
        ? WorkflowStatusTone.success
        : file == null
        ? WorkflowStatusTone.neutral
        : WorkflowStatusTone.attention;
    final format = DeliverableFormatInfo.fromFormat(
      fileFormat ?? item['file_format']?.toString(),
    );
    if (file == null && canUpload) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DeliverableUploadTile(
          title: label,
          format: format,
          status: status,
          enabled: !busy,
          onUpload: () => upload(slot, null),
        ),
      );
    }
    final submission = item['submission'] as Map? ?? const {};
    final latestFile =
        file != null &&
        ((submission['files'] as List? ?? const []).length == 1 ||
            (file['file_url'] != null &&
                submission['file_url'] == file['file_url'] &&
                submission['file_name'] == file['file_name']));
    final uploader =
        (file?['uploaded_by_name'] ??
                (latestFile ? submission['uploaded_by_name'] : null))
            ?.toString();
    void showDetails() {
      if (file == null) return;
      showDeliverableFileDetails(
        context: context,
        label: label,
        stageLabel: widget.stageLabel,
        programScope:
            widget.programScope ??
            item['program_scope']?.toString() ??
            ref.read(capstoneDeliverablesProvider).scope,
        file: file,
        status: status,
        uploader: uploader,
        onReplace: !busy && canUpload && (!accepted || defenseTimed)
            ? () => upload(slot, file)
            : null,
        onRemove: !busy && canUpload && !accepted
            ? () => perform(
                () => ref
                    .read(capstoneDeliverablesProvider.notifier)
                    .removeDeliverable({
                      'team_id': widget.teamId,
                      'stage_label': widget.stageLabel,
                      'deliverable_id': item['id'],
                      'file_id': file['id'],
                    }),
              )
            : null,
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: widget.focused
          ? const EdgeInsets.symmetric(vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: widget.focused
          ? null
          : BoxDecoration(
              color: DefensysTokens.panelOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: accepted
                    ? Color.alphaBlend(
                        DefensysTokens.success.withValues(alpha: .3),
                        DefensysTokens.borderOf(context),
                      )
                    : DefensysTokens.borderOf(context),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  file == null
                      ? label
                      : "${label.split('·').first.trim()} · Rev ${file['revision'] ?? 1}",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: DeliverableStatusBadge(label: status, tone: tone),
              ),
            ],
          ),
          if (file != null) ...[
            const SizedBox(height: 8),
            DeliverableUploadedFileTile(
              fileName: '${file['file_name']}',
              onDetails: showDetails,
              onRevision: rejected && canUpload
                  ? () => upload(slot, file)
                  : null,
              revisionEnabled: !busy,
            ),
            const SizedBox(height: 8),
            DeliverableUploadAttribution(
              uploader: uploader,
              uploadedAt: file['uploaded_at']?.toString(),
            ),
            if ('${file['feedback'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Feedback: ${file['feedback']}',
                style: TextStyle(
                  fontSize: 11,
                  color: WorkflowStatusStyle.of(
                    context,
                    WorkflowStatusTone.attention,
                  ).foreground,
                ),
              ),
            ],
            if (canReview &&
                (defenseTimed || !(item['type'] == 'post' && accepted))) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!accepted && !defenseTimed)
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        enabled: !busy,
                        onPressed: () async {
                          final saved = await review(file, 'accepted');
                          if (saved && widget.focused) nextFile();
                        },
                        child: Text(
                          widget.focused && hasNextFile
                              ? 'Accept & next'
                              : 'Accept',
                        ),
                      ),
                    ShadButton.ghost(
                      size: ShadButtonSize.sm,
                      enabled: !busy,
                      onPressed: () => review(file, 'rejected'),
                      child: const Text('Request corrections'),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'Awaiting team upload',
              style: TextStyle(
                fontSize: 11,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget focusedDocuments() {
    final entries = focusEntries;
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No file slots are configured for this requirement.'),
      );
    }
    var index = entries.indexWhere(
      (entry) => '${entry['key']}' == selectedSlot,
    );
    if (index < 0) index = 0;
    final selected = entries[index];
    final conceptKey = '${selected['key']}'.split(':').first;
    final concept = widget.concepts
        .where((concept) => concept['key'] == conceptKey)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: IntrinsicWidth(
            child: ShadTabs<String>(
              scrollable: true,
              value: '${selected['key']}',
              tabBarAlignment: Alignment.centerLeft,
              gap: 0,
              onChanged: busy
                  ? null
                  : (key) => setState(() => selectedSlot = key),
              tabs: [
                for (final entry in entries)
                  ShadTab(
                    value: '${entry['key']}',
                    child: Text(
                      widget.projectContext
                          ? '${entry['label']}'.split('·').first.trim()
                          : '${entry['label']}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        if ('${concept?['title'] ?? ''}'.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${concept!['title']}',
              style: DefensysTokens.body.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ),
        if ('${concept?['system_title'] ?? ''}'.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Linked to ${concept!['system_title']}',
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
        documentRow(
          '${selected['label']}',
          '${selected['key']}',
          selected['file'] as Map<String, dynamic>?,
          required: selected['required'] != false,
          fileFormat: selected['file_format']?.toString(),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'File ${index + 1} of ${entries.length}',
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  enabled: !busy && index > 0,
                  onPressed: busy || index == 0
                      ? null
                      : () => setState(
                          () => selectedSlot = '${entries[index - 1]['key']}',
                        ),
                  child: const Text('Previous'),
                ),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  enabled: !busy && index + 1 < entries.length,
                  onPressed: busy || index + 1 >= entries.length
                      ? null
                      : nextFile,
                  child: const Text('Next file'),
                ),
              ],
            ),
          ],
        ),
      ],
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
        .where((file) => file['is_current'] != false)
        .map((f) => Map<String, dynamic>.from(f))
        .toList();
    final history = (submission['file_history'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final slots = (item['document_slots'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final multiple = policy['mode'] == 'multiple';
    final requiredSlots = slots.where((s) => s['required'] != false).toList();
    final minimum = multiple
        ? (policy['min_files'] as num? ?? 1).toInt()
        : requiredSlots.length;
    final user = ref.watch(authProvider).user ?? {};
    final presentSlots = files.map((file) => file['slot_key']).toSet();
    final uploadedCount = multiple
        ? files.length
        : requiredSlots
              .where((slot) => presentSlots.contains(slot['key']))
              .length;
    final allUploaded = multiple
        ? files.length >= minimum
        : requiredSlots.every((slot) => presentSlots.contains(slot['key']));

    final allAccepted =
        files.isNotEmpty &&
        allUploaded &&
        files.every((f) => f['status'] == 'accepted');
    final anyRejected = files.any(
      (f) => f['status'] == 'rejected' || f['status'] == 'Needs Revision',
    );
    final missingCount = minimum > uploadedCount ? minimum - uploadedCount : 0;
    final pendingReview = files.any(
      (file) =>
          file['status'] != 'accepted' &&
          file['status'] != 'rejected' &&
          file['status'] != 'Needs Revision',
    );
    final defenseUploaded =
        item['requirement_timing'] == 'defense' &&
        files.isNotEmpty &&
        allUploaded &&
        !anyRejected;
    final groupStatus = allAccepted
        ? (item['type'] == 'post' ? 'Archived' : 'Accepted')
        : missingCount > 0
        ? '$uploadedCount/$minimum Uploaded'
        : anyRejected
        ? 'Corrections requested'
        : defenseUploaded
        ? 'Uploaded'
        : pendingReview
        ? 'Under Review'
        : 'Optional';
    final groupTone = allAccepted || defenseUploaded
        ? WorkflowStatusTone.success
        : missingCount > 0
        ? WorkflowStatusTone.neutral
        : anyRejected
        ? WorkflowStatusTone.attention
        : pendingReview
        ? WorkflowStatusTone.attention
        : WorkflowStatusTone.neutral;
    final progress = minimum == 0
        ? '${files.length} optional files uploaded'
        : multiple && uploadedCount > minimum
        ? '$uploadedCount uploaded · $minimum required'
        : missingCount > 0
        ? '$minimum required files'
        : '$uploadedCount/$minimum uploaded';

    final Color cardBorderColor = allAccepted
        ? Color.alphaBlend(
            DefensysTokens.success.withValues(alpha: .3),
            DefensysTokens.borderOf(context),
          )
        : DefensysTokens.borderOf(context);

    return DefensysShadcnScope(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: widget.focused ? EdgeInsets.zero : const EdgeInsets.all(14),
        decoration: widget.focused
            ? null
            : BoxDecoration(
                color: DefensysTokens.surfaceOf(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.025),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.projectContext) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item['label']}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: DeliverableStatusBadge(
                      label: groupStatus,
                      tone: groupTone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                progress,
                style: TextStyle(
                  fontSize: 11.5,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
            if (multiple)
              Text(
                'Up to ${policy['max_files'] ?? 10} attachments',
                style: TextStyle(
                  fontSize: 11,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
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
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            if (widget.focused)
              focusedDocuments()
            else if (multiple) ...[
              for (final (index, file) in files.indexed)
                documentRow(
                  'Attachment ${index + 1}',
                  '${file['slot_key']}',
                  file,
                ),
              if (item['can_upload'] == true &&
                  (user['role'] == 'student' ||
                      user['role'] == 'admin' ||
                      user['is_superuser'] == true) &&
                  files.length < (policy['max_files'] as int? ?? 10)) ...[
                const SizedBox(height: 8),
                DeliverableUploadTile(
                  title: 'Add attachments',
                  format: DeliverableFormatInfo.fromFormat(
                    item['file_format']?.toString(),
                  ),
                  enabled: !busy,
                  onUpload: () => upload('', null, multiple: true),
                ),
              ],
            ] else
              for (final slot in slots) ...[
                documentRow(
                  '${slot['label']}',
                  '${slot['key']}',
                  files.where((f) => f['slot_key'] == slot['key']).firstOrNull,
                  required: slot['required'] != false,
                  fileFormat: slot['file_format']?.toString(),
                ),
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
    );
  }
}
