import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/defense/capstone_scheduling_api.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/app/unsaved_changes_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/shadcn/workflow_step_progress.dart';
import '../models/capstone_planning_draft.dart';
import 'scheduler_people_picker.dart';
import 'capstone_adviser_readiness.dart';
import '../dialogs/capstone_replacement_dialog.dart';

class CapstoneSchedulingWorkspace extends ConsumerStatefulWidget {
  const CapstoneSchedulingWorkspace({
    super.key,
    this.initialStageId,
    required this.onSaved,
  });
  final int? initialStageId;
  final Future<void> Function() onSaved;
  @override
  ConsumerState<CapstoneSchedulingWorkspace> createState() =>
      _CapstoneSchedulingWorkspaceState();
}

class _CapstoneSchedulingWorkspaceState
    extends ConsumerState<CapstoneSchedulingWorkspace> {
  final _date = TextEditingController();
  final _minutes = TextEditingController();
  final _room = TextEditingController();
  final _gap = TextEditingController(text: '0');
  final _skipDate = TextEditingController();
  final _windows = <List<TextEditingController>>[];
  final _rosters = <int, CapstoneRosterDraft>{};
  final _temporaryChanges = <int, Map<String, dynamic>>{};
  final _editingRosters = <int, CapstoneRosterDraft>{};
  final _replacementEvents = <Map<String, dynamic>>[];
  final _selected = <int>{};
  final _excluded = <String>{};
  List<CapstoneAdviserGroup> _groups = [];
  Map<String, dynamic>? _workspace, _preview;
  List<Map<String, dynamic>> _invitations = [];
  String? _error, _notice;
  String _confirmKey = '';
  int? _stage;
  int _step = 1, _generation = 0;
  bool _busy = false, _previewing = false, _sunday = false, _loading = true;
  bool _replacementDialogOpen = false;
  BuildContext? _shadContext;
  Timer? _debounce;
  late final UnsavedChangesNotifier _unsaved;
  late final UnsavedChangesSaveDraftNotifier _saveDraftNotifier;
  CapstoneSchedulingApi get _api => ref.read(capstoneSchedulingApiProvider);
  List<Map<String, dynamic>> get _teams => capstoneMaps(_workspace?['teams']);
  List<Map<String, dynamic>> get _stages => capstoneMaps(_workspace?['stages']);
  Map<String, dynamic>? get _stageData =>
      _stages.where((s) => s['id'] == _stage).firstOrNull;
  List<Map<String, dynamic>> get _slots => capstoneMaps(_preview?['slots']);
  List<int> get _queue => [
    for (final group in _groups)
      for (final team in group.teams)
        if (_selected.contains(capstoneId(team['id']))) capstoneId(team['id'])!,
  ];
  String get _draftKey =>
      'capstone-auto:${ref.read(authProvider).user?['id']}:'
      '${_workspace?['semester_id']}:$_stage:${_teams.map((t) => '${t['id']}/${t['project_version']}/${t['intake_semester_id']}').join(',')}';
  CapstoneRosterDraft _actualRoster(int id) =>
      _rosters[id]!.applying(_temporaryChanges[id] ?? {});
  CapstoneRosterDraft _displayRoster(int id) =>
      _editingRosters[id] ?? _actualRoster(id);

  @override
  void initState() {
    super.initState();
    _unsaved = ref.read(unsavedChangesProvider.notifier);
    _saveDraftNotifier = ref.read(unsavedChangesSaveDraftProvider.notifier);
    _stage = widget.initialStageId;
    _addWindow('08:00', '12:00');
    _addWindow('13:00', '17:00');
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant CapstoneSchedulingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = widget.initialStageId;
    if (_workspace != null &&
        requested != null &&
        requested != oldWidget.initialStageId &&
        requested != _stage &&
        _stages.any((s) => s['id'] == requested)) {
      unawaited(_followEntryStage(requested));
    }
  }

  Future<void> _followEntryStage(int stage) async {
    await _saveDraft();
    if (!mounted) return;
    _stage = stage;
    await _initializeStage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    releaseUnsavedChangesAfterFrame(_unsaved, _saveDraftNotifier);
    for (final c in [
      _date,
      _minutes,
      _room,
      _gap,
      _skipDate,
      ..._windows.expand((w) => w),
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addWindow(String start, String end) => _windows.add([
    TextEditingController(text: start),
    TextEditingController(text: end),
  ]);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.workspace();
      if (!mounted) return;
      _workspace = data;
      _stage = widget.initialStageId ?? _stage;
      if (!_stages.any((s) => s['id'] == _stage)) {
        _stage = capstoneId(_stages.firstOrNull?['id']);
      }
      await _initializeStage();
    } catch (e) {
      if (mounted) _error = _message(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _initializeStage() async {
    _generation++;
    _debounce?.cancel();
    _preview = null;
    _step = 1;
    _selected.clear();
    _excluded.clear();
    _sunday = false;
    _rosters.clear();
    _temporaryChanges.clear();
    _editingRosters.clear();
    _replacementEvents.clear();
    final applicable = _teams
        .where((t) => (t['applicable_stage_ids'] as List).contains(_stage))
        .toList();
    _groups = capstoneGroups(applicable);
    for (final team in applicable) {
      final id = capstoneId(team['id'])!;
      _rosters[id] = CapstoneRosterDraft.fromJson(
        team['assignment'] == null
            ? null
            : Map<String, dynamic>.from(team['assignment']),
      );
      if ((team['ready_stage_ids'] as List).contains(_stage)) _selected.add(id);
    }
    _minutes.text =
        _stageData?['default_slot_duration_minutes']?.toString() ?? '';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final start = _workspace?['starts_on']?.toString();
    _date.text = start != null && today.compareTo(start) < 0 ? start : today;
    _room.clear();
    _gap.text = '0';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw != null) {
      try {
        final draft = jsonDecode(raw) as Map;
        final revisions = draft['assignment_revisions'] as Map? ?? {};
        final people = draft['people'] as Map? ?? {};
        final temporary = draft['temporary_changes'] as Map? ?? {};
        final pending = draft['pending_people'] as Map? ?? {};
        final matchingIds = <int>{};
        for (final team in applicable) {
          final id = capstoneId(team['id'])!;
          // A newer server assignment wins over an older local people draft.
          if (revisions['$id'] == team['assignment_revision']) {
            matchingIds.add(id);
            if (people['$id'] is Map) {
              _rosters[id] = CapstoneRosterDraft.fromJson(
                Map<String, dynamic>.from(people['$id']),
              );
            }
            if (temporary['$id'] is Map) {
              _temporaryChanges[id] = Map<String, dynamic>.from(
                temporary['$id'],
              );
            }
            if (pending['$id'] is Map) {
              _editingRosters[id] = CapstoneRosterDraft.fromJson(
                Map<String, dynamic>.from(pending['$id']),
              );
            }
          }
        }
        for (final event in capstoneMaps(draft['replacement_events'])) {
          final ids = (event['team_ids'] as List? ?? [])
              .map(capstoneId)
              .whereType<int>()
              .where(matchingIds.contains)
              .toList();
          if (ids.isNotEmpty) {
            _replacementEvents.add({...event, 'team_ids': ids});
          }
        }
        // Older drafts had a reason field and a checkbox rather than reviewed
        // replacement decisions. Keep their choices pending explicit review.
        if (_replacementEvents.isEmpty) {
          for (final team in applicable.where((t) => t['assignment'] != null)) {
            final id = capstoneId(team['id'])!;
            final proposed = _displayRoster(id).copy();
            final saved = CapstoneRosterDraft.fromJson(
              Map<String, dynamic>.from(team['assignment']),
            );
            if (capstoneRosterDeltaHasChanges(
              proposed.changesFrom(saved.toJson()),
            )) {
              _editingRosters[id] = proposed;
              _rosters[id] = saved;
              _temporaryChanges.remove(id);
            }
          }
        }
        _date.text = draft['start_date'] ?? _date.text;
        _minutes.text = '${draft['slot_duration'] ?? _minutes.text}';
        _room.text = draft['room'] ?? '';
        _gap.text = '${draft['gap_minutes'] ?? 0}';
        _sunday = draft['include_sunday'] == true;
        _excluded.addAll(
          (draft['excluded_dates'] as List? ?? []).cast<String>(),
        );
        final order = (draft['group_order'] as List? ?? []).cast<String>();
        _groups.sort(
          (a, b) =>
              (order.contains(a.key) ? order.indexOf(a.key) : order.length)
                  .compareTo(
                    order.contains(b.key) ? order.indexOf(b.key) : order.length,
                  ),
        );
        final windows = capstoneMaps(draft['windows']);
        if (windows.isNotEmpty) {
          for (final w in _windows) {
            for (final c in w) {
              c.dispose();
            }
          }
          _windows.clear();
          for (final w in windows) {
            _addWindow('${w['start_time']}', '${w['end_time']}');
          }
        }
        _notice = 'Saved planning inputs restored for this intake and stage.';
      } catch (_) {
        await prefs.remove(_draftKey);
      }
    }
    _normaliseAdviserDrafts();
    if (mounted) setState(() {});
  }

  void _normaliseAdviserDrafts() {
    for (final group in _groups) {
      final rosters = group.teams.map((t) => _displayRoster(t['id'])).toList();
      if (rosters.map((r) => r.signature).toSet().length <= 1) continue;
      group.hasMixedAssignments = true;
      final first = rosters.first;
      final common = CapstoneRosterDraft(
        chair: rosters.every((r) => r.chair == first.chair)
            ? first.chair
            : null,
        documenter: rosters.every((r) => r.documenter == first.documenter)
            ? first.documenter
            : null,
        members:
            rosters.every(
              (r) => jsonEncode(r.members) == jsonEncode(first.members),
            )
            ? List.of(first.members)
            : null,
        externals:
            rosters.every(
              (r) => jsonEncode(r.externals) == jsonEncode(first.externals),
            )
            ? List.of(first.externals)
            : [],
      );
      for (final team in group.teams) {
        _editingRosters[team['id']] = common.copy();
      }
    }
  }

  bool _formComplete(CapstoneRosterDraft roster) =>
      roster.complete &&
      (_stageData?['minutes_required'] != true || roster.documenter != null);

  String _replacementReason(String scope, {int? teamId}) => _replacementEvents
      .where(
        (event) =>
            event['scope'] == scope &&
            (teamId == null || (event['team_ids'] as List).contains(teamId)),
      )
      .map((event) => '${event['reason']}')
      .toSet()
      .join('; ');

  List<Map<String, dynamic>> _eventsForPlan() => [
    for (final event in _replacementEvents)
      if ((event['team_ids'] as List).any(_selected.contains))
        {
          ...event,
          'team_ids': (event['team_ids'] as List)
              .where(_selected.contains)
              .toList(),
          'changes': {
            for (final entry in (event['changes'] as Map? ?? {}).entries)
              if (_selected.contains(capstoneId(entry.key)) &&
                  (event['team_ids'] as List).contains(capstoneId(entry.key)))
                '${entry.key}': entry.value,
          },
        },
  ];

  void _editAdviserRoster(
    CapstoneAdviserGroup group,
    void Function(CapstoneRosterDraft) edit,
  ) {
    if (_busy || _replacementDialogOpen) return;
    final proposed = _displayRoster(group.teams.first['id']).copy();
    edit(proposed);
    final saved = group.teams.any((team) => team['assignment'] != null);
    for (final team in group.teams) {
      final id = capstoneId(team['id'])!;
      if (saved) {
        _editingRosters[id] = proposed.copy();
      } else {
        _rosters[id] = proposed.copy();
      }
    }
    _changed(plan: false);
    if (saved && _formComplete(proposed)) {
      unawaited(_reviewPendingReplacements(groups: [group]).then<void>((_) {}));
    }
  }

  Future<bool> _reviewPendingReplacements({
    List<CapstoneAdviserGroup>? groups,
  }) async {
    if (_replacementDialogOpen) return false;
    final decisions = <String, CapstoneReplacementDecision>{};
    final proposals = <String, CapstoneRosterDraft>{};
    final targets = groups ?? _groups;
    setState(() => _replacementDialogOpen = true);
    try {
      // Let a people-picker popover close before opening its replacement dialog.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return false;
      for (final group in targets) {
        if (!group.teams.any((t) => _editingRosters.containsKey(t['id']))) {
          continue;
        }
        final proposed = _displayRoster(group.teams.first['id']).copy();
        if (!_formComplete(proposed)) return false;
        proposals[group.key] = proposed;
        final changed = group.teams.any(
          (t) =>
              t['assignment'] != null &&
              capstoneRosterDeltaHasChanges(
                proposed.changesFrom(_actualRoster(t['id']).toJson()),
              ),
        );
        if (!changed) continue;
        final decision = await showShadDialog<CapstoneReplacementDecision>(
          context: _shadContext ?? context,
          barrierLabel: 'Cancel assignment change',
          builder: (_) => CapstoneReplacementDialog(
            adviser: group.name,
            stage: '${_stageData?['label'] ?? ''}',
            changes: [
              for (final team in group.teams)
                {
                  'team': '${team['name']}',
                  'before': _rosterSummary(_actualRoster(team['id']).toJson()),
                  'after': _rosterSummary(proposed.toJson()),
                },
            ],
          ),
        );
        if (!mounted) return false;
        if (decision == null) {
          for (final team in group.teams) {
            _editingRosters.remove(team['id']);
          }
          setState(() {});
          return false;
        }
        decisions[group.key] = decision;
      }
      for (final group in targets) {
        final proposed = proposals[group.key];
        if (proposed == null) continue;
        final decision = decisions[group.key];
        final existing = group.teams
            .where((t) => t['assignment'] != null)
            .firstOrNull;
        final continuingForNew = existing == null
            ? proposed
            : _rosters[existing['id']]!.copy();
        final changes = <String, dynamic>{};
        for (final team in group.teams) {
          final id = capstoneId(team['id'])!;
          final delta = proposed.changesFrom(_actualRoster(id).toJson());
          changes['$id'] = delta;
          if (decision == null) {
            if (team['assignment'] == null) _rosters[id] = proposed.copy();
          } else if (decision.continuing) {
            _rosters[id] = team['assignment'] == null
                ? proposed.copy()
                : _rosters[id]!.applying(
                    capstoneContinuingDelta(
                      delta,
                      _rosters[id]!.toJson(),
                      _replacementEvents
                          .where(
                            (event) =>
                                event['scope'] == 'stage_only' &&
                                (event['team_ids'] as List).contains(id),
                          )
                          .map(
                            (event) => Map<String, dynamic>.from(
                              (event['changes'] as Map)['$id'] as Map? ?? {},
                            ),
                          ),
                    ),
                  );
          } else if (team['assignment'] == null) {
            _rosters[id] = continuingForNew.copy();
          }
          final temporary = proposed.changesFrom(_rosters[id]!.toJson());
          if (capstoneRosterDeltaHasChanges(temporary)) {
            _temporaryChanges[id] = temporary;
          } else {
            _temporaryChanges.remove(id);
          }
          _editingRosters.remove(id);
        }
        if (decision != null) {
          _replacementEvents.add({
            'scope': decision.scope,
            'reason': decision.reason,
            'team_ids': group.teams.map((t) => t['id']).toList(),
            'changes': changes,
          });
        }
      }
      if (proposals.isNotEmpty) _changed(plan: false);
      return true;
    } finally {
      if (mounted) setState(() => _replacementDialogOpen = false);
    }
  }

  void _resetAdviserChanges(CapstoneAdviserGroup group) {
    final ids = group.teams.map((t) => t['id']).toSet();
    for (final team in group.teams) {
      final id = capstoneId(team['id'])!;
      _rosters[id] = CapstoneRosterDraft.fromJson(
        team['assignment'] == null
            ? null
            : Map<String, dynamic>.from(team['assignment']),
      );
      _temporaryChanges.remove(id);
      _editingRosters.remove(id);
    }
    _replacementEvents.removeWhere(
      (event) => (event['team_ids'] as List).any(ids.contains),
    );
    _changed(plan: false);
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
  Map<String, dynamic> _inputs() => {
    'semester_id': _workspace!['semester_id'],
    'defense_stage_id': _stage,
    'team_ids': _queue,
    'start_date': _date.text.trim(),
    'slot_duration': int.tryParse(_minutes.text),
    'gap_minutes': int.tryParse(_gap.text),
    'room': _room.text.trim(),
    'include_sunday': _sunday,
    'excluded_dates': _excluded.toList()..sort(),
    'windows': [
      for (final w in _windows)
        {'start_time': w[0].text.trim(), 'end_time': w[1].text.trim()},
    ],
    'overrides': {
      for (final id in _selected)
        if (_temporaryChanges.containsKey(id))
          '$id': _actualRoster(id).toJson(),
    },
    if (_replacementReason('stage_only').isNotEmpty)
      'replacement_reason': _replacementReason('stage_only'),
    if (_eventsForPlan().isNotEmpty) 'replacement_events': _eventsForPlan(),
  };

  Future<bool> _saveDraft() async {
    if (_workspace == null) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _draftKey,
      jsonEncode({
        ..._inputs(),
        'group_order': _groups.map((g) => g.key).toList(),
        'replacement_events': _replacementEvents,
        'pending_people': {
          for (final entry in _editingRosters.entries)
            '${entry.key}': entry.value.toJson(),
        },
        'people': {
          for (final entry in _rosters.entries)
            '${entry.key}': entry.value.toJson(),
        },
        'temporary_changes': {
          for (final entry in _temporaryChanges.entries)
            '${entry.key}': entry.value,
        },
        'assignment_revisions': {
          for (final team in _teams)
            '${team['id']}': team['assignment_revision'],
        },
      }),
    );
    _unsaved.setDirty(false);
    return true;
  }

  void _changed({bool plan = true}) {
    _generation++;
    _preview = null;
    _previewing = false;
    _error = null;
    _notice = null;
    _unsaved.setDirty(true);
    _saveDraftNotifier.setCallback(_saveDraft);
    setState(() {});
    _debounce?.cancel();
    if (plan && _step > 1) {
      _debounce = Timer(const Duration(milliseconds: 450), _calculate);
    }
  }

  Future<void> _calculate() async {
    final generation = ++_generation;
    if (_queue.isEmpty ||
        _room.text.trim().isEmpty ||
        int.tryParse(_minutes.text) == null ||
        DateTime.tryParse(_date.text) == null) {
      setState(() {
        _previewing = false;
        _error =
            'Choose ready teams, a start date, minutes per team, and a room.';
      });
      return;
    }
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final plan = await _api.preview(_inputs());
      if (!mounted || generation != _generation) return;
      setState(() {
        _preview = plan;
        _confirmKey = _uuid();
      });
      await _saveDraft();
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _previewing = false);
      }
    }
  }

  Future<void> _savePeople() async {
    if (_busy || _replacementDialogOpen) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final group in _groups) {
        if (!_formComplete(_displayRoster(group.teams.first['id']))) {
          throw Exception(
            'Complete the panel and required documenter for ${group.name}, or remove empty extra slots.',
          );
        }
      }
      if (!await _reviewPendingReplacements()) return;
      if (!mounted) return;
      // The form chooses one roster per adviser. Writes remain project-owned
      // so new intakes and historical hearings retain their own identities.
      final edits = <String, Map<String, dynamic>>{};
      for (final group in _groups) {
        if (group.teams
                .map((t) => _actualRoster(t['id']).signature)
                .toSet()
                .length >
            1) {
          throw Exception(
            'Review the shared panel and documenter for ${group.name} before continuing.',
          );
        }
        for (final team in group.teams) {
          final id = capstoneId(team['id'])!;
          final draft = _rosters[id]!;
          if (!draft.complete) {
            throw Exception(
              'Complete the panel for ${group.name} or remove empty extra slots.',
            );
          }
          final before = team['assignment'];
          final changes = before == null
              ? null
              : draft.changesFrom(Map<String, dynamic>.from(before));
          if (changes != null && !capstoneRosterDeltaHasChanges(changes)) {
            continue;
          }
          final edit = before == null
              ? {'roster': draft.toJson()}
              : {'changes': changes};
          final reason = before == null
              ? null
              : _replacementReason('continuing', teamId: id);
          final signature = jsonEncode([edit, reason]);
          final batch = edits.putIfAbsent(
            signature,
            () => {
              'semester_id': _workspace!['semester_id'],
              'defense_stage_id': _stage,
              'team_ids': <int>[],
              'expected_revisions': <String, int>{},
              if (reason != null) 'reason': reason,
              ...edit,
            },
          );
          (batch['team_ids'] as List<int>).add(id);
          (batch['expected_revisions'] as Map<String, int>)['$id'] =
              capstoneId(team['assignment_revision']) ?? 0;
        }
      }
      for (final edit in edits.values) {
        _workspace = await _api.savePeople(edit);
      }
      if (!mounted) return;
      _replacementEvents.removeWhere((event) => event['scope'] == 'continuing');
      // Refresh baseline revisions without discarding independently edited drafts.
      final fresh = {for (final t in _teams) t['id']: t};
      for (final g in _groups) {
        for (var i = 0; i < g.teams.length; i++) {
          g.teams[i] = fresh[g.teams[i]['id']]!;
        }
        g.hasMixedAssignments = false;
      }
      _selected.clear();
      for (final group in _groups) {
        for (final team in group.teams) {
          if (capstoneTeamReadiness(team, _stage)['can_schedule'] == true) {
            _selected.add(team['id']);
          }
        }
      }
      if (_queue.isEmpty) {
        setState(
          () => _notice =
              'Adviser assignments saved. Teams can be scheduled after endorsement.',
        );
        await _saveDraft();
        return;
      }
      setState(() {
        _step = 2;
        _notice = _temporaryChanges.isEmpty
            ? 'Adviser assignments saved. Later stages preload these people.'
            : 'People assigned for this stage. Stage-only replacements keep the continuing roster for later stages.';
      });
      _goToStep(2);
      if (_room.text.trim().isNotEmpty && int.tryParse(_minutes.text) != null) {
        await _calculate();
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final token = _preview?['preview_token'];
    if (token is! String || _preview?['complete'] != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.confirm(token, _confirmKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      _unsaved.setDirty(false);
      await widget.onSaved();
      if (!mounted) return;
      setState(() {
        _notice = '${result['created_count']} defenses scheduled.';
        _invitations = capstoneMaps(result['created_invitations']);
        _preview = null;
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _uuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Widget _button(String label, VoidCallback? action, {bool primary = false}) =>
      primary
      ? ShadButton(
          backgroundColor: DefensysTokens.maroonOf(context),
          foregroundColor: Colors.white,
          enabled: !_busy && !_replacementDialogOpen && action != null,
          onPressed: _busy || _replacementDialogOpen ? null : action,
          child: Text(label),
        )
      : ShadButton.outline(
          enabled: !_busy && !_replacementDialogOpen && action != null,
          onPressed: _busy || _replacementDialogOpen ? null : action,
          child: Text(label),
        );

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      border: Border.all(color: DefensysTokens.borderOf(context)),
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
    ),
    child: child,
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    bool number = false,
    String? hint,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 8),
      ShadInput(
        controller: controller,
        enabled: !_busy,
        placeholder: hint == null ? null : Text(hint),
        keyboardType: number ? TextInputType.number : TextInputType.text,
        style: const TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontSize: 13,
        ),
        onChanged: (_) => _changed(),
      ),
      const SizedBox(height: 14),
    ],
  );

  Widget _dateField(String label, TextEditingController controller) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label),
      const SizedBox(height: 8),
      ShadDatePicker(
        key: ValueKey('$label-${controller.text}'),
        selected: DateTime.tryParse(controller.text),
        enabled: !_busy,
        closeOnSelection: true,
        allowDeselection: false,
        placeholder: const Text('Select date'),
        formatDate: (d) => DateFormat.yMMMd().format(d),
        onChanged: (d) {
          if (d != null) {
            controller.text = DateFormat('yyyy-MM-dd').format(d);
            _changed();
          }
        },
      ),
      const SizedBox(height: 14),
    ],
  );

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Builder(
      builder: (shadContext) {
        _shadContext = shadContext;
        return _workspaceBody();
      },
    ),
  );

  Widget _workspaceBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_workspace == null)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Could not load scheduling workspace',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error ?? 'Scheduling data is unavailable. Please retry.',
                ),
              ),
              const SizedBox(height: 14),
              _button('Retry', _load, primary: true),
            ],
          ),
        )
      else ...[
        _workspaceContext(),
        if (_stages.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Configure the stage pipeline in Defense Stages before scheduling.',
            ),
          ),
        const SizedBox(height: 20),
        WorkflowStepProgress(
          currentStep: _step,
          labels: const ['Assign people', 'Dates & sessions', 'Order & review'],
          compactLabels: const ['People', 'Dates', 'Review'],
        ),
        const SizedBox(height: 18),
        if (_notice != null) _panel(Text(_notice!)),
        if (_error != null)
          _panel(
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: DefensysTokens.dangerText),
              ),
            ),
          ),
        if (_stages.isNotEmpty) ...[
          if (_step == 1)
            _people()
          else if (_step == 2)
            _dates()
          else
            _sorter(),
        ],
        if (_invitations.isNotEmpty)
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('External evaluator access'),
                for (final invite in _invitations)
                  SelectableText(
                    '${invite['evaluator_name'] ?? invite['name'] ?? ''}: ${invite['code'] ?? ''}',
                  ),
              ],
            ),
          ),
      ],
    ],
  );

  Widget _workspaceContext() {
    final summary = CapstoneReadinessSummary([
      for (final group in _groups) ...group.teams,
    ], _stage);
    final stage = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stage: ${_stageData?['label'] ?? 'Not configured'}',
          key: const ValueKey('capstone-stage-context'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 5),
        Text(
          'Panel and documenter assignments by adviser',
          style: TextStyle(
            fontSize: 13,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    );
    final status = Semantics(
      liveRegion: true,
      label: 'Overall team readiness',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CapstoneReadinessBadge(
            key: const ValueKey('overall-readiness'),
            status: summary.status,
            label: summary.label,
          ),
          const SizedBox(height: 6),
          Text(
            '${summary.ready}/${summary.total} teams ready · ${summary.endorsed} endorsed',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 700
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: stage),
                const SizedBox(width: 20),
                status,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                stage,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: status),
              ],
            ),
    );
  }

  Widget _adviserHeader(CapstoneAdviserGroup group) {
    final summary = CapstoneReadinessSummary(group.teams, _stage);
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          '${group.teams.length} ${group.teams.length == 1 ? 'team' : 'teams'} · ${group.intake}',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    );
    final badge = CapstoneReadinessBadge(
      status: summary.status,
      label: summary.label,
    );
    final collapse = Tooltip(
      message:
          '${group.expanded ? 'Collapse' : 'Expand'} ${group.name} assignments',
      child: ShadButton.ghost(
        key: ValueKey('collapse-${group.key}'),
        width: 34,
        height: 34,
        padding: EdgeInsets.zero,
        onPressed: _busy
            ? null
            : () => setState(() => group.expanded = !group.expanded),
        child: Icon(
          group.expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 20,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 650
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: name),
                badge,
                const SizedBox(width: 12),
                collapse,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: 10),
                    collapse,
                  ],
                ),
                const SizedBox(height: 10),
                badge,
              ],
            ),
    );
  }

  Widget _adviserAdoption(CapstoneAdviserGroup group) {
    final candidates = group.teams
        .map((t) => t['adoption_candidate'])
        .whereType<Map>()
        .toList();
    if (candidates.isEmpty) return const SizedBox.shrink();
    final rosters = candidates
        .where((c) => c['requires_review'] == false && c['roster'] is Map)
        .map(
          (c) => CapstoneRosterDraft.fromJson(
            Map<String, dynamic>.from(c['roster']),
          ),
        )
        .toList();
    if (rosters.isEmpty ||
        candidates.any((c) => c['requires_review'] == true) ||
        rosters.map((r) => r.signature).toSet().length != 1) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text(
          'Existing first-stage people need review. Choose this adviser’s shared roster below.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Existing first-stage people',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(_rosterSummary(rosters.first.toJson())),
          const SizedBox(height: 8),
          _button(
            'Use reviewed adviser roster',
            group.teams.every((t) => t['initial_stage_id'] == _stage)
                ? () {
                    for (final team in group.teams) {
                      _rosters[team['id']] = rosters.first.copy();
                    }
                    _changed(plan: false);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _people() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Assign one panel and documenter per adviser. Endorsed teams are included automatically.',
      ),
      const SizedBox(height: 12),
      for (final group in _groups)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _adviserHeader(group),
              if (group.teams.length > 4)
                const Text(
                  'Existing adviser overload: review these teams before adding more.',
                ),
              const SizedBox(height: 10),
              CapstoneAdviserReadiness(
                key: ValueKey('readiness-${group.key}-$_stage'),
                group: group,
                stageId: _stage,
              ),
              if (group.expanded) ...[
                const SizedBox(height: 18),
                if (group.hasMixedAssignments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      'Existing team assignments differ. Choose one shared panel and documenter for ${group.name}; saving applies these choices to all ${group.teams.length} teams.',
                    ),
                  ),
                _adviserAdoption(group),
                _rosterEditor(group, group.teams),
                if (group.teams.any(
                      (t) =>
                          _editingRosters.containsKey(t['id']) ||
                          _temporaryChanges.containsKey(t['id']),
                    ) ||
                    _replacementEvents.any(
                      (e) => (e['team_ids'] as List).any(
                        group.teams.map((t) => t['id']).contains,
                      ),
                    )) ...[
                  const SizedBox(height: 12),
                  Text(
                    group.teams.any(
                          (t) => _temporaryChanges.containsKey(t['id']),
                        )
                        ? 'Stage-only replacement selected. Later stages keep the continuing people.'
                        : 'Changes are ready to assign.',
                  ),
                  const SizedBox(height: 8),
                  _button(
                    'Reset pending changes',
                    () => _resetAdviserChanges(group),
                  ),
                ],
              ],
            ],
          ),
        ),
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Documenter workload · current intake teams'),
            const SizedBox(height: 10),
            ..._documenterLoads(),
          ],
        ),
      ),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 10,
        children: [
          _button('Refresh roster', _load),
          _button(
            _busy ? 'Assigning…' : 'Assign',
            _groups.isEmpty ? null : _savePeople,
            primary: true,
          ),
        ],
      ),
    ],
  );

  List<Widget> _documenterLoads() {
    final counts = <int, int>{};
    for (final id in _rosters.keys) {
      final roster = _displayRoster(id);
      if (roster.documenter != null) {
        counts.update(roster.documenter!, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return [
      for (final entry in counts.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${_personName(entry.key)} · ${entry.value} teams · ${entry.value} expected records for this stage'
            '${capstoneMaps(_workspace?['documenter_workloads']).where((w) => w['documenter_id'] == entry.key).map((w) => ' · ${w['outstanding_minutes']} outstanding confirmed records').join()}',
          ),
        ),
      if (counts.isEmpty)
        const Text('Assign documenters to see the distribution.'),
    ];
  }

  String _personName(int id, {bool external = false}) {
    final people = capstoneMaps(
      _workspace?[external ? 'external_evaluators' : 'faculty'],
    );
    final person = people.where((p) => capstoneId(p['id']) == id).firstOrNull;
    return person == null ? 'Person $id' : schedulerPersonName(person);
  }

  Widget _rosterEditor(
    CapstoneAdviserGroup group,
    List<Map<String, dynamic>> targets,
  ) {
    final roster = _displayRoster(targets.first['id']);
    final facultyCount = capstoneMaps(_workspace?['panelists'])
        .where(
          (p) =>
              capstoneId(p['id']) != group.adviserId &&
              capstoneId(p['id']) != roster.documenter,
        )
        .length;
    final canAddFaculty = roster.members.length + 1 < min(facultyCount, 500);
    final canAddExternal =
        roster.externals.length <
        min(capstoneMaps(_workspace?['external_evaluators']).length, 30);
    void update(void Function(CapstoneRosterDraft) edit) {
      _editAdviserRoster(group, edit);
    }

    Widget picker(
      String label,
      int? selected,
      void Function(int?) change, {
      bool external = false,
      bool doc = false,
    }) {
      final used = {
        roster.chair,
        ...roster.members,
        if (!doc) roster.documenter,
      };
      final people =
          capstoneMaps(
                _workspace?[external
                    ? 'external_evaluators'
                    : doc
                    ? 'faculty'
                    : 'panelists'],
              )
              .where(
                (p) =>
                    capstoneId(p['id']) == selected ||
                    (external
                        ? !roster.externals.contains(capstoneId(p['id']))
                        : capstoneId(p['id']) != group.adviserId &&
                              !used.contains(capstoneId(p['id']))),
              )
              .toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            SchedulerPeoplePicker(
              key: ValueKey('adviser-${group.key}-$label'),
              people: people,
              selected: {if (selected != null) selected},
              onChanged: (ids) => change(ids.firstOrNull),
              multiple: false,
              showClearButton: doc,
              enabled: !_busy && !_replacementDialogOpen,
              placeholder:
                  'Choose ${external ? 'external evaluator' : 'person'}',
              emptyMessage: 'No other eligible people are available.',
            ),
          ],
        ),
      );
    }

    final members = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < roster.members.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: picker(
                  'Panel member ${i + 1}',
                  roster.members[i],
                  (id) => update((r) => r.members[i] = id),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 10),
                child: _button(
                  'Remove',
                  () => update((r) => r.members.removeAt(i)),
                ),
              ),
            ],
          ),
        for (var i = 0; i < roster.externals.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: picker(
                  'External panel member ${i + 1}',
                  roster.externals[i],
                  (id) => update((r) => r.externals[i] = id),
                  external: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 10),
                child: _button(
                  'Remove',
                  () => update((r) => r.externals.removeAt(i)),
                ),
              ),
            ],
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _button(
              '+ Panel member',
              canAddFaculty ? () => update((r) => r.members.add(null)) : null,
            ),
            _button(
              '+ External panelist',
              canAddExternal
                  ? () => update((r) => r.externals.add(null))
                  : null,
            ),
          ],
        ),
        if (!canAddFaculty || !canAddExternal)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              !canAddFaculty
                  ? 'All available faculty positions are represented.'
                  : 'No additional approved external evaluators are available.',
            ),
          ),
      ],
    );
    final chair = picker(
      'Panel chair',
      roster.chair,
      (id) => update((r) => r.chair = id),
    );
    final documenter = picker(
      'Documenter',
      roster.documenter,
      (id) => update((r) => r.documenter = id),
      doc: true,
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 900
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: chair),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: members),
                const SizedBox(width: 20),
                Expanded(child: documenter),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                chair,
                members,
                const SizedBox(height: 14),
                documenter,
              ],
            ),
    );
  }

  Widget _dates() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('${_stageData?['label']} · ${_queue.length} teams · One room'),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, c) {
          final fields = [
            _dateField('Start date', _date),
            _field('Minutes per team (15–240)', _minutes, number: true),
            _field('Room', _room),
          ];
          return c.maxWidth < 700
              ? Column(children: fields)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final field in fields)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: field,
                        ),
                      ),
                  ],
                );
        },
      ),
      LayoutBuilder(
        builder: (context, c) => c.maxWidth < 1000
            ? Column(
                children: [
                  _dateControls(),
                  const SizedBox(height: 18),
                  _calculated(),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _dateControls()),
                  const SizedBox(width: 24),
                  Expanded(child: _calculated()),
                ],
              ),
      ),
      const SizedBox(height: 20),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          _button('← Assignments', () => _goToStep(1)),
          _button('Recalculate', _calculate),
          _button(
            'Order & review →',
            _preview == null || _previewing ? null : () => _goToStep(3),
            primary: true,
          ),
        ],
      ),
    ],
  );

  Widget _dateControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [Text('Scheduled dates'), Text('Filled automatically')],
      ),
      const SizedBox(height: 12),
      _calendar(),
      const SizedBox(height: 10),
      const Text(
        'Uncheck a scheduled date to skip it. Crossed-out dates are unavailable.',
      ),
      const SizedBox(height: 22),
      const Text('Daily sessions'),
      const SizedBox(height: 12),
      for (var i = 0; i < _windows.length; i++)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i == 0
                    ? 'Morning'
                    : i == 1
                    ? 'Afternoon'
                    : 'Session ${i + 1}',
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field('Start', _windows[i][0], hint: 'HH:mm'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _field('End', _windows[i][1], hint: 'HH:mm')),
                ],
              ),
              _button(
                'Remove session',
                _windows.length <= 1
                    ? null
                    : () {
                        final removed = _windows.removeAt(i);
                        for (final c in removed) {
                          c.dispose();
                        }
                        _changed();
                      },
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: _button('+ Add session', () {
          _addWindow('17:00', '18:00');
          _changed();
        }),
      ),
      const SizedBox(height: 20),
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Options'),
            const SizedBox(height: 12),
            ShadCheckbox(
              value: _sunday,
              enabled: !_busy,
              onChanged: (v) {
                _sunday = v;
                _changed();
              },
              label: const Text('Include Sunday'),
            ),
            const SizedBox(height: 16),
            _field('Gap between teams (minutes)', _gap, number: true),
            _dateField('Unavailable date', _skipDate),
            _button('Skip date', () {
              final day = DateTime.tryParse(_skipDate.text.trim());
              if (day == null) {
                setState(() => _error = 'Enter a date as YYYY-MM-DD.');
                return;
              }
              _excluded.add(DateFormat('yyyy-MM-dd').format(day));
              _skipDate.clear();
              _changed();
            }),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final day in _excluded)
                  _button('$day ×', () {
                    _excluded.remove(day);
                    _changed();
                  }),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Monday–Saturday are available. The scheduler calculates the finish within the official semester calendar.',
            ),
          ],
        ),
      ),
    ],
  );

  Widget _calendar() {
    final start = DateTime.tryParse(_date.text.trim());
    if (start == null) {
      return const Text('Enter a start date to calculate dates.');
    }
    final used = (_preview?['scheduled_dates'] as List? ?? [])
        .cast<String>()
        .toSet();
    var last = used.isEmpty
        ? start.add(const Duration(days: 6))
        : DateTime.parse(used.last);
    for (final day in _excluded) {
      final d = DateTime.tryParse(day);
      if (d != null && d.isAfter(last)) last = d;
    }
    final monday = start.subtract(Duration(days: start.weekday - 1));
    final weeks = (last.difference(monday).inDays ~/ 7) + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var week = 0; week < weeks; week++) ...[
          Text(
            '${DateFormat('MMM d').format(monday.add(Duration(days: week * 7)))} – ${DateFormat('MMM d').format(monday.add(Duration(days: week * 7 + 6)))}',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var day = 0; day < 7; day++)
                Builder(
                  builder: (context) {
                    final d = monday.add(Duration(days: week * 7 + day));
                    final iso = DateFormat('yyyy-MM-dd').format(d);
                    final unavailable = _excluded.contains(iso);
                    final eligible =
                        !d.isBefore(start) &&
                        (d.weekday != 7 || _sunday) &&
                        (_workspace?['ends_on'] == null ||
                            iso.compareTo('${_workspace!['ends_on']}') <= 0);
                    return Container(
                      width: 83,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: DefensysTokens.borderOf(context),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: ShadCheckbox(
                        value: used.contains(iso),
                        enabled: eligible && !_busy,
                        onChanged: (_) {
                          unavailable
                              ? _excluded.remove(iso)
                              : _excluded.add(iso);
                          _changed();
                        },
                        label: Text(
                          DateFormat('E\nd').format(d),
                          style: TextStyle(
                            decoration: unavailable
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _calculated() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Calculated plan'),
      const SizedBox(height: 12),
      if (_previewing) const LinearProgressIndicator(),
      _panel(
        Semantics(
          liveRegion: true,
          child: Text(
            _preview == null
                ? 'Enter the scheduling details to calculate the plan.'
                : '${_preview!['days']} defense days · ${_preview!['sessions']} sessions\n${_slots.length}/${_queue.length} teams · Finish: ${_preview!['finish'] ?? '—'}',
          ),
        ),
      ),
      if (_preview?['complete'] == false)
        _panel(
          Text(
            '${_preview!['blocking_reason']}\nRemaining teams: ${(_preview!['remaining_team_ids'] as List).length}',
          ),
        ),
      for (final day in (_preview?['scheduled_dates'] as List? ?? []))
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEE, MMM d').format(DateTime.parse(day)),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final block
                  in _slots
                      .where((s) => s['scheduled_date'] == day)
                      .map((s) => s['block_key'])
                      .toSet()) ...[
                const Divider(height: 22),
                Builder(
                  builder: (_) {
                    final slots = _slots
                        .where((s) => s['block_key'] == block)
                        .toList();
                    return Text(
                      '${slots.first['window_index'] == 0
                          ? 'Morning'
                          : slots.first['window_index'] == 1
                          ? 'Afternoon'
                          : 'Session'} · ${slots.length} teams\n'
                      '${_time(slots.first['start_time'])} – ${_time(slots.last['end_time'])}',
                    );
                  },
                ),
              ],
            ],
          ),
        ),
    ],
  );

  String _time(dynamic value) {
    final parsed = DateTime.tryParse('2000-01-01T$value');
    return parsed == null ? '$value' : DateFormat.jm().format(parsed);
  }

  void _move(int from, int to) {
    final group = _groups.removeAt(from);
    _groups.insert(to, group);
    _changed();
  }

  Widget _sorter() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Adviser scheduling order · ${_slots.length}/${_queue.length} teams',
      ),
      const SizedBox(height: 8),
      const Text(
        'Drag an adviser or use the arrows. Their teams stay together and dates recalculate.',
      ),
      const SizedBox(height: 16),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: _groups.length,
        onReorder: _busy
            ? (_, _) {}
            : (from, to) => _move(from, to > from ? to - 1 : to),
        itemBuilder: (context, index) {
          final g = _groups[index];
          final ids = g.teams.map((t) => t['id']).toSet();
          final slots = _slots
              .where((s) => ids.contains(s['team_id']))
              .toList();
          return Container(
            key: ValueKey(g.key),
            child: _panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        enabled: !_busy,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.drag_indicator),
                        ),
                      ),
                      Text(
                        '${index + 1}. ${g.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('${slots.length} teams · ${g.intake}'),
                      _button(
                        'Move up',
                        index == 0 ? null : () => _move(index, index - 1),
                      ),
                      _button(
                        'Move down',
                        index == _groups.length - 1
                            ? null
                            : () => _move(index, index + 1),
                      ),
                      _button(
                        g.expanded ? 'Hide teams' : 'View teams',
                        () => setState(() => g.expanded = !g.expanded),
                      ),
                    ],
                  ),
                  if (slots.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        '${slots.first['scheduled_date']} ${_time(slots.first['start_time'])} → ${slots.last['scheduled_date']} ${_time(slots.last['end_time'])}',
                      ),
                    ),
                  if (g.expanded)
                    for (final slot in slots)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${slot['team_name']} · ${slot['scheduled_date']} · ${_time(slot['start_time'])} – ${_time(slot['end_time'])} · ${slot['room']}',
                            ),
                            Text(
                              _rosterSummary(
                                Map<String, dynamic>.from(slot['roster']),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
      if (_previewing) const LinearProgressIndicator(),
      const SizedBox(height: 18),
      Text('Finish: ${_preview?['finish'] ?? 'Recalculating…'}'),
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          _button('← Dates & sessions', () => _goToStep(2)),
          _button('Edit people', () => _goToStep(1)),
          _button(
            _busy ? 'Confirming…' : 'Confirm schedule',
            _preview?['complete'] == true && !_previewing ? _confirm : null,
            primary: true,
          ),
        ],
      ),
    ],
  );

  String _rosterSummary(Map<String, dynamic> r) =>
      'Chair: ${r['chair_panelist_id'] == null ? 'Unassigned' : _personName(r['chair_panelist_id'])} · Panel members: '
      '${(r['panelist_ids'] as List).whereType<int>().where((id) => id != r['chair_panelist_id']).map((id) => _personName(id)).join(', ')}'
      '${(r['external_evaluator_ids'] as List).isEmpty ? '' : ' · External: ${(r['external_evaluator_ids'] as List).map((id) => _personName(id, external: true)).join(', ')}'}'
      ' · Documenter: ${r['documenter_id'] == null ? 'Unassigned' : _personName(r['documenter_id'])}';
}
