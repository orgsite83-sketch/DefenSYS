import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

const _commonFields = [
  'label',
  'deliverable_type',
  'required',
  'file_format',
  'file_policy',
  'archive_note',
  'archive_file_template',
  'is_restricted',
  'is_defense_material',
  'verdict_condition',
  'requirement_timing',
  'deadline_hours_before',
  'display_order',
];

dynamic _clean(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (!entry.key.toString().startsWith('_'))
          entry.key.toString(): _clean(entry.value),
    };
  }
  if (value is List) return value.map(_clean).toList();
  return value;
}

Map<String, dynamic> _copy(Map<String, dynamic> row) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(_clean(row))) as Map);

Map<String, dynamic> cleanDeliverableDefinition(Map<String, dynamic> row) =>
    _copy(row)..remove('has_data')..remove('is_locked')..remove('lock_reason');

/// Browser drafts cannot replace or remove requirements protected since saving.
List<Map<String, dynamic>> restoreProtectedDeliverables(dynamic draft, dynamic server) {
  final rows = (draft as List? ?? []).whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row)).toList();
  for (final original in (server as List? ?? []).whereType<Map>()) {
    if (original['has_data'] != true && original['is_locked'] != true) continue;
    final index = rows.indexWhere((row) =>
        (original['id'] != null && row['id'] == original['id']) ||
        row['deliverable_id'] == original['deliverable_id']);
    final protected = Map<String, dynamic>.from(original);
    if (index < 0) {
      rows.add(protected);
    } else {
      rows[index] = protected;
    }
  }
  return rows;
}

String _nextNumber(List<Map<String, dynamic>> rows, String prefix) {
  var number = 1;
  while (rows.any((row) => row['deliverable_id'] == '$prefix$number')) {
    number++;
  }
  return '$prefix$number';
}

/// Existing team and PM records remain independent. Only an explicit link
/// combines their configuration; matching labels never combine historical work.
List<Map<String, dynamic>> deliverableSetupItems(
  List<Map<String, dynamic>> teams,
  List<Map<String, dynamic>> shared,
) {
  final linked = <String>{};
  for (final team in teams) {
    if (team['deliverable_id']?.toString().isNotEmpty != true) {
      team['deliverable_id'] = _nextNumber(teams, 'D');
    }
    final matches = shared.where(
      (row) =>
          row['team_deliverable_id'] == team['deliverable_id'] &&
          row['deliverable_type'] == team['deliverable_type'],
    );
    team['_submissionAudience'] = matches.isEmpty ? 'teams' : 'both';
    final protectedMatch = matches.where((row) => row['is_locked'] == true || row['has_data'] == true).firstOrNull;
    if (protectedMatch != null) {
      team['is_locked'] = true;
      team['has_data'] = protectedMatch['has_data'] == true || team['has_data'] == true;
      team['lock_reason'] = protectedMatch['lock_reason'];
    }
    linked.addAll(matches.map((row) => row['deliverable_id'].toString()));
  }
  final pm = shared
      .where((row) => !linked.contains(row['deliverable_id']))
      .toList();
  for (final row in pm) {
    row['_submissionAudience'] = 'pm';
  }
  return [...teams, ...pm];
}

String deliverableSubmissionAudience(Map<String, dynamic> row) =>
    row['_submissionAudience']?.toString() ??
    row['submission_audience']?.toString() ??
    'teams';

/// Fresh concept defaults are one requirement for both recipients. This is only
/// used when enabling a new shared checklist, never to merge saved evidence.
void linkNewSharedConceptDefaults(
  List<Map<String, dynamic>> teams,
  List<Map<String, dynamic>> shared,
) {
  for (final row in shared) {
    if (!['SHARED_CONCEPTS', 'SHARED_FINAL'].contains(row['deliverable_id'])) {
      continue;
    }
    final automatic = teams
        .where(
          (team) =>
              (team['file_policy'] as Map?)?['auto_added_for'] ==
                  'concept_selection' &&
              team['deliverable_type'] == row['deliverable_type'],
        )
        .firstOrNull;
    if (automatic != null) {
      row['team_deliverable_id'] = automatic['deliverable_id'];
    }
  }
}

