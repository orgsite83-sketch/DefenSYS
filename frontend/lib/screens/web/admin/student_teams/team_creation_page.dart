import 'package:defensys/widgets/shadcn/workflow_step_progress.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/import/team_creation_draft.dart';
import 'components/team_project_setup.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:defensys/services/academic/team_formation_service.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/export/team_roster_excel_generator.dart';
import 'package:defensys/utils/import/team_bulk_import_file.dart';
import 'package:defensys/utils/import/team_bulk_import_csv.dart';
import 'package:defensys/utils/import/class_list_template.dart';
import '../widgets/team_bulk_import_review_table.dart';
import 'dialogs/generate_teams_dialog.dart';

Future<bool?> openTeamCreation(
  BuildContext context, {
  bool importTab = false,
  String? level,
  String? section,
  String? event,
}) {
  final current = GoRouterState.of(context).uri.path;
  final base = current.startsWith('/admin/')
      ? '/admin/student-teams'
      : current.startsWith('/faculty/deliverables')
      ? '/faculty/deliverables'
      : '/faculty/student-teams';
  return context.push<bool>(
    Uri(
      path: '$base/creation',
      queryParameters: {
        'tab': importTab ? 'import' : 'generate',
        if (level != null && level.isNotEmpty) 'level': level,
        if (section != null && section.isNotEmpty) 'section': section,
        if (event != null && event.isNotEmpty) 'event': event,
      },
    ).toString(),
  );
}

