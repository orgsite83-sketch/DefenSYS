import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/defensys_tokens.dart';
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

/// Suggestions only affect ordering in an already authorized account picker.
bool teamImportPossibleName(String reference, String name) {
  List<String> tokens(String value) {
    final parts = value.split(',');
    if (parts.length == 2) value = '${parts[1]} ${parts[0]}';
    return value.toLowerCase().trim().split(RegExp(r'\s+')).map((word) {
      return RegExp(r'^[a-z]\.$').hasMatch(word) ? word.substring(0, 1) : word;
    }).toList();
  }

  final uploaded = tokens(reference), stored = tokens(name);
  if (uploaded.join(' ') == stored.join(' ')) return true;
  if (uploaded.length < 2 || stored.length < 2) return false;
  // Removing an interior one-letter token must reproduce the complete other name.
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

  return omittedInitial(uploaded, stored) || omittedInitial(stored, uploaded);
}

/// An explicit replacement updates leader/member identity together. The server
/// still rechecks identity, role, activity, enrollment and membership afterward.
List<int> applyTeamImportAccount({
  required List<Map<String, dynamic>> rows,
  required int index,
  required Map<String, dynamic> resolution,
  required String username,
  List<Map<String, dynamic>> resolutions = const [],
}) {
  final field = '${resolution['field']}';
  final original = '${resolution['reference']}';
  final row = rows[index];
  if (username.trim().isEmpty) return [];
  final id = username.trim();
  final identities = <String, String>{
    for (final r in resolutions)
      if (r['status'] == 'matched' && r['username'] != null)
        '${r['reference']}': '${r['username']}',
  };
  if (field == 'member_ids' || field == 'leader_id') {
    final oldMembers = (row['member_ids'] as List? ?? []).map((v) => '$v');
    final members = <String>[];
    for (final member in oldMembers) {
      final value = member == original || identities[member] == id
          ? id
          : member;
      if (!members.contains(value)) members.add(value);
    }
    row['member_ids'] = members;
    final leader = '${row['leader_id'] ?? ''}';
    if (leader == original || identities[leader] == id) row['leader_id'] = id;
    // A separately unresolved leader must still be a selected team member.
    if (field == 'leader_id') row['leader_id'] = id;
    return [index];
  }
  if (field == 'project_manager') {
    final changed = <int>[];
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['section'] == row['section'] &&
          '${rows[i][field] ?? ''}' == original) {
        rows[i][field] = id;
        changed.add(i);
      }
    }
    return changed;
  }
  row[field] = id;
  if (field == 'adviser_name') row['adviser_id'] = id;
  return [index];
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
                ShadButton.outline(
                  key: ValueKey(
                    'resolve-${resolution['field']}-${resolution['reference']}',
                  ),
                  enabled: enabled,
                  onPressed: () => _select(context, resolution),
                  child: const Text('Select account'),
                ),
              ],
            ),
          ),
      ],
    );
  }

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
            final aMatch = teamImportPossibleName(
              original,
              teamImportAccountName(a),
            );
            final bMatch = teamImportPossibleName(
              original,
              teamImportAccountName(b),
            );
            return aMatch == bMatch
                ? teamImportAccountName(a).compareTo(teamImportAccountName(b))
                : aMatch
                ? -1
                : 1;
          });
          return DefensysShadcnScope(
            maroonActions: true,
            child: ShadDialog(
              constraints: const BoxConstraints(maxWidth: 480),
              title: Text(
                'Select ${_label('${resolution['field']}').toLowerCase()} account',
              ),
              description: Text('Uploaded reference: $original'),
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
                                  height: null,
                                  onPressed: () => Navigator.pop(
                                    dialogContext,
                                    teamImportAccountId(account),
                                  ),
                                  child: Flexible(
                                    child: Text(
                                      '${teamImportAccountName(account)} (${teamImportAccountId(account)})',
                                      maxLines: 3,
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
