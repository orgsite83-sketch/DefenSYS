import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/documenter_assignment.dart';
import '../../services/documenter_provider.dart';
import '../../theme/defensys_tokens.dart';
import 'minutes_pdf_dialog.dart';

class DocumenterAssignmentsView extends ConsumerStatefulWidget {
  const DocumenterAssignmentsView({
    super.key,
    required this.onOpenMinutes,
    this.recordsOnly = false,
    this.showHeader = true,
  });
  final ValueChanged<int> onOpenMinutes;
  final bool recordsOnly, showHeader;

  @override
  ConsumerState<DocumenterAssignmentsView> createState() =>
      _DocumenterAssignmentsViewState();
}

class _DocumenterAssignmentsViewState
    extends ConsumerState<DocumenterAssignmentsView> {
  DocumenterFilter _filter = DocumenterFilter.today;
  String _search = '';
  bool _pickedInitialFilter = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(documenterProvider.notifier).fetchAssignments();
    });
  }

  Future<void> _refresh() =>
      ref.read(documenterProvider.notifier).fetchAssignments();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documenterProvider);
    final now = DocumenterAssignment.manilaNow;
    final assignments = state.assignments.map(DocumenterAssignment.new).toList()
      ..sort(DocumenterAssignment.chronological);
    int count(DocumenterFilter filter) =>
        assignments.where((a) => a.matches(filter, now)).length;
    if (!_pickedInitialFilter && assignments.isNotEmpty) {
      _pickedInitialFilter = true;
      _filter = [
        DocumenterFilter.today,
        DocumenterFilter.needsAction,
        DocumenterFilter.upcoming,
        DocumenterFilter.records,
        DocumenterFilter.all,
      ].firstWhere((f) => count(f) > 0);
    }
    final selected = widget.recordsOnly ? DocumenterFilter.records : _filter;
    final visible = assignments
        .where(
          (a) =>
              a.matches(selected, now) &&
              '${a.team} ${a.data['project_title']} ${a.data['defense_stage_label']}'
                  .toLowerCase()
                  .contains(_search),
        )
        .toList();
    if (selected == DocumenterFilter.records) {
      visible.sort((a, b) => DocumenterAssignment.chronological(b, a));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showHeader)
                    Text(
                      widget.recordsOnly
                          ? 'Minutes records'
                          : 'Documenter workspace',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                  Text(
                    widget.recordsOnly
                        ? 'Track signatures and open finalized records.'
                        : '${count(DocumenterFilter.needsAction)} unfinished minutes need your attention.',
                    style: TextStyle(
                      color: DefensysTokens.textSecondaryOf(context),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh assignments',
              onPressed: state.isLoading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (!widget.recordsOnly) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in DocumenterFilter.values)
                ChoiceChip(
                  label: Text('${_label(filter)} (${count(filter)})'),
                  selected: selected == filter,
                  onSelected: (_) => setState(() {
                    _filter = filter;
                    _pickedInitialFilter = true;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          onChanged: (value) =>
              setState(() => _search = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search team, project or stage',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        if (state.isLoading) const LinearProgressIndicator(),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(state.error!, textAlign: TextAlign.center),
                TextButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          ),
        if (!state.isLoading && state.error == null && visible.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DefensysTokens.borderOf(context)),
            ),
            child: Column(
              children: [
                const Icon(Icons.assignment_turned_in_outlined, size: 36),
                const SizedBox(height: 12),
                Text(
                  assignments.isEmpty
                      ? 'No assigned defenses yet.'
                      : 'No defenses in this view.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  assignments.isEmpty
                      ? 'Your coordinator will assign defenses here.'
                      : 'Choose another filter or adjust your search.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              for (final assignment in visible)
                _assignment(assignment, wide: constraints.maxWidth >= 900),
            ],
          ),
        ),
      ],
    );
  }

  String _label(DocumenterFilter filter) => switch (filter) {
    DocumenterFilter.today => 'Today',
    DocumenterFilter.needsAction => 'Needs action',
    DocumenterFilter.upcoming => 'Upcoming',
    DocumenterFilter.records => 'Records',
    DocumenterFilter.all => 'All',
  };

  Widget _assignment(DocumenterAssignment assignment, {required bool wide}) {
    final data = assignment.data;
    final date = assignment.date;
    final when = date == null
        ? 'Date to be confirmed'
        : DateFormat('EEE, MMM d, yyyy').format(date);
    final time = _time(data['start_time']);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          assignment.team,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (data['project_title']?.toString().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            data['project_title'].toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          data['defense_stage_label']?.toString() ?? 'Capstone defense',
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          '$when${time.isEmpty ? '' : ' · $time'}',
          style: const TextStyle(fontSize: 13),
        ),
        if (data['room']?.toString().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text('Room: ${data['room']}', style: const TextStyle(fontSize: 13)),
        ],
      ],
    );
    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Text(
            assignment.statusLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          assignment.sessionLabel,
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    );
    final action = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!(assignment.locked && assignment.minutesStatus == null))
          FilledButton(
            onPressed: () => assignment.minutesStatus == 'completed'
                ? _preview(assignment)
                : widget.onOpenMinutes(assignment.id),
            style: FilledButton.styleFrom(
              backgroundColor: DefensysTokens.maroon,
              foregroundColor: Colors.white,
            ),
            child: Text(assignment.actionLabel),
          ),
        if (assignment.minutesStatus != null &&
            assignment.minutesStatus != 'completed')
          IconButton(
            tooltip: 'Preview saved minutes PDF',
            onPressed: () => _preview(assignment),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: details),
                const SizedBox(width: 24),
                Expanded(flex: 3, child: status),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: action),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 14),
                status,
                const SizedBox(height: 14),
                action,
              ],
            ),
    );
  }

  Future<void> _preview(DocumenterAssignment assignment) =>
      MinutesPdfDialog.show(
        context,
        scheduleId: assignment.id,
        finalized: assignment.minutesStatus == 'completed',
        teamName: assignment.team,
      );

  String _time(dynamic value) {
    final parts = value?.toString().split(':') ?? [];
    if (parts.length < 2) return '';
    final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
    return hour == null || minute == null
        ? ''
        : DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour, minute));
  }
}
