import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/team_workflow_status.dart';
import '../../services/academic/section_concept_service.dart';
import '../../services/app/data_refresh_provider.dart';
import '../../services/network/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/universal_file_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'deliverable_file_widgets.dart';
import 'concept_revision_dialog.dart';
import 'concept_review_section.dart';
import 'shared_concept_review.dart';

List<Map<String, dynamic>> _sharedRows(dynamic value) => (value as List? ?? [])
    .whereType<Map>()
    .map((row) => Map<String, dynamic>.from(row))
    .toList();

/// The same document-first requirement card used in student deliverables.
/// Per-concept slots live under their system; section-wide documents occur once.
class SharedDeliverablesPanel extends ConsumerStatefulWidget {
  const SharedDeliverablesPanel({
    super.key,
    required this.group,
    this.onChanged,
    this.selectedSystemKey,
    this.onSystemChanged,
    this.systemHeaderBuilder,
    this.onReviewFiles,
    this.readOnly = false,
    this.normalFlow = false,
  });
  final Map<String, dynamic> group;
  final bool readOnly;
  final bool normalFlow;
  final ValueChanged<Map<String, dynamic>>? onChanged;
  final String? selectedSystemKey;
  final ValueChanged<String>? onSystemChanged;
  final Widget Function(Map<String, dynamic> system)? systemHeaderBuilder;
  final ValueChanged<String>? onReviewFiles;
  @override
  ConsumerState<SharedDeliverablesPanel> createState() =>
      _SharedDeliverablesPanelState();
}

