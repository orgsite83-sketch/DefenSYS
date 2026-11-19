import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/academic/capstone2_confirmation_fields.dart';

/// One form; a rejected request keeps controllers and roster selection alive.
class TeamCreationDialog extends StatefulWidget {
  const TeamCreationDialog({
    super.key,
    required this.data,
    required this.isPitLead,
    required this.isCapstoneAdmin,
    this.pitLeadYear,
    required this.save,
    required this.loadRoster,
  });
  final StudentTeamsState data;
  final bool isPitLead, isCapstoneAdmin;
  final String? pitLeadYear;
  final Future<String?> Function(Map<String, dynamic>) save;
  final Future<List<Map<String, dynamic>>> Function(String, String) loadRoster;
  @override
  State<TeamCreationDialog> createState() => _TeamCreationDialogState();
}

class _TeamCreationDialogState extends State<TeamCreationDialog> {
  final _name = TextEditingController(), _project = TextEditingController();
  final _reference = TextEditingController(),
      _section = TextEditingController();
  final _selected = <int>{};
  List<Map<String, dynamic>> _students = [];
  int? _leader, _adviser;
  bool _saving = false, _loading = false, _confirmed = false;
  String? _error, _event;
  String _search = '', _status = 'Pending', _requestId = '', _lastPayload = '';
  int? _id(dynamic value) => int.tryParse('$value');
  bool get _pit =>
      widget.isPitLead || widget.data.level.toUpperCase().contains('PIT');
  bool get _capstone2 =>
      !_pit && widget.data.capstoneMode == 'capstone_2_continue';
  bool get _first =>
      widget.data.activeSemester?['label']?.toString().contains('1st') == true;
  String get _year => widget.isPitLead
      ? widget.pitLeadYear ?? '3rd Year'
      : _pit
      ? widget.data.yearLevel ?? '1st Year'
      : _first
      ? '4th Year'
      : '3rd Year';
  String get _level => '$_year ${_pit ? 'PIT' : 'Capstone'}';
  List<Map<String, dynamic>> get _members =>
      _students.where((s) => _selected.contains(_id(s['id']))).toList();
  bool get _needsReference =>
      _capstone2 &&
      _members.any((s) => s['requires_capstone2_reference'] != false);

  @override
  void initState() {
    super.initState();
    _students = widget.data.students;
    _event = widget.data.eventName;
    if (_pit && _event != null) _loadEvent(_event);
  }

