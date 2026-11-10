import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/defensys_tokens.dart';
import '../utils/person_name.dart';
import 'shadcn/defensys_shadcn_scope.dart';

/// Pickers submit usernames, never database primary keys or display labels.
String teamImportAccountId(Map account) =>
    '${account['username'] ?? account['student_id'] ?? ''}'.trim();

String teamImportAccountName(Map account) =>
    '${account['name'] ?? account['full_name'] ?? teamImportAccountId(account)}'
        .trim();

List<Map<String, dynamic>> teamImportAccounts(List<dynamic>? options) {
  final accounts = <String, Map<String, dynamic>>{};
  for (final option in options ?? const []) {
    if (option is! Map) continue;
    final id = teamImportAccountId(option);
    if (id.isNotEmpty) accounts[id] = Map<String, dynamic>.from(option);
  }
  return accounts.values.toList()..sort(
    (a, b) => teamImportAccountName(a).compareTo(teamImportAccountName(b)),
  );
}

/// A spelling suggestion is never an automatic identity match.
String? teamImportNameDifference(String reference, String name) {
  if (reference.contains('\ufffd') || name.contains('\ufffd')) {
    return 'Account name needs encoding repair';
  }
  final uploaded = personNameTokens(reference);
  final stored = personNameTokens(name, surnameFirst: false);
  if (uploaded.join(' ') == stored.join(' ')) return 'Formatting match';
  if (uploaded.length < 2 || stored.length < 2) return null;
  bool initial(String word) => RegExp(r'^[a-z]$').hasMatch(word);
  const suffixes = ['jr', 'sr', 'ii', 'iii', 'iv', 'v'];
  final uploadSuffix = suffixes.contains(uploaded.last) ? uploaded.last : '';
  final storedSuffix = suffixes.contains(stored.last) ? stored.last : '';
  final aBody = [...uploaded]..removeWhere((w) => suffixes.contains(w));
  final bBody = [...stored]..removeWhere((w) => suffixes.contains(w));
  if (aBody.join(' ') == bBody.join(' ') && uploadSuffix != storedSuffix) {
    return 'Suffix differs: ${uploadSuffix.isEmpty ? 'not supplied' : uploadSuffix} versus ${storedSuffix.isEmpty ? 'not supplied' : storedSuffix}';
  }
  if (uploadSuffix == storedSuffix &&
      uploaded.length == stored.length &&
      uploaded.first == stored.first &&
      uploaded.last == stored.last) {
    var expanded = false, compatible = true;
    final conflicts = <String>[];
    for (var i = 1; i < uploaded.length - 1; i++) {
      final a = uploaded[i], b = stored[i];
      if (a == b) continue;
      if (initial(a) && !initial(b) && b.startsWith(a) ||
          initial(b) && !initial(a) && a.startsWith(b)) {
        expanded = true;
      } else {
        compatible = false;
        if (initial(a) && initial(b)) {
          conflicts.add('${a.toUpperCase()} versus ${b.toUpperCase()}');
        }
      }
    }
    if (compatible && expanded) return 'Middle initial expanded';
    if (conflicts.isNotEmpty) {
      return 'Middle initial differs: ${conflicts.join(', ')}';
    }
  }
  if (uploaded.length == stored.length &&
      uploaded.first == stored.first &&
      (uploaded.last.endsWith('-${stored.last}') ||
          stored.last.endsWith('-${uploaded.last}'))) {
    return 'Surname variant: ${uploaded.last} versus ${stored.last}';
  }
  bool omittedInitial(List<String> longer, List<String> shorter) {
    if (longer.length != shorter.length + 1) return false;
    for (var i = 1; i < longer.length - 1; i++) {
      if (RegExp(r'^[a-z]$').hasMatch(longer[i])) {
        final without = [...longer]..removeAt(i);
        if (without.join(' ') == shorter.join(' ')) return true;
      }
    }
    return false;
  }

  if (omittedInitial(uploaded, stored) || omittedInitial(stored, uploaded)) {
    return 'Middle initial omitted in one name';
  }
  // Keep the complete uploaded surname (when provided) and suffix compatible.
  final family = reference.contains(',')
      ? personNameTokens(reference.split(',').first, surnameFirst: false)
      : [uploaded.last];
  if (family.length > stored.length ||
      stored.skip(stored.length - family.length).join(' ') !=
          family.join(' ') ||
      uploaded.length != stored.length) {
    return null;
  }
  final differences = [
    for (var i = 0; i < uploaded.length; i++)
      if (uploaded[i] != stored[i]) i,
  ];
  if (differences.length != 1) return null;
  final i = differences.single;
  final a = uploaded[i], b = stored[i];
  if (a.length < 2 ||
      b.length < 2 ||
      const ['jr', 'sr', 'ii', 'iii', 'iv', 'v'].contains(a) ||
      const ['jr', 'sr', 'ii', 'iii', 'iv', 'v'].contains(b)) {
    return null;
  }
  if (!_oneEditApart(a, b)) return null;
  return 'Spelling differs: ${a.toUpperCase()} versus ${b.toUpperCase()}';
}