void _copyFields(Map<String, dynamic> source, Map<String, dynamic> target) {
  final clean = _copy(source);
  for (final field in _commonFields) {
    if (clean.containsKey(field)) {
      target[field] = clean[field];
    } else {
      target.remove(field);
    }
  }
}

String _canonical(dynamic value) {
  dynamic ordered(dynamic input) {
    if (input is Map) {
      final keys = input.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: ordered(input[key])};
    }
    if (input is List) return input.map(ordered).toList();
    return input;
  }

  return jsonEncode(ordered(value));
}

bool _sameAutomaticPaper(
  Map<String, dynamic> first,
  Map<String, dynamic> second,
) {
  Map<String, dynamic> normalized(Map<String, dynamic> row) {
    final policy = Map<String, dynamic>.from(row['file_policy'] as Map? ?? {})
      ..remove('auto_added_for');
    return {
      'label': '${row['label'] ?? ''}'.trim().toLowerCase(),
      'type': row['deliverable_type'],
      'format': row['file_format'] ?? 'any',
      'required': row['required'] == true,
      'policy': policy,
      'restricted': row['is_restricted'] == true,
      'panelist': row['is_defense_material'] == true,
      'template': row['archive_file_template'] ?? '',
    };
  }

  return _canonical(normalized(first)) == _canonical(normalized(second));
}

void setDeliverableSubmissionAudience(
  Map<String, dynamic> item,
  String audience,
  List<Map<String, dynamic>> teams,
  List<Map<String, dynamic>> shared,
) {
  assert(['teams', 'both', 'pm'].contains(audience));
  final inTeams = teams.contains(item);
  final linked = inTeams
      ? shared
            .where(
              (row) => row['team_deliverable_id'] == item['deliverable_id'],
            )
            .toList()
      : <Map<String, dynamic>>[];
  if (audience == 'pm') {
    if (inTeams) {
      final previous = linked.firstOrNull;
      item['_originalTeamNumber'] = item['deliverable_id'];
      item['_originalTeamDatabaseId'] = item.remove('id');
      teams.remove(item);
      shared.removeWhere(linked.contains);
      item['deliverable_id'] =
          previous?['deliverable_id'] ??
          item['_originalSharedNumber'] ??
          _nextNumber(shared, 'SHARED_D');
      if (previous?['legacy_purpose'] != null) {
        item['legacy_purpose'] = previous!['legacy_purpose'];
      }
      item.remove('team_deliverable_id');
      shared.add(item);
    }
  } else {
    Map<String, dynamic>? pmDefinition = linked.firstOrNull;
    if (inTeams &&
        audience == 'both' &&
        pmDefinition == null &&
        (item['file_policy'] as Map?)?['auto_added_for'] ==
            'concept_selection') {
      final number = item['deliverable_type'] == 'pre'
          ? 'SHARED_CONCEPTS'
          : 'SHARED_FINAL';
      pmDefinition = shared
          .where(
            (row) =>
                row['deliverable_id'] == number &&
                row['team_deliverable_id'] == null &&
                _sameAutomaticPaper(item, row),
          )
          .firstOrNull;
    }
    if (!inTeams) {
      final sharedNumber = item['deliverable_id'];
      pmDefinition = _copy(item)..remove('id');
      item['_originalSharedNumber'] = sharedNumber;
      shared.remove(item);
      final original = item['_originalTeamNumber'];
      item['deliverable_id'] =
          original != null &&
              !teams.any((row) => row['deliverable_id'] == original)
          ? original
          : _nextNumber(teams, 'D');
      if (item['_originalTeamDatabaseId'] != null) {
        item['id'] = item['_originalTeamDatabaseId'];
      }
      item.remove('team_deliverable_id');
      teams.add(item);
    }
    if (audience == 'teams') {
      for (final row in linked) {
        item['_originalSharedNumber'] = row['deliverable_id'];
        shared.remove(row);
      }
    } else {
      if (pmDefinition == null) {
        pmDefinition = _copy(item)..remove('id');
        final original = item['_originalSharedNumber'];
        pmDefinition['deliverable_id'] =
            original != null &&
                !shared.any((row) => row['deliverable_id'] == original)
            ? original
            : _nextNumber(shared, 'SHARED_D');
      }
      _copyFields(item, pmDefinition);
      pmDefinition['team_deliverable_id'] = item['deliverable_id'];
      if (!shared.contains(pmDefinition)) shared.add(pmDefinition);
    }
  }
  item['_submissionAudience'] = audience;
}

