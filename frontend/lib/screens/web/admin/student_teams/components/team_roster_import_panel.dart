import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/academic/team_formation_service.dart';
import 'package:defensys/utils/csv_file_io.dart';
import '../../user_management/bulk_import/official_class_list_parser.dart';

/// Links a class list to existing enrollments; it never creates student accounts.
class TeamRosterImportPanel extends ConsumerStatefulWidget {
  const TeamRosterImportPanel({
    super.key,
    required this.level,
    this.section,
    required this.sections,
    required this.students,
    required this.onImported,
    this.onBusyChanged,
    this.onDirtyChanged,
    this.canResolveConflicts = false,
  });
  final String level;
  final String? section;
  final List<Map<String, dynamic>> sections;
  final List<Map<String, dynamic>> students;
  final Future<void> Function() onImported;
  final ValueChanged<bool>? onBusyChanged;
  final ValueChanged<bool>? onDirtyChanged;
  final bool canResolveConflicts;
  @override
  ConsumerState<TeamRosterImportPanel> createState() =>
      _TeamRosterImportPanelState();
}

class _TeamRosterImportPanelState extends ConsumerState<TeamRosterImportPanel> {
  late final TextEditingController section;
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? preview;
  String? error, message;
  bool busy = false, resolveConflicts = false;
  @override
  void initState() {
    super.initState();
    section = TextEditingController(text: widget.section ?? '');
  }

  @override
  void dispose() {
    section.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() operation) async {
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      await operation();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> review() => run(() async {
    final result = await ref.read(teamFormationServiceProvider).importPreview({
      'level': widget.level,
      'section': section.text.trim(),
      'students': rows,
      'resolve_conflicts': resolveConflicts,
    }, roster: true);
    if (mounted) setState(() => preview = result);
  });

  Future<void> pick() async {
    final files = await pickMultipleTabularDataFiles();
    if (files.isEmpty || !mounted) return;
    await run(() async {
      final parsed = <Map<String, dynamic>>[];
      for (final file in files) {
        final result = file.isXlsx
            ? parseOfficialClassListXlsx(file.bytes)
            : parseOfficialClassListCsv(file.text ?? utf8.decode(file.bytes));
        if (result.students.isEmpty) {
          throw FormatException(
            'No students found in ${file.name}. Use the existing By Section class-list format.',
          );
        }
        parsed.addAll(result.students);
        if (section.text.isEmpty && result.metadata['section'] != null) {
          section.text = result.metadata['section'].toString();
        }
      }
      if (mounted) {
        setState(() {
          rows = parsed;
          preview = null;
        });
      }
      widget.onDirtyChanged?.call(true);
    });
    if (rows.isNotEmpty && error == null) await review();
  }

  Future<void> save() => run(() async {
    final result = await ref
        .read(teamFormationServiceProvider)
        .importCommit(preview!['preview_token'] as String, roster: true);
    if (!mounted) return;
    setState(() {
      rows = [];
      preview = null;
      message =
          '${result['updated_count']} section assignments updated; ${result['unchanged_count']} already matched.';
    });
    widget.onDirtyChanged?.call(false);
    await widget.onImported();
  });

  @override
  Widget build(BuildContext context) {
    final reviewRows = (preview?['rows'] as List? ?? []).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. Prepare the roster',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.students.length} students in the available roster. Use the current roster or import an updated class list.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.section?.isNotEmpty != true || rows.isNotEmpty)
              SizedBox(
                width: 250,
                child: TextField(
                  controller: section,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Default section',
                    hintText: 'e.g. BSIT-2B',
                  ),
                  onChanged: (_) => setState(() => preview = null),
                ),
              ),
            OutlinedButton.icon(
              onPressed: busy ? null : pick,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import Class List'),
            ),
            if (rows.isNotEmpty)
              TextButton(
                onPressed: busy ? null : review,
                child: const Text('Review class list'),
              ),
          ],
        ),
        if (widget.students.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('View current roster'),
            children: widget.students
                .map(
                  (s) => ListTile(
                    dense: true,
                    title: Text('${s['name']} · ${s['username']}'),
                    subtitle: Text(
                      '${s['section'].toString().isEmpty ? 'Unassigned' : s['section']}${s['assigned'] == true ? ' · Already in a team' : ''}',
                    ),
                  ),
                )
                .toList(),
          ),
        if (widget.canResolveConflicts && rows.isNotEmpty)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Review existing section reassignments'),
            value: resolveConflicts,
            onChanged: busy
                ? null
                : (v) {
                    setState(() {
                      resolveConflicts = v!;
                      preview = null;
                    });
                    review();
                  },
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (message != null) Text(message!),
        if (preview != null) ...[
          const SizedBox(height: 12),
          Text(
            'Class-list review · ${reviewRows.length} students',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          ...reviewRows.map(
            (row) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${row['name']} · ${row['username']}'),
              subtitle: Text(
                '${row['previous_section'] ?? 'Unassigned'} → ${row['section']} · ${row['action']}\n${(row['issues'] as List).join(' ')}',
              ),
              leading: Icon(
                (row['issues'] as List).isEmpty
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: (row['issues'] as List).isEmpty
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          if (preview!['ready'] == true)
            FilledButton(
              onPressed: busy ? null : save,
              child: const Text('Confirm section assignments'),
            ),
          if (preview!['ready'] != true)
            const Text(
              'Resolve the listed issues, then review again. No records have been changed.',
            ),
        ],
        const SizedBox(height: 12),
        const Divider(),
        Text(
          '2. Configure grouping',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}
