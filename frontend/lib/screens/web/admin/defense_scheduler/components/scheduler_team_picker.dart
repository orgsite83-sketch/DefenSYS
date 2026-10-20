import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/theme/defensys_tokens.dart';
import '../models/schedule_import_models.dart';
import 'scheduler_people_picker.dart';

/// Session membership is explicit; section and assigned faculty narrow the list.
class SchedulerTeamPicker extends StatefulWidget {
  const SchedulerTeamPicker({
    super.key,
    required this.teams,
    required this.selected,
    required this.assignedElsewhere,
    required this.sessionNumber,
    this.scope = 'capstone',
  });

  final List<Map<String, dynamic>> teams;
  final Set<int> selected;
  final Map<int, String> assignedElsewhere;
  final int sessionNumber;
  final String scope;

  static Future<Set<int>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> teams,
    required Set<int> selected,
    required Map<int, String> assignedElsewhere,
    required int sessionNumber,
    required String scope,
  }) => showDialog<Set<int>>(
    context: context,
    builder: (_) => SchedulerTeamPicker(
      teams: teams,
      selected: selected,
      assignedElsewhere: assignedElsewhere,
      sessionNumber: sessionNumber,
      scope: scope,
    ),
  );

  @override
  State<SchedulerTeamPicker> createState() => _SchedulerTeamPickerState();
}

class _SchedulerTeamPickerState extends State<SchedulerTeamPicker> {
  late final Set<int> _selected = Set.of(widget.selected);
  String _query = '';
  int _faculty = 0;
  String _section = '';
  static const _unassignedSection = '__unassigned_section__';

  bool get _isPit => widget.scope == 'pit';

  List<Map<String, dynamic>> _facultyFor(Map<String, dynamic> team) {
    if (_isPit) {
      final people = team['instructors'];
      return people is List
          ? people
                .whereType<Map>()
                .map((person) => Map<String, dynamic>.from(person))
                .toList()
          : const [];
    }
    final id = asInt(team['adviser']);
    return id == null
        ? const []
        : [
            {'id': id, 'name': team['adviser_name']},
          ];
  }

