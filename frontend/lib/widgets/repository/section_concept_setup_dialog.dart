import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/academic/section_concept_service.dart';
import 'section_concept_workspace.dart';

List<Map<String, dynamic>> _maps(dynamic value) => (value as List? ?? [])
    .whereType<Map>()
    .map((r) => Map<String, dynamic>.from(r))
    .toList();

class SectionConceptSetupDialog extends ConsumerStatefulWidget {
  const SectionConceptSetupDialog({
    super.key,
    required this.details,
    required this.scope,
  });
  final Map<String, dynamic> details;
  final String scope;
  @override
  ConsumerState<SectionConceptSetupDialog> createState() =>
      _SectionConceptSetupDialogState();
}

class _SectionConceptSetupDialogState
    extends ConsumerState<SectionConceptSetupDialog> {
  Map<String, dynamic>? selected;
  List<Map<String, dynamic>> reviewers = [];
  int? manager, reviewer;
  String mode = 'student_proposed';
  bool busy = false;
  String? error;
  List<Map<String, dynamic>> get contexts =>
      _maps(widget.details['concept_contexts']);
  @override
  void initState() {
    super.initState();
    selected = contexts.firstOrNull;
    manager = widget.details['project_manager_id'] as int?;
    if (selected != null) {
      Future.microtask(loadReviewers);
    }
  }

  Future<void> loadReviewers() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final options = widget.details;
      if (mounted) {
        setState(() {
          reviewers = _maps(options['system_reviewers']);
          reviewer = reviewers.any((r) => r['id'] == reviewer)
              ? reviewer
              : reviewers.firstOrNull?['id'] as int?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (selected == null || manager == null || reviewer == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref.read(sectionConceptServiceProvider).configure({
        'team_ids': _maps(selected!['teams']).map((t) => t['id']).toList(),
        'stage_label': selected!['label'],
        'project_manager_id': manager,
        'reviewer_id': reviewer,
        'title_mode': mode,
      });
      if (!mounted) return;
      Navigator.pop(context, result['id']);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString().replaceFirst('Exception: ', '');
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.details['section']} · Shared system setup'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Create the number of shared system proposals configured for this stage/event, with matching module proposals from every team. Supplied titles fill the first proposal. Activate this before concept work starts.',
            ),
            const SizedBox(height: 16),
            if (contexts.isEmpty)
              const Text('Enable concept selection on a stage/event first.'),
            DropdownButtonFormField<String>(
              initialValue: selected?['key']?.toString(),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Concept stage / event',
              ),
              items: [
                for (final c in contexts)
                  DropdownMenuItem(
                    value: '${c['key']}',
                    child: Text('${c['label']}'),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) {
                      setState(
                        () => selected = contexts.firstWhere(
                          (c) => c['key'] == v,
                        ),
                      );
                      loadReviewers();
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: manager,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Section project manager',
              ),
              items: [
                for (final s in _maps(widget.details['students']))
                  DropdownMenuItem(
                    value: s['id'] as int,
                    child: Text('${s['name']}'),
                  ),
              ],
              onChanged: busy ? null : (v) => setState(() => manager = v),
            ),
            const SizedBox(height: 12),
            if (widget.scope == 'pit' && reviewers.length == 1)
              Text('Section instructor: ${reviewers.single['name']}')
            else if (reviewers.isNotEmpty)
              DropdownButtonFormField<int>(
                key: ValueKey('reviewer-$reviewer'),
                initialValue: reviewer,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'System faculty reviewer',
                ),
                items: [
                  for (final r in reviewers)
                    DropdownMenuItem(
                      value: r['id'] as int,
                      child: Text('${r['name']}'),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => reviewer = v),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Proposal names'),
              items: const [
                DropdownMenuItem(
                  value: 'student_proposed',
                  child: Text('Students propose; faculty confirms'),
                ),
                DropdownMenuItem(
                  value: 'faculty_provided',
                  child: Text('Faculty starts; students complete'),
                ),
              ],
              onChanged: busy ? null : (v) => setState(() => mode = v!),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            busy || selected == null || manager == null || reviewer == null
            ? null
            : save,
        child: const Text('Activate shared system'),
      ),
    ],
  );
}

Future<void> openSectionConceptSetup(
  BuildContext context,
  Map<String, dynamic> details,
  String scope,
) async {
  final id = await showDialog<int>(
    context: context,
    builder: (_) => SectionConceptSetupDialog(details: details, scope: scope),
  );
  if (id != null && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SectionConceptWorkspace(projectId: id),
      ),
    );
  }
}
