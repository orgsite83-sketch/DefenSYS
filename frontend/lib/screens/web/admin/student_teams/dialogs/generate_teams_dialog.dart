import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/academic/team_formation_service.dart';
import 'package:defensys/services/student_teams_provider.dart';
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
  bool busy = false;
  bool rosterBusy = false, rosterDirty = false;
  String? error;
  Map<String, dynamic>? options;
  final sections = <String>{};
  final sources = <int>{};
  List<Map<String, dynamic>> teams = [];
  List<Map<String, dynamic>> students = [];
  String? token;

  bool get isPit => level.contains('PIT');
  String get year => level.substring(0, level.lastIndexOf(' '));
  List<Map<String, dynamic>> get events =>
      widget.events.where((e) => e['year_level'] == year).toList();
  TeamFormationService get service => ref.read(teamFormationServiceProvider);

  @override
  void initState() {
    super.initState();
    level = widget.initialLevel;
    event = events.any((e) => e['event_name'] == widget.initialEvent)
        ? widget.initialEvent
        : events.firstOrNull?['event_name']?.toString();
    Future.microtask(loadOptions);
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
        conceptStage = _maps(result['concept_contexts']).firstOrNull?['label']?.toString();
        sources.clear();
        final available = _maps(result['sections'])
            .where((s) => (s['eligible_count'] as num) > 0)
            .map((s) => s['name'].toString())
            .toSet();
        sections.clear();
        selectedStudents.clear();
        if (available.contains(widget.initialSection)) {
          sections.add(widget.initialSection!);
        } else if (available.length == 1) {
          sections.add(available.single);
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
    if (isPit) 'event_name': event,
    'sections': sections.toList(),
    'method': method,
    'group_size': size,
    'source_team_ids': sources.toList(),
    'leader_method': leaderMethod,
    'roster_mode': rosterMode,
    'include_assigned': includeAssigned,
    if (rosterMode == 'custom') 'student_ids': selectedStudents.toList(),
    if (sharedSystem) 'shared_system': {
      'project_manager_id': projectManagerId, 'reviewer_id': systemReviewerId,
      'title_mode': titleMode, 'stage_label': conceptStage,
    },
  };

  Future<void> preview() async {
    if (sharedSystem && (rosterMode != 'sections' || sections.length != 1 ||
        projectManagerId == null || systemReviewerId == null || conceptStage == null ||
        !_maps(options?['students']).any((s) => s['id'] == projectManagerId && s['section'] == sections.single))) {
      setState(() => error = 'For a shared system, select one section, its student project manager, a faculty reviewer and a concept stage/event.');
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
        widget.onDraftChanged?.call(token != null || rosterDirty);
      }
    });
    final reviewing = token != null;
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
                  child: reviewing ? review() : settings(),
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
                    if (reviewing) {
                      setState(() {
                        token = null;
                        teams = [];
                        error = null;
                      });
                    } else {
                      Navigator.pop(context);
                    }
                  },
            child: Text(reviewing ? 'Back to settings' : 'Cancel'),
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
                    rosterBusy ||
                    (!reviewing &&
                        ((isPit && event == null) ||
                            options == null ||
                            (rosterMode == 'custom'
                                ? selectedStudents.isEmpty
                                : sections.isEmpty) ||
                            (method == 'reuse' && sources.isEmpty)))
                ? null
                : (reviewing ? save : preview),
            icon: Icon(reviewing ? Icons.check : Icons.arrow_forward),
            label: Text(
              reviewing
                  ? 'Create ${teams.length} ${teams.length == 1 ? 'team' : 'teams'}'
                  : 'Preview teams',
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
          Expanded(child: alert.content!),
          const Divider(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: alert.actions!.skip(reviewing ? 0 : 1).toList(),
          ),
        ],
      ),
    );
  }

  Widget settings() {
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
                            event = events.firstOrNull?['event_name']
                                ?.toString();
                          });
                          loadOptions();
                        },
                ),
              ),
              if (isPit)
                SizedBox(
                  width: 330,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('event-$level-$event'),
                    initialValue: event,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'PIT event'),
                    items: events
                        .map(
                          (e) => DropdownMenuItem(
                            value: e['event_name'].toString(),
                            child: Text(
                              e['event_name'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(() => event = value);
                            loadOptions();
                          },
                  ),
                ),
            ],
          ),
        if (widget.embedded) ...[
          TeamRosterImportPanel(
            level: level,
            section: widget.initialSection,
            sections: _maps(options?['sections']),
            students: _maps(options?['students']),
            canResolveConflicts: options?['can_manage_policy'] == true,
            onBusyChanged: (v) => setState(() => rosterBusy = v),
            onDirtyChanged: (v) => setState(() => rosterDirty = v),
            onImported: loadOptions,
          ),
          const SizedBox(height: 20),
        ],
        if (isPit && events.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Create a PIT event for this year level in PIT Events, then return here.',
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
                          (id) => _maps(
                            options!['students'],
                          ).any((s) => s['id'] == id && s['assigned'] == true),
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
                  label: Text('$name · $count/${s['total_count']} available'),
                  selected: sections.contains(name),
                  onSelected: busy || count == 0
                      ? null
                      : (selected) => setState(() {
                          selected ? sections.add(name) : sections.remove(name);
                          sources.clear();
                        }),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('leader-method-$method'),
            initialValue: leaderMethod,
            decoration: const InputDecoration(labelText: 'Leader selection'),
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
            onChanged: busy ? null : (v) => setState(() => leaderMethod = v!),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 280,
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
                    if (isPit)
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
                width: 200,
                child: DropdownButtonFormField<int>(
                  initialValue: size,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Maximum team size',
                  ),
                  items: [1, 2, 3, 4]
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
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Remaining students are distributed evenly. You can change members and leaders in the preview.',
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
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('One shared system for this section'),
            subtitle: const Text('Three system proposals for the project manager; three corresponding module proposals for every team.'),
            value: sharedSystem,
            onChanged: busy || _maps(options?['concept_contexts']).isEmpty ? null : (v) => setState(() => sharedSystem = v),
          ),
          if (_maps(options?['concept_contexts']).isEmpty)
            const Text('Enable concept selection in stage/event setup to use shared system proposals.'),
          if (sharedSystem) ...[
            if (rosterMode != 'sections' || sections.length != 1)
              const Text('Select one enrolled section for the shared system.'),
            DropdownButtonFormField<int>(
              key: ValueKey('shared-manager-${sections.join(',')}'),
              initialValue: _maps(options?['students']).any((s) => s['id'] == projectManagerId && sections.contains(s['section'])) ? projectManagerId : null,
              isExpanded: true, decoration: const InputDecoration(labelText: 'Section project manager'),
              items: [for (final s in _maps(options?['students']).where((s) => sections.contains(s['section'])))
                DropdownMenuItem(value: s['id'] as int, child: Text('${s['name']}'))],
              onChanged: busy ? null : (v) => setState(() => projectManagerId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(initialValue: systemReviewerId, isExpanded: true,
              decoration: const InputDecoration(labelText: 'System faculty reviewer'),
              items: [for (final r in _maps(options?['system_reviewers'])) DropdownMenuItem(value: r['id'] as int, child: Text('${r['name']}'))],
              onChanged: busy ? null : (v) => setState(() => systemReviewerId = v)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(initialValue: conceptStage, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Concept stage / event'),
              items: [for (final c in _maps(options?['concept_contexts'])) DropdownMenuItem(value: '${c['label']}', child: Text('${c['label']}'))],
              onChanged: busy ? null : (v) => setState(() => conceptStage = v)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(initialValue: titleMode, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Proposal names'),
              items: const [DropdownMenuItem(value: 'student_proposed', child: Text('Students propose; faculty confirms')),
                DropdownMenuItem(value: 'faculty_provided', child: Text('Faculty provides names'))],
              onChanged: busy ? null : (v) => setState(() => titleMode = v!)),
          ],
          const SizedBox(height: 16),
          const Text(
            'New teams start without a selected project. Leaders will be asked for their team name and the concepts configured for their stage or event.',
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
                    width: 390,
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
                    width: 310,
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
