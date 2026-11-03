import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/services/defense/capstone_scheduling_api.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/app/unsaved_changes_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/shadcn/workflow_step_progress.dart';
import '../models/capstone_planning_draft.dart';
import 'scheduler_people_picker.dart';
import 'capstone_adviser_readiness.dart';
import 'capstone_review_group.dart';
import 'documenter_workload_summary.dart';
import '../dialogs/capstone_replacement_dialog.dart';

class CapstoneSchedulingWorkspace extends ConsumerStatefulWidget {
  const CapstoneSchedulingWorkspace({
    super.key,
    this.initialStageId,
    this.header,
    this.scrollable = false,
    required this.onSaved,
  });
  final int? initialStageId;
  final Widget? header;
  final bool scrollable;
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
  final _windows = <List<TextEditingController>>[];
  final _rosters = <int, CapstoneRosterDraft>{};
  final _temporaryChanges = <int, Map<String, dynamic>>{};
  final _editingRosters = <int, CapstoneRosterDraft>{};
  final _replacementEvents = <Map<String, dynamic>>[];
  final _selected = <int>{};
  final _excluded = <String>{};
  final _expandedReviewGroups = <String>{};
  String? _keyboardReviewGroup;
  List<String>? _keyboardOriginalOrder;
  bool _pointerReorder = false;
  int? _pointerReorderFrom;
  Map<String, dynamic>? _lastReviewPreview;
  List<CapstoneAdviserGroup> _groups = [];
  Map<String, dynamic>? _workspace, _preview;
  List<Map<String, dynamic>> _invitations = [];
  String? _error, _notice;
  String _confirmKey = '';
  int? _stage;
  int _step = 1, _generation = 0;
  bool _busy = false, _previewing = false, _sunday = false, _loading = true;
  bool _replacementDialogOpen = false;
  bool _stageSetupIssue = false;
  BuildContext? _shadContext;
  Timer? _debounce;
  late final UnsavedChangesNotifier _unsaved;
  late final UnsavedChangesSaveDraftNotifier _saveDraftNotifier;
  CapstoneSchedulingApi get _api => ref.read(capstoneSchedulingApiProvider);
  List<Map<String, dynamic>> get _teams => capstoneMaps(_workspace?['teams']);
  List<Map<String, dynamic>> get _stages => capstoneMaps(_workspace?['stages']);
  Map<String, dynamic>? get _stageData =>
      _stages.where((s) => s['id'] == _stage).firstOrNull;
  Map<String, dynamic>? get _displayPlan =>
      _preview ?? (_step == 3 ? _lastReviewPreview : null);
  List<Map<String, dynamic>> get _slots => capstoneMaps(_displayPlan?['slots']);
  List<CapstoneAdviserGroup> get _reviewGroups => _groups
      .where(
        (group) => group.teams.any(
          (team) => _selected.contains(capstoneId(team['id'])),
        ),
      )
      .toList();
  bool get _reordering => _pointerReorder || _keyboardReviewGroup != null;
  bool get _reviewUpdating =>
      _reordering || _previewing || (_preview == null && _error == null);
  bool get _canConfirmReview =>
      !_busy &&
      !_replacementDialogOpen &&
      !_reordering &&
      !_previewing &&
      _error == null &&
      _preview?['complete'] == true &&
      _confirmKey.isNotEmpty;
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
    _lastReviewPreview = null;
    _expandedReviewGroups.clear();
    _keyboardReviewGroup = null;
    _keyboardOriginalOrder = null;
    _pointerReorder = false;
    _pointerReorderFrom = null;
    _step = 1;
    _selected.clear();
    _excluded.clear();
    _sunday = false;
    _rosters.clear();
    _temporaryChanges.clear();
    _editingRosters.clear();
    _replacementEvents.clear();
    final applicable = _teams
        .where(
          (t) =>
              (t['applicable_stage_ids'] as List).contains(_stage) &&
              capstoneTeamNeedsScheduling(t, _stage),
        )
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
    if (_keyboardReviewGroup != null) _endKeyboardReview(cancel: true);
    setState(() {
      _step = step;
      if (step == 1) {
        _generation++;
        _debounce?.cancel();
        _previewing = false;
        _error = null;
        _stageSetupIssue = false;
      }
    });
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
    _confirmKey = '';
    _previewing = false;
    _error = null;
    _stageSetupIssue = false;
    _notice = null;
    _unsaved.setDirty(true);
    _saveDraftNotifier.setCallback(_saveDraft);
    setState(() {});
    _debounce?.cancel();
    if (plan && _step > 1) {
      _debounce = Timer(const Duration(milliseconds: 450), _calculate);
    }
  }

  String? get _planInputIssue {
    final issues = <String>[];
    if (_queue.isEmpty) {
      issues.add('No teams are ready to schedule for this stage.');
    }
    if (DateTime.tryParse(_date.text.trim()) == null) {
      issues.add('Choose a valid start date.');
    }
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes < 15 || minutes > 240) {
      issues.add('Enter minutes per team between 15 and 240.');
    }
    if (_room.text.trim().isEmpty) {
      issues.add('Enter a room.');
    }
    return issues.isEmpty ? null : issues.join(' ');
  }

  Future<void> _calculate() async {
    final generation = ++_generation;
    if (_planInputIssue != null) {
      setState(() {
        _previewing = false;
        _preview = null;
        _confirmKey = '';
        _error = null;
        _stageSetupIssue = false;
      });
      return;
    }
    setState(() {
      _previewing = true;
      _error = null;
      _stageSetupIssue = false;
    });
    try {
      final plan = await _api.preview(_inputs());
      if (!mounted || generation != _generation) return;
      setState(() {
        _preview = plan;
        _lastReviewPreview = plan;
        _confirmKey = _uuid();
      });
      await _saveDraft();
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _message(e);
          _stageSetupIssue =
              e is CapstoneSchedulingException && e.requiresStageSetup;
        });
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
        g.teams.removeWhere(
          (team) => !capstoneTeamNeedsScheduling(team, _stage),
        );
        g.hasMixedAssignments = false;
      }
      _groups.removeWhere((group) => group.teams.isEmpty);
      final visibleIds = {
        for (final group in _groups)
          for (final team in group.teams) team['id'],
      };
      _rosters.removeWhere((id, _) => !visibleIds.contains(id));
      _temporaryChanges.removeWhere((id, _) => !visibleIds.contains(id));
      _editingRosters.removeWhere((id, _) => !visibleIds.contains(id));
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
          () => _notice = _groups.isEmpty
              ? 'No teams need scheduling for this stage.'
              : 'Adviser assignments saved. Teams can be scheduled after endorsement.',
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
    if (!_canConfirmReview) return;
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
        if (!widget.scrollable) return _workspaceBody();
        final inset = MediaQuery.sizeOf(context).width < 640 ? 16.0 : 40.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('capstone-workspace-scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(inset, 20, inset, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.header != null) ...[
                      widget.header!,
                      const SizedBox(height: 20),
                    ],
                    _workspaceBody(),
                  ],
                ),
              ),
            ),
            if (_step == 2 && _workspace != null && !_loading)
              _dateActions(horizontalPadding: inset),
            if (_step == 3 && _workspace != null && !_loading)
              _reviewActions(horizontalPadding: inset),
          ],
        );
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
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _notice!,
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
          ),
        if (_error != null && _step == 1)
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
          style: const TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          switch (_step) {
            2 => 'Set daily sessions, then review the calculated dates.',
            3 => 'Review adviser order and allocated defense times.',
            _ => 'Panel and documenter assignments by adviser',
          },
          style: TextStyle(
            fontSize: 13,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    );
    final status = Semantics(
      liveRegion: true,
      label: 'Scheduling readiness',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CapstoneReadinessBadge(
            key: const ValueKey('overall-readiness'),
            status: summary.status,
            label: summary.counts,
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
      Text(
        _groups.isEmpty
            ? 'No teams need scheduling for this stage.'
            : 'Assign one panel and documenter per adviser. Ready teams are included automatically.',
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
      _documenterLoads(),
      const SizedBox(height: 14),
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

  Widget _documenterLoads() {
    final counts = <int, int>{};
    for (final id in _rosters.keys) {
      final roster = _displayRoster(id);
      if (roster.documenter != null) {
        counts.update(roster.documenter!, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final eligible = capstoneMaps(
      _workspace?['documenters'],
    ).map((person) => capstoneId(person['id'])).whereType<int>().toSet();
    final rows = <DocumenterWorkload>[
      for (final id in {...eligible, ...counts.keys})
        DocumenterWorkload(
          id: id,
          name: _personName(id),
          teams: counts[id] ?? 0,
          eligible: eligible.contains(id),
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final total = counts.values.fold<int>(0, (total, count) => total + count);
    return _scheduleSection(
      'Documenter workload',
      description: total == 0
          ? '${eligible.length} documenters available · No teams assigned yet'
          : '$total ${total == 1 ? 'team' : 'teams'} assigned across ${rows.where((row) => row.teams > 0).length} of ${rows.length} documenters',
      child: DocumenterWorkloadSummary(items: rows),
    );
  }

  String _personName(int id, {bool external = false}) {
    final people = capstoneMaps(
      _workspace?[external ? 'external_evaluators' : 'faculty'],
    );
    final person = people.where((p) => capstoneId(p['id']) == id).firstOrNull;
    return person == null ? 'Person $id' : schedulerPersonName(person);
  }

  Future<void> _openFacultyStaff() async {
    if (!await _saveDraft() || !mounted) return;
    context.go('${AdminRoutes.users}?tab=faculty');
  }

  Widget _roleAvailabilityHelp(String role, String people) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'No eligible $people are available. Assign the $role role in User Management.',
        style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
      ),
      const SizedBox(height: 8),
      _button('Faculty & Staff', _openFacultyStaff),
    ],
  );

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
    final noPanelists = facultyCount == 0;
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
                    ? 'documenters'
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
            if (doc && people.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _roleAvailabilityHelp('Documenter', 'documenters'),
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
        if (noPanelists)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _roleAvailabilityHelp('Defense Panelist', 'panelists'),
          )
        else if (!canAddFaculty || !canAddExternal)
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
      LayoutBuilder(
        builder: (context, c) {
          final fields = [
            _dateField('Start date', _date),
            _field('Minutes per team (15–240)', _minutes, number: true),
            _field('Room', _room),
          ];
          return c.maxWidth < 700
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: fields,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(child: fields[i]),
                    ],
                  ],
                );
        },
      ),
      LayoutBuilder(
        builder: (context, c) => c.maxWidth < 1000
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _calculated(),
                  const SizedBox(height: 20),
                  _dateControls(),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _dateControls()),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: _calculated()),
                ],
              ),
      ),
      if (!widget.scrollable) ...[const SizedBox(height: 20), _dateActions()],
    ],
  );

  Widget _dateControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _scheduleSection(
        'Daily sessions',
        description: 'Breaks between sessions stay free.',
        trailing: ShadButton.ghost(
          size: ShadButtonSize.sm,
          enabled: !_busy,
          onPressed: () {
            _addWindow('17:00', '18:00');
            _changed();
          },
          leading: const Icon(Icons.add_rounded, size: 16),
          child: const Text('Add session'),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (constraints.maxWidth >= 520) ...[
                Row(
                  children: [
                    const SizedBox(width: 98),
                    Expanded(child: Text('Start', style: _supportingStyle)),
                    const SizedBox(width: 36),
                    Expanded(child: Text('End', style: _supportingStyle)),
                    const SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              for (var i = 0; i < _windows.length; i++) ...[
                if (i > 0) const Divider(height: 16),
                _sessionRow(i),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      _scheduleSection(
        'Scheduled dates',
        description:
            'Filled automatically from your sessions. Uncheck a scheduled date to skip it.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _calendar(),
            const SizedBox(height: 4),
            Text('Crossed-out dates are unavailable.', style: _supportingStyle),
            if (_excluded.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Skipped dates', style: _supportingStyle),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final day in (_excluded.toList()..sort()))
                    ShadButton.ghost(
                      key: ValueKey('restore-date-$day'),
                      size: ShadButtonSize.sm,
                      enabled: !_busy,
                      leading: const Icon(Icons.undo_rounded, size: 15),
                      onPressed: () {
                        _excluded.remove(day);
                        _changed();
                      },
                      child: Text(
                        'Restore ${DateFormat('MMM d').format(DateTime.parse(day))}',
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      ShadAccordion<String>(
        children: [
          ShadAccordionItem(
            value: 'scheduling-options',
            title: const Text('Scheduling options'),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _schedulingOptions(),
            ),
          ),
        ],
      ),
    ],
  );

  TextStyle get _supportingStyle => TextStyle(
    fontFamily: DefensysTokens.fontFamilyInter,
    fontSize: 12,
    color: DefensysTokens.textSecondaryOf(context),
  );

  Widget _scheduleSection(
    String title, {
    required Widget child,
    String? description,
    Widget? trailing,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      border: Border.all(color: DefensysTokens.borderOf(context)),
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(description, style: _supportingStyle),
        ],
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _sessionRow(int i) {
    final name = i == 0
        ? 'Morning'
        : i == 1
        ? 'Afternoon'
        : 'Session ${i + 1}';
    Widget time(int position) => Semantics(
      label: '$name ${position == 0 ? 'start' : 'end'} time',
      child: ShadInput(
        key: ValueKey('session-$i-${position == 0 ? 'start' : 'end'}'),
        controller: _windows[i][position],
        enabled: !_busy,
        placeholder: const Text('HH:mm'),
        style: const TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontSize: 13,
        ),
        onChanged: (_) => _changed(),
      ),
    );
    final remove = Tooltip(
      message: 'Remove $name session',
      child: ShadButton.ghost(
        key: ValueKey('remove-session-$i'),
        size: ShadButtonSize.sm,
        enabled: !_busy && _windows.length > 1,
        onPressed: () {
          final removed = _windows.removeAt(i);
          for (final controller in removed) {
            controller.dispose();
          }
          _changed();
        },
        child: const Icon(Icons.close_rounded, size: 16),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        return Column(
          key: ValueKey('schedule-session-$i'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrow)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  remove,
                ],
              ),
            Row(
              children: [
                if (!narrow)
                  SizedBox(
                    width: 98,
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (narrow) ...[
                        Text('Start', style: _supportingStyle),
                        const SizedBox(height: 6),
                      ],
                      time(0),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(10, narrow ? 22 : 0, 10, 0),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (narrow) ...[
                        Text('End', style: _supportingStyle),
                        const SizedBox(height: 6),
                      ],
                      time(1),
                    ],
                  ),
                ),
                if (!narrow) ...[const SizedBox(width: 8), remove],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _schedulingOptions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
      Text(
        'Monday–Saturday are available. The scheduler calculates the finish within the official semester calendar.',
        style: _supportingStyle,
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
    DateTime weekOf(DateTime day) =>
        DateTime(day.year, day.month, day.day - day.weekday + 1);
    // Show only weeks used by the allocation. A disabled Sunday must not add
    // the preceding empty week; skipped dates stay restorable below the calendar.
    final firstAvailable = start.weekday == DateTime.sunday && !_sunday
        ? start.add(const Duration(days: 1))
        : start;
    final weeks =
        (used.isEmpty
                ? {weekOf(firstAvailable)}
                : used.map((day) => weekOf(DateTime.parse(day))).toSet())
            .toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final monday in weeks) ...[
          Text(
            '${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(monday.add(const Duration(days: 6)))}',
            key: ValueKey(
              'calendar-week-${DateFormat('yyyy-MM-dd').format(monday)}',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var day = 0; day < 7; day++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: day == 6 ? 0 : 4),
                    child: Builder(
                      builder: (context) {
                        final d = monday.add(Duration(days: day));
                        final iso = DateFormat('yyyy-MM-dd').format(d);
                        final unavailable = _excluded.contains(iso);
                        final eligible =
                            !d.isBefore(start) &&
                            (d.weekday != 7 || _sunday) &&
                            (_workspace?['ends_on'] == null ||
                                iso.compareTo('${_workspace!['ends_on']}') <=
                                    0);
                        return Semantics(
                          label:
                              '${DateFormat('EEEE, MMMM d').format(d)}${unavailable
                                  ? ', unavailable'
                                  : used.contains(iso)
                                  ? ', scheduled'
                                  : ', unused'}',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: used.contains(iso)
                                  ? DefensysTokens.maroonOf(
                                      context,
                                    ).withValues(alpha: .05)
                                  : null,
                              border: Border.all(
                                color: DefensysTokens.borderOf(context),
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  DateFormat('E').format(d).substring(0, 2),
                                  maxLines: 1,
                                  style: _supportingStyle,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${d.day}',
                                  style: TextStyle(
                                    fontFamily: DefensysTokens.fontFamilyInter,
                                    fontSize: 14,
                                    fontWeight: used.contains(iso)
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: eligible
                                        ? DefensysTokens.textPrimaryOf(context)
                                        : DefensysTokens.textSecondaryOf(
                                            context,
                                          ),
                                    decoration: unavailable
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                ShadCheckbox(
                                  key: ValueKey('schedule-date-$iso'),
                                  value: used.contains(iso),
                                  enabled: eligible && !_busy,
                                  onChanged: (_) {
                                    unavailable
                                        ? _excluded.remove(iso)
                                        : _excluded.add(iso);
                                    _changed();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _calculated() => _scheduleSection(
    'Calculated plan',
    trailing: ShadButton.ghost(
      size: ShadButtonSize.sm,
      enabled: !_busy && !_previewing,
      onPressed: _calculate,
      child: const Text('Recalculate'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_previewing) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
        ],
        if (_error != null) ...[
          Semantics(
            liveRegion: true,
            child: ShadAlert.destructive(
              title: Text(
                _stageSetupIssue
                    ? 'Stage setup needs attention'
                    : 'Could not calculate the plan',
              ),
              description: Text(_error!),
            ),
          ),
          if (_stageSetupIssue) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: _button('Review stage setup', _openStageSetup),
            ),
          ],
        ] else if (_preview == null)
          Text(
            _planInputIssue ?? 'Recalculate to update the plan.',
            style: _supportingStyle,
          )
        else ...[
          _previewTotals(),
          _previewDivider(),
          _previewTiming(),
          if (_preview?['complete'] == false)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ShadAlert.destructive(
                title: const Text('Some teams could not fit'),
                description: Text(
                  '${_preview!['blocking_reason']}\nRemaining teams: ${(_preview!['remaining_team_ids'] as List).length}',
                ),
              ),
            ),
          for (final day in _allocatedDates) ...[
            _previewDivider(),
            _previewDay(day),
          ],
        ],
      ],
    ),
  );

  List<String> get _allocatedDates =>
      ((_preview?['scheduled_dates'] as List? ?? [])
          .cast<String>()
          .toSet()
          .toList()
        ..sort());

  Widget _previewDivider() =>
      Divider(height: 28, color: DefensysTokens.borderOf(context));

  Widget _previewTotals() => Semantics(
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _previewStat(
          'Teams',
          '${_slots.length}/${_queue.length}',
          'plan-teams-count',
          semantics: '${_slots.length} of ${_queue.length} teams allocated',
        ),
        _previewStatDivider(),
        _previewStat('Days', '${_displayPlan!['days']}', 'plan-days-count'),
        _previewStatDivider(),
        _previewStat(
          'Sessions',
          '${_displayPlan!['sessions']}',
          'plan-sessions-count',
        ),
      ],
    ),
  );

  Widget _previewStatDivider() => Container(
    width: 1,
    height: 38,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: DefensysTokens.borderOf(context),
  );

  Widget _previewStat(
    String label,
    String value,
    String key, {
    String? semantics,
  }) => Expanded(
    child: Semantics(
      label: semantics ?? '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              key: ValueKey(key),
              style: const TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(label, style: _supportingStyle),
        ],
      ),
    ),
  );

  Widget _previewTiming() {
    final starts =
        _slots
            .map(
              (slot) => DateTime.tryParse(
                '${slot['scheduled_date']} ${slot['start_time']}',
              ),
            )
            .whereType<DateTime>()
            .toList()
          ..sort();
    final start = starts.firstOrNull;
    final end = DateTime.tryParse('${_displayPlan?['finish']}');
    return Semantics(
      liveRegion: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 320;
          final first = _previewBoundary(
            'Start of defense',
            start,
            'start',
            horizontal: stacked,
          );
          final last = _previewBoundary(
            'End of defense',
            end,
            'end',
            horizontal: stacked,
            accent: true,
          );
          return stacked
              ? Column(children: [first, const SizedBox(height: 14), last])
              : Row(
                  children: [
                    Expanded(child: first),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    Expanded(child: last),
                  ],
                );
        },
      ),
    );
  }

  Widget _previewBoundary(
    String label,
    DateTime? moment,
    String name, {
    bool horizontal = false,
    bool accent = false,
  }) {
    final time = Text(
      moment == null ? '—' : DateFormat.jm().format(moment),
      key: ValueKey('plan-$name-time'),
      style: TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: accent
            ? DefensysTokens.maroonTextOf(context)
            : DefensysTokens.textPrimaryOf(context),
      ),
    );
    final date = Text(
      moment == null ? '—' : DateFormat('EEE, MMM d').format(moment),
      key: ValueKey('plan-$name-date'),
      style: _supportingStyle,
    );
    return Semantics(
      label:
          '$label: ${moment == null ? 'Not allocated' : DateFormat('EEE, MMM d · h:mm a').format(moment)}',
      excludeSemantics: true,
      child: horizontal
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: _supportingStyle),
                      const SizedBox(height: 4),
                      date,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                time,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, style: _supportingStyle),
                const SizedBox(height: 6),
                time,
                const SizedBox(height: 5),
                date,
              ],
            ),
    );
  }

  Widget _previewDay(String day) {
    final date = DateTime.parse(day);
    final slots = _slots
        .where((slot) => slot['scheduled_date'] == day)
        .toList();
    final blocks = slots.map((slot) => slot['block_key']).toSet().toList();
    return Row(
      key: ValueKey('plan-day-$day'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceHigherOf(context),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Text(
                '${date.day}',
                style: const TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(DateFormat('MMM').format(date), style: _supportingStyle),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('EEEE').format(date),
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${slots.length} ${slots.length == 1 ? 'team' : 'teams'}',
                    style: _supportingStyle,
                  ),
                ],
              ),
              for (final block in blocks) ...[
                const SizedBox(height: 8),
                _previewSession(
                  slots.where((slot) => slot['block_key'] == block).toList(),
                  showCount: blocks.length > 1,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewSession(
    List<Map<String, dynamic>> slots, {
    required bool showCount,
  }) {
    final index = capstoneId(slots.first['window_index']) ?? 0;
    final name = index == 0
        ? 'Morning'
        : index == 1
        ? 'Afternoon'
        : 'Session ${index + 1}';
    final label = Text(
      '$name${showCount ? ' · ${slots.length} ${slots.length == 1 ? 'team' : 'teams'}' : ''}',
      style: _supportingStyle,
    );
    final time = Text(
      '${_time(slots.first['start_time'])} – ${_time(slots.last['end_time'])}',
      style: const TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        fontFeatures: [FontFeature.tabularFigures()],
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 280
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 4), time],
            )
          : Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 12),
                time,
              ],
            ),
    );
  }

  Future<void> _openStageSetup() async {
    if (_stage == null || !await _saveDraft() || !mounted) return;
    context.go(AdminRoutes.defenseStageEdit(_stage!));
  }

  Widget _dateActions({double horizontalPadding = 0}) => Container(
    key: const ValueKey('capstone-date-actions'),
    padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 14),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      border: Border(top: BorderSide(color: DefensysTokens.borderOf(context))),
    ),
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final back = Semantics(
            label: 'Back to assignments',
            child: _button(
              constraints.maxWidth < 340 ? '← People' : '← Assignments',
              () => _goToStep(1),
            ),
          );
          final next = _button(
            'Order & review →',
            _preview == null || _previewing || _error != null
                ? null
                : () => _goToStep(3),
            primary: true,
          );
          final status = Text(
            _previewing
                ? 'Calculating…'
                : _error != null
                ? 'Resolve the plan issue to continue'
                : _preview == null
                ? 'Complete the scheduling details'
                : '${_slots.length}/${_queue.length} teams allocated',
            style: _supportingStyle,
          );
          return constraints.maxWidth < 600
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    status,
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      runSpacing: 8,
                      children: [back, next],
                    ),
                  ],
                )
              : Row(
                  children: [
                    back,
                    const SizedBox(width: 20),
                    Expanded(child: status),
                    const SizedBox(width: 12),
                    next,
                  ],
                );
        },
      ),
    ),
  );

  String _time(dynamic value) {
    final parsed = DateTime.tryParse('2000-01-01T$value');
    return parsed == null ? '$value' : DateFormat.jm().format(parsed);
  }

  void _announceReview(String key, {bool reveal = false}) {
    final index = _reviewGroups.indexWhere((group) => group.key == key);
    if (index < 0) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${_reviewGroups[index].name}, position ${index + 1} of ${_reviewGroups.length}',
        Directionality.of(context),
      ),
    );
    if (reveal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focused = FocusManager.instance.primaryFocus?.context;
        if (mounted && focused != null) {
          Scrollable.ensureVisible(
            focused,
            duration: const Duration(milliseconds: 120),
          );
        }
      });
    }
  }

  void _moveReview(int from, int to, {bool commit = true}) {
    final visible = _reviewGroups;
    if (_busy ||
        from == to ||
        from < 0 ||
        to < 0 ||
        from >= visible.length ||
        to >= visible.length) {
      return;
    }
    final group = visible[from], anchor = visible[to];
    _groups.remove(group);
    _groups.insert(_groups.indexOf(anchor) + (to > from ? 1 : 0), group);
    if (commit) {
      _changed();
    } else {
      setState(() {});
    }
    _announceReview(group.key, reveal: !commit);
  }

  void _beginKeyboardReview(String key) {
    if (_busy || _pointerReorder) return;
    if (_keyboardReviewGroup != null) _endKeyboardReview(cancel: true);
    setState(() {
      _keyboardOriginalOrder = _groups.map((group) => group.key).toList();
      _keyboardReviewGroup = key;
    });
    _announceReview(key);
  }

  void _moveKeyboardReview(int delta) {
    final index = _reviewGroups.indexWhere(
      (group) => group.key == _keyboardReviewGroup,
    );
    if (index >= 0) _moveReview(index, index + delta, commit: false);
  }

  void _endKeyboardReview({bool cancel = false}) {
    final key = _keyboardReviewGroup;
    final before = _keyboardOriginalOrder;
    if (key == null || before == null) return;
    final changed =
        before.join('|') != _groups.map((group) => group.key).join('|');
    if (cancel) {
      final byKey = {for (final group in _groups) group.key: group};
      _groups = before
          .map((key) => byKey[key])
          .whereType<CapstoneAdviserGroup>()
          .toList();
    }
    _keyboardReviewGroup = null;
    _keyboardOriginalOrder = null;
    if (!cancel && changed) {
      _changed();
    } else {
      setState(() {});
    }
    _announceReview(key);
  }

  Widget _sorter() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 1000
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _reviewSummary(),
                  const SizedBox(height: 20),
                  _reviewList(),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _reviewList()),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: min(380, (constraints.maxWidth - 24) * .30),
                    child: _reviewSummary(),
                  ),
                ],
              ),
      ),
      if (!widget.scrollable) ...[const SizedBox(height: 20), _reviewActions()],
    ],
  );

  Widget _reviewList() {
    final groups = _reviewGroups;
    final showIntake =
        groups
            .map((group) => group.teams.first['intake_semester_id'])
            .toSet()
            .length >
        1;
    final slotRosters = {
      for (final slot in _slots)
        capstoneId(slot['team_id']): Map<String, dynamic>.from(
          slot['roster'] as Map,
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Defense order',
          style: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Drag advisers to set the order. Their teams stay together.',
          style: _supportingStyle,
        ),
        const SizedBox(height: 16),
        ReorderableListView.builder(
          key: const ValueKey('review-order-list'),
          primary: false,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: groups.length,
          onReorderStart: (index) => setState(() {
            _pointerReorder = true;
            _pointerReorderFrom = index;
          }),
          onReorderEnd: (to) {
            final from = _pointerReorderFrom;
            if (from == null || (to > from ? to - 1 : to) == from) {
              setState(() {
                _pointerReorder = false;
                _pointerReorderFrom = null;
              });
            }
            // A changed drop commits only after Flutter's proxy animation.
          },
          onReorder: (from, to) {
            _moveReview(from, to > from ? to - 1 : to);
            setState(() {
              _pointerReorder = false;
              _pointerReorderFrom = null;
            });
          },
          proxyDecorator: (child, index, animation) => Material(
            color: Colors.transparent,
            textStyle: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              color: DefensysTokens.textPrimaryOf(context),
            ),
            elevation: 2,
            shadowColor: DefensysTokens.textPrimaryOf(
              context,
            ).withValues(alpha: .08),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            child: child,
          ),
          itemBuilder: (context, index) {
            final group = groups[index];
            final teams = group.teams
                .where((team) => _selected.contains(capstoneId(team['id'])))
                .toList();
            final ids = teams.map((team) => capstoneId(team['id'])).toSet();
            final slots =
                _slots
                    .where((slot) => ids.contains(capstoneId(slot['team_id'])))
                    .toList()
                  ..sort(
                    (a, b) => '${a['scheduled_date']} ${a['start_time']}'
                        .compareTo('${b['scheduled_date']} ${b['start_time']}'),
                  );
            return CapstoneReviewGroup(
              key: ValueKey(group.key),
              group: group,
              teams: teams,
              slots: slots,
              rosters: {
                for (final id in ids.whereType<int>())
                  id: slotRosters[id] ?? _actualRoster(id).toJson(),
              },
              index: index,
              count: groups.length,
              intake: showIntake ? group.intake : null,
              expanded: _expandedReviewGroups.contains(group.key),
              enabled: !_busy,
              keyboardActive: _keyboardReviewGroup == group.key,
              updating: _reviewUpdating,
              onToggle: () => setState(
                () => _expandedReviewGroups.contains(group.key)
                    ? _expandedReviewGroups.remove(group.key)
                    : _expandedReviewGroups.add(group.key),
              ),
              onPickUp: () => _beginKeyboardReview(group.key),
              onDrop: _endKeyboardReview,
              onCancel: () => _endKeyboardReview(cancel: true),
              onMove: _moveKeyboardReview,
              onPointerCancel: () {
                if (_pointerReorder) {
                  setState(() {
                    _pointerReorder = false;
                    _pointerReorderFrom = null;
                  });
                }
              },
              onAccessibleMove: (delta) {
                if (_reordering) return;
                final current = _reviewGroups.indexWhere(
                  (item) => item.key == group.key,
                );
                _moveReview(current, current + delta);
              },
              facultyName: _personName,
              externalName: (id) => _personName(id, external: true),
            );
          },
        ),
      ],
    );
  }

  Widget _reviewSummary() => _scheduleSection(
    'Schedule summary',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_reviewUpdating) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _reordering ? 'Reordering advisers…' : 'Updating times…',
              style: _supportingStyle,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          ShadAlert.destructive(
            title: const Text('Schedule needs attention'),
            description: Text(_error!),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _button('Retry calculation', _reordering ? null : _calculate),
              if (_stageSetupIssue)
                _button('Review stage setup', _openStageSetup),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (_displayPlan != null) ...[
          _previewTotals(),
          _previewDivider(),
          _previewTiming(),
          _previewDivider(),
          Text('Room', style: _supportingStyle),
          const SizedBox(height: 5),
          Text(
            '${_slots.firstOrNull?['room'] ?? _room.text}',
            style: const TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_preview?['complete'] == false) ...[
            const SizedBox(height: 16),
            ShadAlert.destructive(
              title: const Text('Some teams could not fit'),
              description: Text(
                '${_preview!['blocking_reason']}\nRemaining teams: ${(_preview!['remaining_team_ids'] as List? ?? []).length}',
              ),
            ),
          ],
        ],
      ],
    ),
  );

  Widget _reviewActions({double horizontalPadding = 0}) => Container(
    key: const ValueKey('capstone-review-actions'),
    padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 14),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      border: Border(top: BorderSide(color: DefensysTokens.borderOf(context))),
    ),
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          final back = _button(
            narrow ? '← Dates' : '← Dates & sessions',
            _pointerReorder ? null : () => _goToStep(2),
          );
          final edit = ShadButton.ghost(
            enabled: !_busy && !_pointerReorder,
            onPressed: () => _goToStep(1),
            child: const Text('Edit people'),
          );
          final confirm = _button(
            _busy ? 'Confirming…' : 'Confirm schedule',
            _canConfirmReview ? _confirm : null,
            primary: true,
          );
          final status = Text(
            _busy
                ? 'Confirming schedule…'
                : _reordering
                ? 'Drop to update the schedule'
                : _reviewUpdating
                ? 'Updating times…'
                : _error != null
                ? 'Resolve the schedule issue'
                : '${_slots.length}/${_queue.length} teams allocated',
            style: _supportingStyle,
          );
          return narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    status,
                    const SizedBox(height: 8),
                    Row(children: [back, const Spacer(), edit]),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: confirm),
                  ],
                )
              : Row(
                  children: [
                    back,
                    const SizedBox(width: 20),
                    Expanded(child: status),
                    edit,
                    const SizedBox(width: 8),
                    confirm,
                  ],
                );
        },
      ),
    ),
  );

  String _rosterSummary(Map<String, dynamic> r) =>
      'Chair: ${r['chair_panelist_id'] == null ? 'Unassigned' : _personName(r['chair_panelist_id'])} · Panel members: '
      '${(r['panelist_ids'] as List).whereType<int>().where((id) => id != r['chair_panelist_id']).map((id) => _personName(id)).join(', ')}'
      '${(r['external_evaluator_ids'] as List).isEmpty ? '' : ' · External: ${(r['external_evaluator_ids'] as List).map((id) => _personName(id, external: true)).join(', ')}'}'
      ' · Documenter: ${r['documenter_id'] == null ? 'Unassigned' : _personName(r['documenter_id'])}';
}
