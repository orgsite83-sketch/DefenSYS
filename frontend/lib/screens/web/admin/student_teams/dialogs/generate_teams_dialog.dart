import 'dart:convert';
import 'package:defensys/widgets/shadcn/workflow_step_progress.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/utils/import/team_creation_draft.dart';
import '../components/team_project_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/academic/team_formation_service.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import '../components/team_roster_import_panel.dart';

List<Map<String, dynamic>> _maps(dynamic value) => (value as List? ?? [])
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList();

class GenerateTeamsDialog extends ConsumerStatefulWidget {
  const GenerateTeamsDialog({
    super.key,
    required this.levels,
    required this.initialLevel,
    required this.events,
    this.initialSection,
    this.semester,
    this.initialEvent,
    this.embedded = false,
    this.onCreated,
    this.onBusyChanged,
    this.onDraftChanged,
  });
  final List<String> levels;
  final String initialLevel;
  final List<Map<String, dynamic>> events;
  final String? initialSection;
  final Map<String, dynamic>? semester;
  final String? initialEvent;
  final bool embedded;
  final VoidCallback? onCreated;
  final ValueChanged<bool>? onBusyChanged;
  final ValueChanged<bool>? onDraftChanged;

  @override
  ConsumerState<GenerateTeamsDialog> createState() =>
      _GenerateTeamsDialogState();
}

class _GenerateTeamsDialogState extends ConsumerState<GenerateTeamsDialog> {
  late String level;
  String? event;
  String method = 'random';
  String leaderMethod = 'random';
  String rosterMode = 'sections';
  final selectedStudents = <int>{};
  bool includeAssigned = false;
  bool sharedSystem = false;
  int? projectManagerId, systemReviewerId;
  String titleMode = 'student_proposed';
  String? conceptStage;
  int size = 4;
  int step = 1;
  Map<String, dynamic>? savedDraft;
  bool busy = false;
  bool rosterBusy = false, rosterDirty = false;
  String? error;
  Map<String, dynamic>? options;
  final sections = <String>{};
  final sources = <int>{};
  List<Map<String, dynamic>> teams = [];
  List<Map<String, dynamic>> students = [];
  String? token, previewSignature;

  bool get isPit => level.contains('PIT');
  Map<String, dynamic>? get assignedInstructor {
    if (!isPit || sections.length != 1) return null;
    final assigned = options?['section_instructors'] as Map? ?? {};
    final instructors = _maps(assigned[sections.single]);
    return instructors.length == 1 ? instructors.single : null;
  }

  int? get resolvedReviewerId =>
      assignedInstructor?['faculty_id'] as int? ?? systemReviewerId;
  String get year => level.substring(0, level.lastIndexOf(' '));
  List<Map<String, dynamic>> get events =>
      widget.events.where((e) => e['year_level'] == year).toList();
  TeamFormationService get service => ref.read(teamFormationServiceProvider);

  @override
  void initState() {
    super.initState();
    level = widget.initialLevel;
    event = null;
    Future.microtask(() async {
      await loadOptions();
      final draft = await draftStore.load();
      if (mounted) setState(() => savedDraft = draft);
    });
  }

