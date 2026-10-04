import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/defense_board_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../../widgets/shadcn/defensys_workflow_widgets.dart';
import '../../../../../widgets/feedback/defensys_loading.dart';
import 'schedule_manager_dialog.dart';

Future<void> showScheduleOperationsDialog(
  BuildContext context,
  Map<String, dynamic> schedule, {
  String target = 'schedule',
  String tab = 'panel',
}) => showScheduleManager(
  context,
  schedule: schedule,
  scope: target == 'selected'
      ? 'selected'
      : target == 'stage_selected'
      ? 'stage'
      : target,
  action: tab == 'delete'
      ? 'delete'
      : const [
          'status',
          'paused',
          'postponed',
          'no_show',
          'cancelled',
          'normal',
        ].contains(tab)
      ? 'status'
      : 'edit',
  tab: tab == 'edit' || tab == 'assignments'
      ? 'panel'
      : tab == 'timetable'
      ? 'time'
      : tab,
);

/// Group editors share tabs. Saving changes only the selected tab and scope.
class ScheduleOperationsDialog extends ConsumerStatefulWidget {
  const ScheduleOperationsDialog({
    super.key,
    required this.schedule,
    required this.target,
    required this.tab,
  });
  final Map<String, dynamic> schedule;
  final String target, tab;
  @override
  ConsumerState<ScheduleOperationsDialog> createState() =>
      _ScheduleOperationsDialogState();
}