List<Map<String, dynamic>> _maps(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

class TeamCreationPage extends ConsumerStatefulWidget {
  const TeamCreationPage({
    super.key,
    this.initialTab = 'generate',
    this.initialLevel,
    this.initialSection,
    this.initialEvent,
  });
  final String initialTab;
  final String? initialLevel, initialSection, initialEvent;
  @override
  ConsumerState<TeamCreationPage> createState() => _TeamCreationPageState();
}

class _TeamCreationPageState extends ConsumerState<TeamCreationPage> {
  Map<String, dynamic>? config;
  String? level, event, error, selectedSection;
  String? get currentSection => selectedSection;
  List<String> get assignedSections {
    final sections =
        _maps(config?['assignments'])
            .where(
              (a) => a['year_level'] == level?.split(' ').take(2).join(' '),
            )
            .map((a) => a['section']?.toString().trim() ?? '')
            .where((section) => section.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return sections;
  }

  late int tab;
  final busyTabs = <int, bool>{}, dirtyTabs = <int, bool>{};
  late final UnsavedChangesNotifier guard;
  late final UnsavedChangesSaveDraftNotifier draftGuard;
  bool get busy => busyTabs.values.any((v) => v);
  bool get dirty => dirtyTabs.values.any((v) => v);
  List<Map<String, dynamic>> get events => _maps(config?['events'])
      .where(
        (e) =>
            e['year_level'] == level?.split(' ').take(2).join(' ') &&
            e['is_officially_complete'] != true,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    tab = widget.initialTab == 'import' ? 0 : 1;
    guard = ref.read(unsavedChangesProvider.notifier);
    draftGuard = ref.read(unsavedChangesSaveDraftProvider.notifier);
    Future.microtask(load);
  }

  @override
  void dispose() {
    releaseUnsavedChangesAfterFrame(guard, draftGuard);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await ref.read(teamFormationServiceProvider).context();
      if (!mounted) return;
      final levels = List<String>.from(result['levels'] as List);
      setState(() {
        config = result;
        if (result['can_generate'] == false) tab = 0;
        error = null;
        final preferred = widget.initialLevel == 'Capstone'
            ? (result['semester']?['label']?.toString().contains('1st') == true
                  ? '4th Year Capstone'
                  : '3rd Year Capstone')
            : widget.initialLevel;
        level = levels.contains(preferred) ? preferred : levels.firstOrNull;
        selectedSection = assignedSections.contains(widget.initialSection)
            ? widget.initialSection
            : assignedSections.firstOrNull ?? widget.initialSection;
        event =
            tab == 0 &&
                result['can_manage_policy'] == true &&
                events.any((e) => e['event_name'] == widget.initialEvent)
            ? widget.initialEvent
            : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void track(int index, {bool? saving, bool? edited}) {
    if (!mounted ||
        (saving == null || busyTabs[index] == saving) &&
            (edited == null || dirtyTabs[index] == edited)) {
      return;
    }
    setState(() {
      if (saving != null) busyTabs[index] = saving;
      if (edited != null) dirtyTabs[index] = edited;
    });
    guard.setDirty(dirty);
    draftGuard.setCallback(null);
  }

  Future<bool> canLeave() async {
    if (busy) return false;
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave team creation?'),
            content: const Text(
              'Your unsaved imports and team previews will be discarded.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard and leave'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> back({bool saved = false}) async {
    if (!saved && !await canLeave() || !mounted) return;
    setState(() {
      busyTabs.clear();
      dirtyTabs.clear();
    });
    guard.setDirty(false);
    // PopScope must rebuild before a programmatic pop after discarding a draft.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.canPop()) {
        context.pop(saved);
      } else {
        context.go(
          GoRouterState.of(context).uri.path.replaceFirst('/creation', ''),
        );
      }
    });
  }

  Future<void> changeContext(String? nextLevel, String? nextEvent) async {
    if (!await canLeave() || !mounted) return;
    setState(() {
      dirtyTabs.clear();
      busyTabs.clear();
      level = nextLevel;
      if (!assignedSections.contains(selectedSection)) {
        selectedSection = assignedSections.firstOrNull;
      }
      event = events.any((e) => e['event_name'] == nextEvent)
          ? nextEvent
          : null;
    });
    guard.setDirty(false);
  }

  Future<void> changeSection(String nextSection) async {
    if (!assignedSections.contains(nextSection) ||
        !await canLeave() ||
        !mounted) {
      return;
    }
    setState(() {
      dirtyTabs.clear();
      busyTabs.clear();
      selectedSection = nextSection;
    });
    guard.setDirty(false);
  }

  @override
  Widget build(BuildContext context) {
    final levels = List<String>.from(config?['levels'] as List? ?? []);
    final scopeKey = '$level-$event-$currentSection';
    return PopScope(
      canPop: !busy && !dirty,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) back();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to teams',
                      onPressed: busy ? null : back,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tab == 0 ? 'Import teams' : 'Generate teams',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      config?['semester']?['display_name']?.toString() ??
                          'Active semester',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (config != null && levels.isNotEmpty) ...[
                      if (level != null)
                        if (levels.length > 1)
                          PopupMenuButton<String>(
                            tooltip: 'Switch year level',
                            initialValue: level,
                            onSelected: busy
                                ? null
                                : (v) => changeContext(v, null),
                            itemBuilder: (context) => levels
                                .map(
                                  (v) =>
                                      PopupMenuItem(value: v, child: Text(v)),
                                )
                                .toList(),
                            child: Chip(
                              avatar: const Icon(
                                Icons.school_outlined,
                                size: 16,
                              ),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    level!,
                                    style: const TextStyle(
                                      fontFamily:
                                          DefensysTokens.fontFamilyInter,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_drop_down, size: 16),
                                ],
                              ),
                            ),
                          )
                        else
                          Chip(
                            avatar: const Icon(Icons.school_outlined, size: 16),
                            label: Text(
                              level!,
                              style: const TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                              ),
                            ),
                          ),
                      if (currentSection?.isNotEmpty == true)
                        if (assignedSections.length > 1)
                          PopupMenuButton<String>(
                            key: const ValueKey('team-creation-section'),
                            tooltip: 'Switch assigned section',
                            initialValue: currentSection,
                            onSelected: busy ? null : changeSection,
                            itemBuilder: (context) => assignedSections
                                .map(
                                  (section) => PopupMenuItem(
                                    value: section,
                                    child: Text(section),
                                  ),
                                )
                                .toList(),
                            child: Chip(
                              avatar: const Icon(
                                Icons.groups_outlined,
                                size: 16,
                              ),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Section $currentSection',
                                    style: const TextStyle(
                                      fontFamily:
                                          DefensysTokens.fontFamilyInter,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down, size: 16),
                                ],
                              ),
                            ),
                          )
                        else
                          Chip(
                            avatar: const Icon(Icons.groups_outlined, size: 16),
                            label: Text(
                              'Section $currentSection',
                              style: const TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                              ),
                            ),
                          ),
                      if (event?.isNotEmpty == true)
                        if (events.length > 1)
                          PopupMenuButton<String>(
                            tooltip: 'Switch PIT event',
                            initialValue: event,
                            onSelected: busy
                                ? null
                                : (v) => changeContext(level, v),
                            itemBuilder: (context) => events
                                .map(
                                  (e) => PopupMenuItem(
                                    value: e['event_name'].toString(),
                                    child: Text(e['event_name'].toString()),
                                  ),
                                )
                                .toList(),
                            child: Chip(
                              avatar: const Icon(
                                Icons.event_outlined,
                                size: 16,
                              ),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    event!,
                                    style: const TextStyle(
                                      fontFamily:
                                          DefensysTokens.fontFamilyInter,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_drop_down, size: 16),
                                ],
                              ),
                            ),
                          )
                        else
                          Chip(
                            avatar: const Icon(Icons.event_outlined, size: 16),
                            label: Text(
                              event!,
                              style: const TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(onPressed: load, child: const Text('Retry')),
                ],
              ),
            ),
          if (config == null && error == null) const LinearProgressIndicator(),
          if (config != null && levels.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No active instructor assignment is available. Ask your admin/PIT lead to assign your handled section.',
              ),
            ),
          if (config != null && level != null) ...[
            Expanded(
              child: tab == 0
                  ? _PreparedTeamsPane(
                      key: ValueKey('import-$scopeKey'),
                      level: level!,
                      event: event,
                      section: currentSection,
                      semester: Map<String, dynamic>.from(
                        config!['semester'] as Map,
                      ),
                      canResolveConflicts: config!['can_manage_policy'] == true,
                      onBusy: (v) => track(0, saving: v),
                      onDirty: (v) => track(0, edited: v),
                      onSaved: () => back(saved: true),
                    )
                  : GenerateTeamsDialog(
                      key: ValueKey('generate-$scopeKey'),
                      embedded: true,
                      levels: [level!],
                      initialLevel: level!,
                      semester: Map<String, dynamic>.from(
                        config!['semester'] as Map,
                      ),
                      initialSection: currentSection,
                      initialEvent: event,
                      events: events,
                      onBusyChanged: (v) => track(1, saving: v),
                      onDraftChanged: (v) => track(1, edited: v),
                      onCreated: () => back(saved: true),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreparedTeamsPane extends ConsumerStatefulWidget {
  const _PreparedTeamsPane({
    super.key,
    required this.level,
    this.event,
    this.section,
    required this.semester,
    required this.canResolveConflicts,
    required this.onBusy,
    required this.onDirty,
    required this.onSaved,
  });
  final String level;
  final String? event, section;
  final Map<String, dynamic> semester;
  final bool canResolveConflicts;
  final ValueChanged<bool> onBusy, onDirty;
  final VoidCallback onSaved;
  @override
  ConsumerState<_PreparedTeamsPane> createState() => _PreparedTeamsPaneState();
}

class _PreparedTeamsPaneState extends ConsumerState<_PreparedTeamsPane> {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? preview;
  String? error;
  bool busy = false, resolveConflicts = false;
  int revision = 0, step = 1;
  Map<String, dynamic>? options, savedDraft;
  final projectSetups = <String, Map<String, dynamic>>{};
  TeamCreationDraftStore get draftStore => TeamCreationDraftStore(
    '${ref.read(authProvider).user?['id']}',
    'import:${widget.semester['id']}:${widget.level}:${widget.section ?? ''}:${widget.event ?? 'current'}',
  );

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final result = await ref
            .read(teamFormationServiceProvider)
            .rosterOptions(widget.level, widget.event);
        final draft = await draftStore.load();
        if (mounted) {
          setState(() {
            options = result;
            savedDraft = draft;
          });
        }
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      }
    });
  }

  Future<void> saveDraft() async {
    await draftStore.save({
      'rows': rows,
      'project_setups': projectSetups,
      'resolve_conflicts': resolveConflicts,
    });
    if (mounted) {
      showSuccessToast(
        context,
        'Import draft saved. Review it again before importing.',
      );
    }
  }

  void resumeDraft() {
    setState(() {
      rows = _maps(savedDraft!['rows']);
      projectSetups.addAll(
        Map<String, dynamic>.from(
          savedDraft!['project_setups'] ?? {},
        ).map((k, v) => MapEntry(k, Map<String, dynamic>.from(v))),
      );
      resolveConflicts = savedDraft!['resolve_conflicts'] == true;
      preview = null;
      step = 2;
      savedDraft = null;
    });
    widget.onDirty(true);
  }

  Timer? debounce;
  bool get pit => widget.level.contains('PIT');
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<void> pick() async {
    final files = await pickMultipleTabularDataFiles();
    if (!mounted || files.isEmpty) return;
    try {
      final result = parseTeamBulkCsv(readTeamImportFiles(files));
      if (result.rows.isEmpty) {
        throw const FormatException(
          'No teams found. Use the prepared-team template.',
        );
      }
      setState(() {
        rows = result.rows
            .map(
              (r) => <String, dynamic>{
                ...r,
                'section': r['section']?.toString().trim().isNotEmpty == true
                    ? r['section']
                    : result.section?.contains(',') == false
                    ? result.section
                    : widget.section,
              },
            )
            .toList();
        preview = null;
        error = null;
      });
      widget.onDirty(true);
      // Continue opens the editable review; uploading never commits teams.
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> review() async {
    debounce?.cancel();
    if (rows.isEmpty) return;
    final currentRevision = ++revision;
    setState(() {
      busy = true;
      preview = null;
      error = null;
    });
    widget.onBusy(true);
    try {
      final result = await ref
          .read(teamFormationServiceProvider)
          .importPreview({
            'level': widget.level,
            if (pit && widget.event != null) 'event_name': widget.event,
            if (pit && widget.event != null)
              'roster_override': widget.canResolveConflicts,
            'project_setups': projectSetups,
            'partial': widget.canResolveConflicts && widget.event == null,
            'section': widget.section ?? '',
            'teams': rows,
            'resolve_conflicts': resolveConflicts,
          });
      if (mounted && revision == currentRevision) {
        setState(() => preview = result);
      }
    } catch (e) {
      if (mounted && revision == currentRevision) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && revision == currentRevision) {
        setState(() => busy = false);
        widget.onBusy(false);
      }
    }
  }

  void changed() {
    ++revision;
    setState(() {
      preview = null;
      busy = false;
    });
    widget.onBusy(false);
    widget.onDirty(rows.isNotEmpty);
    debounce?.cancel();
    if (rows.isNotEmpty) {
      debounce = Timer(const Duration(milliseconds: 600), review);
    }
  }

  Future<void> save() async {
    if (preview?['ready'] != true || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    widget.onBusy(true);
    try {
      final result = await ref
          .read(teamFormationServiceProvider)
          .importCommit(preview!['preview_token'] as String);
      await ref
          .read(studentTeamsProvider.notifier)
          .refreshAfterGeneration(result['created_count'] as int);
      if (!mounted) return;
      await draftStore.clear();
      if (!mounted) return;
      widget.onDirty(false);
      widget.onBusy(false);
      showSuccessToast(
        context,
        '${result['created_count']} teams created; ${result['updated_count']} teams updated.',
      );
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusy(false);
      }
    }
  }

  Future<void> template() async {
    await downloadBinaryFile(
      filename: importTemplateFilename(
        kind: '${pit ? 'pit' : 'capstone'}-teams',
        section: widget.section,
        level: widget.level.split(' ').take(2).join(' '),
        extension: 'xlsx',
      ),
      bytes: generateOfficialTeamRosterExcelBytes(
        isCapstone: !pit,
        assignedSection: widget.section,
        instructorName: templateInstructorName(ref.read(authProvider).user),
      ),
    );
  }

  Widget projectSection(String section) {
    final instructors = _maps(
      (options?['section_instructors'] as Map? ?? {})[section],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            section.isEmpty ? 'Section required' : section,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TeamProjectSetup(
            allowTitleReplacement: true,
            value:
                projectSetups[section] ?? const {'architecture': 'independent'},
            students: _maps(
              options?['students'],
            ).where((s) => s['section'] == section).toList(),
            contexts: _maps(options?['concept_contexts']),
            reviewers: _maps(options?['system_reviewers']),
            instructor: instructors.length == 1 ? instructors.single : null,
            isPit: pit,
            enabled: !busy,
            onChanged: (v) {
              setState(() => projectSetups[section] = v);
              changed();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewRows = _maps(preview?['rows']);
    final ready = previewRows.where((r) => r['ready'] == true).toList();
    final sections =
        rows
            .map((r) => '${r['section'] ?? widget.section ?? ''}')
            .toSet()
            .toList()
          ..sort();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkflowStepProgress(
            currentStep: step,
            labels: const [
              'Upload roster',
              'Resolve & configure',
              'Review & import',
            ],
            compactLabels: const ['Upload', 'Configure', 'Review'],
          ),
          const SizedBox(height: 24),
          if (savedDraft != null)
            Wrap(
              spacing: 12,
              children: [
                const Text('A saved import draft is available.'),
                TextButton(
                  onPressed: resumeDraft,
                  child: const Text('Resume draft'),
                ),
                TextButton(
                  onPressed: () async {
                    await draftStore.clear();
                    if (mounted) setState(() => savedDraft = null);
                  },
                  child: const Text('Discard'),
                ),
              ],
            ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceOf(context),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.event == null
                          ? (pit ? 'Current roster' : 'Capstone roster')
                          : '${widget.event} roster',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      !pit
                          ? 'Import the finalized Capstone teams for this semester. Project titles and advisers are preserved; each defense stage keeps its own records.'
                          : widget.event == null
                          ? 'Matching PIT events use this roster automatically. Event submissions, schedules and grades are kept separately.'
                          : 'This import replaces the roster only for the sections in this file and this event. Other events keep their roster.',
                    ),
                    const SizedBox(height: 24),
                    if (step == 1) ...[
                      const Text(
                        'Upload team names, members, leaders and sections. Project titles are optional. Existing student accounts are linked.',
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: busy ? null : template,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Download template'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy ? null : pick,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Upload CSV / Excel'),
                          ),
                        ],
                      ),
                      if (rows.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(
                            '${rows.length} teams loaded. Continue to review the rows.',
                          ),
                        ),
                    ],
                    if (step == 2) ...[
                      if (widget.canResolveConflicts)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Review changes to existing section assignments',
                          ),
                          subtitle: const Text(
                            'Section changes appear in the preview before you import.',
                          ),
                          value: resolveConflicts,
                          onChanged: busy
                              ? null
                              : (v) {
                                  setState(() => resolveConflicts = v!);
                                  changed();
                                },
                        ),
                      for (final section in sections) projectSection(section),
                      IgnorePointer(
                        ignoring: busy,
                        child: TeamBulkImportReviewTable(
                          rows: rows,
                          previewRows: previewRows,
                          isCapstoneAdmin: !pit,
                          pitLeadYear: pit
                              ? widget.level.replaceFirst(' PIT', '')
                              : null,
                          showIssuesOnly: false,
                          sectionOptions: [
                            if (widget.section != null) widget.section!,
                          ],
                          onRowChanged: (_) => changed(),
                          onDeleteRow: (index) {
                            rows.removeAt(index);
                            changed();
                          },
                          onAddRow: () {
                            rows.add({
                              'team_name': '',
                              'member_ids': <String>[],
                              'leader_id': '',
                              'section': widget.section ?? '',
                            });
                            changed();
                          },
                        ),
                      ),
                    ],
                    if (step == 3) ...[
                      Text(
                        '${ready.where((r) => r['action'] == 'create').length} create · ${ready.where((r) => r['action'] == 'update').length} update · ${previewRows.length - ready.length} blocked / skipped',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      for (final row in previewRows)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            row['ready'] == true
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                          ),
                          title: Text('${row['team_name']}'),
                          subtitle: Text(
                            '${row['section']} · ${row['member_count']} members · ${row['action']}\n${[...row['issues'] ?? [], ...row['warnings'] ?? []].join(' ')}',
                          ),
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Shared sections are imported with their complete project setup. Blocked rows must be resolved before replacing an event roster.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 32),
          Row(
            children: [
              if (step > 1)
                OutlinedButton(
                  onPressed: busy ? null : () => setState(() => step--),
                  child: const Text('Back'),
                ),
              const Spacer(),
              TextButton(
                onPressed: busy || rows.isEmpty ? null : saveDraft,
                child: const Text('Save draft'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: busy || rows.isEmpty
                    ? null
                    : () async {
                        if (step == 1) {
                          setState(() => step = 2);
                        } else if (step == 2) {
                          await review();
                          if (mounted && preview?['ready'] == true) {
                            setState(() => step = 3);
                          }
                        } else {
                          await save();
                        }
                      },
                icon: Icon(step == 3 ? Icons.check : Icons.arrow_forward),
                label: Text(
                  step == 3
                      ? 'Import ${ready.length} teams'
                      : step == 2
                      ? 'Review import'
                      : 'Continue',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
