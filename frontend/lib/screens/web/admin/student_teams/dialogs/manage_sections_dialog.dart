import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/widgets/feedback/defensys_loading.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

import 'edit_section_dialog.dart';

Future<void> showManageSectionsDialog({
  required BuildContext context,
  required String level,
  String scope = 'active',
  String? yearLevel,
  String? section,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ManageSectionsDialog(
    level: level,
    scope: scope,
    yearLevel: yearLevel,
    section: section,
  ),
);

class ManageSectionsDialog extends ConsumerStatefulWidget {
  const ManageSectionsDialog({
    super.key,
    required this.level,
    this.scope = 'active',
    this.yearLevel,
    this.section,
  });

  final String level;
  final String scope;
  final String? yearLevel, section;

  @override
  ConsumerState<ManageSectionsDialog> createState() =>
      _ManageSectionsDialogState();
}

class _ManageSectionsDialogState extends ConsumerState<ManageSectionsDialog> {
  List<Map<String, dynamic>> _sections = [];
  int? _selectedTeamId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final teams = await ref
          .read(studentTeamsProvider.notifier)
          .fetchSectionTeams(
            level: widget.level,
            scope: widget.scope,
            yearLevel: widget.yearLevel,
            section: widget.section,
          );
      final grouped = <String, Map<String, dynamic>>{};
      for (final team in teams) {
        final section = team['section']?.toString().trim() ?? '';
        final id = int.tryParse('${team['id']}');
        if (team['is_editable'] != true || section.isEmpty || id == null) {
          continue;
        }
        final key =
            '${team['semester_id'] ?? team['display_semester'] ?? ''}\u0000$section';
        final choice = grouped.putIfAbsent(
          key,
          () => {
            'team_id': id,
            'section': section,
            'year_level': team['year_level']?.toString() ?? '',
            'team_count': 0,
          },
        );
        choice['team_count'] = (choice['team_count'] as int) + 1;
      }
      final sections = grouped.values.toList()
        ..sort(
          (a, b) => '${a['section']}'.toLowerCase().compareTo(
            '${b['section']}'.toLowerCase(),
          ),
        );
      for (final choice in sections) {
        final count = choice['team_count'] as int;
        choice['label'] = [
          choice['section'],
          if ('${choice['year_level']}'.isNotEmpty) choice['year_level'],
          '$count ${count == 1 ? 'team' : 'teams'}',
        ].join(' · ');
      }
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _selectedTeamId = sections.firstOrNull?['team_id'] as int?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedTeamId != null) {
      return EditSectionDialog(
        key: ValueKey(_selectedTeamId),
        teamId: _selectedTeamId!,
        scope: widget.scope,
        sectionOptions: _sections,
        onSectionChanged: (id) => setState(() => _selectedTeamId = id),
      );
    }
    return DefensysShadcnScope(
      child: ShadDialog(
        constraints: const BoxConstraints(maxWidth: 600),
        title: const Text('Manage sections'),
        description: Text('${widget.level} · Current term'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (_error != null)
            ShadButton(onPressed: _load, child: const Text('Retry')),
        ],
        child: SizedBox(
          width: 552,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: _loading
                ? DefensysLoading.section(
                    height: 100,
                    label: 'Loading sections…',
                  )
                : Text(
                    _error ??
                        'No editable sections in this view. Assign teams to a section in the current term first.',
                  ),
          ),
        ),
      ),
    );
  }
}