  String _facultyName(Map<String, dynamic> team) {
    final names = _facultyFor(team)
        .map((person) => person['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .join(', ');
    if (names.isNotEmpty) return names;
    // Keep rows readable when an older response has only its display name.
    final legacy =
        team[_isPit ? 'instructor_name' : 'adviser_name']?.toString().trim() ??
        '';
    return legacy.isEmpty
        ? _isPit
              ? 'No instructor assigned'
              : 'No adviser assigned'
        : legacy;
  }

  String _sectionOf(Map<String, dynamic> team) =>
      team['section']?.toString().trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final faculty = <int, String>{
      for (final team in widget.teams)
        for (final person in _facultyFor(team))
          if (asInt(person['id']) != null)
            asInt(person['id'])!:
                person['name']?.toString() ??
                (_isPit ? 'Instructor' : 'Adviser'),
    };
    final facultyOptions = faculty.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final sections =
        widget.teams.map(_sectionOf).where((s) => s.isNotEmpty).toSet().toList()
          ..sort();
    final shown = widget.teams
        .where(
          (team) =>
              (_section.isEmpty ||
                  (_section == _unassignedSection
                      ? _sectionOf(team).isEmpty
                      : _sectionOf(team) == _section)) &&
              (_faculty == 0 ||
                  (_faculty == -1
                      ? _facultyFor(team).isEmpty
                      : _facultyFor(
                          team,
                        ).any((person) => asInt(person['id']) == _faculty))) &&
              '${team['name'] ?? ''} ${team['project_title'] ?? ''} ${_facultyName(team)} ${_sectionOf(team)}'
                  .toLowerCase()
                  .contains(_query.trim().toLowerCase()),
        )
        .toList();
    final available = {
      for (final team in shown)
        if (asInt(team['id']) != null &&
            !widget.assignedElsewhere.containsKey(asInt(team['id'])))
          asInt(team['id'])!,
    };
    final secondary = DefensysTokens.textSecondaryOf(context);
    return SchedulerShadcnScope(
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: (MediaQuery.sizeOf(context).height - 80).clamp(250, 720),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose teams for Session\u00a0${widget.sessionNumber}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close team selection',
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _isPit
                      ? 'Choose teams or filter by section and instructor. Teams assigned to another session stay there.'
                      : 'Choose teams or filter by section and adviser. Teams assigned to another session stay there.',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                const SizedBox(height: 16),
                ShadInput(
                  key: const ValueKey('session-team-search'),
                  placeholder: Text(
                    _isPit
                        ? 'Search teams or instructors'
                        : 'Search teams or advisers',
                  ),
                  onChanged: (query) => setState(() => _query = query),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (_, constraints) {
                    final showFaculty = _isPit || faculty.isNotEmpty;
                    final stacked = constraints.maxWidth < 460;
                    final width = showFaculty && !stacked
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: width,
                          child: ShadSelect<String>(
                            key: ValueKey('session-team-section-$_section'),
                            initialValue: _section,
                            minWidth: width,
                            maxWidth: width,
                            options: [
                              const ShadOption(
                                value: '',
                                child: Text('All sections'),
                              ),
                              for (final section in sections)
                                ShadOption(
                                  value: section,
                                  child: Text(section),
                                ),
                              if (widget.teams.any(
                                (team) => _sectionOf(team).isEmpty,
                              ))
                                const ShadOption(
                                  value: _unassignedSection,
                                  child: Text('No section assigned'),
                                ),
                            ],
                            selectedOptionBuilder: (_, section) => Text(
                              section.isEmpty
                                  ? 'All sections'
                                  : section == _unassignedSection
                                  ? 'No section assigned'
                                  : section,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: (value) =>
                                setState(() => _section = value ?? ''),
                          ),
                        ),
                        if (showFaculty)
                          SizedBox(
                            width: width,
                            child: ShadSelect<int>(
                              key: ValueKey(
                                'session-team-${_isPit ? 'instructor' : 'adviser'}-$_faculty',
                              ),
                              initialValue: _faculty,
                              minWidth: width,
                              maxWidth: width,
                              options: [
                                ShadOption(
                                  value: 0,
                                  child: Text(
                                    _isPit ? 'All instructors' : 'All advisers',
                                  ),
                                ),
                                for (final entry in facultyOptions)
                                  ShadOption(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                ShadOption(
                                  value: -1,
                                  child: Text(
                                    _isPit
                                        ? 'No instructor assigned'
                                        : 'No adviser assigned',
                                  ),
                                ),
                              ],
                              selectedOptionBuilder: (_, id) => Text(
                                id == 0
                                    ? _isPit
                                          ? 'All instructors'
                                          : 'All advisers'
                                    : id == -1
                                    ? _isPit
                                          ? 'No instructor assigned'
                                          : 'No adviser assigned'
                                    : faculty[id] ??
                                          (_isPit ? 'Instructor' : 'Adviser'),
                                overflow: TextOverflow.ellipsis,
                              ),
                              onChanged: (id) =>
                                  setState(() => _faculty = id ?? 0),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ShadButton.outline(
                      key: const ValueKey('session-select-shown-teams'),
                      size: ShadButtonSize.sm,
                      enabled: available.isNotEmpty,
                      onPressed: available.isEmpty
                          ? null
                          : () {
                              setState(() => _selected.addAll(available));
                            },
                      leading: const Icon(LucideIcons.listChecks, size: 14),
                      child: Text(
                        _faculty > 0 &&
                                _query.trim().isEmpty &&
                                _section.isEmpty
                            ? _isPit
                                  ? 'Select instructor’s teams'
                                  : 'Select adviser’s teams'
                            : 'Select shown teams',
                      ),
                    ),
                    ShadButton.outline(
                      key: const ValueKey('session-clear-shown-teams'),
                      size: ShadButtonSize.sm,
                      enabled: available.any(_selected.contains),
                      onPressed: available.any(_selected.contains)
                          ? () {
                              setState(() => _selected.removeAll(available));
                            }
                          : null,
                      leading: const Icon(LucideIcons.x, size: 14),
                      child: const Text('Clear shown teams'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Divider(color: DefensysTokens.borderOf(context)),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Text(
                            'No eligible teams match this selection.',
                            style: TextStyle(color: secondary),
                          ),
                        )
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (_, index) {
                            final team = shown[index],
                                id = asInt(shown[index]['id']);
                            final assigned = widget.assignedElsewhere[id];
                            return CheckboxListTile(
                              key: ValueKey('session-team-$id'),
                              activeColor: DefensysTokens.maroonOf(context),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _selected.contains(id),
                              onChanged: id == null || assigned != null
                                  ? null
                                  : (checked) => setState(() {
                                      if (checked == true) {
                                        _selected.add(id);
                                      } else {
                                        _selected.remove(id);
                                      }
                                    }),
                              title: Text(
                                team['name']?.toString() ?? 'Team',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (_sectionOf(team).isNotEmpty)
                                    _sectionOf(team),
                                  _facultyName(team),
                                  if ((team['project_title']
                                              ?.toString()
                                              .trim() ??
                                          '')
                                      .isNotEmpty)
                                    team['project_title'].toString().trim(),
                                  if (assigned != null) 'Assigned to $assigned',
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: secondary,
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Text(
                      '${_selected.length} teams selected',
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                    ShadButton(
                      key: const ValueKey('apply-session-teams'),
                      onPressed: () => Navigator.pop(context, _selected),
                      child: const Text('Use selected teams'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
