import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import '../../defense_scheduler/components/scheduler_people_picker.dart';

/// Assigns approved evaluators across confirmed stages/events in one action.
class ExternalAssignmentDialog extends ConsumerStatefulWidget {
  const ExternalAssignmentDialog({
    super.key,
    this.initialEvaluatorIds = const {},
    required this.onAddEvaluator,
    required this.onCreated,
    required this.pickExpiry,
  });
  final Set<int> initialEvaluatorIds;
  final Future<void> Function(BuildContext) onAddEvaluator;
  final Future<void> Function(BuildContext, List<Map<String, dynamic>>)
  onCreated;
  final Future<DateTime?> Function(BuildContext, DateTime) pickExpiry;
  @override
  ConsumerState<ExternalAssignmentDialog> createState() =>
      _ExternalAssignmentDialogState();
}

class _ExternalAssignmentDialogState
    extends ConsumerState<ExternalAssignmentDialog> {
  late Set<int> _evaluators;
  final Set<int> _schedules = {};
  final Set<String> _expanded = {};
  final Map<String, String> _teamQueries = {};
  String? _scope, _year;
  int? _period;
  DateTime _expiry = DateTime.now().add(const Duration(hours: 8));
  bool _customExpiry = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _evaluators = {...widget.initialEvaluatorIds};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(externalEvaluatorProvider.notifier).fetch();
    });
  }

  int _id(Map<String, dynamic> item) => (item['id'] as num).toInt();
  String _count(int count, String singular) =>
      '$count $singular${count == 1 ? '' : 's'}';
  String _sessionKey(Map<String, dynamic> item) => item['scope'] == 'pit'
      ? 'pit:${item['year_level']}:${item['event_name'] ?? item['stage_label']}'
      : 'capstone:${item['year_level']}:${item['defense_stage_id'] ?? item['stage_label']}';

  Set<int> _selectedEvaluators(ExternalEvaluatorState state) =>
      _evaluators.intersection(state.approved.map(_id).toSet());

  bool _alreadyAssigned(int scheduleId, ExternalEvaluatorState state) {
    final evaluators = _selectedEvaluators(state);
    return state.invitations.any(
      (invitation) =>
          evaluators.contains(invitation['evaluator_id']) &&
          (invitation['schedule_ids'] as List? ?? []).contains(scheduleId),
    );
  }

  DateTime _defaultExpiry(Iterable<Map<String, dynamic>> schedules) {
    var result = DateTime.now().add(const Duration(hours: 8));
    for (final schedule in schedules) {
      final date = DateTime.tryParse(schedule['date'].toString());
      if (date == null) continue;
      final parts = (schedule['start_time'] ?? '00:00').toString().split(':');
      final end =
          DateTime(
            date.year,
            date.month,
            date.day,
            int.tryParse(parts.first) ?? 0,
            parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
          ).add(
            Duration(
              minutes: (schedule['slot_duration'] as num?)?.toInt() ?? 60,
            ),
          );
      final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
      if (endOfDay.isAfter(result)) result = endOfDay;
    }
    return result;
  }

  void _toggle(Iterable<Map<String, dynamic>> schedules, bool selected) {
    final state = ref.read(externalEvaluatorProvider);
    setState(() {
      for (final schedule in schedules) {
        if (_alreadyAssigned(_id(schedule), state)) continue;
        selected
            ? _schedules.add(_id(schedule))
            : _schedules.remove(_id(schedule));
      }
      if (!_customExpiry) {
        _expiry = _defaultExpiry(
          state.schedules.where((s) => _schedules.contains(_id(s))),
        );
      }
      _error = null;
    });
  }

  void _changeContext(VoidCallback change) => setState(() {
    change();
    _schedules.clear();
    _expanded.clear();
    _teamQueries.clear();
    _error = null;
    if (!_customExpiry) _expiry = _defaultExpiry([]);
  });

  Future<void> _addEvaluator() async {
    final before = ref
        .read(externalEvaluatorProvider)
        .approved
        .map(_id)
        .toSet();
    await widget.onAddEvaluator(context);
    if (!mounted) return;
    final added = ref
        .read(externalEvaluatorProvider)
        .approved
        .map(_id)
        .toSet()
        .difference(before);
    if (added.length == 1) setState(() => _evaluators.add(added.single));
  }

  Future<void> _create(List<Map<String, dynamic>> schedules) async {
    if (_busy) return;
    final state = ref.read(externalEvaluatorProvider);
    final evaluators = _selectedEvaluators(state);
    if (evaluators.isEmpty || schedules.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(externalEvaluatorProvider.notifier)
        .invite(
          evaluators.toList()..sort(),
          schedules.map(_id).toList()..sort(),
          _expiry,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error =
            ref.read(externalEvaluatorProvider).error ??
            'Unable to assign evaluators. Try again.';
      });
      return;
    }
    final invitations = ref.read(externalEvaluatorProvider).createdInvitations;
    final navigator = Navigator.of(context);
    navigator.pop();
    await widget.onCreated(navigator.context, invitations);
  }

  Widget _section(String number, String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DefensysTokens.panelOf(context),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            number,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _select<T>({
    required String label,
    required T value,
    required Map<T, String> options,
    required ValueChanged<T?> onChanged,
    required bool enabled,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 8),
      ShadSelect<T>(
        initialValue: value,
        enabled: enabled,
        options: options.entries
            .map(
              (entry) => ShadOption(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        selectedOptionBuilder: (_, value) => Text(
          options[value] ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onChanged: onChanged,
      ),
    ],
  );

  Widget _sessionCard(
    String key,
    List<Map<String, dynamic>> schedules,
    Set<int> selected,
    ExternalEvaluatorState state,
    bool enabled,
  ) {
    final available = schedules
        .where((s) => !_alreadyAssigned(_id(s), state))
        .toList();
    final count = available.where((s) => selected.contains(_id(s))).length;
    final expanded = _expanded.contains(key);
    final query = (_teamQueries[key] ?? '').trim().toLowerCase();
    final teams = schedules
        .where(
          (s) => '${s['team_name']} ${s['room']}'.toLowerCase().contains(query),
        )
        .toList();
    final dates = schedules.map((s) => s['date'].toString()).toSet().toList()
      ..sort();
    final first = DateTime.tryParse(dates.first);
    final last = DateTime.tryParse(dates.last);
    final dateLabel = first == null
        ? dates.first
        : '${DateFormat('MMM d').format(first)}${last == null || first == last ? '' : ' – ${DateFormat('MMM d').format(last)}'}';
    final title = schedules.first['stage_label'].toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ShadCheckbox(
                  key: ValueKey('session-$key'),
                  enabled: enabled && available.isNotEmpty,
                  value: count > 0,
                  icon: count < available.length && count > 0
                      ? const Icon(LucideIcons.minus, size: 12)
                      : null,
                  onChanged: (_) =>
                      _toggle(available, count < available.length),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() {
                      expanded ? _expanded.remove(key) : _expanded.add(key);
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${schedules.first['year_level']} · $dateLabel · ${_count(schedules.length, 'team')}${count > 0 ? ' · $count selected' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Choose teams',
                  child: ShadButton.ghost(
                    key: ValueKey('expand-$key'),
                    size: ShadButtonSize.sm,
                    onPressed: () => setState(() {
                      expanded ? _expanded.remove(key) : _expanded.add(key);
                    }),
                    child: Icon(
                      expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: DefensysTokens.borderOf(context)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ShadInput(
                    key: ValueKey('search-$key'),
                    placeholder: const Text('Search teams'),
                    leading: const Icon(LucideIcons.search, size: 15),
                    onChanged: (value) =>
                        setState(() => _teamQueries[key] = value),
                  ),
                  const SizedBox(height: 10),
                  if (teams.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No matching teams.'),
                    ),
                  for (final schedule in teams)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShadCheckbox(
                            key: ValueKey('defense-${_id(schedule)}'),
                            enabled:
                                enabled &&
                                !_alreadyAssigned(_id(schedule), state),
                            value: selected.contains(_id(schedule)),
                            onChanged: (on) => _toggle([schedule], on),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  schedule['team_name'].toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${schedule['date']} · ${schedule['start_time']?.toString().split(':').take(2).join(':') ?? ''} · ${schedule['room']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DefensysTokens.textSecondaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                                if (_alreadyAssigned(_id(schedule), state))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Already assigned · manage their access in Invitations',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: DefensysTokens.textSecondaryOf(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(externalEvaluatorProvider);
    final availableScopes = state.canApprove
        ? {'capstone': 'Capstone', 'pit': 'PIT'}
        : {'pit': 'PIT'};
    final scopesWithSchedules = state.schedules
        .map((s) => s['scope'].toString())
        .toSet();
    final scope =
        _scope ??
        (!state.canApprove
            ? 'pit'
            : scopesWithSchedules.contains('capstone')
            ? 'capstone'
            : scopesWithSchedules.contains('pit')
            ? 'pit'
            : 'capstone');
    final scopeSchedules = state.schedules
        .where((s) => s['scope'] == scope)
        .toList();
    final periods = <int, String>{
      for (final s in scopeSchedules)
        (s['semester_id'] as num).toInt():
            s['display_semester']?.toString() ?? 'Academic period',
    };
    final periodIds = periods.keys.toList()..sort((a, b) => b.compareTo(a));
    final period = periods.containsKey(_period)
        ? _period
        : periods.containsKey(state.activeSemesterId)
        ? state.activeSemesterId
        : periodIds.firstOrNull;
    final years =
        scopeSchedules
            .where((s) => s['semester_id'] == period)
            .map((s) => s['year_level']?.toString() ?? '')
            .toSet()
            .toList()
          ..sort();
    final year = _year == 'all' || (years.length > 1 && _year == null)
        ? 'all'
        : years.contains(_year)
        ? _year
        : years.firstOrNull;
    final candidates = scopeSchedules
        .where(
          (s) =>
              s['semester_id'] == period &&
              (year == 'all' || (s['year_level']?.toString() ?? '') == year),
        )
        .toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final schedule in candidates) {
      groups.putIfAbsent(_sessionKey(schedule), () => []).add(schedule);
    }
    final evaluators = _selectedEvaluators(state);
    final selected = _schedules.intersection(
      candidates
          .where((s) => !_alreadyAssigned(_id(s), state))
          .map(_id)
          .toSet(),
    );
    final selectedSchedules = candidates
        .where((s) => selected.contains(_id(s)))
        .toList();
    final sessionCount = selectedSchedules.map(_sessionKey).toSet().length;
    final enabled = !state.saving && !state.loading && !_busy;
    final evaluatorNames = state.approved
        .where((person) => evaluators.contains(_id(person)))
        .map((person) => person['name'].toString())
        .join(', ');
    final valid =
        evaluators.isNotEmpty &&
        selected.isNotEmpty &&
        _expiry.isAfter(DateTime.now());
    final sessionWord = scope == 'pit' ? 'events' : 'stages';
    return DefensysShadcnScope(
      child: Dialog(
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: DefensysTokens.surfaceOf(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
        child: SizedBox(
          width: 860,
          height: (MediaQuery.sizeOf(context).height * .88).clamp(0, 780),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;
              final padding = narrow ? 16.0 : 24.0;
              return Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Assign external evaluators',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                evaluatorNames.isEmpty
                                    ? 'Assign teams across stages or PIT events, then share evaluator access.'
                                    : 'Evaluators: $evaluatorNames',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: DefensysTokens.textSecondaryOf(
                                    context,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'Close',
                          child: ShadButton.ghost(
                            size: ShadButtonSize.sm,
                            onPressed: enabled
                                ? () => Navigator.pop(context)
                                : null,
                            child: const Icon(LucideIcons.x, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (state.loading)
                      const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _section(
                              '1',
                              'Choose evaluators',
                              'Every selected evaluator receives the same defense assignments.',
                            ),
                            SchedulerPeoplePicker(
                              key: const ValueKey('assignment-evaluators'),
                              people: state.approved,
                              selected: evaluators,
                              placeholder: 'Select external evaluators',
                              searchPlaceholder: 'Search name or institution',
                              emptyMessage:
                                  'No approved evaluators. Add an evaluator to begin.',
                              enabled: enabled,
                              detailBuilder: (person) =>
                                  person['institution']?.toString(),
                              onChanged: (ids) => setState(() {
                                _evaluators = ids;
                                _schedules.removeWhere(
                                  (id) => _alreadyAssigned(id, state),
                                );
                                _error = null;
                              }),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ShadButton.ghost(
                                size: ShadButtonSize.sm,
                                onPressed: enabled ? _addEvaluator : null,
                                leading: const Icon(LucideIcons.plus, size: 14),
                                child: const Text('Add evaluator'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            _section(
                              '2',
                              'Choose $sessionWord and teams',
                              'Check a ${scope == 'pit' ? 'PIT event' : 'stage'} for all its teams. Expand it to choose specific teams.',
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: ShadTabs<String>(
                                value: scope,
                                gap: 0,
                                onChanged: (value) => _changeContext(() {
                                  _scope = value;
                                  _period = null;
                                  _year = null;
                                }),
                                tabs: availableScopes.entries
                                    .map(
                                      (entry) => ShadTab(
                                        value: entry.key,
                                        enabled: enabled,
                                        child: Flexible(
                                          child: Text(
                                            entry.value,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (period != null) ...[
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width: narrow
                                        ? constraints.maxWidth - padding * 2
                                        : 440,
                                    child: _select<int>(
                                      label: 'Academic period',
                                      value: period,
                                      options: {
                                        for (final id in periodIds)
                                          id: periods[id]!,
                                      },
                                      enabled: enabled,
                                      onChanged: (value) => _changeContext(() {
                                        _period = value;
                                        _year = null;
                                      }),
                                    ),
                                  ),
                                  if (years.length > 1 &&
                                      year != null &&
                                      year.isNotEmpty)
                                    SizedBox(
                                      width: narrow
                                          ? constraints.maxWidth - padding * 2
                                          : 180,
                                      child: _select<String>(
                                        label: 'Year level',
                                        value: year,
                                        options: {
                                          if (years.length > 1)
                                            'all': 'All year levels',
                                          for (final year in years) year: year,
                                        },
                                        enabled: enabled,
                                        onChanged: (value) =>
                                            _changeContext(() => _year = value),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (groups.isNotEmpty) ...[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ShadButton.outline(
                                    key: const ValueKey('select-all-sessions'),
                                    size: ShadButtonSize.sm,
                                    onPressed: enabled
                                        ? () => _toggle(candidates, true)
                                        : null,
                                    leading: const Icon(
                                      LucideIcons.listChecks,
                                      size: 14,
                                    ),
                                    child: Text('Select all $sessionWord'),
                                  ),
                                  if (selected.isNotEmpty)
                                    ShadButton.ghost(
                                      size: ShadButtonSize.sm,
                                      onPressed: enabled
                                          ? () => _toggle(candidates, false)
                                          : null,
                                      child: const Text('Clear selection'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              for (final entry in groups.entries)
                                _sessionCard(
                                  entry.key,
                                  entry.value,
                                  selected,
                                  state,
                                  enabled,
                                ),
                            ] else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Text(
                                  'No confirmed $sessionWord for this selection. Confirm schedules to make them available here.',
                                  style: TextStyle(
                                    color: DefensysTokens.textSecondaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            _section(
                              '3',
                              'Access expiry',
                              'Each stage or event gets a separate access link for every evaluator.',
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ShadButton.outline(
                                onPressed: enabled
                                    ? () async {
                                        final expiry = await widget.pickExpiry(
                                          context,
                                          _expiry,
                                        );
                                        if (expiry != null && mounted) {
                                          setState(() {
                                            _expiry = expiry;
                                            _customExpiry = true;
                                          });
                                        }
                                      }
                                    : null,
                                leading: const Icon(
                                  LucideIcons.clock,
                                  size: 16,
                                ),
                                child: Flexible(
                                  child: Text(
                                    DateFormat(
                                      'MMM d, y · h:mm a',
                                    ).format(_expiry),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _customExpiry
                                  ? 'Custom expiry. Access must cover the final assigned defense.'
                                  : 'Automatically follows the latest selected defense.',
                              style: TextStyle(
                                fontSize: 12,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                            if (_customExpiry)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ShadButton.ghost(
                                  size: ShadButtonSize.sm,
                                  onPressed: enabled
                                      ? () => setState(() {
                                          _customExpiry = false;
                                          _expiry = _defaultExpiry(
                                            selectedSchedules,
                                          );
                                        })
                                      : null,
                                  child: const Text('Use automatic expiry'),
                                ),
                              ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null || state.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error ?? state.error!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: DefensysTokens.borderOf(context)),
                    const SizedBox(height: 16),
                    Text(
                      '${_count(evaluators.length, 'evaluator')} · ${_count(selected.length, 'defense')} · ${_count(sessionCount, scope == 'pit' ? 'event' : 'stage')}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Creates ${_count(evaluators.length * sessionCount, 'access link')}. Copy and share them after assigning.',
                      style: TextStyle(
                        color: DefensysTokens.textSecondaryOf(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ShadButton.outline(
                            onPressed: enabled
                                ? () => Navigator.pop(context)
                                : null,
                            child: const Flexible(
                              child: Text(
                                'Cancel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: narrow ? 2 : 3,
                          child: ShadButton(
                            key: const ValueKey('confirm-external-assignments'),
                            enabled: enabled && valid && !state.loading,
                            onPressed: enabled && valid && !state.loading
                                ? () => _create(selectedSchedules)
                                : null,
                            leading: const Icon(LucideIcons.userPlus, size: 16),
                            child: Flexible(
                              child: Text(
                                _busy || state.saving
                                    ? 'Assigning…'
                                    : 'Assign evaluators',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
