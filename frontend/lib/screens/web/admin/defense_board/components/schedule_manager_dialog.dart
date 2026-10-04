import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../services/defense_board_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/feedback/defensys_loading.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../../widgets/shadcn/defensys_workflow_widgets.dart';

Future<void> showScheduleManager(
  BuildContext context, {
  Map<String, dynamic>? schedule,
  String scope = 'semester',
  String action = 'edit',
  String tab = 'panel',
  String defenseType = 'capstone',
}) => showDialog<void>(
  context: context,
  builder: (_) => ScheduleManagerDialog(
    schedule: schedule,
    initialScope: scope,
    initialAction: action,
    initialTab: tab,
    defenseType: defenseType,
  ),
);

int? _id(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value');
List<Map<String, dynamic>> _maps(dynamic value) => (value is List ? value : [])
    .whereType<Map>()
    .map((v) => Map<String, dynamic>.from(v))
    .toList();
Set<int> _ids(dynamic value) =>
    (value is List ? value : []).map(_id).whereType<int>().toSet();
String _time(dynamic value) =>
    '${value ?? ''}'.length >= 5 ? '$value'.substring(0, 5) : '${value ?? ''}';

class _RosterDraft {
  String action = 'add';
  final Set<int> added = {};
  int? departing, replacement, chair;
  Map<String, dynamic>? get changes => switch (action) {
    'add' when added.isNotEmpty => {
      'action': 'add',
      'panelist_ids': added.toList(),
    },
    'remove' when departing != null => {
      'action': 'remove',
      'panelist_id': departing,
      if (chair != null) 'chair_panelist_id': chair,
    },
    'replace' when departing != null && replacement != null => {
      'action': 'replace',
      'panelist_id': departing,
      'replacement_id': replacement,
    },
    'chair' when chair != null => {
      'action': 'chair',
      'chair_panelist_id': chair,
    },
    _ => null,
  };
}

/// One editor for semester, stage, section, session, and defense shortcuts.
class ScheduleManagerDialog extends ConsumerStatefulWidget {
  const ScheduleManagerDialog({
    super.key,
    this.schedule,
    this.initialScope = 'semester',
    this.initialAction = 'edit',
    this.initialTab = 'panel',
    this.defenseType = 'capstone',
  });
  final Map<String, dynamic>? schedule;
  final String initialScope, initialAction, initialTab, defenseType;
  @override
  ConsumerState<ScheduleManagerDialog> createState() =>
      _ScheduleManagerDialogState();
}

class _ScheduleManagerDialogState extends ConsumerState<ScheduleManagerDialog> {
  late String _scope = widget.initialScope,
      _action = widget.initialAction,
      _tab = widget.initialTab,
      _type = widget.schedule?['scope'] ?? widget.defenseType;
  String? _stage, _section, _session;
  final _faculty = _RosterDraft(), _external = _RosterDraft();
  String _pool = 'faculty', _status = 'paused', _shiftDirection = 'later';
  final _room = TextEditingController(),
      _shift = TextEditingController(text: '0'),
      _reason = TextEditingController(),
      _startTime = TextEditingController();
  DateTime? _date;
  bool _documenterChanged = false,
      _busy = true,
      _review = false,
      _success = false,
      _eligibleOnly = false,
      _excludeTiming = false,
      _minutes = false,
      _showSelection = false,
      _showDeleteRules = false;
  int? _documenter;
  final Set<int> _selected = {};
  Map<String, dynamic>? _context, _reviewData, _result;
  String? _error;
  List<Map<String, dynamic>> get _entries => _maps(_context?['entries']);
  List<Map<String, dynamic>> get _typed =>
      _entries.where((e) => e['scope'] == _type).toList();
  String _stageKey(Map<String, dynamic> e) => e['scope'] == 'pit'
      ? 'pit:${e['stage_label']}'
      : 'capstone:${e['defense_stage_id']}';
  String _sectionKey(Map<String, dynamic> e) =>
      '${e['year_level']}|${e['section']}';
  List<Map<String, dynamic>> get _scopeEntries => _typed
      .where(
        (e) => switch (_scope) {
          'stage' => _stageKey(e) == _stage,
          'section' => _sectionKey(e) == _section,
          'session' => e['session_id'] == _session,
          'selected' => _selected.contains(_id(e['id'])),
          'schedule' => _id(e['id']) == _id(widget.schedule?['id']),
          _ => true,
        },
      )
      .toList();
  bool get _single => _scope == 'schedule';
  bool get _roomChanged =>
      _room.text.trim().isNotEmpty &&
      (!_single || _room.text.trim() != widget.schedule?['room']);
  int get _shiftMinutes =>
      (int.tryParse(_shift.text.trim()) ?? 0) *
      (_shiftDirection == 'earlier' ? -1 : 1);
  bool get _timeChanged => _single
      ? _date != null &&
            (DateFormat('yyyy-MM-dd').format(_date!) !=
                    widget.schedule?['scheduled_date'] ||
                _startTime.text.trim() != _time(widget.schedule?['start_time']))
      : _shiftMinutes != 0;
  bool get _timingChanged =>
      _action == 'edit' && (_roomChanged || _timeChanged);
  bool _editable(Map<String, dynamic> e) =>
      e['can_edit'] != false &&
      (e['status'] == 'scheduled' ||
          _action == 'status' &&
              _status == 'normal' &&
              e['status'] == 'cancelled');
  List<Map<String, dynamic>> get _timingProtected => _scopeEntries
      .where((e) => _editable(e) && e['can_reschedule'] == false)
      .toList();
  List<Map<String, dynamic>> get _affected => _action == 'delete'
      ? _scopeEntries
      : _scopeEntries
            .where(
              (e) =>
                  _editable(e) &&
                  !(_excludeTiming &&
                      _timingChanged &&
                      e['can_reschedule'] == false),
            )
            .toList();
  int get _eligible => _affected.where((e) => e['can_delete'] == true).length;
  int get _protected => _affected.length - _eligible;
  int get _pending =>
      (_faculty.changes != null ? 1 : 0) +
      (_external.changes != null ? 1 : 0) +
      (_documenterChanged ? 1 : 0) +
      (_roomChanged ? 1 : 0) +
      (_timeChanged ? 1 : 0);

  String get _scopeLabel => switch (_scope) {
    'stage' =>
      '${_scopeEntries.firstOrNull?['stage_label'] ?? (_type == 'pit' ? 'PIT event' : 'Stage')}',
    'section' => _section?.replaceAll('|', ' · ') ?? 'Academic section',
    'session' => 'Session · ${_scopeEntries.firstOrNull?['stage_label'] ?? ''}',
    'selected' => 'Selected defenses',
    'schedule' => '${widget.schedule?['team_name'] ?? 'This defense'}',
    _ => 'All ${_type == 'pit' ? 'PIT' : 'Capstone'} schedules',
  };

  @override
  void initState() {
    super.initState();
    if (_tab == 'external') {
      _tab = 'panel';
      _pool = 'external';
    }
    if (!const ['panel', 'documenter', 'room', 'time'].contains(_tab)) {
      _tab = 'panel';
    }
    if ([
      'paused',
      'normal',
      'postponed',
      'no_show',
      'cancelled',
    ].contains(widget.initialTab)) {
      _action = 'status';
      _status = widget.initialTab;
      _tab = 'panel';
    }
    if (_single) {
      _room.text = '${widget.schedule?['room'] ?? ''}';
    }
    _date = DateTime.tryParse('${widget.schedule?['scheduled_date']}');
    _startTime.text = _time(widget.schedule?['start_time']);
    _load();
  }

  @override
  void dispose() {
    for (final c in [_room, _shift, _reason, _startTime]) {
      c.dispose();
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
      final data = await ref
          .read(defenseBoardProvider.notifier)
          .managementContext();
      if (!mounted) return;
      setState(() {
        _context = data;
        final initial =
            _entries
                .where((e) => _id(e['id']) == _id(widget.schedule?['id']))
                .firstOrNull ??
            _typed.firstOrNull;
        _stage ??= initial == null ? null : _stageKey(initial);
        _section ??= initial == null ? null : _sectionKey(initial);
        _session ??= initial?['session_id']?.toString();
        if (_scope == 'selected' && _selected.isEmpty && initial != null) {
          _selected.add(_id(initial['id'])!);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _change(VoidCallback change) => setState(() {
    change();
    _review = false;
    _reviewData = null;
    _error = null;
  });

  List<int> _resultIds(
    Map<String, dynamic> e,
    _RosterDraft draft,
    String field,
  ) {
    final result = _ids(e[field]).toList();
    if (draft.action == 'add') {
      result.addAll(draft.added.where((id) => !result.contains(id)));
    }
    if (['remove', 'replace'].contains(draft.action) &&
        result.contains(draft.departing)) {
      result.remove(draft.departing);
      if (draft.action == 'replace' &&
          draft.replacement != null &&
          !result.contains(draft.replacement)) {
        result.add(draft.replacement!);
      }
    }
    return result;
  }

  bool _willChange(Map<String, dynamic> e) {
    final before = _ids(e['panelist_ids']),
        after = _resultIds(e, _faculty, 'panelist_ids').toSet();
    final ebefore = _ids(e['external_evaluator_ids']),
        eafter = _resultIds(e, _external, 'external_evaluator_ids').toSet();
    return before.length != after.length ||
        !before.containsAll(after) ||
        ebefore.length != eafter.length ||
        !ebefore.containsAll(eafter) ||
        const ['chair', 'remove'].contains(_faculty.action) &&
            _faculty.chair != null &&
            _faculty.chair != _id(e['chair_panelist_id']) ||
        _faculty.action == 'replace' &&
            _faculty.departing == _id(e['chair_panelist_id']) &&
            _faculty.replacement != null ||
        _documenterChanged && _documenter != _id(e['documenter_id']) ||
        _roomChanged && _room.text.trim() != e['room'] ||
        _timeChanged;
  }

  bool get _needsMinutes =>
      _action == 'edit' &&
      _affected.any(
        (e) => e['minutes_requires_amendment'] == true && _willChange(e),
      );
  Map<String, dynamic> _changes() => {
    if (_faculty.changes != null) 'panel_change': _faculty.changes,
    if (_external.changes != null) 'external_change': _external.changes,
    if (_documenterChanged) 'documenter_id': _documenter,
    if (_roomChanged) 'room': _room.text.trim(),
    if (_timeChanged && _single) ...{
      'scheduled_date': DateFormat('yyyy-MM-dd').format(_date!),
      'start_time': _startTime.text.trim(),
    },
    if (_timeChanged && !_single) 'shift_minutes': _shiftMinutes,
    if (_minutes) 'acknowledge_minutes_amendment': true,
  };
  Map<String, dynamic> _payload(String action) {
    final changes = _action == 'status'
        ? <String, dynamic>{
            if (_status == 'cancelled') 'status': 'cancelled',
            if (_status != 'cancelled') 'operation_state': _status,
            if (_status == 'normal') 'status': 'scheduled',
          }
        : _changes();
    return {
      'action': action,
      'target': 'management_selected',
      'anchor_id': _affected.first['id'],
      'schedule_ids': _affected.map((e) => e['id']).toList(),
      'expected_revisions': {
        for (final e in _affected)
          '${e['id']}':
              (_context?['expected_revisions'] as Map?)?['${e['id']}'] ??
              e['revision'],
      },
      'reason': _reason.text.trim(),
      'empty_only': _eligibleOnly,
      if (_action != 'delete') 'changes': changes,
    };
  }

  bool get _canReview =>
      _context != null &&
      _affected.isNotEmpty &&
      _reason.text.trim().length >= 5 &&
      (_action != 'edit' || _pending > 0) &&
      (!_timingChanged || _excludeTiming || _timingProtected.isEmpty) &&
      (!_needsMinutes || _minutes) &&
      (_action != 'delete' ||
          _eligible > 0 && (_protected == 0 || _eligibleOnly));
  Future<void> _next() async {
    if (!_canReview) return;
    if (_action == 'edit' &&
        (_shift.text.trim().isNotEmpty &&
                int.tryParse(_shift.text.trim()) == null ||
            (int.tryParse(_shift.text.trim()) ?? 0) < 0 ||
            _shiftMinutes.abs() > 1440)) {
      setState(
        () => _error = 'Use a whole number of minutes between 0 and 1440.',
      );
      return;
    }
    if (_single &&
        _timeChanged &&
        !RegExp(
          r'^([01]\d|2[0-3]):[0-5]\d$',
        ).hasMatch(_startTime.text.trim())) {
      setState(() => _error = 'Enter a valid 24-hour time, such as 08:30.');
      return;
    }
    if (_action == 'delete') {
      setState(() => _review = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final review = await ref
          .read(defenseBoardProvider.notifier)
          .operation(_payload('preview_update'));
      if (mounted) {
        setState(() {
          _reviewData = review;
          _review = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(defenseBoardProvider.notifier)
          .operation(_payload(_action == 'delete' ? 'delete' : 'update'));
      if (mounted) {
        setState(() {
          _result = result;
          _success = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _review = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _person(int? id, {bool external = false}) {
    if (id == null) return 'Unassigned';
    final pool = _maps(_context?[external ? 'external_evaluators' : 'faculty']);
    final found = pool.where((p) => _id(p['id']) == id).firstOrNull;
    if (found != null) return '${found['name']}';
    for (final e in _entries) {
      final ids =
          (e[external ? 'external_evaluator_ids' : 'panelist_ids'] as List?) ??
          [];
      final names =
          (e[external ? 'external_evaluator_names' : 'panelist_names']
              as List?) ??
          [];
      final index = ids.indexOf(id);
      if (index >= 0 && index < names.length) return '${names[index]}';
    }
    return 'Previously assigned person';
  }

  Widget _badge(String text, {bool removed = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: (removed ? DefensysTokens.danger : DefensysTokens.success)
          .withValues(alpha: .12),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: DefensysTokens.isDark(context)
            ? (removed ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7))
            : (removed
                  ? DefensysTokens.dangerText
                  : DefensysTokens.successText),
      ),
    ),
  );
  Widget _personRow(
    int id,
    String indicator, {
    bool external = false,
    VoidCallback? undo,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: DefensysTokens.borderOf(context)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(LucideIcons.userRound, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(_person(id, external: external))),
        const SizedBox(width: 6),
        _badge(indicator, removed: indicator == 'Will be removed'),
        if (undo != null)
          ShadButton.ghost(
            enabled: !_busy,
            onPressed: _busy ? null : undo,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: const Text('Undo'),
          ),
      ],
    ),
  );

  Widget _scopePair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth < 540
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, second],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 12),
              Expanded(child: second),
            ],
          ),
  );

  Widget _scopeControls() {
    final stages = {
      for (final e in _typed) _stageKey(e): '${e['stage_label']}',
    };
    final sections = {
      for (final e in _typed)
        if ('${e['section'] ?? ''}'.isNotEmpty)
          _sectionKey(e): '${e['year_level']} · ${e['section']}',
    };
    final sessions = <String, String>{};
    for (final e in _typed) {
      final key = '${e['session_id']}';
      sessions.putIfAbsent(
        key,
        () =>
            '${e['stage_label']} · ${e['date']} · ${e['room']} · ${_time(e['start_time'])}',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scopePair(
          WorkflowSelect(
            label: 'Defense type',
            value: _type,
            searchable: false,
            enabled: !_busy,
            options: {
              for (final scope in const {
                'capstone': 'Capstone',
                'pit': 'PIT',
              }.entries)
                if ((_context?['allowed_scopes'] as List?)?.contains(
                      scope.key,
                    ) ??
                    true)
                  scope.key: scope.value,
            },
            onChanged: (v) => _change(() {
              _type = v;
              _stage = null;
              _section = null;
              _session = null;
              _selected.clear();
              _excludeTiming = false;
              final first = _typed.firstOrNull;
              if (first != null) {
                _stage = _stageKey(first);
                _section = _sectionKey(first);
                _session = '${first['session_id']}';
              }
              _documenterChanged = false;
              _faculty.added.clear();
              _faculty.departing = null;
              _faculty.replacement = null;
              _faculty.chair = null;
              _external.added.clear();
              _external.departing = null;
              _external.replacement = null;
              if (_tab == 'documenter' && v == 'pit') _tab = 'panel';
            }),
          ),
          WorkflowSelect(
            label: 'Apply to',
            value: _scope,
            searchable: false,
            enabled: !_busy,
            options: {
              'semester':
                  'All ${_type == 'pit' ? 'PIT' : 'Capstone'} schedules in the active semester',
              'stage': _type == 'pit' ? 'A PIT event' : 'A stage',
              'section': 'An academic section',
              'session': 'A session',
              'selected': 'Selected defenses',
              if (widget.schedule != null) 'schedule': 'This defense only',
            },
            onChanged: (v) => _change(() {
              _scope = v;
              _eligibleOnly = false;
              _excludeTiming = false;
              _showSelection = v == 'selected';
              if (v == 'selected' && _selected.isEmpty) {
                _selected.addAll(_typed.map((e) => _id(e['id'])!));
              }
              if (v != 'schedule' &&
                  _room.text.trim() == widget.schedule?['room']) {
                _room.clear();
              }
            }),
          ),
        ),
        if (_scope == 'stage')
          WorkflowSelect(
            label: _type == 'pit' ? 'PIT event' : 'Stage',
            value: _stage,
            options: stages,
            enabled: !_busy,
            onChanged: (v) => _change(() => _stage = v),
          ),
        if (_scope == 'section')
          WorkflowSelect(
            label: 'Section',
            value: _section,
            options: sections,
            enabled: !_busy,
            onChanged: (v) => _change(() => _section = v),
          ),
        if (_scope == 'session')
          WorkflowSelect(
            label: 'Session',
            value: _session,
            options: sessions,
            enabled: !_busy,
            onChanged: (v) => _change(() => _session = v),
          ),
        Text(
          '${_scopeEntries.length} defenses · ${_scopeEntries.map((e) => e['session_id']).toSet().length} sessions · Active semester only',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Board search and filters do not limit this selection.',
          style: TextStyle(fontSize: 12),
        ),
        if (_scope == 'selected') ...[
          ShadButton.ghost(
            enabled: !_busy,
            onPressed: () => _change(() => _showSelection = !_showSelection),
            mainAxisAlignment: MainAxisAlignment.start,
            padding: EdgeInsets.zero,
            child: Text(
              _showSelection ? 'Hide defense selection' : 'Choose defenses',
            ),
          ),
          if (_showSelection)
            ..._typed.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ShadCheckbox(
                  value: _selected.contains(_id(e['id'])),
                  enabled: !_busy,
                  onChanged: (v) => _change(
                    () => v
                        ? _selected.add(_id(e['id'])!)
                        : _selected.remove(_id(e['id'])),
                  ),
                  label: Text(
                    '${e['team_name']} · ${e['stage_label']} · ${e['date']} ${_time(e['start_time'])}',
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        if (_action != 'delete' && _scopeEntries.length != _affected.length)
          WorkflowNotice(
            title: '${_scopeEntries.length - _affected.length} defenses kept',
            message:
                'Completed or protected defenses are excluded. ${_affected.length} defenses remain in this change.',
          ),
      ],
    );
  }

  Widget _panelForm() {
    final external = _pool == 'external',
        draft = external ? _external : _faculty;
    final field = external ? 'external_evaluator_ids' : 'panelist_ids';
    final assigned = {for (final e in _affected) ..._ids(e[field])};
    final locked = {
      for (final e in _affected)
        ..._ids(
          e[external
              ? 'submitted_external_evaluator_ids'
              : 'submitted_panelist_ids'],
        ),
    };
    final directory = _maps(
      _context?[external ? 'external_evaluators' : 'panelists'],
    );
    final unavailable = {
      for (final e in _affected)
        if (_id(e['adviser_id']) != null) _id(e['adviser_id'])!,
      for (final e in _affected)
        if ((_documenterChanged ? _documenter : _id(e['documenter_id'])) !=
            null)
          (_documenterChanged ? _documenter : _id(e['documenter_id']))!,
    };
    final incoming = {
      for (final p in directory)
        if (external || !unavailable.contains(_id(p['id'])))
          '${p['id']}': '${p['name']}',
    };
    final remaining = _affected
        .map((e) => _resultIds(e, _faculty, 'panelist_ids').toSet())
        .toList();
    final common = remaining.isEmpty
        ? <int>{}
        : remaining.skip(1).fold<Set<int>>({
            ...remaining.first,
          }, (a, b) => a.intersection(b));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkflowSelect(
          label: 'Panel type',
          value: _pool,
          searchable: false,
          enabled: !_busy,
          options: const {
            'faculty': 'Faculty panel',
            'external': 'External evaluators',
          },
          onChanged: (v) => _change(() => _pool = v),
        ),
        WorkflowSelect(
          label: 'Panel change',
          value: draft.action,
          searchable: false,
          enabled: !_busy,
          options: {
            'add': 'Add panelist',
            'replace': 'Replace panelist',
            'remove': 'Remove panelist',
            if (!external) 'chair': 'Change panel chair',
          },
          onChanged: (v) => _change(() => draft.action = v),
        ),
        if (draft.action == 'add') ...[
          WorkflowSelect(
            key: ValueKey('manager-add-$_pool-${draft.added.join('-')}'),
            label: 'Add panelist',
            placeholder: 'Search and add a panelist',
            enabled: !_busy,
            options: {
              for (final e in incoming.entries)
                if (!draft.added.contains(int.parse(e.key))) e.key: e.value,
            },
            onChanged: (v) => _change(() => draft.added.add(int.parse(v))),
          ),
          ...draft.added.map(
            (id) => _personRow(
              id,
              _affected.isNotEmpty &&
                      _affected.every((e) => _ids(e[field]).contains(id))
                  ? 'Already assigned'
                  : 'Added',
              external: external,
              undo: () => _change(() => draft.added.remove(id)),
            ),
          ),
          const WorkflowNotice(
            title: 'Existing panels are preserved',
            message:
                'Each defense keeps its other panelists. Someone already assigned is left unchanged.',
          ),
        ],
        if (['remove', 'replace'].contains(draft.action)) ...[
          WorkflowSelect(
            label: draft.action == 'replace'
                ? 'Panelist to replace'
                : 'Panelist to remove',
            value: draft.departing?.toString(),
            enabled: !_busy,
            options: {
              for (final id in assigned)
                if (!locked.contains(id))
                  '$id': _person(id, external: external),
            },
            onChanged: (v) => _change(() => draft.departing = int.parse(v)),
          ),
          if (draft.departing != null)
            _personRow(
              draft.departing!,
              'Will be removed',
              external: external,
              undo: () => _change(() => draft.departing = null),
            ),
          if (draft.action == 'replace') ...[
            WorkflowSelect(
              label: 'Replacement panelist',
              value: draft.replacement?.toString(),
              enabled: !_busy,
              options: {
                for (final e in incoming.entries)
                  if (int.parse(e.key) != draft.departing) e.key: e.value,
              },
              onChanged: (v) => _change(() => draft.replacement = int.parse(v)),
            ),
            if (draft.replacement != null)
              _personRow(draft.replacement!, 'Added', external: external),
            const Text(
              'A replacement takes the chair role only where the departing panelist was chair.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (!external &&
              draft.action == 'remove' &&
              _affected.any(
                (e) => _id(e['chair_panelist_id']) == draft.departing,
              ))
            WorkflowSelect(
              label: 'New panel chair',
              value: draft.chair?.toString(),
              enabled: !_busy,
              options: {for (final id in common) '$id': _person(id)},
              onChanged: (v) => _change(() => draft.chair = int.parse(v)),
            ),
          if (locked.isNotEmpty)
            WorkflowNotice(
              title: 'Submitted evaluators stay assigned',
              message:
                  '${locked.map((id) => _person(id, external: external)).join(', ')}. Their evaluations keep the original author.',
            ),
        ],
        if (draft.action == 'chair') ...[
          WorkflowSelect(
            label: 'New panel chair',
            value: draft.chair?.toString(),
            enabled: !_busy,
            options: {for (final id in common) '$id': _person(id)},
            onChanged: (v) => _change(() => draft.chair = int.parse(v)),
          ),
          if (draft.chair != null) _personRow(draft.chair!, 'Chair changed'),
          const Text(
            'Choose someone assigned to every defense in this selection.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _input(
    String label,
    TextEditingController controller,
    String key, {
    String? helper,
    bool numeric = false,
  }) => WorkflowField(
    label: label,
    helper: helper,
    child: ShadInput(
      key: ValueKey(key),
      controller: controller,
      enabled: !_busy,
      keyboardType: numeric ? TextInputType.number : null,
      onChanged: (_) => _change(() {}),
    ),
  );
  Widget _editForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ShadTabs<String>(
        value: _tab,
        scrollable: true,
        tabBarAlignment: Alignment.centerLeft,
        gap: 0,
        onChanged: (v) => _change(() => _tab = v),
        tabs: [
          for (final e in {
            'panel': 'Panel',
            if (_type != 'pit') 'documenter': 'Documenter',
            'room': 'Room',
            'time': 'Time',
          }.entries)
            ShadTab(
              value: e.key,
              enabled: !_busy,
              content: const SizedBox.shrink(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.value),
                  if (switch (e.key) {
                    'panel' =>
                      _faculty.changes != null || _external.changes != null,
                    'documenter' => _documenterChanged,
                    'room' => _roomChanged,
                    _ => _timeChanged,
                  }) ...[
                    const SizedBox(width: 5),
                    _badge('Changed'),
                  ],
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (_tab == 'panel') _panelForm(),
      if (_tab == 'documenter')
        WorkflowSelect(
          label: 'Documenter',
          value: _documenterChanged
              ? (_documenter?.toString() ?? 'none')
              : 'keep',
          enabled: !_busy,
          options: {
            'keep': 'Keep existing documenters',
            'none': 'Unassigned',
            for (final p in _maps(_context?['faculty']))
              if (!_affected.any(
                (e) =>
                    _id(e['adviser_id']) == _id(p['id']) ||
                    _resultIds(
                      e,
                      _faculty,
                      'panelist_ids',
                    ).contains(_id(p['id'])),
              ))
                '${p['id']}': '${p['name']}',
          },
          onChanged: (v) => _change(() {
            _documenterChanged = v != 'keep';
            _documenter = int.tryParse(v);
          }),
        ),
      if (_tab == 'room') ...[
        _input(
          'New room',
          _room,
          'manager-room',
          helper: 'Leave this blank to keep existing rooms.',
        ),
        if (_roomChanged) _badge('Changed'),
      ],
      if (_tab == 'time' && !_single) ...[
        WorkflowSelect(
          label: 'Move selected defenses',
          value: _shiftDirection,
          searchable: false,
          enabled: !_busy,
          options: const {'later': 'Later', 'earlier': 'Earlier'},
          onChanged: (v) => _change(() => _shiftDirection = v),
        ),
        _input(
          'By how many minutes?',
          _shift,
          'manager-shift',
          numeric: true,
          helper:
              'Spacing and order are preserved. Use 0 to keep current times.',
        ),
      ],
      if (_tab == 'time' && _single) ...[
        WorkflowField(
          label: 'Defense date',
          child: ShadDatePicker(
            selected: _date,
            enabled: !_busy,
            closeOnSelection: true,
            allowDeselection: false,
            onChanged: (v) => _change(() => _date = v),
          ),
        ),
        _input(
          'Start time',
          _startTime,
          'manager-time',
          helper: '24-hour time, for example 08:30.',
        ),
      ],
      if (_pending > 0) ...[
        const SizedBox(height: 12),
        WorkflowNotice(
          title: '$_pending pending ${_pending == 1 ? 'change' : 'changes'}',
          message:
              'All edited tabs are included in the review. ${_affected.where(_willChange).length} defenses will change.',
        ),
      ],
      if (_timingChanged && _timingProtected.isNotEmpty && !_excludeTiming) ...[
        WorkflowNotice(
          title:
              '${_timingProtected.length} defenses keep their original timetable',
          message:
              'Submitted evaluations protect the original room and time. Exclude these defenses to continue.',
        ),
        ShadButton.outline(
          enabled: !_busy,
          onPressed: () => _change(() => _excludeTiming = true),
          child: const Text('Exclude defenses with recorded evaluations'),
        ),
      ],
      if (_needsMinutes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: ShadCheckbox(
            enabled: !_busy,
            value: _minutes,
            onChanged: (v) => _change(() => _minutes = v),
            label: const Text(
              'Preserve signed minutes as a previous version and request new signatures',
            ),
          ),
        ),
    ],
  );
  Widget _deleteForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Only schedules with no recorded defense activity can be deleted.',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      ShadButton.ghost(
        enabled: !_busy,
        onPressed: () => _change(() => _showDeleteRules = !_showDeleteRules),
        padding: EdgeInsets.zero,
        mainAxisAlignment: MainAxisAlignment.start,
        child: const Text('What counts as recorded activity?'),
      ),
      if (_showDeleteRules)
        const WorkflowNotice(
          title: 'Recorded activity protects the schedule',
          message:
              'Scores (including 0), evaluation drafts with scores or remarks, minutes/comments/signatures, generated minutes documents, grades, verdicts, or correction history. Completed and archived defenses are protected. Assigning a panel, room, date, or time alone does not prevent deletion.',
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _badge('$_eligible can be deleted'),
          _badge('$_protected will be kept', removed: true),
        ],
      ),
      const SizedBox(height: 14),
      for (final e in _affected)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${e['team_name']} · ${_time(e['start_time'])}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                e['can_delete'] == true
                    ? 'Can delete · No defense activity recorded'
                    : 'Protected · ${(e['blockers'] as List? ?? []).join(' ')}',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      if (_protected > 0 && _eligible > 0)
        ShadCheckbox(
          enabled: !_busy,
          value: _eligibleOnly,
          onChanged: (v) => _change(() => _eligibleOnly = v),
          label: Text(
            'Delete eligible schedules only. Keep $_protected protected schedules.',
          ),
        ),
      const SizedBox(height: 12),
      const Text(
        'Stage setup, teams, and their submissions are kept. Deleted schedules cannot be restored.',
        style: TextStyle(fontSize: 12),
      ),
    ],
  );
  List<Widget> _form() => [
    ShadTabs<String>(
      value: _action,
      scrollable: true,
      tabBarAlignment: Alignment.centerLeft,
      gap: 0,
      onChanged: (v) => _change(() {
        _action = v;
        _eligibleOnly = false;
      }),
      tabs: [
        for (final e in const {
          'edit': 'Edit schedules',
          'status': 'Change status',
          'delete': 'Delete schedules',
        }.entries)
          ShadTab(
            value: e.key,
            enabled: !_busy,
            content: const SizedBox.shrink(),
            child: Text(e.value),
          ),
      ],
    ),
    const SizedBox(height: 16),
    _scopeControls(),
    if (_action == 'edit' && _affected.isNotEmpty) _editForm(),
    if (_action == 'delete') _deleteForm(),
    if (_action == 'status' && _affected.isNotEmpty) ...[
      WorkflowSelect(
        label: 'New status',
        value: _status,
        enabled: !_busy,
        searchable: false,
        options: const {
          'paused': 'Paused',
          'postponed': 'Postponed',
          'no_show': 'No-show',
          'cancelled': 'Cancelled',
          'normal': 'Resume as scheduled',
        },
        onChanged: (v) => _change(() => _status = v),
      ),
      const WorkflowNotice(
        title: 'Defense records are preserved',
        message: 'Existing evaluations, grades, and minutes are kept.',
      ),
    ],
    if (_affected.isEmpty)
      const WorkflowNotice(
        title: 'No eligible defenses',
        message: 'Choose a scope containing defenses that can be changed.',
      ),
    const SizedBox(height: 16),
    if ((_action != 'delete' && _affected.isNotEmpty) ||
        (_action == 'delete' && _eligible > 0))
      WorkflowField(
        label: 'Reason',
        helper: 'Required · Recorded with your name in the audit history.',
        child: ShadInput(
          key: const ValueKey('manager-reason'),
          controller: _reason,
          enabled: !_busy,
          minLines: 2,
          maxLines: 3,
          maxLength: 2000,
          onChanged: (_) => _change(() {}),
          placeholder: const Text('Explain what changed and why.'),
        ),
      ),
  ];
  List<Widget> _reviewContent() => [
    Text(
      _action == 'delete'
          ? 'Delete $_eligible schedules · Keep $_protected protected schedules'
          : '${_reviewData?['updated'] ?? 0} defenses will change · ${_reviewData?['unchanged'] ?? 0} unchanged',
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 12),
    if (_action == 'delete')
      ..._affected.map(
        (e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${e['team_name']} · ${e['can_delete'] == true ? 'Delete' : 'Keep'}',
          ),
        ),
      ),
    if (_action != 'delete')
      ..._maps(_reviewData?['entries']).map(
        (e) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${e['team_name']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (e['will_change'] != true)
                const Text(
                  'Already matches · Kept unchanged',
                  style: TextStyle(fontSize: 12),
                ),
              ..._maps(e['changes']).map(
                (c) => WorkflowComparison(
                  label: '${c['label']}',
                  before: '${c['before']}',
                  after: '${c['after']}',
                ),
              ),
            ],
          ),
        ),
      ),
    const SizedBox(height: 12),
    Text('Reason: ${_reason.text.trim()}'),
    const SizedBox(height: 10),
    const Text(
      'Your name, the reason, and before-and-after values will be recorded.',
      style: TextStyle(fontSize: 12),
    ),
  ];
  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadDialog(
      constraints: const BoxConstraints(maxWidth: 720),
      title: Text(
        _success
            ? 'Changes saved'
            : _review
            ? 'Review changes'
            : 'Manage schedules',
      ),
      description: Text(
        '${_context?['active_semester']?['display_name'] ?? 'Active semester'} · ${_type == 'pit' ? 'PIT' : 'Capstone'}\n$_scopeLabel · ${_affected.length} defenses',
      ),
      actions: [
        if (_success)
          ShadButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to schedules'),
          )
        else ...[
          if (_error != null)
            ShadButton.ghost(
              enabled: !_busy,
              onPressed: _busy ? null : _load,
              child: const Text('Refresh records'),
            ),
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
          if (_action != 'delete' || _eligible > 0)
            ShadButton(
              enabled:
                  !_busy &&
                  (_review
                      ? (_action == 'delete'
                            ? _eligible > 0
                            : (_reviewData?['updated'] ?? 0) > 0)
                      : _canReview),
              onPressed: _busy
                  ? null
                  : _review
                  ? _save
                  : _next,
              child: Text(
                _busy
                    ? 'Please wait…'
                    : _review
                    ? (_action == 'delete'
                          ? 'Delete $_eligible ${_eligible == 1 ? 'schedule' : 'schedules'}'
                          : 'Save changes')
                    : _action == 'delete'
                    ? 'Review deletion'
                    : 'Review changes',
              ),
            ),
        ],
      ],
      child: SizedBox(
        width: 660,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .66,
          ),
          child: _busy && _context == null
              ? DefensysLoading.section(
                  height: 140,
                  label: 'Loading schedule management…',
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
                      if (_success) ...[
                        const Icon(LucideIcons.circleCheck, size: 34),
                        const SizedBox(height: 12),
                        Text(
                          _action == 'delete'
                              ? '${_result?['deleted']} schedules deleted · ${_result?['protected'] ?? 0} protected schedules kept'
                              : '${_result?['updated']} defenses updated · ${_result?['unchanged'] ?? 0} unchanged',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'The audit history is saved. Updated sessions show a View changes shortcut.',
                        ),
                      ] else if (_context != null)
                        ...(_review ? _reviewContent() : _form()),
                      if (_context == null && !_busy)
                        ShadButton.outline(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    ),
  );
}

class ScheduleChangesButton extends StatelessWidget {
  const ScheduleChangesButton({super.key, required this.schedules});
  final List<Map<String, dynamic>> schedules;
  @override
  Widget build(BuildContext context) {
    final changed = schedules.where((s) => s['latest_change'] is Map).toList()
      ..sort(
        (a, b) => '${b['latest_change']['created_at']}'.compareTo(
          '${a['latest_change']['created_at']}',
        ),
      );
    if (changed.isEmpty) return const SizedBox.shrink();
    final latest = changed.first['latest_change'] as Map;
    return DefensysShadcnScope(
      child: Tooltip(
        message:
            '${latest['summary']} · ${latest['actor']}\n${latest['reason']}',
        child: ShadButton.outline(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          leading: const Icon(LucideIcons.history, size: 14),
          onPressed: () => showScheduleHistory(
            context,
            _id(changed.first['id'])!,
            session: true,
          ),
          child: const Text(
            'Updated · View changes',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }
}

Future<void> showScheduleHistory(
  BuildContext context,
  int id, {
  bool session = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => ScheduleHistoryDialog(scheduleId: id, session: session),
);

class ScheduleHistoryDialog extends ConsumerStatefulWidget {
  const ScheduleHistoryDialog({
    super.key,
    required this.scheduleId,
    this.session = false,
  });
  final int scheduleId;
  final bool session;
  @override
  ConsumerState<ScheduleHistoryDialog> createState() =>
      _ScheduleHistoryDialogState();
}

class _ScheduleHistoryDialogState extends ConsumerState<ScheduleHistoryDialog> {
  List<Map<String, dynamic>>? _history;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(defenseBoardProvider.notifier)
          .scheduleHistory(widget.scheduleId, session: widget.session);
      if (mounted) setState(() => _history = data);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadDialog(
      constraints: const BoxConstraints(maxWidth: 660),
      title: const Text('Schedule change history'),
      description: Text(
        widget.session
            ? 'Changes recorded for this session'
            : 'Changes recorded for this defense',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
      child: SizedBox(
        width: 600,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  WorkflowNotice(
                    title: 'History could not be loaded',
                    message: _error!,
                    error: true,
                  ),
                if (_error == null && _history == null)
                  DefensysLoading.section(
                    height: 120,
                    label: 'Loading change history…',
                  ),
                if (_history?.isEmpty == true)
                  const Text('No schedule changes recorded.'),
                for (final h in _history ?? <Map<String, dynamic>>[]) ...[
                  Text(
                    '${h['team_name'] ?? ''} · ${h['summary']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${h['actor']} · ${DateTime.tryParse('${h['created_at']}') == null ? h['created_at'] : DateFormat('MMM d, y · HH:mm').format(DateTime.parse('${h['created_at']}').toLocal())}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  ..._maps(h['changes']).map(
                    (c) => WorkflowComparison(
                      label: '${c['label']}',
                      before: '${c['before']}',
                      after: '${c['after']}',
                    ),
                  ),
                  Text('Reason: ${h['reason']}'),
                  const SizedBox(height: 22),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
