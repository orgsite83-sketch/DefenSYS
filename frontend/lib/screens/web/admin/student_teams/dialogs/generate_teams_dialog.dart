import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/academic/team_formation_service.dart';
import 'package:defensys/services/student_teams_provider.dart';

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
  });
  final List<String> levels;
  final String initialLevel;
  final List<Map<String, dynamic>> events;
  final String? initialSection;

  @override
  ConsumerState<GenerateTeamsDialog> createState() =>
      _GenerateTeamsDialogState();
}

class _GenerateTeamsDialogState extends ConsumerState<GenerateTeamsDialog> {
  late String level;
  String? event;
  String method = 'random';
  int size = 4;
  bool busy = false;
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
    event = events.firstOrNull?['event_name']?.toString();
    Future.microtask(loadOptions);
  }

  Future<void> loadOptions() async {
    if (isPit && event == null) {
      setState(() {
        options = null;
        token = null;
      });
      return;
    }
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
        sources.clear();
        final available = _maps(result['sections'])
            .where((s) => (s['eligible_count'] as num) > 0)
            .map((s) => s['name'].toString())
            .toSet();
        sections.clear();
        if (available.contains(widget.initialSection)) {
          sections.add(widget.initialSection!);
        } else {
          sections.addAll(available);
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
  };

  Future<void> preview() async {
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
    if (teams.any((t) => t['name'].toString().trim().isEmpty)) {
      setState(
        () => error =
            'Enter a name for every team. Leaders can update these names during setup.',
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
      if (mounted) Navigator.pop(context, true);
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
    if (target.length >= 4 || origin.length <= 1) return;
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
    final reviewing = token != null;
    final color = Theme.of(context).colorScheme.primary;
    return PopScope(
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
                    ? '${teams.length} teams · ${students.length} students. Review names, members, and leaders before creating.'
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
                    (!reviewing &&
                        (options == null ||
                            sections.isEmpty ||
                            (method == 'reuse' && sources.isEmpty)))
                ? null
                : (reviewing ? save : preview),
            icon: Icon(reviewing ? Icons.check : Icons.arrow_forward),
            label: Text(
              reviewing ? 'Create ${teams.length} teams' : 'Preview teams',
            ),
          ),
        ],
      ),
    );
  }

  Widget settings() {
    final sourceTeams = _maps(
      options?['source_teams'],
    ).where((s) => sections.contains(s['section'])).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                          event = events.firstOrNull?['event_name']?.toString();
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
        if (isPit && events.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Create a PIT event for this year level in PIT Events, then return here.',
            ),
          ),
        if (options != null) ...[
          if (isPit) ...[
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
              return FilterChip(
                label: Text(
                  '$name · ${s['eligible_count']}/${s['total_count']} available',
                ),
                selected: sections.contains(name),
                onSelected: busy || s['eligible_count'] == 0
                    ? null
                    : (selected) => setState(() {
                        selected ? sections.add(name) : sections.remove(name);
                        sources.clear();
                      }),
              );
            }).toList(),
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
                  onChanged: busy ? null : (v) => setState(() => method = v!),
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
                      initialValue: team['leader_id'] as int,
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
                          (e.value['member_ids'] as List).length < 4,
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
