import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../services/academic/team_formation_service.dart';
import '../../../widgets/shadcn/defensys_workflow_widgets.dart';
import '../admin/student_teams/components/team_roster_import_panel.dart';

/// Confirms the section class list before the roster workspace groups students.
class TeamRosterStudentsStep extends ConsumerStatefulWidget {
  const TeamRosterStudentsStep({
    super.key,
    required this.year,
    required this.section,
    required this.onConfirmed,
    required this.onCancel,
    required this.onBusyChanged,
  });

  final String year, section;
  final ValueChanged<List<int>> onConfirmed;
  final VoidCallback onCancel;
  final ValueChanged<bool> onBusyChanged;

  @override
  ConsumerState<TeamRosterStudentsStep> createState() =>
      _TeamRosterStudentsStepState();
}

class _TeamRosterStudentsStepState
    extends ConsumerState<TeamRosterStudentsStep> {
  Map<String, dynamic>? options;
  String? error;
  bool loading = true, importing = false, dirty = false, confirmed = false;
  bool get busy => loading || importing;
  List<Map<String, dynamic>> get students =>
      (options?['students'] as List? ?? [])
          .whereType<Map>()
          .where((student) => student['section'] == widget.section)
          .map((student) => Map<String, dynamic>.from(student))
          .toList();

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      confirmed = false;
      error = null;
    });
    widget.onBusyChanged(true);
    try {
      final result = await ref
          .read(teamFormationServiceProvider)
          .options('${widget.year} PIT', null);
      if (mounted) setState(() => options = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          options = null;
          error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        widget.onBusyChanged(busy);
      }
    }
  }

  Future<void> refreshAfterImport() async {
    await load();
    if (mounted) {
      // A failed refresh removes the importer, so its final busy callback may
      // never run. Release it here to keep retry and navigation available.
      setState(() => importing = false);
      widget.onBusyChanged(busy);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Import the official class list to confirm which students belong to this section. If the class list is already imported, review it and confirm it below.',
        style: TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 20),
      if (error != null) ...[
        WorkflowNotice(
          title: 'Unable to load the class list',
          message: error!,
          error: true,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            enabled: !busy,
            onPressed: load,
            height: 0,
            child: const Flexible(child: Text('Retry class list')),
          ),
        ),
      ],
      if (options != null) ...[
        TeamRosterImportPanel(
          level: '${widget.year} PIT',
          section: widget.section,
          sections: [
            for (final item in options!['sections'] as List? ?? [])
              Map<String, dynamic>.from(item as Map),
          ],
          students: students,
          showGroupingHeader: false,
          canResolveConflicts: options!['can_manage_policy'] == true,
          onBusyChanged: (value) {
            setState(() => importing = value);
            widget.onBusyChanged(busy);
          },
          onDirtyChanged: (value) => setState(() {
            dirty = value;
            confirmed = false;
          }),
          onImported: refreshAfterImport,
        ),
        const SizedBox(height: 20),
        if (students.isEmpty)
          WorkflowNotice(
            title: 'Import students first',
            message:
                'No students are confirmed in ${widget.section}. Import and apply the class list before choosing how to group teams.',
          )
        else
          ShadCheckbox(
            key: const ValueKey('confirm-generation-students'),
            value: confirmed,
            enabled: !busy && !dirty,
            onChanged: (value) => setState(() => confirmed = value),
            label: Text(
              'I confirm these ${students.length} students belong to ${widget.section}.',
            ),
            sublabel: const Text(
              'All students in this class list will be included in the generated teams.',
            ),
          ),
        if (dirty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Apply or remove the staged class list before continuing.',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
      const SizedBox(height: 20),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 10,
        runSpacing: 10,
        children: [
          ShadButton.outline(
            enabled: !busy,
            onPressed: widget.onCancel,
            height: 0,
            child: const Flexible(child: Text('Cancel')),
          ),
          ShadButton(
            key: const ValueKey('continue-generation-grouping'),
            height: 0,
            enabled:
                !busy &&
                !dirty &&
                confirmed &&
                students.isNotEmpty &&
                error == null,
            onPressed: () => widget.onConfirmed([
              for (final student in students) student['id'] as int,
            ]),
            child: const Flexible(
              child: Text('Continue to grouping', textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    ],
  );
}
