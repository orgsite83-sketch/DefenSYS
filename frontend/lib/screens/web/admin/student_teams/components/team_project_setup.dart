import 'package:flutter/material.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/shadcn/defensys_workflow_widgets.dart';

/// The same section project choices for generated and imported rosters.
class TeamProjectSetup extends StatelessWidget {
  const TeamProjectSetup({
    super.key,
    required this.value,
    required this.onChanged,
    required this.students,
    required this.contexts,
    required this.reviewers,
    this.instructor,
    this.allowTitleReplacement = false,
    this.isPit = true,
    this.enabled = true,
  });
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final List<Map<String, dynamic>> students, contexts, reviewers;
  final Map<String, dynamic>? instructor;
  final bool isPit, enabled, allowTitleReplacement;

  void change(String key, dynamic next) => onChanged({...value, key: next});

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkflowSelect(
          label: 'Project architecture',
          value: value['architecture'] ?? 'independent',
          searchable: false,
          enabled: enabled,
          options: const {
            'independent': 'Independent projects',
            'shared': 'Shared section system',
          },
          onChanged: (v) => change('architecture', v),
        ),
        Text(
          value['architecture'] == 'shared'
              ? 'Teams propose modules for the same shared system alternatives. Stage setup controls the total.'
              : 'Each team proposes its own alternatives. Supplied titles fill the first concept; stage setup controls the total.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (value['architecture'] == 'shared') ...[
          const SizedBox(height: 20),
          WorkflowSelect(
            label: 'Section project manager',
            value: value['project_manager_id']?.toString(),
            enabled: enabled,
            options: {for (final s in students) '${s['id']}': '${s['name']}'},
            onChanged: (v) => change('project_manager_id', int.parse(v)),
          ),
          if (isPit)
            WorkflowField(
              label: 'Section instructor',
              helper:
                  'Assigned automatically from the section instructor assignment.',
              child: Text(
                instructor == null
                    ? 'Assign one active section instructor before continuing.'
                    : '${instructor!['faculty__first_name'] ?? ''} ${instructor!['faculty__last_name'] ?? ''}'
                          .trim(),
              ),
            )
          else
            WorkflowSelect(
              label: 'Shared paper reviewer',
              enabled: enabled,
              value: value['reviewer_id']?.toString(),
              options: {
                for (final r in reviewers) '${r['id']}': '${r['name']}',
              },
              onChanged: (v) => change('reviewer_id', int.parse(v)),
            ),
          WorkflowSelect(
            label: 'Concept stage / event',
            value: value['stage_label'],
            enabled: enabled,
            options: {
              for (final c in contexts) '${c['label']}': '${c['label']}',
            },
            onChanged: (v) => change('stage_label', v),
          ),
          if (isPit)
            const WorkflowField(
              label: 'Roster availability',
              child: Text(
                'This selects where shared proposals are reviewed. The current roster is available to all matching PIT events automatically.',
              ),
            ),
          WorkflowSelect(
            label: 'Proposal names',
            value: value['title_mode'] ?? 'student_proposed',
            enabled: enabled,
            searchable: false,
            options: const {
              'student_proposed': 'Students propose; faculty confirms',
              'faculty_provided': 'Faculty starts; students complete',
            },
            onChanged: (v) => change('title_mode', v),
          ),
          if (contexts.isEmpty)
            const Text(
              'Enable concept selection in stage/event setup before choosing shared proposals.',
            ),
        ],
      ],
    ),
  );
}
