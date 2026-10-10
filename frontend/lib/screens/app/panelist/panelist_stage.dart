import 'dart:convert';

import 'panelist_models.dart';

/// Stage identity includes the program and term; equal labels in different
/// semesters or PIT events must never merge in the panel workspace.
class PanelistStage {
  final String key;
  final String label;
  final String term;

  PanelistStage({
    required String scope,
    required String semesterId,
    required String defenseStageId,
    required String stage,
    required String event,
    required this.term,
  }) : key = json.encode([
         scope,
         semesterId,
         scope == 'capstone' && defenseStageId.isNotEmpty
             ? defenseStageId
             : scope == 'pit' && event.isNotEmpty
             ? event
             : stage,
       ]),
       label =
           '${scope == 'capstone'
               ? 'Capstone'
               : scope == 'pit'
               ? 'PIT'
               : 'Defense'} · ${scope == 'pit' && event.isNotEmpty
               ? event
               : stage.isNotEmpty
               ? stage
               : 'Unspecified stage'}';

  factory PanelistStage.forTeam(TeamData team) => PanelistStage(
    scope: team.scope,
    semesterId: team.semesterId,
    defenseStageId: team.defenseStageId,
    stage: team.stageName,
    event: team.eventName,
    term: team.semesterLabel,
  );

  factory PanelistStage.forResult(Map<String, dynamic> result) => PanelistStage(
    scope: result['scope']?.toString() ?? 'unknown',
    semesterId: result['semester_id']?.toString() ?? '',
    defenseStageId: result['defense_stage_id']?.toString() ?? '',
    stage: result['stage']?.toString() ?? '',
    event: result['event_name']?.toString() ?? '',
    term: result['display_semester']?.toString() ?? '',
  );
}