  @override
  void dispose() {
    for (final c in [_name, _project, _reference, _section]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEvent(String? value) async {
    setState(() {
      _event = value;
      _selected.clear();
      _leader = null;
      _loading = true;
      _error = null;
    });
    try {
      final students = value == null
          ? widget.data.students
          : await widget.loadRoster(_level, value);
      if (mounted) setState(() => _students = students);
    } catch (e) {
      if (mounted) {
        setState(() {
          _students = [];
          _error = 'Could not load students. Try selecting the event again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _add(int? id) {
    if (id == null) return;
    if (_selected.length >= 4 && !_selected.contains(id)) {
      setState(() => _error = 'A team can have at most four members.');
      return;
    }
    setState(() {
      _selected.add(id);
      _leader ??= id;
      _confirmed = false;
      _search = '';
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty || _selected.isEmpty || _leader == null) {
      setState(
        () =>
            _error = 'Enter a team name, select members, and choose a leader.',
      );
      return;
    }
    if (_capstone2 &&
        (_project.text.trim().isEmpty ||
            !_confirmed ||
            (_needsReference && _reference.text.trim().isEmpty))) {
      setState(
        () => _error =
            'Enter the project title, confirm eligibility, and supply the school reference when required.',
      );
      return;
    }
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'project_title': _project.text.trim(),
      'leader_id': _leader,
      'member_ids': _selected.toList(),
      'adviser_id': _pit ? null : _adviser,
      'status': _capstone2 ? 'Pending' : _status,
      if (_section.text.trim().isNotEmpty) 'section': _section.text.trim(),
      if (_pit) 'level': _level,
      if (_pit) 'year_level': _year,
      if (_pit && _event != null) 'current_defense_stage': _event,
    };
    if (_capstone2) {
      final stamp = jsonEncode([payload, _reference.text.trim()]);
      if (_lastPayload != stamp) {
        _requestId = newCapstoneRequestId();
        _lastPayload = stamp;
      }
      payload['capstone2_confirmation'] = {
        'confirmed': _confirmed,
        'reference': _reference.text.trim(),
        'request_id': _requestId,
      };
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final error = await widget.save(payload);
      if (!mounted) return;
      if (error == null) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = error);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not confirm the save. Your entries are retained; retry to check the same request.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, Widget input) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 6),
      input,
    ],
  );
  Widget _input(String label, TextEditingController controller) => _field(
    label,
    ShadInput(
      key: ValueKey(label),
      controller: controller,
      enabled: !_saving,
      maxLength: label == 'Project title'
          ? 255
          : label == 'Section'
          ? 80
          : 120,
    ),
  );
  Widget _pair(Widget a, Widget b) => LayoutBuilder(
    builder: (_, box) => box.maxWidth >= 600
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 16),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: 14), b],
          ),
  );
  Widget _studentPicker() => LayoutBuilder(
    builder: (_, box) => ShadSelect<int>.withSearch(
      key: ValueKey('student-picker-${_selected.join(',')}'),
      enabled: !_saving && !_loading,
      minWidth: box.maxWidth,
      maxWidth: box.maxWidth,
      maxHeight: 240,
      placeholder: const Text('Add a student'),
      searchPlaceholder: const Text('Search by name or student ID'),
      clearSearchOnClose: true,
      onSearchChanged: (v) => setState(() => _search = v.toLowerCase().trim()),
      options: [
        for (final s in _students)
          if (!_selected.contains(_id(s['id'])) &&
              '${s['name']} ${s['username']}'.toLowerCase().contains(_search))
            ShadOption<int>(
              value: _id(s['id'])!,
              child: Text(
                '${s['name']} (${s['username']})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
      ],
      selectedOptionBuilder: (_, id) => const Text('Add a student'),
      onChanged: _add,
    ),
  );
  Widget _adviserPicker() => LayoutBuilder(
    builder: (_, box) => ShadSelect<int>(
      initialValue: _adviser ?? 0,
      enabled: !_saving,
      minWidth: box.maxWidth,
      maxWidth: box.maxWidth,
      maxHeight: 220,
      options: [
        const ShadOption(value: 0, child: Text('Unassigned')),
        for (final a in widget.data.advisers)
          ShadOption(
            value: _id(a['id'])!,
            child: Text(
              '${a['name']} (${a['username']})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      selectedOptionBuilder: (_, id) => Text(
        id == 0
            ? 'Unassigned'
            : widget.data.advisers
                  .firstWhere((a) => _id(a['id']) == id)['name']
                  .toString(),
        overflow: TextOverflow.ellipsis,
      ),
      onChanged: (id) => setState(() => _adviser = id == 0 ? null : id),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: ShadDialog(
        constraints: BoxConstraints(
          maxWidth: 840,
          maxHeight: MediaQuery.sizeOf(context).height - 32,
        ),
        title: Text(_capstone2 ? 'Add Capstone 2 team' : 'Add team'),
        description: Text(
          '${_pit
              ? _level
              : _capstone2
              ? 'Capstone 2'
              : 'Capstone 1'} · ${widget.data.activeSemester?['school_year'] ?? ''} ${widget.data.activeSemester?['label'] ?? 'Active semester'}',
        ),
        closeIcon: const SizedBox.shrink(),
        expandActionsWhenTiny: false,
        actions: [
          ShadButton.outline(
            enabled: !_saving,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ShadButton(
            enabled: !_saving && !_loading,
            onPressed: _save,
            child: Text(_saving ? 'Saving…' : 'Add team'),
          ),
        ],
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                _pair(
                  _input('Team name', _name),
                  _input('Project title', _project),
                ),
                const SizedBox(height: 16),
                _pair(
                  _input('Section', _section),
                  _pit
                      ? _field(
                          'Team result',
                          ShadSelect<String>(
                            initialValue: _status,
                            enabled: !_saving,
                            options: [
                              for (final s
                                  in widget.data.statuses.isEmpty
                                      ? ['Pending', 'Approved', 'Failed']
                                      : widget.data.statuses)
                                ShadOption(value: s, child: Text(s)),
                            ],
                            selectedOptionBuilder: (_, value) => Text(value),
                            onChanged: (value) =>
                                setState(() => _status = value ?? 'Pending'),
                          ),
                        )
                      : _field('Adviser', _adviserPicker()),
                ),
                if (!_pit && !_capstone2) ...[
                  const SizedBox(height: 16),
                  _field(
                    'Team result',
                    ShadSelect<String>(
                      initialValue: _status,
                      enabled: !_saving,
                      options: [
                        for (final status
                            in widget.data.statuses.isEmpty
                                ? ['Pending', 'Approved', 'Failed']
                                : widget.data.statuses)
                          ShadOption(value: status, child: Text(status)),
                      ],
                      selectedOptionBuilder: (_, value) => Text(value),
                      onChanged: (value) =>
                          setState(() => _status = value ?? 'Pending'),
                    ),
                  ),
                ],
                if (_pit && widget.data.pitEvents.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _field(
                    'PIT event',
                    ShadSelect<String>(
                      initialValue: _event ?? '',
                      enabled: !_saving && !_loading,
                      options: [
                        const ShadOption(value: '', child: Text('General PIT')),
                        for (final e in widget.data.pitEvents)
                          ShadOption(
                            value: e['event_name'].toString(),
                            child: Text(e['event_name'].toString()),
                          ),
                      ],
                      selectedOptionBuilder: (_, value) =>
                          Text(value.isEmpty ? 'General PIT' : value),
                      onChanged: (v) => _loadEvent(v == '' ? null : v),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Members',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text('${_selected.length} / 4'),
                  ],
                ),
                const SizedBox(height: 8),
                if (_loading) const LinearProgressIndicator(),
                _studentPicker(),
                for (final s in _members)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${s['name']}'),
                              Text(
                                '${s['username']}',
                                style: TextStyle(
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                  fontSize: 12,
                                  color: DefensysTokens.textSecondaryOf(
                                    context,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ShadButton.ghost(
                          foregroundColor: DefensysTokens.textPrimaryOf(
                            context,
                          ),
                          hoverForegroundColor: DefensysTokens.textPrimaryOf(
                            context,
                          ),
                          enabled: !_saving,
                          onPressed: () => setState(() {
                            _selected.remove(_id(s['id']));
                            if (_leader == _id(s['id'])) {
                              _leader = _selected.firstOrNull;
                            }
                            _confirmed = false;
                          }),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  ),
                if (_selected.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _field(
                    'Leader',
                    LayoutBuilder(
                      builder: (_, box) => ShadSelect<int>(
                        key: ValueKey('leader-$_leader-${_selected.join(',')}'),
                        initialValue: _leader,
                        enabled: !_saving,
                        minWidth: box.maxWidth,
                        maxWidth: box.maxWidth,
                        options: [
                          for (final s in _members)
                            ShadOption(
                              value: _id(s['id'])!,
                              child: Text('${s['name']}'),
                            ),
                        ],
                        selectedOptionBuilder: (_, id) => Text(
                          _members
                              .firstWhere((s) => _id(s['id']) == id)['name']
                              .toString(),
                        ),
                        onChanged: (id) => setState(() => _leader = id),
                      ),
                    ),
                  ),
                ],
                if (_capstone2) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),
                  Capstone2ConfirmationFields(
                    confirmed: _confirmed,
                    onChanged: (v) => setState(() => _confirmed = v),
                    reference: _reference,
                    needsReference: _needsReference,
                    enabled: !_saving,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    key: const Key('team-form-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
