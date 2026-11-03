import 'dart:convert';

int? capstoneId(dynamic value) => int.tryParse('$value');
bool capstoneRosterDeltaHasChanges(Map<String, dynamic> delta) =>
    delta.containsKey('chair_panelist_id') ||
    delta.containsKey('documenter_id') ||
    [
      'add_panelist_ids',
      'remove_panelist_ids',
      'add_external_evaluator_ids',
      'remove_external_evaluator_ids',
    ].any((key) => (delta[key] as List? ?? []).isNotEmpty);
List<Map<String, dynamic>> capstoneMaps(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];

/// Resolve an explicitly replaced temporary member back to the continuing
/// member they cover. Other temporary choices stay outside a permanent edit.
Map<String, dynamic> capstoneContinuingDelta(
  Map<String, dynamic> edit,
  Map<String, dynamic> continuing,
  Iterable<Map<String, dynamic>> temporaryHistory,
) {
  final result = Map<String, dynamic>.from(edit);
  for (final key in ['panelist_ids', 'external_evaluator_ids']) {
    final baseline = (continuing[key] as List).toSet();
    final removals = <dynamic>{...edit['remove_$key'] as List? ?? []};
    for (final removed in List.of(removals)) {
      if (baseline.contains(removed)) continue;
      dynamic original = removed;
      for (final delta in temporaryHistory.toList().reversed) {
        final added = delta['add_$key'] as List? ?? [];
        final replaced = delta['remove_$key'] as List? ?? [];
        final index = added.indexOf(original);
        if (index < 0) continue;
        original = added.length == replaced.length ? replaced[index] : null;
        if (original == null || baseline.contains(original)) break;
      }
      if (baseline.contains(original)) removals.add(original);
    }
    if (removals.isNotEmpty) result['remove_$key'] = removals.toList();
  }
  return result;
}

/// A row owns its own slots. Adding a member never changes another adviser.
class CapstoneRosterDraft {
  CapstoneRosterDraft({
    this.chair,
    List<int?>? members,
    List<int?>? externals,
    this.documenter,
  }) : members = members ?? [null, null, null],
       externals = externals ?? [];
  int? chair;
  List<int?> members;
  List<int?> externals;
  int? documenter;

  factory CapstoneRosterDraft.fromJson(Map<String, dynamic>? data) {
    if (data == null) return CapstoneRosterDraft();
    final chair = capstoneId(data['chair_panelist_id']);
    return CapstoneRosterDraft(
      chair: chair,
      documenter: capstoneId(data['documenter_id']),
      members: (data['panelist_ids'] as List? ?? [])
          .map(capstoneId)
          .where((id) => chair == null || id != chair)
          .toList(),
      externals: (data['external_evaluator_ids'] as List? ?? [])
          .map(capstoneId)
          .toList(),
    );
  }
  bool get complete =>
      chair != null && !members.contains(null) && !externals.contains(null);
  Map<String, dynamic> toJson() => {
    'chair_panelist_id': chair,
    'panelist_ids': [if (chair != null) chair, ...members],
    'external_evaluator_ids': externals,
    'documenter_id': documenter,
  };
  String get signature {
    final data = toJson();
    for (final key in ['panelist_ids', 'external_evaluator_ids']) {
      data[key] = List<int?>.from(data[key] as List)
        ..sort((a, b) => (a ?? -1).compareTo(b ?? -1));
    }
    return jsonEncode(data);
  }

  CapstoneRosterDraft copy() => CapstoneRosterDraft.fromJson(toJson());

  CapstoneRosterDraft applying(Map<String, dynamic> delta) {
    final data = toJson();
    for (final key in ['chair_panelist_id', 'documenter_id']) {
      if (delta.containsKey(key)) data[key] = delta[key];
    }
    for (final key in ['panelist_ids', 'external_evaluator_ids']) {
      final ids = List<dynamic>.from(data[key] as List);
      ids.removeWhere(
        (id) => (delta['remove_$key'] as List? ?? []).contains(id),
      );
      for (final id in delta['add_$key'] as List? ?? []) {
        if (id == null || !ids.contains(id)) ids.add(id);
      }
      data[key] = ids;
    }
    return CapstoneRosterDraft.fromJson(data);
  }

