import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import '../../models/documenter_assignment.dart';
import '../../services/documenter_provider.dart';
import '../../theme/defensys_tokens.dart';
import 'documenter_assignment_tile.dart';
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
  final _searchController = TextEditingController();
  DocumenterFilter _filter = DocumenterFilter.today;
  String _search = '';
  bool _pickedInitialFilter = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      ref.read(documenterProvider.notifier).fetchAssignments();
  void _select(DocumenterFilter filter) => setState(() {
    _filter = filter;
    _pickedInitialFilter = true;
  });

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
      _filter = DocumenterFilter.values.firstWhere((f) => count(f) > 0);
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
    final secondary = DefensysTokens.textSecondaryOf(context);
    return DefensysShadcnScope(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.showHeader) ...[
                          Text(
                            'Defense documentation',
                            style: TextStyle(
                              color: DefensysTokens.maroonTextOf(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          widget.recordsOnly
                              ? 'Minutes records'
                              : widget.showHeader
                              ? 'Documenter workspace'
                              : 'Your defense desk',
                          style: TextStyle(
                            fontFamily: DefensysTokens.fontFamilyInter,
                            fontSize: widget.showHeader ? 28 : 24,
                            height: 1.25,
                            letterSpacing: -0.6,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.recordsOnly
                              ? 'Follow signatures through to the final record.'
                              : 'Capture panel feedback and track signed minutes.',
                          style: TextStyle(
                            color: secondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Refresh assignments',
                    child: ShadButton.outline(
                      width: 40,
                      height: 40,
                      padding: EdgeInsets.zero,
                      enabled: !state.isLoading,
                      onPressed: _refresh,
                      child: const Icon(LucideIcons.refreshCw, size: 17),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (!widget.recordsOnly) ...[
                Row(
                  children: [
                    for (final filter in [
                      DocumenterFilter.today,
                      DocumenterFilter.needsAction,
                      DocumenterFilter.records,
                    ]) ...[
                      if (filter != DocumenterFilter.today)
                        const SizedBox(width: 8),
                      Expanded(
                        child: _summary(
                          filter,
                          count(filter),
                          selected == filter,
                          loading: state.isLoading && assignments.isEmpty,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 22),
                ShadTabs<DocumenterFilter>(
                  value: selected,
                  onChanged: _select,
                  scrollable: true,
                  gap: 0,
                  tabBarAlignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(4),
                  tabs: [
                    for (final filter in DocumenterFilter.values)
                      ShadTab(
                        value: filter,
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '${_label(filter)} (${count(filter)})',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              ShadInput(
                controller: _searchController,
                onChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
                leading: const Icon(LucideIcons.search, size: 18),
                placeholder: const Text('Search team, project or stage'),
                style: const TextStyle(fontSize: 13),
                placeholderStyle: const TextStyle(fontSize: 13),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                trailing: _searchController.text.isEmpty
                    ? null
                    : Tooltip(
                        message: 'Clear search',
                        child: ShadButton.ghost(
                          width: 24,
                          height: 24,
                          padding: EdgeInsets.zero,
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _search = '';
                          }),
                          child: const Icon(LucideIcons.x, size: 16),
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _sectionLabel(selected),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Text(
                    '${visible.length} ${visible.length == 1 ? 'defense' : 'defenses'}',
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                selected == DocumenterFilter.records
                    ? 'Most recent first'
                    : 'In schedule order',
                style: TextStyle(fontSize: 12, color: secondary),
              ),
              const SizedBox(height: 16),
              if (state.isLoading && assignments.isEmpty) _loading(),
              if (state.isLoading && assignments.isNotEmpty) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
              ],
              if (state.error != null)
                _message(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not refresh assignments',
                  detail: state.error!,
                  action: ShadButton.outline(
                    onPressed: _refresh,
                    leading: const Icon(LucideIcons.refreshCw, size: 16),
                    child: const Text('Try again'),
                  ),
                ),
              if (!state.isLoading && state.error == null && visible.isEmpty)
                _message(
                  icon: _search.isNotEmpty
                      ? Icons.search_off_rounded
                      : Icons.assignment_turned_in_outlined,
                  title: _search.isNotEmpty
                      ? 'No matching defenses'
                      : assignments.isEmpty
                      ? 'No assigned defenses yet'
                      : selected == DocumenterFilter.needsAction
                      ? 'You are all caught up'
                      : selected == DocumenterFilter.records
                      ? 'No signed minutes yet'
                      : 'No defenses in this view',
                  detail: _search.isNotEmpty
                      ? 'Try another team, project title or stage.'
                      : assignments.isEmpty
                      ? 'Your coordinator will assign defenses here.'
                      : selected == DocumenterFilter.records
                      ? 'Minutes appear here after you sign them.'
                      : 'Choose another view to see your assignments.',
                  action: _search.isEmpty
                      ? null
                      : ShadButton.ghost(
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _search = '';
                          }),
                          child: const Text('Clear search'),
                        ),
                ),
              LayoutBuilder(
                builder: (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < visible.length; index++) ...[
                      if (index == 0 ||
                          visible[index].date != visible[index - 1].date)
                        Padding(
                          padding: EdgeInsets.only(
                            top: index == 0 ? 0 : 12,
                            bottom: 10,
                          ),
                          child: Text(
                            _dayLabel(visible[index].date, now),
                            style: TextStyle(
                              color: secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      DocumenterAssignmentTile(
                        assignment: visible[index],
                        wide: constraints.maxWidth >= 900,
                        onOpen: () =>
                            visible[index].minutesStatus == 'completed'
                            ? _preview(visible[index])
                            : widget.onOpenMinutes(visible[index].id),
                        onPreview: () => _preview(visible[index]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _summary(
    DocumenterFilter filter,
    int count,
    bool selected, {
    required bool loading,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ShadButton.outline(
      expands: true,
      onPressed: () => _select(filter),
      height: (compact ? 80 : 104) * MediaQuery.textScalerOf(context).scale(1),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 16,
        vertical: compact ? 6 : 16,
      ),
      mainAxisAlignment: MainAxisAlignment.start,
      backgroundColor: selected
          ? DefensysTokens.surfaceHigherOf(context)
          : DefensysTokens.surfaceOf(context),
      hoverBackgroundColor: DefensysTokens.surfaceHigherOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            loading ? '—' : '$count',
            style: TextStyle(
              fontSize: compact ? 22 : 28,
              height: 1,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          SizedBox(height: compact ? 3 : 6),
          Text(
            switch (filter) {
              DocumenterFilter.today => 'Today',
              DocumenterFilter.needsAction => 'To complete',
              _ => compact ? 'Records' : 'Minutes records',
            },
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              height: 1.15,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String detail,
    Widget? action,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Icon(icon, size: 32, color: DefensysTokens.maroonTextOf(context)),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        if (action != null) ...[const SizedBox(height: 12), action],
      ],
    ),
  );

  Widget _loading() => Semantics(
    label: 'Loading assigned defenses',
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            height: 110,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceOf(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.65,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 14,
                      color: DefensysTokens.surfaceHigherOf(context),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 10,
                      color: DefensysTokens.surfaceHigherOf(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  String _dayLabel(DateTime? date, DateTime now) {
    if (date == null) return 'Date to be confirmed';
    final today = DateTime(now.year, now.month, now.day);
    return '${date == today ? 'Today · ' : ''}${DateFormat('EEEE, MMM d, yyyy').format(date)}';
  }

  String _label(DocumenterFilter filter) => switch (filter) {
    DocumenterFilter.today => 'Today',
    DocumenterFilter.needsAction => 'Needs action',
    DocumenterFilter.upcoming => 'Upcoming',
    DocumenterFilter.records => 'Records',
    DocumenterFilter.all => 'All',
  };
  String _sectionLabel(DocumenterFilter filter) => switch (filter) {
    DocumenterFilter.today => "Today's defenses",
    DocumenterFilter.needsAction => 'Defenses to document',
    DocumenterFilter.upcoming => 'Upcoming defenses',
    DocumenterFilter.records => 'Minutes records',
    DocumenterFilter.all => 'All assignments',
  };
  Future<void> _preview(DocumenterAssignment assignment) =>
      MinutesPdfDialog.show(
        context,
        scheduleId: assignment.id,
        finalized: assignment.minutesStatus == 'completed',
        teamName: assignment.team,
      );
}