bool _oneEditApart(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length >= b.length) i++;
    if (b.length >= a.length) j++;
  }
  return edits + (a.length - i) + (b.length - j) == 1;
}

bool teamImportPossibleName(String reference, String name) =>
    teamImportNameDifference(reference, name) != null;

/// Apply a deliberate selection to equivalent references in this staged batch.
/// Role and section/event boundaries are retained; every changed row revalidates.
List<int> applyTeamImportAccount({
  required List<Map<String, dynamic>> rows,
  required int index,
  required Map<String, dynamic> resolution,
  required String username,
  List<Map<String, dynamic>> resolutions = const [],
  List<List<Map<String, dynamic>>>? allResolutions,
}) {
  final field = '${resolution['field']}';
  if (!const [
    'member_ids',
    'leader_id',
    'adviser_name',
    'instructor_name',
    'project_manager',
  ].contains(field)) {
    return [];
  }
  final original = '${resolution['reference']}';
  final source = rows[index];
  if (username.trim().isEmpty) return [];
  final id = username.trim();
  final sourceKey = '${resolution['reference_key'] ?? personNameKey(original)}';
  final changed = <int>[];
  bool sameScope(Map row) {
    final sourcePit = '${source['level'] ?? ''}'.toUpperCase().contains('PIT');
    final targetPit = '${row['level'] ?? ''}'.toUpperCase().contains('PIT');
    if (sourcePit != targetPit) return false;
    if (field == 'adviser_name') return !targetPit;
    if ('${source['section'] ?? ''}'.trim().isEmpty) return false;
    if (row['section'] != source['section'] ||
        row['year_level'] != source['year_level']) {
      return false;
    }
    return field != 'member_ids' && field != 'leader_id' ||
        row['current_defense_stage'] == source['current_defense_stage'];
  }

  for (var offset = 0; offset < rows.length; offset++) {
    final row = rows[offset];
    if (offset != index && !sameScope(row)) continue;
    final projected = allResolutions != null && offset < allResolutions.length
        ? allResolutions[offset]
        : offset == index
        ? resolutions
        : <Map<String, dynamic>>[];
    bool equivalent(String reference, String targetField) {
      final projection = projected
          .where(
            (r) => r['field'] == targetField && r['reference'] == reference,
          )
          .firstOrNull;
      // An unvalidated row cannot inherit a selection made in another role/scope.
      if (offset != index && allResolutions != null && projection == null) {
        return false;
      }
      return '${projection?['reference_key'] ?? personNameKey(reference)}' ==
          sourceKey;
    }

    if (field == 'member_ids' || field == 'leader_id') {
      final oldMembers = (row['member_ids'] as List? ?? [])
          .map((v) => '$v')
          .toList();
      final leader = '${row['leader_id'] ?? ''}';
      final memberMatch = oldMembers.any((m) => equivalent(m, 'member_ids'));
      final leaderMatch = equivalent(leader, 'leader_id');
      if (!memberMatch && !leaderMatch) continue;
      final identities = <String, String>{
        for (final r in projected)
          if (r['status'] == 'matched' && r['username'] != null)
            '${r['reference']}': '${r['username']}',
      };
      final members = <String>[];
      for (final member in oldMembers) {
        final value =
            equivalent(member, 'member_ids') || identities[member] == id
            ? id
            : member;
        if (!members.contains(value)) members.add(value);
      }
      row['member_ids'] = members;
      if (leaderMatch || identities[leader] == id) row['leader_id'] = id;
    } else {
      final reference = '${row[field] ?? ''}'.isEmpty && field == 'adviser_name'
          ? '${row['adviser_id'] ?? ''}'
          : '${row[field] ?? ''}';
      if (!equivalent(reference, field)) continue;
      row[field] = id;
      if (field == 'adviser_name') row['adviser_id'] = id;
    }
    changed.add(offset);
  }
  return changed;
}

class TeamImportReferenceCorrections extends StatelessWidget {
  const TeamImportReferenceCorrections({
    super.key,
    required this.resolutions,
    required this.onSelected,
    this.students,
    this.faculty,
    this.enabled = true,
  });

  final List<Map<String, dynamic>> resolutions;
  final List<dynamic>? students, faculty;
  final bool enabled;
  final void Function(Map<String, dynamic> resolution, String username)
  onSelected;

