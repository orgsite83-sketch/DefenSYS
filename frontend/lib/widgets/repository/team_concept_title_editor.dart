import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../services/academic/team_concept_service.dart';
import '../../services/academic/section_concept_service.dart';
import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'shared_concept_review.dart';

Future<Map<String, dynamic>?> editTeamConceptTitles(
  BuildContext context, {
  required int teamId,
  required String stageLabel,
}) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      TeamConceptTitleEditor(teamId: teamId, stageLabel: stageLabel),
);

Future<Map<String, dynamic>?> editSharedSystemTitles(
  BuildContext context,
  Map<String, dynamic> project,
) => showDialog<Map<String, dynamic>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => TeamConceptTitleEditor(
    teamId: project['team_id'] as int? ?? 0,
    stageLabel: '${project['stage_label']}',
    sharedSystemProject: project,
  ),
);

/// A focused editor shared by phone and desktop; the server owns the slot set.
class TeamConceptTitleEditor extends ConsumerStatefulWidget {
  const TeamConceptTitleEditor({
    super.key,
    required this.teamId,
    required this.stageLabel,
    this.sharedSystemProject,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic>? sharedSystemProject;

  @override
  ConsumerState<TeamConceptTitleEditor> createState() =>
      _TeamConceptTitleEditorState();
}

class _TeamConceptTitleEditorState
    extends ConsumerState<TeamConceptTitleEditor> {
  Map<String, dynamic>? workflow;
  Map<String, dynamic>? systemProject;
  final editors = <String, TextEditingController>{};
  final original = <String, String>{};
  bool loading = true, saving = false, allowClose = false;
  String? error;
  List<Map<String, dynamic>> get rows => conceptRows(workflow?['concepts']);
  bool get dirty =>
      editors.entries.any((e) => e.value.text.trim() != original[e.key]);
  bool get shared =>
      workflow?['section_project_id'] != null ||
      workflow?['shared_import_pending'] == true ||
      workflow?['selection_mode'] == 'shared_module';
  bool get systems => widget.sharedSystemProject != null;
  bool get editable => workflow?['can_edit_titles'] == true;
  int get provided =>
      editors.values.where((e) => e.text.trim().isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void dispose() {
    for (final editor in editors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final Map<String, dynamic> value;
      if (systems) {
        final service = ref.read(sectionConceptServiceProvider);
        final snapshot = widget.sharedSystemProject!;
        systemProject = snapshot['imported'] == true
            ? await service.imported(
                widget.teamId,
                stageLabel: widget.stageLabel,
              )
            : await service.get(snapshot['id'] as int);
        value = {
          'can_edit_titles': systemProject!['can_edit_names'] == true,
          'module_review_token': systemProject!['review_token'],
          'concepts': [
            for (final row in conceptRows(systemProject!['systems']))
              {
                ...row,
                'faculty_confirmed':
                    row['confirmed'] == true &&
                    systemProject!['can_review'] != true &&
                    systemProject!['can_manage'] != true,
              },
          ],
        };
      } else {
        value = await ref
            .read(teamConceptServiceProvider)
            .load(widget.teamId, widget.stageLabel);
      }
      if (!mounted) return;
      for (final editor in editors.values) {
        editor.dispose();
      }
      editors.clear();
      original.clear();
      for (final row in conceptRows(value['concepts'])) {
        final key = '${row['key']}';
        original[key] = '${row['title'] ?? ''}';
        editors[key] = TextEditingController(text: original[key]);
      }
      setState(() {
        workflow = value;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> close() async {
    if (saving) return;
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => DefensysShadcnScope(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ShadDialog(
              constraints: const BoxConstraints(maxWidth: 400),
              expandActionsWhenTiny: false,
              actionsAxis: MediaQuery.sizeOf(ctx).width < 360
                  ? Axis.vertical
                  : Axis.horizontal,
              removeBorderRadiusWhenTiny: false,
              title: const Text('Discard unsaved titles?'),
              description: const Text('Your changes have not been saved.'),
              actions: [
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep editing'),
                ),
                ShadButton.destructive(
                  size: ShadButtonSize.sm,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Discard changes'),
                ),
              ],
            ),
          ),
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => allowClose = true);
    Navigator.of(context).pop();
  }

  Future<void> save() async {
    if (saving || !editable || !dirty) return;
    if (systems && editors.values.any((e) => e.text.trim().isEmpty)) {
      setState(() => error = 'Enter a title for every shared system.');
      return;
    }
    if (editors.values.any((e) => e.text.trim().length > 255)) {
      setState(() => error = 'Keep each title within 255 characters.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final titles = [
        for (final row in rows)
          <String, dynamic>{
            'key': row['key'],
            'title': editors['${row['key']}']!.text.trim(),
          },
      ];
      final updated = systems
          ? systemProject!['imported'] == true
                ? await ref
                      .read(sectionConceptServiceProvider)
                      .saveImported(systemProject!, titles)
                : await ref.read(sectionConceptServiceProvider).action(
                    systemProject!,
                    'save_titles',
                    {'concepts': titles},
                  )
          : await ref
                .read(teamConceptServiceProvider)
                .save(
                  widget.teamId,
                  widget.stageLabel,
                  titles,
                  '${workflow!['module_review_token'] ?? ''}',
                );
      if (!mounted) return;
      setState(() {
        saving = false;
        allowClose = true;
      });
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    final surface = DefensysTokens.surfaceOf(context);
    final content = DefensysShadcnScope(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        systems
                            ? 'Edit system titles'
                            : shared
                            ? 'Edit module titles'
                            : 'Edit concept titles',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.stageLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: saving ? null : close,
                  tooltip: 'Close editor',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: loading
                ? const SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (workflow != null) ...[
                          Text(
                            '$provided of ${rows.length} titles completed',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            systems && editable
                                ? 'Complete every system title before saving. These alternatives are shared by all participating teams.'
                                : editable
                                ? 'Save your progress at any time. Complete every required title before faculty review.'
                                : 'These titles are read-only. Your faculty reviewer manages confirmed names and scheduled hearings.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                          for (final row in rows) ...[
                            SizedBox(height: shared ? 24 : 22),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    systems || shared
                                        ? 'System ${systemLetter(row['key'])}'
                                        : 'Concept ${'${row['key']}'.replaceFirst('c', '')}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (!shared && row['faculty_confirmed'] == true)
                                  const Icon(Icons.lock_outline, size: 15),
                              ],
                            ),
                            if (shared) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${row['system_title'] ?? ''}'.trim().isEmpty
                                    ? 'System name not yet provided'
                                    : '${row['system_title']}'.trim(),
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: DefensysTokens.textSecondaryOf(
                                    context,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Module title',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (row['faculty_confirmed'] == true)
                                    const Icon(Icons.lock_outline, size: 15),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            ShadInput(
                              key: ValueKey('concept-title-${row['key']}'),
                              controller: editors['${row['key']}'],
                              enabled:
                                  editable &&
                                  !saving &&
                                  row['faculty_confirmed'] != true,
                              minLines: 2,
                              maxLines: 4,
                              maxLength: 255,
                              onChanged: (_) => setState(() {}),
                              placeholder: Text(
                                systems
                                    ? 'Enter proposed shared system title'
                                    : shared
                                    ? 'Enter proposed module title'
                                    : 'Enter proposed concept title',
                              ),
                            ),
                          ],
                        ],
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              error!,
                              key: const ValueKey('concept-title-error'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (workflow == null && error != null)
                          TextButton(
                            onPressed: load,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ShadButton.outline(
                  onPressed: saving ? null : close,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShadButton(
                    expands: true,
                    onPressed: loading || saving || !editable || !dirty
                        ? null
                        : save,
                    child: Text(
                      saving
                          ? 'Saving…'
                          : systems
                          ? 'Save system titles'
                          : shared
                          ? 'Save module titles'
                          : 'Save concept titles',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final screen = PopScope(
      canPop: allowClose || (!dirty && !saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: Dialog(
        key: const ValueKey('team-concept-title-dialog'),
        backgroundColor: surface,
        insetPadding: EdgeInsets.all(phone ? 16 : 24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: shared ? 800 : 720),
          child: SizedBox(width: 600, child: content),
        ),
      ),
    );
    return screen;
  }
}