  Future<void> loadOptions() async {
    setState(() {
      busy = true;
      error = null;
      token = null;
      teams = [];
    });
    try {
      final result = await service.options(level, event);
      if (!mounted) return;
      setState(() {
        options = result;
        sharedSystem = false;
        projectManagerId = null;
        systemReviewerId = null;
        conceptStage = _maps(
          result['concept_contexts'],
        ).firstOrNull?['label']?.toString();
        sources.clear();
        final allSections = _maps(
          result['sections'],
        ).map((s) => s['name'].toString()).toSet();
        final available = _maps(result['sections'])
            .where((s) => (s['eligible_count'] as num) > 0)
            .map((s) => s['name'].toString())
            .toSet();
        sections.clear();
        selectedStudents.clear();
        if (widget.initialSection != null &&
            widget.initialSection!.isNotEmpty) {
          sections.add(widget.initialSection!);
        } else if (available.length == 1) {
          sections.add(available.single);
        } else if (allSections.length == 1) {
          sections.add(allSections.single);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _error(e);
          options = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _error(Object e) => e.toString().replaceFirst('Exception: ', '');

  Map<String, dynamic> get request => {
    'level': level,
    if (isPit && event != null) 'event_name': event,
    'sections': sections.toList(),
    'method': method,
    'group_size': size,
    'source_team_ids': sources.toList(),
    'leader_method': leaderMethod,
    'roster_mode': rosterMode,
    'include_assigned': includeAssigned,
    if (rosterMode == 'custom') 'student_ids': selectedStudents.toList(),
    if (sharedSystem)
      'shared_system': {
        'project_manager_id': projectManagerId,
        if (resolvedReviewerId != null) 'reviewer_id': resolvedReviewerId,
        'title_mode': titleMode,
        'stage_label': conceptStage,
      },
  };

  Future<void> preview() async {
    if (token != null && previewSignature == jsonEncode(request)) {
      setState(() => step = 3);
      return;
    }
    if (token != null && teams.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Regenerate team preview?'),
          content: const Text(
            'Your grouping or project settings changed. Generating a new preview replaces edits to the previous teams.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Regenerate preview'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    if (sharedSystem &&
        (rosterMode != 'sections' ||
            sections.length != 1 ||
            projectManagerId == null ||
            resolvedReviewerId == null ||
            conceptStage == null ||
            !_maps(options?['students']).any(
              (s) =>
                  s['id'] == projectManagerId &&
                  s['section'] == sections.single,
            ))) {
      setState(
        () => error =
            'For a shared system, select one section, its student project manager, a faculty reviewer and a concept stage/event.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await service.preview(request);
      if (!mounted) return;
      setState(() {
        teams = _maps(result['teams']);
        students = _maps(result['students']);
        token = result['preview_token'].toString();
        previewSignature = jsonEncode(request);
        step = 3;
      });
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (teams.any(
      (t) => t['name'].toString().trim().isEmpty || t['leader_id'] == null,
    )) {
      setState(
        () => error =
            'Enter a name and choose a leader for every team. Leaders can update team names during setup.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await service.create({
        ...request,
        'preview_token': token,
        'teams': teams,
      });
      await draftStore.clear();
      await ref
          .read(studentTeamsProvider.notifier)
          .refreshAfterGeneration(result['created_count'] as int);
      if (mounted) {
        if (widget.onCreated != null) {
          widget.onCreated!();
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _error(e);
          busy = false;
        });
      }
    }
  }

  Future<void> changePolicy(String value) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.setPolicy(options!['event_id'] as int, value);
      await loadOptions();
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void move(int studentId, int from, int to) {
    final origin = List<int>.from(teams[from]['member_ids'] as List);
    final target = List<int>.from(teams[to]['member_ids'] as List);
    final limit = method == 'reuse' ? 4 : size;
    if (target.length >= limit || origin.length <= 1) return;
    setState(() {
      origin.remove(studentId);
      target.add(studentId);
      teams[from]['member_ids'] = origin;
      teams[to]['member_ids'] = target;
      if (teams[from]['leader_id'] == studentId) {
        teams[from]['leader_id'] = origin.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onBusyChanged?.call(busy || rosterBusy);
        widget.onDraftChanged?.call(step > 1 || token != null || rosterDirty);
      }
    });
    final reviewing = step == 3;
    final color = Theme.of(context).colorScheme.primary;
    final dialog = PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              reviewing ? Icons.fact_check_outlined : Icons.groups_outlined,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                reviewing ? 'Review generated teams' : 'Generate teams',
              ),
            ),
            IconButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              tooltip: 'Close',
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 960,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reviewing
                    ? '${teams.length} ${teams.length == 1 ? 'team' : 'teams'} · ${students.length} students. Review names, members, and leaders before creating.'
                    : step == 2
                    ? 'Choose how these teams will organize their project work.'
                    : 'Form teams from enrolled students. Each section is grouped separately.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (busy) const LinearProgressIndicator(minHeight: 2),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8),
                  child: reviewing
                      ? review()
                      : step == 2
                      ? projectSetup()
                      : settings(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy
                ? null
                : () {
                    if (step > 1) {
                      setState(() {
                        step--;
                        error = null;
                      });
                    } else {
                      Navigator.pop(context);
                    }
                  },
            child: Text(step > 1 ? 'Back' : 'Cancel'),
          ),
          if (reviewing)
            OutlinedButton.icon(
              onPressed: busy ? null : preview,
              icon: const Icon(Icons.refresh),
              label: const Text('Regenerate preview'),
            ),
          FilledButton.icon(
            onPressed:
                busy ||
                    rosterBusy || rosterDirty ||
                    (!reviewing &&
                        (options == null ||
                            !_maps(options?['students']).any(
                              (s) =>
                                  s['eligible'] == true &&
                                  (includeAssigned || s['assigned'] != true) &&
                                  (rosterMode == 'custom'
                                      ? selectedStudents.contains(s['id'])
                                      : sections.contains(s['section'])),
                            ) ||
                            (rosterMode == 'custom'
                                ? selectedStudents.isEmpty
                                : sections.isEmpty) ||
                            (method == 'reuse' && sources.isEmpty)))
                ? null
                : (reviewing
                      ? save
                      : step == 2
                      ? preview
                      : () => setState(() => step = 2)),
            icon: Icon(reviewing ? Icons.check : Icons.arrow_forward),
            label: Text(
              reviewing
                  ? 'Create ${teams.length} ${teams.length == 1 ? 'team' : 'teams'}'
                  : step == 2
                  ? 'Review teams'
                  : 'Continue',
            ),
          ),
        ],
      ),
    );
    if (!widget.embedded) return dialog;
    final alert = dialog.child as AlertDialog;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkflowStepProgress(
            currentStep: step,
            labels: const [
              'Roster & grouping',
              'Project setup',
              'Review & create',
            ],
            compactLabels: const ['Roster', 'Project', 'Review'],
          ),
          const SizedBox(height: 24),
          if (savedDraft != null)
            Wrap(
              spacing: 12,
              children: [
                const Text('A saved draft is available for this roster.'),
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
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceOf(context),
                border: Border.all(color: DefensysTokens.borderOf(context)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: alert.content!,
            ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              if (step > 1) alert.actions!.first,
              const Spacer(),
              TextButton(
                onPressed: busy ? null : saveDraft,
                child: const Text('Save draft'),
              ),
              const SizedBox(width: 12),
              alert.actions!.last,
            ],
          ),
        ],
      ),
    );
  }

