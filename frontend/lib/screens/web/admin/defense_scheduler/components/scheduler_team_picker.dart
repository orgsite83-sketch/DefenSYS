import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/theme/defensys_tokens.dart';
import '../models/schedule_import_models.dart';
import 'scheduler_people_picker.dart';

/// Session membership is selected explicitly; adviser filtering is a shortcut.
class SchedulerTeamPicker extends StatefulWidget {
  const SchedulerTeamPicker({
    super.key,
    required this.teams,
    required this.selected,
    required this.assignedElsewhere,
    required this.sessionNumber,
  });

  final List<Map<String, dynamic>> teams;
  final Set<int> selected;
  final Map<int, String> assignedElsewhere;
  final int sessionNumber;

  static Future<Set<int>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> teams,
    required Set<int> selected,
    required Map<int, String> assignedElsewhere,
    required int sessionNumber,
  }) => showDialog<Set<int>>(
    context: context,
    builder: (_) => SchedulerTeamPicker(
      teams: teams,
      selected: selected,
      assignedElsewhere: assignedElsewhere,
      sessionNumber: sessionNumber,
    ),
  );

  @override
  State<SchedulerTeamPicker> createState() => _SchedulerTeamPickerState();
}

class _SchedulerTeamPickerState extends State<SchedulerTeamPicker> {
  late final Set<int> _selected = Set.of(widget.selected);
  String _query = '';
  int _adviser = 0;

  int? _adviserId(Map<String, dynamic> team) => asInt(team['adviser']);

  @override
  Widget build(BuildContext context) {
    final advisers = <int, String>{
      for (final team in widget.teams)
        if (_adviserId(team) != null)
          _adviserId(team)!: team['adviser_name']?.toString() ?? 'Adviser',
    };
    final shown = widget.teams
        .where(
          (team) =>
              (_adviser == 0 ||
                  (_adviser == -1
                      ? _adviserId(team) == null
                      : _adviserId(team) == _adviser)) &&
              '${team['name']} ${team['project_title']} ${team['adviser_name']} ${team['section']}'
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
                        'Choose teams for Session ${widget.sessionNumber}',
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
                  'Choose individual teams or select an adviser’s available advisees. Teams assigned to another session stay there.',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                const SizedBox(height: 16),
                ShadInput(
                  key: const ValueKey('session-team-search'),
                  placeholder: const Text('Search teams, projects or advisers'),
                  onChanged: (query) => setState(() => _query = query),
                ),
                if (advisers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (_, constraints) => ShadSelect<int>(
                      key: ValueKey('session-team-adviser-$_adviser'),
                      initialValue: _adviser,
                      minWidth: constraints.maxWidth,
                      maxWidth: constraints.maxWidth,
                      options: [
                        const ShadOption(value: 0, child: Text('All advisers')),
                        for (final entry in advisers.entries)
                          ShadOption(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        const ShadOption(
                          value: -1,
                          child: Text('No adviser assigned'),
                        ),
                      ],
                      selectedOptionBuilder: (_, id) => Text(
                        id == 0
                            ? 'All advisers'
                            : id == -1
                            ? 'No adviser assigned'
                            : advisers[id] ?? 'Adviser',
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: (id) => setState(() => _adviser = id ?? 0),
                    ),
                  ),
                ],
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
                        _adviser > 0 && _query.trim().isEmpty
                            ? 'Select adviser’s teams'
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
                                assigned != null
                                    ? 'Assigned to $assigned'
                                    : '${team['adviser_name'] ?? 'No adviser'}${(team['project_title']?.toString() ?? '').isEmpty ? '' : ' · ${team['project_title']}'}',
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