  /// Diff against the continuing roster only; temporary roster snapshots never
  /// become an implicit source for permanent changes in other fields.
  Map<String, dynamic> changesFrom(Map<String, dynamic> before) {
    final after = toJson();
    return {
      for (final key in ['chair_panelist_id', 'documenter_id'])
        if (after[key] != before[key]) key: after[key],
      for (final key in ['panelist_ids', 'external_evaluator_ids']) ...{
        'add_$key': (after[key] as List)
            .where((id) => !(before[key] as List).contains(id))
            .toList(),
        'remove_$key': (before[key] as List)
            .where((id) => !(after[key] as List).contains(id))
            .toList(),
      },
    }..removeWhere((key, value) => value is List && value.isEmpty);
  }
}

class CapstoneAdviserGroup {
  CapstoneAdviserGroup(this.key, this.teams);
  final String key;
  final List<Map<String, dynamic>> teams;
  bool expanded = true;
  bool hasMixedAssignments = false;
  String get name => '${teams.first['adviser_name']}';
  String get intake => '${teams.first['intake_label']}';
  int? get adviserId => capstoneId(teams.first['adviser_id']);
}

Map<String, dynamic> capstoneTeamReadiness(
  Map<String, dynamic> team,
  int? stageId,
) {
  final statuses = team['stage_readiness'];
  if (statuses is Map && statuses['$stageId'] is Map) {
    return Map<String, dynamic>.from(statuses['$stageId']);
  }
  final ready = (team['ready_stage_ids'] as List? ?? []).contains(stageId);
  return {
    'status': ready ? 'ready' : 'awaiting_endorsement',
    'label': ready ? 'Ready to schedule' : 'Awaiting endorsement',
    'endorsed': ready,
    'can_schedule': ready,
  };
}

bool capstoneTeamNeedsScheduling(Map<String, dynamic> team, int? stageId) {
  final state = capstoneTeamReadiness(team, stageId);
  return state['include_in_scheduler'] != false &&
      !const {
        'approved',
        'completed',
        'scheduled',
        'redefense_scheduled',
      }.contains(state['status']);
}

class CapstoneReadinessSummary {
  CapstoneReadinessSummary(List<Map<String, dynamic>> teams, int? stageId)
    : states = teams
          .where((t) => capstoneTeamNeedsScheduling(t, stageId))
          .map((t) => capstoneTeamReadiness(t, stageId))
          .toList();
  final List<Map<String, dynamic>> states;
  int get total => states.length;
  int get ready => states.where((s) => s['can_schedule'] == true).length;
  int get endorsed => states.where((s) => s['endorsed'] == true).length;
  int get readyForRedefense => states
      .where(
        (s) =>
            s['status'] == 'ready_for_redefense' && s['can_schedule'] == true,
      )
      .length;
  int get preparingRedefense =>
      states.where((s) => s['status'] == 'preparing_redefense').length;
  int get awaitingEndorsement =>
      states.where((s) => s['status'] == 'awaiting_endorsement').length;
  String get counts => [
    if (ready - readyForRedefense > 0)
      '${ready - readyForRedefense} ready to schedule',
    if (readyForRedefense > 0) '$readyForRedefense ready for re-defense',
    if (preparingRedefense > 0) '$preparingRedefense preparing re-defense',
    if (awaitingEndorsement > 0) '$awaitingEndorsement awaiting endorsement',
    if (total - ready - preparingRedefense - awaitingEndorsement > 0)
      '${total - ready - preparingRedefense - awaitingEndorsement} pending',
    if (total == 0) 'No teams to schedule',
  ].join(' · ');
  String get status => total == 0
      ? 'empty'
      : ready == total
      ? 'ready'
      : ready > 0
      ? 'partial'
      : preparingRedefense > 0
      ? 'preparing_redefense'
      : states.any((s) => s['status'] == 'blocked')
      ? 'blocked'
      : 'awaiting_endorsement';
  String get label => switch (status) {
    'ready' =>
      readyForRedefense == total ? 'Ready for re-defense' : 'Ready to schedule',
    'partial' => 'Partly ready',
    'preparing_redefense' => 'Preparing re-defense',
    'blocked' => 'Not ready to schedule',
    'empty' => 'No teams to schedule',
    _ => 'Awaiting endorsement',
  };
}

List<CapstoneAdviserGroup> capstoneGroups(List<Map<String, dynamic>> teams) {
  final result = <String, List<Map<String, dynamic>>>{};
  for (final team in teams) {
    result
        .putIfAbsent(
          '${team['adviser_id']}:${team['intake_semester_id']}',
          () => [],
        )
        .add(team);
  }
  return result.entries
      .map((e) => CapstoneAdviserGroup(e.key, e.value))
      .toList();
}