class _ScheduleOperationsDialogState
    extends ConsumerState<ScheduleOperationsDialog> {
  late String _task = widget.tab == 'edit' || widget.tab == 'assignments'
      ? 'panel'
      : widget.tab == 'timetable'
      ? 'time'
      : widget.tab;
  final _reason = TextEditingController();
  late final _room = TextEditingController(
    text: '${widget.schedule['room'] ?? ''}',
  );
  late final _time = TextEditingController(
    text: _shortTime(widget.schedule['start_time']),
  );
  final _shift = TextEditingController(text: '30');
  late DateTime? _date = DateTime.tryParse(
    '${widget.schedule['scheduled_date']}',
  );
  late final Set<int> _originalPanels = _ids(widget.schedule['panelist_ids']);
  late final Set<int> _panels = {..._originalPanels};
  late final Set<int> _originalExternals =
      _maps(widget.schedule['external_evaluators'])
          .where((p) => p['is_active'] != false)
          .map((p) => _id(p['id']))
          .whereType<int>()
          .toSet();
  late final Set<int> _externals = {..._originalExternals};
  late bool _showExternals = _externals.isNotEmpty;
  late final int? _originalChair = _maps(widget.schedule['panelists'])
      .where((p) => p['is_chair'] == true)
      .map((p) => _id(p['id'] ?? p['panelist_id']))
      .firstOrNull;
  late int? _chair = _originalChair;
  late int? _documenter = _id(widget.schedule['documenter']);
  final Set<int> _selected = {};
  Map<String, dynamic>? _preview;
  Map<String, dynamic> _options = {};
  bool _busy = true,
      _review = false,
      _emptyOnly = false,
      _chooseDefenses = false,
      _minutesAmendment = false;
  String _shiftDirection = 'later';
  late String _state =
      const [
        'paused',
        'postponed',
        'no_show',
        'cancelled',
        'normal',
      ].contains(_task)
      ? _task
      : '${widget.schedule['operation_state'] ?? 'normal'}';
  String? _error;

  static int? _id(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  static String _shortTime(dynamic value) {
    final text = '${value ?? '08:00'}';
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  static Set<int> _ids(dynamic value) =>
      (value is List ? value : []).map(_id).whereType<int>().toSet();
  static List<Map<String, dynamic>> _maps(dynamic value) =>
      (value is List ? value : [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
  bool get _deleting => _task == 'delete';
  bool get _tabbed => widget.tab == 'edit';
  bool get _stage =>
      widget.target == 'stage' || widget.target == 'stage_selected';
  bool get _bulk => widget.target != 'schedule';
  bool get _selectionRequired =>
      const ['selected', 'stage_selected'].contains(widget.target) ||
      (_bulk && !_deleting);
  bool _eligible(Map<String, dynamic> entry) =>
      _deleting ||
      entry['can_edit'] != false &&
          (entry['status'] == 'scheduled' ||
              (_task == 'normal' || _task == 'status' && _state == 'normal') &&
                  entry['status'] == 'cancelled') &&
          (!const ['room', 'time'].contains(_task) ||
              entry['can_reschedule'] != false);
  List<Map<String, dynamic>> get _entries => _maps(_preview?['entries']);
  List<Map<String, dynamic>> get _affected => _entries
      .where(
        (entry) => !_selectionRequired || _selected.contains(_id(entry['id'])),
      )
      .toList();
  int get _empty =>
      _affected.where((entry) => entry['can_delete'] == true).length;
  int get _protected => _affected.length - _empty;
  Set<int> get _lockedPanels => {
    for (final entry in _affected) ..._ids(entry['submitted_panelist_ids']),
  };
  Set<int> get _lockedExternals => {
    for (final entry in _affected)
      ..._ids(entry['submitted_external_evaluator_ids']),
  };
  bool get _requiresNewSignatures =>
      _affected.any((entry) => entry['minutes_requires_amendment'] == true) &&
      const ['panel', 'external', 'documenter', 'room', 'time'].contains(_task);
  String get _scopeName => _stage
      ? 'this stage'
      : _bulk
      ? 'this session'
      : 'this defense';
  String get _groupLabel => _stage
      ? 'stage'
      : _bulk
      ? 'session'
      : 'defense';
  String get _title => _tabbed
      ? 'Edit ${_stage
            ? 'stage schedules'
            : _bulk
            ? 'session'
            : 'defense'}'
      : switch (_task) {
          'panel' => 'Edit panel',
          'external' => 'Edit external evaluators',
          'documenter' => 'Change documenter',
          'room' => 'Change room',
          'time' => _bulk ? 'Adjust $_groupLabel times' : 'Reschedule defense',
          'delete' =>
            'Delete ${_stage
                ? 'stage schedules'
                : _bulk
                ? 'session schedules'
                : 'schedule'}',
          'paused' => 'Pause $_groupLabel',
          'normal' => 'Resume $_groupLabel',
          'postponed' => 'Postpone $_groupLabel',
          'no_show' => 'Mark as no-show',
          'cancelled' => 'Cancel $_groupLabel',
          _ => 'Change $_groupLabel status',
        };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_reason, _room, _time, _shift]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _review = false;
    });
    try {
      final notifier = ref.read(defenseBoardProvider.notifier);
      final results = await Future.wait([
        notifier.operation({
          'action': 'preview_delete',
          'target': _stage
              ? 'stage'
              : widget.target == 'selected'
              ? 'session'
              : widget.target,
          'anchor_id': widget.schedule['id'],
        }),
        if (_tabbed ||
            const ['panel', 'external', 'documenter'].contains(_task))
          notifier.operationOptions(),
      ]);
      if (!mounted) return;
      setState(() {
        _preview = results[0];
        if (results.length > 1) _options = results[1];
        _selected.clear();
        for (final entry in _entries) {
          if (_eligible(entry)) {
            _selected.add(_id(entry['id'])!);
          }
        }
        if (_bulk && _task == 'panel') {
          _panels.addAll(_lockedPanels);
          _externals.addAll(_lockedExternals);
          if (_externals.isNotEmpty) _showExternals = true;
        }
        _chooseDefenses = const [
          'selected',
          'stage_selected',
        ].contains(widget.target);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  bool _same(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  void _switchTask(String task) => setState(() {
    _task = task;
    _review = false;
    _error = null;
    _reason.clear();
    _minutesAmendment = false;
    _selected.removeWhere(
      (id) =>
          !_entries.any((entry) => _id(entry['id']) == id && _eligible(entry)),
    );
    if (!_chooseDefenses) {
      _selected.addAll(
        _entries.where(_eligible).map((entry) => _id(entry['id'])!),
      );
    }
    if (_task == 'panel') {
      _panels.addAll(_lockedPanels);
      _externals.addAll(_lockedExternals);
      if (_externals.isNotEmpty) _showExternals = true;
    }
  });

  Widget _editTabs() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ShadTabs<String>(
        value: _task,
        scrollable: true,
        tabBarAlignment: Alignment.centerLeft,
        onChanged: _switchTask,
        gap: 0,
        tabs: [
          for (final entry in {
            'panel': 'Panel',
            if (widget.schedule['scope'] != 'pit') 'documenter': 'Documenter',
            'room': 'Room',
            'time': 'Time',
          }.entries)
            ShadTab(
              value: entry.key,
              enabled: !_busy,
              content: const SizedBox.shrink(),
              child: Text(entry.value),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Only the current tab’s changes will be saved.',
        style: TextStyle(
          fontSize: 12,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 16),
    ],
  );
  Map<String, dynamic> _changes() {
    final changes = <String, dynamic>{};
    if (_task == 'panel' &&
        (_bulk ||
            !_same(_panels, _originalPanels) ||
            _chair != _originalChair)) {
      changes.addAll({
        'panelist_ids': _panels.toList(),
        'chair_panelist_id': _chair,
      });
    }
    if (const ['panel', 'external'].contains(_task) &&
        ((_bulk && _task == 'external') ||
            !_same(_externals, _originalExternals))) {
      changes['external_evaluator_ids'] = _externals.toList();
    }
    if (_task == 'documenter' &&
        (_bulk || _documenter != _id(widget.schedule['documenter']))) {
      changes['documenter_id'] = _documenter;
    }
    if (_task == 'room' &&
        (_bulk || _room.text.trim() != widget.schedule['room'])) {
      changes['room'] = _room.text.trim();
    }
    if (_task == 'time') {
      if (_bulk) {
        changes['shift_minutes'] =
            (int.tryParse(_shift.text.trim()) ?? 0) *
            (_shiftDirection == 'earlier' ? -1 : 1);
      } else {
        final date = _date == null
            ? ''
            : DateFormat('yyyy-MM-dd').format(_date!);
        if (date != widget.schedule['scheduled_date']) {
          changes['scheduled_date'] = date;
        }
        if (_time.text.trim() != _shortTime(widget.schedule['start_time'])) {
          changes['start_time'] = _time.text.trim();
        }
      }
    }
    if (const [
      'status',
      'paused',
      'normal',
      'postponed',
      'no_show',
      'cancelled',
    ].contains(_task)) {
      if (_state == 'cancelled') {
        changes['status'] = 'cancelled';
      } else {
        changes['operation_state'] = _state;
        if (_state == 'normal') {
          changes['status'] = 'scheduled';
        }
      }
    }
    if (_minutesAmendment && changes.isNotEmpty) {
      changes['acknowledge_minutes_amendment'] = true;
    }
    return changes;
  }

  Future<void> _save() async {
    if (_task == 'panel' && _panels.isNotEmpty && !_panels.contains(_chair)) {
      setState(() => _error = 'Choose a chair from the faculty panel.');
      return;
    }
    if (const ['panel', 'external'].contains(_task) &&
        _panels.isEmpty &&
        _externals.isEmpty) {
      setState(() => _error = 'Keep at least one evaluator assigned.');
      return;
    }
    if (_reason.text.trim().length < 5) {
      setState(
        () => _error =
            'Tell us why this change is needed. This will be saved in the audit trail.',
      );
      return;
    }
    final changes = _changes();
    if (!_deleting &&
        (changes.isEmpty ||
            (_task == 'time' && _bulk && changes['shift_minutes'] == 0))) {
      setState(() => _error = 'Make a change before continuing.');
      return;
    }
    if (_task == 'time' &&
        !_bulk &&
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(_time.text.trim())) {
      setState(() => _error = 'Enter a valid time, such as 08:30 or 13:00.');
      return;
    }
    if (_task == 'time' &&
        _bulk &&
        (int.tryParse(_shift.text.trim()) == null ||
            int.parse(_shift.text.trim()) < 1 ||
            int.parse(_shift.text.trim()) > 1440)) {
      setState(() => _error = 'Enter a number of minutes between 1 and 1440.');
      return;
    }
    if (_task == 'room' && _room.text.trim().isEmpty) {
      setState(() => _error = 'Enter the new room.');
      return;
    }
    if (_requiresNewSignatures && !_minutesAmendment) {
      setState(
        () => _error =
            'Confirm that the amended minutes will need new signatures. The signed version will be kept.',
      );
      return;
    }
    if (!_review) {
      setState(() {
        _review = true;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final revisions = Map<String, dynamic>.from(
        _preview!['expected_revisions'],
      );
      if (_selectionRequired) {
        revisions.removeWhere((id, _) => !_selected.contains(int.parse(id)));
      }
      await ref.read(defenseBoardProvider.notifier).operation({
        'action': _deleting ? 'delete' : 'update',
        'target': _selectionRequired
            ? _stage
                  ? 'stage_selected'
                  : 'selected'
            : widget.target,
        'anchor_id': widget.schedule['id'],
        if (_selectionRequired) 'schedule_ids': _selected.toList(),
        'expected_revisions': revisions,
        'reason': _reason.text.trim(),
        'empty_only': _emptyOnly,
        if (!_deleting) 'changes': changes,
      });
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _review = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _person(int? id, String pool) {
    if (id == null) return 'Unassigned';
    final options = [
      ..._maps(_options[pool]),
      ..._maps(
        widget.schedule[pool == 'panelists'
            ? 'panelists'
            : 'external_evaluators'],
      ),
    ];
    return options
            .where((person) => _id(person['id']) == id)
            .firstOrNull?['name']
            ?.toString() ??
        'Previously assigned person';
  }

  Widget _input(
    String label,
    TextEditingController controller, {
    String? helper,
    String? hint,
    String? key,
    bool numeric = false,
  }) => WorkflowField(
    label: label,
    helper: helper,
    child: ShadInput(
      key: key == null ? null : ValueKey(key),
      controller: controller,
      enabled: !_busy,
      keyboardType: numeric ? TextInputType.number : null,
      placeholder: hint == null ? null : Text(hint),
    ),
  );

  Widget _people(
    String heading,
    String pool,
    Set<int> selected,
    Set<int> locked,
  ) {
    final unavailable = {
      for (final entry in _affected)
        if (_id(entry['adviser_id']) != null) _id(entry['adviser_id'])!,
      for (final entry in _affected)
        if (_id(entry['documenter_id']) != null) _id(entry['documenter_id'])!,
      if (_id(widget.schedule['documenter']) != null)
        _id(widget.schedule['documenter'])!,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          heading,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (selected.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'None assigned',
              style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
            ),
          ),
        for (final id in selected)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            decoration: BoxDecoration(
              border: Border.all(color: DefensysTokens.borderOf(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  pool == 'panelists'
                      ? LucideIcons.userRound
                      : LucideIcons.globe,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_person(id, pool)),
                      if (locked.contains(id))
                        Text(
                          'Evaluation submitted · assignment kept',
                          style: TextStyle(
                            fontSize: 11,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                    ],
                  ),
                ),
                if (pool == 'panelists' && id == _chair)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Chair',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Tooltip(
                  message: locked.contains(id)
                      ? 'This panelist has submitted scores. Their assignment must be kept.'
                      : 'Remove ${_person(id, pool)}',
                  child: ShadButton.ghost(
                    width: 32,
                    height: 32,
                    padding: EdgeInsets.zero,
                    enabled: !_busy && !locked.contains(id),
                    onPressed: _busy || locked.contains(id)
                        ? null
                        : () => setState(() {
                            selected.remove(id);
                            if (!_panels.contains(_chair)) {
                              _chair = _panels.firstOrNull;
                            }
                          }),
                    child: const Icon(LucideIcons.x, size: 15),
                  ),
                ),
              ],
            ),
          ),
        WorkflowSelect(
          key: ValueKey('add-$pool-${selected.join('-')}'),
          label: pool == 'panelists'
              ? 'Add panelist'
              : 'Add external evaluator',
          placeholder: pool == 'panelists'
              ? 'Search and add a panelist'
              : 'Search approved external evaluators',
          enabled: !_busy,
          options: {
            for (final person in _maps(_options[pool]))
              if (!selected.contains(_id(person['id'])) &&
                  (pool != 'panelists' ||
                      !unavailable.contains(_id(person['id']))))
                '${person['id']}': '${person['name']}',
          },
          onChanged: (value) => setState(() {
            selected.add(int.parse(value));
            _chair ??= _panels.firstOrNull;
          }),
        ),
      ],
    );
  }

  Widget _scope() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _bulk
            ? '${_affected.length} ${_affected.length == 1 ? 'defense' : 'defenses'} in $_scopeName will be ${_deleting ? 'reviewed for deletion' : 'updated'}.'
            : '${widget.schedule['room']} · ${_shortTime(widget.schedule['start_time'])}',
        style: TextStyle(
          fontSize: 12,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      if (_stage)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Applies across all sessions in this stage for the active semester. Search and table filters do not limit this action.',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
      if (_stage && _affected.any((entry) => entry['session_id'] != null))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${_affected.map((entry) => entry['session_id']).whereType<String>().toSet().length} ${_affected.map((entry) => entry['session_id']).whereType<String>().toSet().length == 1 ? 'session' : 'sessions'} affected',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      if (_bulk && _selectionRequired) ...[
        ShadButton.ghost(
          enabled: !_busy,
          onPressed: _busy
              ? null
              : () => setState(() => _chooseDefenses = !_chooseDefenses),
          mainAxisAlignment: MainAxisAlignment.start,
          padding: EdgeInsets.zero,
          child: Text(
            _chooseDefenses
                ? 'Hide defense selection'
                : 'Choose which defenses…',
          ),
        ),
        if (_chooseDefenses)
          ..._entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ShadCheckbox(
                value: _selected.contains(_id(entry['id'])),
                enabled: !_busy && _eligible(entry),
                onChanged: (value) => setState(() {
                  value
                      ? _selected.add(_id(entry['id'])!)
                      : _selected.remove(_id(entry['id']));
                  if (_task == 'panel') {
                    _panels.addAll(_lockedPanels);
                    _externals.addAll(_lockedExternals);
                  }
                }),
                label: Text(
                  '${entry['team_name']} · ${_stage ? '${entry['date']} · ' : ''}${_shortTime(entry['start_time'])}',
                ),
              ),
            ),
          ),
        if (_entries.any((entry) => !_eligible(entry)))
          const Text(
            'Completed defenses and records that cannot be changed are excluded.',
            style: TextStyle(fontSize: 12),
          ),
      ],
      const SizedBox(height: 16),
    ],
  );

  List<Widget> _form() => [
    if (_task == 'panel') ...[
      if (_bulk)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('This panel will be assigned to the selected defenses.'),
        ),
      _people('Faculty panel', 'panelists', _panels, _lockedPanels),
      if (_panels.length > 1)
        WorkflowSelect(
          label: 'Panel chair',
          value: _chair?.toString(),
          enabled: !_busy,
          options: {for (final id in _panels) '$id': _person(id, 'panelists')},
          onChanged: (value) => setState(() => _chair = int.parse(value)),
        ),
      ShadButton.ghost(
        key: const ValueKey('external-panel-section'),
        enabled: !_busy,
        mainAxisAlignment: MainAxisAlignment.start,
        padding: EdgeInsets.zero,
        leading: Icon(
          _showExternals ? LucideIcons.chevronDown : LucideIcons.chevronRight,
          size: 16,
        ),
        onPressed: _busy
            ? null
            : () => setState(() => _showExternals = !_showExternals),
        child: Text(
          'External evaluators${_externals.isEmpty ? ' (optional)' : ' (${_externals.length})'}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      if (_showExternals)
        _people(
          'External panel',
          'external_evaluators',
          _externals,
          _lockedExternals,
        ),
    ],
    if (_task == 'external')
      _people(
        'External evaluators',
        'external_evaluators',
        _externals,
        _lockedExternals,
      ),
    if (_task == 'documenter') ...[
      Text(
        'Current documenter: ${widget.schedule['documenter_name'] ?? 'Unassigned'}',
      ),
      const SizedBox(height: 12),
      WorkflowSelect(
        label: 'New documenter',
        value: _documenter?.toString() ?? '',
        enabled: !_busy,
        options: {
          '': 'Unassigned',
          for (final person in _maps(_options['faculty']))
            if (!_affected.any(
              (entry) =>
                  _id(entry['adviser_id']) == _id(person['id']) ||
                  _ids(entry['panelist_ids']).contains(_id(person['id'])),
            ))
              '${person['id']}': '${person['name']}',
        },
        onChanged: (value) => setState(() => _documenter = int.tryParse(value)),
      ),
    ],
    if (_task == 'room')
      _input(
        'New room',
        _room,
        hint: 'For example: Room 301',
        key: 'schedule-room',
      ),
    if (_task == 'time' && !_bulk) ...[
      WorkflowField(
        label: 'Defense date',
        child: ShadDatePicker(
          selected: _date,
          enabled: !_busy,
          closeOnSelection: true,
          allowDeselection: false,
          formatDate: (date) => DateFormat('MMM d, y').format(date),
          onChanged: (value) => setState(() => _date = value),
        ),
      ),
      _input(
        'Start time',
        _time,
        helper: 'Use 24-hour time, such as 08:30 or 13:00.',
        key: 'schedule-start-time',
      ),
    ],
    if (_task == 'time' && _bulk) ...[
      WorkflowSelect(
        label: 'Move selected defenses',
        value: _shiftDirection,
        searchable: false,
        enabled: !_busy,
        options: const {'later': 'Later', 'earlier': 'Earlier'},
        onChanged: (value) => setState(() => _shiftDirection = value),
      ),
      _input(
        'By how many minutes?',
        _shift,
        numeric: true,
        key: 'schedule-shift-minutes',
        helper: 'Spacing between defenses stays the same.',
      ),
    ],
    if (_task == 'status')
      WorkflowSelect(
        label: 'New status',
        enabled: !_busy,
        value: _state,
        searchable: false,
        options: const {
          'paused': 'Paused',
          'normal': 'Resume',
          'postponed': 'Postponed',
          'no_show': 'No-show',
          'cancelled': 'Cancelled',
        },
        onChanged: (value) => setState(() {
          _state = value;
          _selected.removeWhere(
            (id) => !_entries.any(
              (entry) => _id(entry['id']) == id && _eligible(entry),
            ),
          );
          if (!_chooseDefenses) {
            _selected.addAll(
              _entries.where(_eligible).map((entry) => _id(entry['id'])!),
            );
          }
        }),
      ),
    if (const [
      'status',
      'paused',
      'normal',
      'postponed',
      'no_show',
      'cancelled',
    ].contains(_task))
      Text(
        _state == 'normal'
            ? 'Grading will reopen for the selected defenses.'
            : 'Grading will be paused. Existing scores and minutes will be kept.',
      ),
    if (_deleting) ...[
      Text(
        '$_empty ${_empty == 1 ? 'empty schedule can' : 'empty schedules can'} be deleted${_protected == 0 ? '.' : '; $_protected ${_protected == 1 ? 'record is' : 'records are'} protected.'}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      if (_protected > 0 && _empty > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ShadCheckbox(
            value: _emptyOnly,
            enabled: !_busy,
            onChanged: (value) => setState(() => _emptyOnly = value),
            label: const Text(
              'Delete only empty schedules and keep recorded defenses',
            ),
          ),
        ),
      for (final entry in _affected)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                entry['can_delete'] == true
                    ? LucideIcons.trash2
                    : LucideIcons.lock,
                size: 15,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry['team_name']} · ${_shortTime(entry['start_time'])}',
                    ),
                    if (entry['can_delete'] != true)
                      Text(
                        (entry['blockers'] as List? ?? []).join(' '),
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
        ),
      Text(
        _empty == 0
            ? 'These schedules contain recorded activity and cannot be deleted.'
            : 'Deleting a schedule cannot be undone. Stage setup and team submissions will be kept.',
        style: TextStyle(
          fontSize: 12,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
    ],
    if (_requiresNewSignatures)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ShadCheckbox(
          value: _minutesAmendment,
          enabled: !_busy,
          onChanged: (value) => setState(() => _minutesAmendment = value),
          label: const Text(
            'Keep the signed minutes as a previous version and request new signatures',
          ),
        ),
      ),
    if (!_deleting || _empty > 0) ...[
      const SizedBox(height: 16),
      WorkflowField(
        label: 'Why is this change needed?',
        helper: 'Required · saved in the audit trail.',
        child: ShadInput(
          key: const ValueKey('schedule-change-reason'),
          controller: _reason,
          enabled: !_busy,
          minLines: 2,
          maxLines: 3,
          maxLength: 2000,
          placeholder: const Text(
            'Explain the change, for example: a panelist needs an emergency replacement.',
          ),
        ),
      ),
    ],
  ];

  String _current(String field, String fallback) {
    if (!_bulk) return fallback;
    String value(Map<String, dynamic> entry) {
      final item = entry[field];
      return item is List
          ? item.isEmpty
                ? 'None'
                : item.join(', ')
          : '${item ?? fallback}';
    }

    final values = _affected.map(value).toSet();
    return values.length == 1
        ? values.first
        : _affected
              .map((entry) => '${entry['team_name']}: ${value(entry)}')
              .join('\n');
  }

  List<Widget> _reviewContent() {
    final changes = _changes();
    return [
      Text(
        _deleting
            ? 'Delete $_empty ${_empty == 1 ? 'empty schedule' : 'empty schedules'}${_protected > 0 ? ' and keep $_protected protected ${_protected == 1 ? 'record' : 'records'}' : ''}?'
            : 'Review changes to ${_affected.length} ${_affected.length == 1 ? 'defense' : 'defenses'}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 14),
      if (changes.containsKey('panelist_ids'))
        WorkflowComparison(
          label: 'Faculty panel',
          before: _current(
            'panelist_names',
            _originalPanels.map((id) => _person(id, 'panelists')).join(', '),
          ),
          after: _panels.map((id) => _person(id, 'panelists')).join(', '),
        ),
      if (changes.containsKey('chair_panelist_id'))
        WorkflowComparison(
          label: 'Panel chair',
          before: _current('chair_name', _person(_originalChair, 'panelists')),
          after: _person(_chair, 'panelists'),
        ),
      if (changes.containsKey('external_evaluator_ids'))
        WorkflowComparison(
          label: 'External evaluators',
          before: _current(
            'external_evaluator_names',
            _originalExternals.isEmpty
                ? 'None'
                : _originalExternals
                      .map((id) => _person(id, 'external_evaluators'))
                      .join(', '),
          ),
          after: _externals.isEmpty
              ? 'None'
              : _externals
                    .map((id) => _person(id, 'external_evaluators'))
                    .join(', '),
        ),
      if (changes.containsKey('documenter_id'))
        WorkflowComparison(
          label: 'Documenter',
          before: _current(
            'documenter_name',
            '${widget.schedule['documenter_name'] ?? 'Unassigned'}',
          ),
          after: _person(_documenter, 'faculty'),
        ),
      if (changes.containsKey('room'))
        WorkflowComparison(
          label: 'Room',
          before: _current('room', '${widget.schedule['room']}'),
          after: _room.text.trim(),
        ),
      if (_task == 'time' && !_bulk)
        WorkflowComparison(
          label: 'Date and time',
          before:
              '${widget.schedule['scheduled_date']} · ${_shortTime(widget.schedule['start_time'])}',
          after:
              '${DateFormat('MMM d, y').format(_date!)} · ${_time.text.trim()}',
        ),
      if (_task == 'time' && _bulk) ...[
        for (final entry in _affected)
          WorkflowComparison(
            label: '${entry['team_name']}',
            before: '${entry['date']} · ${_shortTime(entry['start_time'])}',
            after: DateFormat('MMM d · HH:mm').format(
              DateTime.parse(
                '${entry['date']}T${entry['start_time']}',
              ).add(Duration(minutes: changes['shift_minutes'] as int)),
            ),
          ),
      ],
      if (changes.containsKey('operation_state') ||
          changes.containsKey('status'))
        Text(
          'New status: ${_state == 'normal' ? 'Resume grading' : _state.replaceAll('_', '-')}',
        ),
      if (_minutesAmendment)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Signed minutes will be kept. The updated document will need new signatures.',
          ),
        ),
      if (_bulk && _task != 'time') ...[
        const SizedBox(height: 10),
        for (final entry in _affected)
          Text(
            '${entry['team_name']} · ${_shortTime(entry['start_time'])}${_deleting
                ? entry['can_delete'] == true
                      ? ' · Delete'
                      : ' · Keep'
                : ''}',
          ),
      ],
      const SizedBox(height: 14),
      Text('Reason: ${_reason.text.trim()}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        _preview != null &&
        _affected.isNotEmpty &&
        (_deleting || _affected.every(_eligible)) &&
        (!_deleting || (_empty > 0 && (_protected == 0 || _emptyOnly)));
    return DefensysShadcnScope(
      child: ShadDialog(
        constraints: const BoxConstraints(maxWidth: 620),
        title: Text(_review ? 'Confirm change' : _title),
        description: Text(
          _bulk
              ? '${widget.schedule['stage_label']} · ${_stage ? 'All sessions · Active semester' : 'Session on ${widget.schedule['scheduled_date']}'}'
              : '${widget.schedule['team_name']} · ${widget.schedule['stage_label']}',
        ),
        actions: [
          ShadButton.outline(
            enabled: !_busy,
            onPressed: _busy
                ? null
                : () {
                    if (_review) {
                      setState(() => _review = false);
                    } else {
                      Navigator.pop(context);
                    }
                  },
            child: Text(_review ? 'Back' : 'Close'),
          ),
          if (!_deleting || _empty > 0)
            ShadButton(
              enabled: !_busy && canSave,
              onPressed: _busy || !canSave ? null : _save,
              child: Text(
                _busy
                    ? 'Please wait…'
                    : _review
                    ? _deleting
                          ? 'Delete schedules'
                          : 'Save changes'
                    : 'Review changes',
              ),
            ),
        ],
        child: Container(
          width: 560,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .64,
          ),
          child: _busy && _preview == null
              ? DefensysLoading.section(
                  height: 140,
                  label: 'Loading defense schedules…',
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        WorkflowNotice(
                          title: 'Check this change',
                          message: _error!,
                          error: true,
                        ),
                      if (_preview == null && !_busy)
                        ShadButton.outline(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      if (_preview != null)
                        ...(_review
                            ? _reviewContent()
                            : [
                                _scope(),
                                if (_tabbed) _editTabs(),
                                if (!_deleting &&
                                    (!_affected.every(_eligible) ||
                                        _affected.isEmpty))
                                  const WorkflowNotice(
                                    title: 'No eligible defenses',
                                    message:
                                        'These records cannot be changed with this action. Submitted evaluations keep their original room and time; completed defenses require an amendment.',
                                  )
                                else
                                  ..._form(),
                              ]),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