  @override
  Widget build(BuildContext context) {
    final unresolved = resolutions
        .where(
          (r) => const [
            'not_found',
            'ambiguous',
            'selection_required',
            'inactive',
            'encoding_problem',
          ].contains(r['status']),
        )
        .where(
          (r) =>
              r['field'] != 'leader_id' ||
              !resolutions.any(
                (m) =>
                    m['field'] == 'member_ids' &&
                    m['reference'] == r['reference'],
              ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final resolution in unresolved)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${_label('${resolution['field']}')}: ${resolution['reference']}',
                  style: const TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12,
                  ),
                ),
                ShadBadge.outline(
                  child: Text(
                    resolution['status'] == 'encoding_problem'
                        ? 'Encoding problem'
                        : resolution['status'] == 'not_found' &&
                              _spellingSuggestions(resolution).isEmpty
                        ? 'Needs account'
                        : 'Needs confirmation',
                  ),
                ),
                ShadButton.outline(
                  key: ValueKey(
                    'resolve-${resolution['field']}-${resolution['reference']}',
                  ),
                  enabled: enabled,
                  onPressed: () => _select(context, resolution),
                  child: const Text('Select account'),
                ),
                for (final account in _spellingSuggestions(resolution))
                  Text(
                    'Possible match: ${teamImportAccountName(account)} (${teamImportAccountId(account)}). '
                    '${teamImportNameDifference('${resolution['reference']}', teamImportAccountName(account))}',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 12,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
              ],
            ),
          ),
        for (final match in resolutions.where(
          (r) =>
              r['status'] == 'matched' &&
              const [
                'omitted_initial',
                'middle_initial_expanded',
                'surname_separator',
              ].contains(r['match_kind']) &&
              r['field'] != 'leader_id',
        ))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Matched: ${match['reference']} → ${match['name']} (${match['username']}). '
              '${match['match_kind'] == 'middle_initial_expanded'
                  ? 'Middle initial expanded.'
                  : match['match_kind'] == 'surname_separator'
                  ? 'Surname separator normalized.'
                  : 'Middle initial omitted in one name.'}',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
      ],
    );
  }

  Iterable<Map<String, dynamic>> _spellingSuggestions(Map resolution) =>
      teamImportAccounts(
            const [
                  'adviser_name',
                  'instructor_name',
                ].contains(resolution['field'])
                ? faculty
                : students,
          )
          .where(
            (account) =>
                teamImportNameDifference(
                  '${resolution['reference']}',
                  teamImportAccountName(account),
                )?.startsWith('Spelling differs:') ==
                true,
          )
          .take(2);

  String _label(String field) => switch (field) {
    'member_ids' => 'Member',
    'leader_id' => 'Leader',
    'adviser_name' => 'Adviser',
    'instructor_name' => 'Instructor',
    'project_manager' => 'Project Manager',
    _ => 'Account',
  };

  Future<void> _select(
    BuildContext context,
    Map<String, dynamic> resolution,
  ) async {
    final isFaculty = const [
      'adviser_name',
      'instructor_name',
    ].contains(resolution['field']);
    final options = teamImportAccounts(isFaculty ? faculty : students);
    final original = '${resolution['reference']}';
    var search = '', typedId = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final visible = options
              .where(
                (a) => '${teamImportAccountName(a)} ${teamImportAccountId(a)}'
                    .toLowerCase()
                    .contains(search.toLowerCase()),
              )
              .toList();
          visible.sort((a, b) {
            final aMatch = teamImportNameDifference(
              original,
              teamImportAccountName(a),
            );
            final bMatch = teamImportNameDifference(
              original,
              teamImportAccountName(b),
            );
            int rank(String? reason) =>
                reason == null || reason.contains('encoding repair')
                ? 2
                : reason.startsWith('Spelling')
                ? 1
                : 0;
            return rank(aMatch) == rank(bMatch)
                ? teamImportAccountName(a).compareTo(teamImportAccountName(b))
                : rank(aMatch).compareTo(rank(bMatch));
          });
          return DefensysShadcnScope(
            maroonActions: true,
            child: ShadDialog(
              constraints: const BoxConstraints(maxWidth: 480),
              title: Text(
                'Select ${_label('${resolution['field']}').toLowerCase()} account',
              ),
              description: Text(
                'Uploaded reference: $original\n'
                '${resolution['field'] == 'adviser_name' ? 'Equivalent adviser references in this upload' : 'Equivalent references in this section'} will use the selected ID.',
              ),
              actions: [
                ShadButton.outline(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShadInput(
                      placeholder: const Text('Search registered name or ID'),
                      onChanged: (value) => update(() => search = value),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .3,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final account in visible)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: ShadButton.outline(
                                  key: ValueKey(
                                    'select-account-${teamImportAccountId(account)}',
                                  ),
                                  height: 0,
                                  onPressed: () => Navigator.pop(
                                    dialogContext,
                                    teamImportAccountId(account),
                                  ),
                                  child: Flexible(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${teamImportAccountName(account)} (${teamImportAccountId(account)})',
                                          maxLines: 3,
                                        ),
                                        if (teamImportNameDifference(
                                              original,
                                              teamImportAccountName(account),
                                            )
                                            case final String reason)
                                          Text(
                                            reason,
                                            style: TextStyle(
                                              fontFamily: DefensysTokens
                                                  .fontFamilyInter,
                                              fontSize: 11,
                                              color:
                                                  DefensysTokens.textSecondaryOf(
                                                    context,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (visible.isEmpty)
                              const Text('No matching account in this list.'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      placeholder: const Text(
                        'Or enter the registered account ID',
                      ),
                      onChanged: (value) =>
                          update(() => typedId = value.trim()),
                    ),
                    const SizedBox(height: 8),
                    ShadButton(
                      enabled: typedId.isNotEmpty,
                      onPressed: () => Navigator.pop(dialogContext, typedId),
                      child: const Text('Use ID and validate'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (selected != null && context.mounted) onSelected(resolution, selected);
  }
}