  TeamCreationDraftStore get draftStore => TeamCreationDraftStore(
    '${ref.read(authProvider).user?['id']}',
    'generate:${widget.semester?['id']}:$level:${widget.initialSection ?? ''}',
  );

  Future<void> saveDraft() async {
    await draftStore.save({
      ...request,
      'teams': teams,
      'students': students,
      'token': token,
      'signature': previewSignature,
      'step': step,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Draft saved. It will be checked again before teams are created.',
          ),
        ),
      );
    }
  }

  void resumeDraft() {
    final draft = savedDraft!;
    setState(() {
      method = draft['method'] ?? 'random';
      leaderMethod = draft['leader_method'] ?? 'random';
      size = draft['group_size'] ?? 4;
      rosterMode = draft['roster_mode'] ?? 'sections';
      includeAssigned = draft['include_assigned'] == true;
      sections
        ..clear()
        ..addAll(List<String>.from(draft['sections'] ?? []));
      sources
        ..clear()
        ..addAll(List<int>.from(draft['source_team_ids'] ?? []));
      selectedStudents
        ..clear()
        ..addAll(List<int>.from(draft['student_ids'] ?? []));
      final setup = Map<String, dynamic>.from(draft['shared_system'] ?? {});
      sharedSystem = setup.isNotEmpty;
      projectManagerId = setup['project_manager_id'];
      systemReviewerId = setup['reviewer_id'];
      conceptStage = setup['stage_label'];
      titleMode = setup['title_mode'] ?? 'student_proposed';
      teams = _maps(draft['teams']);
      students = _maps(draft['students']);
      token = draft['token'];
      previewSignature = draft['signature'];
      step = token == null ? 1 : 3;
      savedDraft = null;
    });
  }

  Widget projectSetup() => TeamProjectSetup(
    value: {
      'architecture': sharedSystem ? 'shared' : 'independent',
      'project_manager_id': projectManagerId,
      'reviewer_id': resolvedReviewerId,
      'stage_label': conceptStage,
      'title_mode': titleMode,
    },
    students: _maps(
      options?['students'],
    ).where((s) => sections.contains(s['section'])).toList(),
    contexts: _maps(options?['concept_contexts']),
    reviewers: _maps(options?['system_reviewers']),
    instructor: assignedInstructor,
    isPit: isPit,
    enabled: !busy,
    onChanged: (v) => setState(() {
      sharedSystem = v['architecture'] == 'shared';
      projectManagerId = v['project_manager_id'];
      systemReviewerId = v['reviewer_id'];
      conceptStage = v['stage_label'];
      titleMode = v['title_mode'] ?? 'student_proposed';
    }),
  );

  Widget settings() {
    final isInstructorSectionMode =
        widget.embedded ||
        (widget.initialSection != null && widget.initialSection!.isNotEmpty);
    final effectiveSection =
        widget.initialSection ??
        sections.firstOrNull ??
        _maps(options?['sections']).firstOrNull?['name']?.toString() ??
        '';
    if (isInstructorSectionMode &&
        effectiveSection.isNotEmpty &&
        !sections.contains(effectiveSection)) {
      sections.add(effectiveSection);
    }
    final eligibleCount = _maps(options?['students'])
        .where(
          (student) =>
              student['section'] == effectiveSection &&
              student['eligible'] == true &&
              (includeAssigned || student['assigned'] != true),
        )
        .length;
    final totalCount = _maps(
      options?['students'],
    ).where((student) => student['section'] == effectiveSection).length;

    final sourceTeams = _maps(options?['source_teams'])
        .where(
          (s) => rosterMode == 'custom'
              ? (s['member_ids'] as List).every(selectedStudents.contains)
              : sections.contains(s['section']),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded)
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 255,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('level-$level'),
                  isExpanded: true,
                  initialValue: level,
                  decoration: const InputDecoration(
                    labelText: 'Program and year',
                  ),
                  items: widget.levels
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            level = value;
                            event = null;
                          });
                          loadOptions();
                        },
                ),
              ),
            ],
          ),
        if (widget.embedded && options != null) ...[
          ExpansionTile(
            key: ValueKey('class-list-${_maps(options?['students']).length}'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Import or update class list'),
            subtitle: Text(
              '${_maps(options?['students']).where((s) => sections.contains(s['section'])).length} enrolled students available. Continue with these students or upload an updated list.',
            ),
            initiallyExpanded: _maps(
              options?['students'],
            ).where((s) => sections.contains(s['section'])).isEmpty,
            children: [
              TeamRosterImportPanel(
                level: level,
                semester: widget.semester,
                section: widget.initialSection,
                sections: _maps(options?['sections']),
                students: _maps(options?['students']),
                canResolveConflicts: options?['can_manage_policy'] == true,
                onBusyChanged: (v) => setState(() => rosterBusy = v),
                onDirtyChanged: (v) => setState(() => rosterDirty = v),
                onImported: loadOptions,
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (isPit)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Create the current section roster. Matching PIT events use these teams automatically; scheduling happens later.',
            ),
          ),
        if (options != null) ...[
          if (isPit &&
              event != null &&
              options!['can_manage_policy'] != false) ...[
            const SizedBox(height: 22),
            Text(
              'Event membership policy',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'The PIT lead decides the limit for this event. The same roster can be reused in other events.',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 360,
              child: DropdownButtonFormField<String>(
                key: ValueKey('policy-${options!['team_membership_policy']}'),
                isExpanded: true,
                initialValue: options!['team_membership_policy'] as String,
                decoration: const InputDecoration(
                  labelText: 'Students may join',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'single',
                    child: Text('One team in this event'),
                  ),
                  DropdownMenuItem(
                    value: 'multiple',
                    child: Text('Multiple teams in this event'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        if (v != null) changePolicy(v);
                      },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Changes apply immediately to this event, including manual creation and bulk import.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (isInstructorSectionMode) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      effectiveSection.isNotEmpty
                          ? 'Target Roster: Section $effectiveSection'
                          : 'Target Roster: Current Assigned Section',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: eligibleCount > 0
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1)
                          : Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      effectiveSection.isNotEmpty
                          ? '$effectiveSection · $eligibleCount/$totalCount available'
                          : (eligibleCount > 0
                                ? '$eligibleCount eligible students'
                                : '0 students available'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: eligibleCount > 0
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 22),
            DropdownButtonFormField<String>(
              initialValue: rosterMode,
              decoration: const InputDecoration(labelText: 'Roster selection'),
              items: const [
                DropdownMenuItem(value: 'sections', child: Text('By section')),
                DropdownMenuItem(
                  value: 'custom',
                  child: Text('Choose a custom roster'),
                ),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      rosterMode = v!;
                      sources.clear();
                    }),
            ),
            const SizedBox(height: 12),
            if (options!['team_membership_policy'] == 'multiple')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include students already in teams'),
                subtitle: const Text(
                  'The PIT lead permits additional memberships in this event.',
                ),
                value: includeAssigned,
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        includeAssigned = v;
                        if (!v) {
                          selectedStudents.removeWhere(
                            (id) => _maps(options!['students']).any(
                              (s) => s['id'] == id && s['assigned'] == true,
                            ),
                          );
                        }
                      }),
              ),
            if (rosterMode == 'custom') ...[
              const Text(
                'Explicitly select students to include. Their academic sections will be preserved.',
              ),
              ..._maps(options!['students'])
                  .where(
                    (s) =>
                        s['eligible'] == true &&
                        (includeAssigned || s['assigned'] != true),
                  )
                  .map(
                    (s) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${s['name']} · ${s['username']}'),
                      subtitle: Text(
                        '${s['section'].toString().isEmpty ? 'Unassigned' : s['section']}${s['assigned'] == true ? ' · Already in a team' : ''}',
                      ),
                      value: selectedStudents.contains(s['id']),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              v == true
                                  ? selectedStudents.add(s['id'] as int)
                                  : selectedStudents.remove(s['id']);
                            }),
                    ),
                  ),
            ],
            if (rosterMode == 'sections') ...[
              Text('Sections', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_maps(options!['sections']).isEmpty)
                const Text(
                  'No enrolled section rosters are available for this year and term.',
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _maps(options!['sections']).map((s) {
                  final name = s['name'].toString();
                  final count = _maps(options!['students'])
                      .where(
                        (student) =>
                            student['section'] == name &&
                            student['eligible'] == true &&
                            (includeAssigned || student['assigned'] != true),
                      )
                      .length;
                  return FilterChip(
                    selectedColor: DefensysTokens.surfaceHigherOf(context),
                    checkmarkColor: DefensysTokens.maroonTextOf(context),
                    side: BorderSide(
                      color: sections.contains(name)
                          ? DefensysTokens.maroonTextOf(context)
                          : DefensysTokens.borderOf(context),
                    ),
                    label: Text('$name · $count/${s['total_count']} available'),
                    selected: sections.contains(name),
                    onSelected: busy || count == 0
                        ? null
                        : (selected) => setState(() {
                            selected
                                ? sections.add(name)
                                : sections.remove(name);
                            sources.clear();
                          }),
                  );
                }).toList(),
              ),
            ],
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<int>(
                  initialValue: size,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Maximum team size',
                  ),
                  items: [1, 2, 3, 4, 5]
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text('$n students'),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => size = v!),
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String>(
                  initialValue: method,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Grouping method',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'random',
                      child: Text('Randomize students'),
                    ),
                    const DropdownMenuItem(
                      value: 'alphabetical',
                      child: Text('Alphabetical by surname'),
                    ),
                    if (isPit && event != null)
                      const DropdownMenuItem(
                        value: 'reuse',
                        child: Text('Reuse team rosters'),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          method = v!;
                          if (method != 'reuse' && leaderMethod == 'keep') {
                            leaderMethod = 'random';
                          }
                        }),
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('leader-method-$method'),
                  initialValue: leaderMethod,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Leader selection',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'random',
                      child: Text('Randomize leaders'),
                    ),
                    const DropdownMenuItem(
                      value: 'manual',
                      child: Text('Choose leaders in preview'),
                    ),
                    if (method == 'reuse')
                      const DropdownMenuItem(
                        value: 'keep',
                        child: Text('Keep previous leaders'),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => leaderMethod = v!),
                ),
              ),
            ],
          ),
          if (method == 'reuse') ...[
            const SizedBox(height: 20),
            Text(
              'Choose rosters to reuse',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Text(
              'Members and leaders are copied into new teams for this event. Earlier event records stay attached to their original teams. Remaining students are grouped alphabetically.',
            ),
            if (sourceTeams.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No teams from another event are available in the selected sections.',
                ),
              ),
            ...sourceTeams.map(
              (t) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t['name'].toString()),
                subtitle: Text(
                  '${t['section']} · ${t['event_name']} · ${(t['member_ids'] as List).length} members',
                ),
                value: sources.contains(t['id']),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        v == true
                            ? sources.add(t['id'] as int)
                            : sources.remove(t['id']);
                      }),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Remaining students will be distributed evenly. Teams start with provisional names and no selected project. You can review, rename, and reassign leaders and members in the preview step before saving.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget review() {
    final byId = {for (final s in students) s['id'] as int: s};
    return Column(
      children: teams.asMap().entries.map((entry) {
        final index = entry.key, team = entry.value;
        final ids = List<int>.from(team['member_ids'] as List);
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 14),
              Text(
                '${team['section']} · ${ids.length} members',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 128).clamp(
                      180.0,
                      390.0,
                    ),
                    child: TextFormField(
                      key: ValueKey('name-$index-${token.hashCode}'),
                      initialValue: team['name'].toString(),
                      enabled: !busy,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Provisional team name',
                        counterText: '',
                      ),
                      onChanged: (v) => team['name'] = v,
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 128).clamp(
                      180.0,
                      310.0,
                    ),
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('leader-$index-${team['leader_id']}'),
                      initialValue: team['leader_id'] as int?,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Team leader',
                      ),
                      items: ids
                          .map(
                            (id) => DropdownMenuItem(
                              value: id,
                              child: Text(
                                byId[id]!['name'].toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (id) => setState(() => team['leader_id'] = id),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...ids.map((id) {
                final destinations = teams
                    .asMap()
                    .entries
                    .where(
                      (e) =>
                          e.key != index &&
                          e.value['section'] == team['section'] &&
                          (e.value['member_ids'] as List).length <
                              (method == 'reuse' ? 4 : size),
                    )
                    .toList();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    id == team['leader_id']
                        ? Icons.star_outline
                        : Icons.person_outline,
                    color: id == team['leader_id']
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(byId[id]!['name'].toString()),
                  subtitle: Text(byId[id]!['username'].toString()),
                  trailing: ids.length <= 1 || destinations.isEmpty
                      ? null
                      : PopupMenuButton<int>(
                          enabled: !busy,
                          tooltip: 'Move student to another team',
                          onSelected: (to) => move(id, index, to),
                          itemBuilder: (_) => destinations
                              .map(
                                (e) => PopupMenuItem(
                                  value: e.key,
                                  child: Text('Move to ${e.value['name']}'),
                                ),
                              )
                              .toList(),
                          icon: const Icon(Icons.drive_file_move_outline),
                        ),
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }
}