class _SharedDeliverablesPanelState
    extends ConsumerState<SharedDeliverablesPanel> {
  late Map<String, dynamic> group;
  String? systemKey;
  String? error;
  bool busy = false;
  bool showHistory = false;
  @override
  void initState() {
    super.initState();
    group = widget.group;
  }

  @override
  void didUpdateWidget(covariant SharedDeliverablesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.group, widget.group)) {
      if (oldWidget.group['identity'] != widget.group['identity'] ||
          oldWidget.group['selected_key'] != widget.group['selected_key']) {
        showHistory = false;
        systemKey = null;
      }
      group = widget.group;
      error = null;
    }
  }

  void changed(Map<String, dynamic> response) {
    final value = Map<String, dynamic>.from(
      response['shared_deliverables'] as Map,
    );
    setState(() {
      group = value;
      error = null;
    });
    widget.onChanged?.call(value);
    ref.read(dataRefreshProvider.notifier).markChanged(const [
      DataArea.dashboard,
      DataArea.teams,
      DataArea.deliverables,
      DataArea.grades,
      DataArea.repository,
    ]);
  }

  Future<void> upload(
    Map<String, dynamic> requirement,
    Map<String, dynamic> document,
  ) async {
    final format =
        '${document['file_format'] ?? requirement['file_format'] ?? 'any'}';
    final info = DeliverableFormatInfo.fromFormat(format);
    final anyFile = format == 'any' || info.extensions.isEmpty;
    final picked = await FilePicker.platform.pickFiles(
      type: anyFile ? FileType.any : FileType.custom,
      allowedExtensions: anyFile ? null : info.extensions,
      withData: true,
    );
    if (picked == null || !mounted) return;
    final file = picked.files.single;
    final limit =
        (document['max_file_size'] ??
                requirement['max_file_size'] ??
                50 * 1024 * 1024)
            as int;
    if (file.bytes == null || file.size == 0 || file.size > limit) {
      setState(
        () => error =
            'Choose a readable file of up to ${limit ~/ (1024 * 1024)} MB.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final suggested =
          '${document['suggested_file_name'] ?? requirement['suggested_file_name'] ?? ''}';
      final repositoryName =
          requirement['deliverable_type'] == 'post' && suggested.isNotEmpty
          ? info.extensions.isEmpty && !file.name.contains('.')
                ? suggested
                : info.recommendedFileName(
                    suggested,
                    selectedFileName: file.name,
                  )
          : file.name;
      final response = await ref
          .read(sectionConceptServiceProvider)
          .uploadShared(
            group,
            '${requirement['deliverable_id']}',
            '${document['key'] ?? ''}',
            repositoryName,
            file.bytes!,
          );
      if (mounted) changed(response);
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> view(Map<String, dynamic> file) async {
    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile('${file['file_url']}');
      if (mounted) {
        await viewFileInDialog(
          context: context,
          fileBytes: bytes,
          fileName: '${file['file_name']}',
        );
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  Future<void> review(
    Map<String, dynamic> requirement,
    Map<String, dynamic> document,
    String status,
  ) async {
    final snapshot = Map<String, dynamic>.from(group);
    final result = status == 'rejected'
        ? await showConceptRevisionDialog(
            context,
            description:
                '${(document['file'] as Map)['file_name']} · Revision ${(document['file'] as Map)['revision']}',
            titleAvailable: document['title_revision_available'] == true,
          )
        : const ConceptRevision('paper', '');
    if (result == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await ref
          .read(sectionConceptServiceProvider)
          .reviewShared(
            snapshot,
            '${requirement['deliverable_id']}',
            '${document['key']}',
            {
              ...Map<String, dynamic>.from(document['file'] as Map),
              'revision_scope': result.scope,
            },
            status,
            result.feedback,
          );
      if (mounted) changed(response);
    } catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget requirementCard(Map<String, dynamic> requirement, {String? key}) {
    final documents = _sharedRows(
      requirement['documents'],
    ).where((row) => key == null || row['system_key'] == key).toList();
    final mode = (requirement['file_policy'] as Map?)?['mode'] ?? 'single';
    final history = _sharedRows(requirement['history'])
        .where(
          (file) => key == null || '${file['slot_key']}'.startsWith('$key:'),
        )
        .toList();
    if (mode == 'concepts' && documents.isEmpty) return const SizedBox.shrink();
    final relevantFiles = documents
        .where((row) => row['file'] is Map)
        .map((row) => row['file'] as Map)
        .toList();
    final accepted =
        documents.isNotEmpty &&
        documents
            .where((row) => row['required'] != false)
            .every((row) => (row['file'] as Map?)?['status'] == 'accepted');
    final rejected = relevantFiles.any((file) => file['status'] == 'rejected');
    final status = (key == null
        ? requirement['status']
        : accepted
        ? 'accepted'
        : rejected
        ? 'rejected'
        : relevantFiles.isNotEmpty
        ? 'pending'
        : 'missing');
    final post = requirement['deliverable_type'] == 'post';
    final label = status == 'accepted'
        ? post
              ? 'Accepted & archived'
              : 'Accepted'
        : status == 'rejected'
        ? 'Corrections requested'
        : status == 'pending'
        ? 'Pending review'
        : requirement['required'] == true
        ? 'Action Required'
        : 'Optional';
    final tone = status == 'accepted'
        ? WorkflowStatusTone.success
        : status == 'rejected' || label == 'Action Required'
        ? WorkflowStatusTone.destructive
        : WorkflowStatusTone.neutral;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${requirement['label']}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: DeliverableStatusBadge(label: label, tone: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            requirement['required'] == true
                ? post
                      ? 'Required after defense'
                      : 'Mandatory for oral defense'
                : 'Optional shared document',
            style: TextStyle(
              fontSize: 11.5,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          for (final document in documents) ...[
            if (post &&
                '${document['suggested_file_name'] ?? requirement['suggested_file_name'] ?? ''}'
                    .isNotEmpty)
              _archiveNameSuggestion(
                '${document['suggested_file_name'] ?? requirement['suggested_file_name']}',
                archived: (document['file'] as Map?)?['status'] == 'accepted',
              ),
            if (document['file'] is Map) ...[
              DeliverableUploadedFileTile(
                fileName: '${(document['file'] as Map)['file_name']}',
                onDetails: () =>
                    view(Map<String, dynamic>.from(document['file'] as Map)),
                onRevision:
                    !widget.readOnly &&
                        document['can_upload'] == true &&
                        !(post &&
                            (document['file'] as Map)['status'] == 'accepted')
                    ? () => upload(requirement, document)
                    : null,
                revisionEnabled: !busy,
              ),
              Text(
                'Revision ${(document['file'] as Map)['revision']} · ${post && (document['file'] as Map)['status'] == 'accepted' ? 'Archived' : (document['file'] as Map)['status']}',
                style: TextStyle(
                  fontSize: 11,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              if ('${(document['file'] as Map)['feedback'] ?? ''}'.isNotEmpty)
                Text(
                  '${(document['file'] as Map)['feedback']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              if ('${document['title_blocker'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${document['title_blocker']}'),
                ),
              if (!widget.readOnly &&
                  document['can_review'] == true &&
                  !(post && (document['file'] as Map)['status'] == 'accepted'))
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShadButton.outline(
                      height: 40,
                      enabled: !busy,
                      onPressed: () =>
                          review(requirement, document, 'rejected'),
                      child: const Text('Request revision'),
                    ),
                    if ((document['file'] as Map)['status'] != 'accepted')
                      ShadButton(
                        height: 40,
                        backgroundColor: DefensysTokens.maroonOf(context),
                        foregroundColor: Colors.white,
                        enabled:
                            !busy &&
                            '${document['title_blocker'] ?? ''}'.isEmpty,
                        onPressed: () =>
                            review(requirement, document, 'accepted'),
                        child: const Text('Accept file'),
                      ),
                  ],
                ),
            ] else
              DeliverableUploadTile(
                title: 'Upload ${document['label']}',
                format: DeliverableFormatInfo.fromFormat(
                  '${document['file_format'] ?? requirement['file_format']}',
                ),
                maxFileSizeMb:
                    ((document['max_file_size'] as int? ?? 50 * 1024 * 1024) ~/
                    (1024 * 1024)),
                enabled:
                    !widget.readOnly && !busy && document['can_upload'] == true,
                onUpload: () => upload(requirement, document),
              ),
            const SizedBox(height: 8),
          ],
          if (post &&
              mode == 'multiple' &&
              documents.isEmpty &&
              '${requirement['suggested_file_name'] ?? ''}'.isNotEmpty)
            _archiveNameSuggestion('${requirement['suggested_file_name']}'),
          if (mode == 'multiple' &&
              !widget.readOnly &&
              !(post && status == 'accepted'))
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: !busy && requirement['can_add_attachment'] == true
                    ? () => upload(requirement, {
                        'key': '',
                        'file_format': requirement['file_format'],
                        'max_file_size': requirement['max_file_size'],
                      })
                    : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add attachment'),
              ),
            ),
          if (relevantFiles.isEmpty)
            Text(
              'Awaiting PM upload',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          if ('${requirement['unavailable_reason'] ?? ''}'.isNotEmpty)
            Text(
              '${requirement['unavailable_reason']}',
              style: TextStyle(
                fontSize: 11,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          if (history.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Previous versions',
                style: TextStyle(fontSize: 12),
              ),
              children: [
                for (final file in history)
                  ListTile(
                    dense: true,
                    title: Text('${file['file_name']}'),
                    subtitle: Text(
                      'Revision ${file['revision']} · ${file['status']}',
                    ),
                    onTap: () => view(file),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _archiveNameSuggestion(String name, {bool archived = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Suggested archive filename',
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                width: 30,
                height: 30,
                padding: EdgeInsets.zero,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: name));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Archive filename copied.')),
                    );
                  }
                },
                child: const Tooltip(
                  message: 'Copy archive filename',
                  child: Icon(Icons.copy_outlined, size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            archived
                ? 'Archive naming reference. This file is accepted and read-only.'
                : 'Used for new uploads and revisions. Your local file keeps its name.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _normalFlow() {
    final systems = _sharedRows(group['systems']);
    final system =
        systems
            .where((row) => row['key'] == group['selected_key'])
            .firstOrNull ??
        (systems.length == 1 ? systems.single : null);
    final requirements = _sharedRows(group['requirements']);
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${system?['title'] ?? ''}'.trim().isEmpty
                ? 'Shared system title unavailable'
                : '${system!['title']}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Project manager: ${group['project_manager_name'] ?? 'Not assigned'}',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 20),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final requirement in requirements)
            if ((requirement['file_policy'] as Map?)?['mode'] != 'concepts')
              requirementCard(requirement)
            else if (system != null)
              requirementCard(requirement, key: '${system['key']}'),
          if (requirements.any(
                (row) => (row['file_policy'] as Map?)?['mode'] == 'concepts',
              ) &&
              system == null)
            const Text('A selected shared system is needed to show its files.'),
          if (requirements.isEmpty)
            Text(
              'No shared deliverables are currently due.',
              style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.normalFlow) return _normalFlow();
    final requirements = _sharedRows(group['requirements']);
    final allRepeated = requirements
        .where((row) => (row['file_policy'] as Map?)?['mode'] == 'concepts')
        .toList();
    final once = requirements
        .where((row) => (row['file_policy'] as Map?)?['mode'] != 'concepts')
        .toList();
    final systems = _sharedRows(group['systems']);
    final official = systems
        .where((system) => system['key'] == group['selected_key'])
        .firstOrNull;
    final repeated = allRepeated
        .where((row) => official == null || row['deliverable_type'] != 'post')
        .toList();
    final alternatives = systems
        .where((system) => system['key'] != group['selected_key'])
        .toList();
    final visibleSystems = official == null
        ? systems
        : showHistory
        ? alternatives
        : [official];
    final active =
        visibleSystems
            .where(
              (system) =>
                  system['key'] == (widget.selectedSystemKey ?? systemKey),
            )
            .firstOrNull ??
        visibleSystems.firstOrNull;
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (official != null) ...[
            SharedSystemSelectionBanner(project: group),
            const SizedBox(height: 10),
            Text(
              'Project manager: ${group['project_manager_name'] ?? 'Not assigned'}. '
              'Only the selected system needs a final paper; earlier proposals remain available in history.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 14),
            for (final requirement in requirements.where(
              (row) => row['deliverable_type'] == 'post',
            ))
              requirementCard(
                requirement,
                key: (requirement['file_policy'] as Map?)?['mode'] == 'concepts'
                    ? '${official['key']}'
                    : null,
              ),
            if (alternatives.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          showHistory = !showHistory;
                          systemKey = null;
                        }),
                  leading: Icon(
                    showHistory ? Icons.arrow_back : Icons.history,
                    size: 15,
                  ),
                  child: Text(
                    showHistory
                        ? 'Back to selected system'
                        : 'Earlier proposals (${alternatives.length})',
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (showHistory)
              Text(
                'Proposal history · Not selected for final submission',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
          ],
          if (official == null &&
              systems.length == 1 &&
              repeated.isEmpty &&
              '${active?['title'] ?? ''}'.isNotEmpty) ...[
            Text(
              '${active!['title']}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (once.any(
                (row) => official == null || row['deliverable_type'] != 'post',
              ) &&
              widget.systemHeaderBuilder == null) ...[
            Text(
              'For the entire section',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 10),
            for (final requirement in once.where(
              (row) => official == null || row['deliverable_type'] != 'post',
            ))
              requirementCard(requirement),
          ],
          if ((repeated.isNotEmpty || widget.systemHeaderBuilder != null) &&
              active != null) ...[
            if (visibleSystems.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ShadTabs<String>(
                  value: '${active['key']}',
                  scrollable: true,
                  tabBarAlignment: Alignment.centerLeft,
                  gap: 0,
                  onChanged: busy
                      ? null
                      : (value) {
                          setState(() => systemKey = value);
                          widget.onSystemChanged?.call(value);
                        },
                  tabs: [
                    for (final system in visibleSystems)
                      ShadTab(
                        value: '${system['key']}',
                        child: Text('System ${systems.indexOf(system) + 1}'),
                      ),
                  ],
                ),
              ),
            if (widget.systemHeaderBuilder != null)
              ConceptReviewSection(
                titleReview: widget.systemHeaderBuilder!(active),
                onReviewFiles: widget.onReviewFiles == null
                    ? null
                    : () => widget.onReviewFiles!('${active['key']}'),
                deliverables: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final requirement in repeated)
                      requirementCard(requirement, key: '${active['key']}'),
                    if (repeated.isEmpty)
                      Text(
                        'No deliverables are configured for this system.',
                        style: TextStyle(
                          fontSize: 12,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                  ],
                ),
              )
            else ...[
              Text(
                '${active['title'] == '' ? 'Awaiting system title' : active['title']}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 10),
              for (final requirement in repeated)
                requirementCard(requirement, key: '${active['key']}'),
            ],
          ],
          if (once.any(
                (row) => official == null || row['deliverable_type'] != 'post',
              ) &&
              widget.systemHeaderBuilder != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Section-wide documents',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'The project manager submits these once for the section.',
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 10),
            for (final requirement in once.where(
              (row) => official == null || row['deliverable_type'] != 'post',
            ))
              requirementCard(requirement),
          ],
          if (requirements.isEmpty)
            Text(
              'No shared deliverables are currently due.',
              style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
            ),
        ],
      ),
    );
  }
}

/// Read-only discovery for a chosen stage/event; opening it never creates work.
class SharedDeliverablesSection extends ConsumerStatefulWidget {
  const SharedDeliverablesSection({
    super.key,
    required this.teamId,
    required this.stageLabel,
    this.summary,
    this.embedded = false,
    this.onChanged,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic>? summary;
  final bool embedded;
  final VoidCallback? onChanged;
  @override
  ConsumerState<SharedDeliverablesSection> createState() =>
      _SharedDeliverablesSectionState();
}

class _SharedDeliverablesSectionState
    extends ConsumerState<SharedDeliverablesSection> {
  Map<String, dynamic>? group;
  String? error;
  bool loading = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    if (widget.embedded || widget.summary == null) load();
  }

  @override
  void didUpdateWidget(covariant SharedDeliverablesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId ||
        oldWidget.stageLabel != widget.stageLabel) {
      load();
    }
  }

  Future<void> load() async {
    final request = ++revision;
    setState(() {
      group = null;
      error = null;
      loading = true;
    });
    try {
      final response = await ref
          .read(sectionConceptServiceProvider)
          .sharedDeliverables(widget.teamId, stageLabel: widget.stageLabel);
      if (mounted && request == revision) {
        setState(() {
          loading = false;
          group = response['shared_deliverables'] is Map
              ? Map<String, dynamic>.from(
                  response['shared_deliverables'] as Map,
                )
              : null;
        });
      }
    } catch (exception) {
      if (mounted && request == revision) {
        setState(() {
          loading = false;
          error = '$exception';
        });
      }
    }
  }

  void changed(Map<String, dynamic> value) {
    setState(() => group = value);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Container(
        key: const ValueKey('shared-deliverables-workspace'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          border: Border.all(color: DefensysTokens.borderOf(context)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Shared system',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${group?['section'] ?? widget.summary?['section'] ?? ''} · ${widget.stageLabel}',
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 20),
            if (loading)
              const LinearProgressIndicator()
            else if (error != null) ...[
              Text(error!),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: load,
                  child: const Text('Retry shared deliverables'),
                ),
              ),
            ] else if (group != null)
              SharedDeliverablesPanel(
                group: group!,
                normalFlow: true,
                onChanged: changed,
              )
            else
              const Text('No shared deliverables are currently available.'),
          ],
        ),
      );
    }
    if (error != null) {
      return TextButton(
        onPressed: load,
        child: const Text('Retry shared deliverables'),
      );
    }
    if (group == null && widget.summary == null) return const SizedBox.shrink();
    final info = group ?? widget.summary!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('Shared system deliverables · ${info['section']}'),
        subtitle: Text('Project manager: ${info['project_manager_name']}'),
        onExpansionChanged: (expanded) {
          if (expanded && group == null) load();
        },
        children: [
          if (group != null)
            SharedDeliverablesPanel(group: group!, onChanged: changed)
          else
            const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