void removeConfiguredDeliverable(
  Map<String, dynamic> item,
  List<Map<String, dynamic>> teams,
  List<Map<String, dynamic>> shared,
) {
  if (teams.contains(item)) {
    shared.removeWhere(
      (row) => row['team_deliverable_id'] == item['deliverable_id'],
    );
    teams.remove(item);
  } else {
    shared.remove(item);
  }
}

/// Synchronize the one edited definition into its separate PM submission record.
List<Map<String, dynamic>> configuredSharedDeliverables(
  List<Map<String, dynamic>> teams,
  List<Map<String, dynamic>> shared,
) => shared.map((row) {
  final result = _copy(row)..remove('id');
  final team = teams
      .where((item) => item['deliverable_id'] == row['team_deliverable_id'])
      .firstOrNull;
  if (team != null) _copyFields(team, result);
  return result;
}).toList();

/// Presets carry the choice, without copying database IDs or PM record links.
List<Map<String, dynamic>> deliverablePresetItems(
  List<Map<String, dynamic>> teams,
  List<Map<String, dynamic>> shared,
) => deliverableSetupItems(teams, shared)
    .map(
      (row) => _copy(row)
        ..remove('id')
        ..remove('team_deliverable_id')
        ..remove('has_data')
        ..remove('is_locked')
        ..remove('lock_reason')
        ..['submission_audience'] = deliverableSubmissionAudience(row),
    )
    .toList();

void applyDeliverablePresetItems(
  List<Map<String, dynamic>> items,
  List<Map<String, dynamic>> teams,
  List<Map<String, dynamic>> shared,
) {
  teams.clear();
  shared.clear();
  for (final source in items) {
    final row = _copy(source)
      ..remove('id')
      ..remove('team_deliverable_id')
      ..remove('has_data')
      ..remove('is_locked')
      ..remove('lock_reason');
    final audience = row.remove('submission_audience')?.toString() ?? 'teams';
    row['deliverable_id'] = _nextNumber(teams, 'D');
    teams.add(row);
    if (audience != 'teams') {
      setDeliverableSubmissionAudience(row, audience, teams, shared);
    }
  }
}

class DeliverableSubmissionPicker extends StatelessWidget {
  const DeliverableSubmissionPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const labels = {
      'teams': 'Teams only',
      'both': 'Teams and project managers',
      'pm': 'Project managers only',
    };
    const hints = {
      'teams':
          'Each team submits its own files, including shared-system module teams.',
      'both':
          'Each team submits its own files. The project manager also submits for the whole shared system.',
      'pm':
          'The project manager submits for the whole shared system or section.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Who must submit?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 10),
        DefensysShadcnScope(
          child: ShadRadioGroup<String>(
            key: ValueKey('deliverable-submitters-$value'),
            initialValue: value,
            enabled: enabled,
            axis: Axis.horizontal,
            spacing: 20,
            runSpacing: 12,
            items: [
              for (final entry in labels.entries)
                ShadRadio(
                  value: entry.key,
                  label: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            onChanged: (next) {
              if (next != null && next != value) onChanged(next);
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hints[value] ?? hints['teams']!,
          style: TextStyle(
            fontSize: 11.5,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    );
  }
}
