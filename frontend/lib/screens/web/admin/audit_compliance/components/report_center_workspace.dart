import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/export/report_catalog.dart';
import 'package:defensys/widgets/export/report_export_configuration.dart';
import 'package:defensys/widgets/export/report_navigation.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';

class ReportCenterWorkspace extends ConsumerStatefulWidget {
  const ReportCenterWorkspace({super.key, this.reportQuery = const {}});
  final Map<String, String> reportQuery;

  @override
  ConsumerState<ReportCenterWorkspace> createState() =>
      _ReportCenterWorkspaceState();
}

class _ReportCenterWorkspaceState extends ConsumerState<ReportCenterWorkspace> {
  final _searchController = TextEditingController();
  String _search = '';
  ReportGroup? _group;
  Map<String, String> _recordParams = {};
  bool _dialogOpen = false;
  int _linkVersion = 0;

  @override
  void initState() {
    super.initState();
    _readReportLink();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(academicPeriodProvider).activeSemester == null) {
        ref.read(academicPeriodProvider.notifier).fetchPeriods();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ReportCenterWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.reportQuery, widget.reportQuery)) {
      _readReportLink();
    }
  }

  void _readReportLink() {
    final version = ++_linkVersion;
    final report = ReportCatalog.find(widget.reportQuery['report'] ?? '');
    if (report == null ||
        !ReportCatalog.visible(ref.read(authProvider).user).contains(report)) {
      return;
    }
    _group = ReportNavigation.groupFor(report.id);
    final params = Map<String, String>.of(widget.reportQuery)
      ..remove('tab')
      ..remove('report')
      ..remove('source');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && version == _linkVersion) {
        _openReport(report, params: params);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, String> _retainedParams(ReportDefinition report) => {
    for (final key in const [
      'semester_id',
      'scope',
      'type',
      'year_level',
      'section',
      'stage_id',
      'pit_event_config_id',
      'academic_year',
      'school_year',
      'semester',
      'coverage',
      'detail_level',
    ])
      if (_recordParams.containsKey(key) &&
          (report.filters.contains(key) ||
              (const ['team-grade', 'individual-grade'].contains(report.id) &&
                  const ['year_level', 'section'].contains(key))) &&
          (key != 'coverage' ||
              (report.id.endsWith('grade-masterlist')
                      ? const ['assessment', 'semester']
                      : const ['latest', 'all'])
                  .contains(_recordParams[key])))
        key: _recordParams[key]!,
  };

  Future<void> _openReport(
    ReportDefinition report, {
    Map<String, String>? params,
  }) async {
    if (_dialogOpen ||
        !ReportCatalog.visible(ref.read(authProvider).user).contains(report)) {
      return;
    }
    _dialogOpen = true;
    try {
      await showReportExportConfiguration(
        context: context,
        ref: ref,
        report: report,
        params: params ?? _retainedParams(report),
        simplified: true,
        onParamsChanged: (values) => _recordParams = Map.of(values),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  void _openGroup(ReportGroup group) => setState(() {
    _group = group;
    _search = '';
    _searchController.clear();
  });

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final visible = ReportCatalog.visible(user);
    final reports = _group?.reportsFor(user) ?? <ReportDefinition>[];
    final groupAvailable = _group != null && reports.isNotEmpty;
    final source = widget.reportQuery['source'] ?? '';
    return DefensysShadcnScope(
      maroonActions: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (source.startsWith('/admin/') ||
              source.startsWith('/faculty/')) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                leading: const Icon(Icons.arrow_back, size: 16),
                onPressed: () {
                  if (GoRouter.of(context).canPop()) {
                    context.pop();
                  } else {
                    context.go(source);
                  }
                },
                child: const Text('Back to source'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (groupAvailable) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                key: const ValueKey('report-back'),
                leading: const Icon(Icons.arrow_back, size: 16),
                onPressed: () => setState(() => _group = null),
                child: const Text('All reports'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          DefensysPageHeader(
            icon: groupAvailable ? _group!.icon : Icons.summarize_outlined,
            title: groupAvailable ? _group!.title : 'Report Center',
            subtitle: groupAvailable
                ? 'Choose a report to set its filters and preview the results.'
                : 'Choose what you need to report.',
          ),
          const SizedBox(height: 24),
          if (groupAvailable)
            _categoryReports(reports)
          else if (visible.isEmpty)
            const Text('No reports are available for this account.')
          else ...[
            Row(
              children: [
                Expanded(
                  child: ShadInput(
                    key: const ValueKey('report-search'),
                    controller: _searchController,
                    placeholder: const Text('Find a report…'),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                if (_search.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Clear report search',
                    child: ShadButton.ghost(
                      width: 36,
                      height: 36,
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                      child: const Icon(Icons.close, size: 16),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (_search.trim().isEmpty)
              _groups(user)
            else
              _reportCards(ReportNavigation.search(user, _search)),
          ],
        ],
      ),
    );
  }

  Widget _categoryReports(List<ReportDefinition> reports) {
    if (_group!.id != 'grades') return _reportCards(reports);
    final lists = reports
        .where(
          (report) => const [
            'student-grade-masterlist',
            'team-grade-masterlist',
            'individual-grade',
            'team-grade',
          ].contains(report.id),
        )
        .toList();
    final summaries = reports
        .where((report) => !lists.contains(report))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Grade lists & report cards'),
        const SizedBox(height: 12),
        _reportCards(lists),
        if (summaries.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionLabel('Grade summaries'),
          const SizedBox(height: 12),
          _reportCards(summaries),
        ],
      ],
    );
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: DefensysTokens.textPrimaryOf(context),
    ),
  );

  Widget _groups(Map<String, dynamic>? user) => _grid([
    for (final group in ReportNavigation.groups.where(
      (group) => group.reportsFor(user).isNotEmpty,
    ))
      _ReportCard(
        key: ValueKey('report-group-${group.id}'),
        title: group.title,
        description: group.description,
        icon: group.icon,
        onPressed: () => _openGroup(group),
      ),
  ]);

  Widget _reportCards(List<ReportDefinition> reports) {
    if (reports.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('No reports found. Try another name or topic.'),
      );
    }
    return _grid([
      for (final report in reports)
        _ReportCard(
          key: ValueKey('open-report-${report.id}'),
          title: ReportNavigation.title(report),
          description: ReportNavigation.description(report),
          icon: report.icon,
          onPressed: () => _openReport(report),
        ),
    ]);
  }

  Widget _grid(List<Widget> cards) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1100
          ? 3
          : constraints.maxWidth >= 620
          ? 2
          : 1;
      final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final card in cards) SizedBox(width: width, child: card),
        ],
      );
    },
  );
}

/// One keyboard-accessible hit target covers the complete card surface.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onPressed,
  });
  final String title, description;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ShadButton.outline(
    onPressed: onPressed,
    height: 0,
    padding: const EdgeInsets.all(18),
    backgroundColor: DefensysTokens.surfaceOf(context),
    hoverBackgroundColor: DefensysTokens.surfaceHigherOf(context),
    foregroundColor: DefensysTokens.textPrimaryOf(context),
    hoverForegroundColor: DefensysTokens.textPrimaryOf(context),
    decoration: ShadDecoration(
      border: ShadBorder.all(
        color: DefensysTokens.borderOf(context),
        radius: BorderRadius.circular(DefensysTokens.radiusLg),
      ),
    ),
    child: Expanded(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 82),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: DefensysTokens.maroonTextOf(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 12,
                height: 1.5,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
