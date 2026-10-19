import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../../theme/defensys_tokens.dart';
import 'curriculum_chart_palette.dart';
import 'curriculum_explorer_charts.dart';

/// Technology uses form the pie's denominator; rankings count unique projects.
/// Repeated documents and repeated mentions never add technology uses.
class CurriculumProjectDistribution extends StatefulWidget {
  const CurriculumProjectDistribution({
    super.key,
    required this.projects,
    required this.technology,
    required this.ranking,
    required this.onTechnology,
    required this.onRanking,
    required this.onGroup,
  });
  final List<Map<String, dynamic>> projects;
  final String? technology;
  final String ranking;
  final ValueChanged<String?> onTechnology;
  final ValueChanged<String> onRanking;
  final void Function(String field, String group) onGroup;

  @override
  State<CurriculumProjectDistribution> createState() =>
      _CurriculumProjectDistributionState();
}

class _CurriculumProjectDistributionState
    extends State<CurriculumProjectDistribution> {
  bool _showOther = false;
  TextStyle get _muted => TextStyle(
    fontSize: 12,
    height: 1.5,
    color: DefensysTokens.textSecondaryOf(context),
  );

  List<String> _technologies(Map<String, dynamic> project) =>
      (project['technologies'] as List? ?? [])
          .whereType<String>()
          .toSet()
          .toList();

  Widget _panel(String title, String description, Widget child) => ShadCard(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    title: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    description: Text(description, style: _muted),
    child: Padding(padding: const EdgeInsets.only(top: 18), child: child),
  );

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final project in widget.projects) {
      for (final name in _technologies(project)) {
        counts.update(name, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final technologies = counts.entries.toList()
      ..sort(
        (a, b) => b.value.compareTo(a.value) == 0
            ? a.key.compareTo(b.key)
            : b.value.compareTo(a.value),
      );
    final uses = counts.values.fold(0, (a, b) => a + b);
    final covered = widget.projects
        .where((p) => _technologies(p).isNotEmpty)
        .length;
    final slices = <Map<String, dynamic>>[
      for (final entry in technologies.take(2))
        {'name': entry.key, 'count': entry.value},
      if (technologies.length > 2)
        {
          'name': 'Other technologies',
          'count': technologies
              .skip(2)
              .fold(0, (sum, entry) => sum + entry.value),
          'other': true,
        },
    ];
    void select(Map<String, dynamic> slice) {
      if (slice['other'] == true) {
        setState(() => _showOther = !_showOther);
      } else {
        widget.onTechnology('${slice['name']}');
      }
    }

    final left = _panel(
      'Technology usage',
      'Share of documented technology uses · top two and Other',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (uses == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'No technologies are established in the eligible project documents. Tentative choices are excluded.',
                style: _muted,
              ),
            )
          else ...[
            Semantics(
              label:
                  'Technology usage pie. Each technology is counted once per project. Use the labelled buttons below to select a technology.',
              child: SizedBox(
                height: 240,
                child: SfCircularChart(
                  key: const ValueKey('technology-usage-pie'),
                  margin: EdgeInsets.zero,
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    format: 'point.x: point.y uses',
                  ),
                  series: <CircularSeries<Map<String, dynamic>, String>>[
                    PieSeries<Map<String, dynamic>, String>(
                      dataSource: slices,
                      xValueMapper: (r, _) => '${r['name']}',
                      yValueMapper: (r, _) => r['count'] as num,
                      pointColorMapper: (_, i) =>
                          CurriculumChartPalette.slice(context, i),
                      dataLabelMapper: (r, _) =>
                          '${((r['count'] as num) / uses * 100).toStringAsFixed(1)}%',
                      dataLabelSettings: DataLabelSettings(
                        isVisible: true,
                        labelPosition: ChartDataLabelPosition.outside,
                        textStyle: _muted.copyWith(
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      radius: '78%',
                      animationDuration: 0,
                      onPointTap: (details) {
                        if (details.pointIndex != null) {
                          select(slices[details.pointIndex!]);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            for (final entry in slices.asMap().entries)
              ShadButton.ghost(
                key: ValueKey(
                  entry.value['other'] == true
                      ? 'technology-other'
                      : 'technology-${entry.value['name']}',
                ),
                width: double.infinity,
                height: 56,
                mainAxisAlignment: MainAxisAlignment.start,
                onPressed: () => select(entry.value),
                child: Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        color: CurriculumChartPalette.slice(context, entry.key),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${entry.value['name']}',
                          textAlign: TextAlign.left,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: entry.value['name'] == widget.technology
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.value['count']} · ${((entry.value['count'] as num) / uses * 100).toStringAsFixed(1)}%',
                        style: _muted.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_showOther) ...[
              const Divider(height: 20),
              Text(
                'Other technologies · choose one to filter projects',
                style: _muted,
              ),
              for (final entry in technologies.skip(2))
                ShadButton.ghost(
                  key: ValueKey('technology-${entry.key}'),
                  width: double.infinity,
                  mainAxisAlignment: MainAxisAlignment.start,
                  onPressed: () => widget.onTechnology(entry.key),
                  child: Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('${entry.value} projects', style: _muted),
                      ],
                    ),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 12),
          Text(
            '$covered / ${widget.projects.length} projects have documented technologies.',
            key: const ValueKey('technology-coverage'),
            style: _muted,
          ),
          const SizedBox(height: 4),
          Text(
            'A project may use several technologies. Pie shares describe uses, not the percentage of projects. Missing evidence is outside the pie.',
            style: _muted,
          ),
        ],
      ),
    );
    final filtered = widget.projects
        .where(
          (p) =>
              widget.technology == null ||
              _technologies(p).contains(widget.technology),
        )
        .toList();
    final groups = <String, int>{};
    for (final project in filtered) {
      final value =
          '${project[widget.ranking] ?? (widget.ranking == 'domain' ? 'Unresolved domain' : 'Unclassified')}';
      groups.update(value, (n) => n + 1, ifAbsent: () => 1);
    }
    final ranks = groups.entries.toList()
      ..sort(
        (a, b) => b.value == a.value
            ? a.key.compareTo(b.key)
            : b.value.compareTo(a.value),
      );
    final right = _panel(
      'Project rankings',
      'Explore application domains and computing focus within this selection',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShadTabs<String>(
            key: const ValueKey('project-ranking-tabs'),
            value: widget.ranking,
            gap: 0,
            scrollable: false,
            onChanged: widget.onRanking,
            tabs: const [
              ShadTab(
                value: 'domain',
                child: Flexible(child: Text('Domain')),
              ),
              ShadTab(
                value: 'category',
                child: Flexible(
                  child: Text(
                    'Project focus',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${widget.technology ?? 'All technologies'} · ${filtered.length} unique projects',
                key: const ValueKey('project-ranking-selection'),
                style: _muted.copyWith(fontWeight: FontWeight.w600),
              ),
              if (widget.technology != null)
                ShadButton.link(
                  key: const ValueKey('clear-project-technology'),
                  size: ShadButtonSize.sm,
                  onPressed: () => widget.onTechnology(null),
                  child: const Text('All technologies'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            widget.ranking == 'domain'
                ? 'Application domains'
                : 'Primary computing focus',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (ranks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No projects match this technology.', style: _muted),
            ),
          for (final rank in ranks)
            ShadButton.ghost(
              key: ValueKey('${widget.ranking}-${rank.key}'),
              width: double.infinity,
              height: 83,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              mainAxisAlignment: MainAxisAlignment.start,
              onPressed: () => widget.onGroup(widget.ranking, rank.key),
              child: Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rank.key,
                            textAlign: TextAlign.left,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${rank.value} · ${(rank.value / filtered.length * 100).toStringAsFixed(1)}%',
                          style: _muted.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 9,
                      child: LayoutBuilder(
                        builder: (_, constraints) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width:
                                constraints.maxWidth *
                                rank.value /
                                filtered.length,
                            height: 9,
                            decoration: BoxDecoration(
                              color: CurriculumChartPalette.primary(context),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (ranks.isNotEmpty) const CurriculumPercentAxis(),
          const SizedBox(height: 14),
          Text(
            'Select a ranked group to open its projects and source documents. Computing focus is a document-based estimate.',
            style: _muted,
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (_, constraints) => constraints.maxWidth < 850
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: 18), right],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: 20),
                Expanded(child: right),
              ],
            ),
    );
  }
}
