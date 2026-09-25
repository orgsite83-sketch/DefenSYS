import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../../theme/defensys_tokens.dart';

/// Data point representing a criterion on the Competency Benchmark Chart.
class RadarCriterionPoint {
  final String name;
  final double? panelScore;
  final double? adviserScore;
  final double? peerScore;
  final double? combinedScore;
  final double benchmark;
  final String? divergenceStatus;
  final double? divergence;

  const RadarCriterionPoint({
    required this.name,
    this.panelScore,
    this.adviserScore,
    this.peerScore,
    this.combinedScore,
    this.benchmark = 75.0,
    this.divergenceStatus,
    this.divergence,
  });

  factory RadarCriterionPoint.fromMap(Map<String, dynamic> map) {
    final name = map['name']?.toString() ?? 'Criterion';
    final evalBreakdown = map['evaluator_breakdown'] as Map<String, dynamic>?;

    double? parseScore(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    final panelVal = evalBreakdown != null && evalBreakdown['panel'] != null
        ? parseScore(evalBreakdown['panel']['score'])
        : null;
    final adviserVal = evalBreakdown != null && evalBreakdown['adviser'] != null
        ? parseScore(evalBreakdown['adviser']['score'])
        : null;
    final peerVal = evalBreakdown != null && evalBreakdown['peer'] != null
        ? parseScore(evalBreakdown['peer']['score'])
        : null;
    final combinedVal = parseScore(map['average_score'] ?? map['score']);

    final divVal = parseScore(map['divergence']);
    final divStatus = map['divergence_status']?.toString();

    return RadarCriterionPoint(
      name: name,
      panelScore: panelVal,
      adviserScore: adviserVal,
      peerScore: peerVal,
      combinedScore: combinedVal,
      benchmark: parseScore(map['benchmark']) ?? 75.0,
      divergenceStatus: divStatus,
      divergence: divVal,
    );
  }
}

class _StageClusterData {
  final String stageName;
  final double? panelScore;
  final double? adviserScore;
  final double? peerScore;
  final double? avgScore;

  _StageClusterData({
    required this.stageName,
    this.panelScore,
    this.adviserScore,
    this.peerScore,
    this.avgScore,
  });
}

class _SingleCriterionData {
  final String criterionName;
  final double score;
  final String roleName;
  final Color roleColor;

  _SingleCriterionData({
    required this.criterionName,
    required this.score,
    required this.roleName,
    required this.roleColor,
  });
}

/// View modes: Clustered Columns vs. Ranked Horizontal Bars
enum CurriculumViewMode {
  clusteredColumns,
  rankedBars,
}

/// Interactive Multi-Role Clustered Column Chart with Embedded Stage Dropdown
/// and Two-Level Intelligence:
/// - Overall Mode: Macro Stage Comparison (Panelist vs Adviser vs Peer per stage)
/// - Single Stage Mode: Micro All Criteria Presentation (Color-coded by role)
class CurriculumRadarChart extends StatefulWidget {
  final List<RadarCriterionPoint> criteria;
  final String stageTitle;
  final String selectedStageId;
  final List<Map<String, dynamic>> availableStages;
  final ValueChanged<String> onStageChanged;
  final List<Map<String, dynamic>> stageOverview;
  final bool isLoading;

  const CurriculumRadarChart({
    super.key,
    required this.criteria,
    required this.stageTitle,
    required this.selectedStageId,
    required this.availableStages,
    required this.onStageChanged,
    required this.stageOverview,
    this.isLoading = false,
  });

  @override
  State<CurriculumRadarChart> createState() => _CurriculumRadarChartState();
}

class _CurriculumRadarChartState extends State<CurriculumRadarChart> {
  CurriculumViewMode _viewMode = CurriculumViewMode.clusteredColumns;

  // Multi-select role toggles (no Combined!)
  bool _showPanel = true;
  bool _showAdviser = true;
  bool _showPeer = true;
  bool _showBenchmark = true;

  late TooltipBehavior _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _tooltipBehavior = TooltipBehavior(
      enable: true,
      canShowMarker: false,
      header: '',
      format: 'series.name: point.y%',
    );
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  bool get _isOverall => widget.selectedStageId == 'all';
  bool get _allSelected => _showPanel && _showAdviser && _showPeer;

  void _toggleAllRoles() {
    setState(() {
      if (_allSelected) {
        // Keep active
      } else {
        _showPanel = true;
        _showAdviser = true;
        _showPeer = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return Container(
        height: 420,
        alignment: Alignment.center,
        child: CircularProgressIndicator(color: DefensysTokens.maroonOf(context)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: _isDark ? const Color(0x20000000) : const Color(0x04000000),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Header: Title & Icon on Left, View Mode + Stage Dropdown on Right
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroonOf(context).withValues(alpha: _isDark ? 0.20 : 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.bar_chart_rounded,
                      color: DefensysTokens.maroonOf(context),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isOverall
                            ? 'Cohort Stages Benchmark'
                            : '${widget.stageTitle}: Competencies',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.textPrimaryOf(context),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _isOverall
                            ? 'Multi-role evaluation consensus across defense stages'
                            : 'All individual rubric criteria benchmarked at 75%',
                        style: TextStyle(
                          fontSize: 11,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Right-Side Controls: Mode Switcher & Stage Dropdown
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mode Switcher (Columns vs Ranked)
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DefensysTokens.borderOf(context)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _modeButton(
                          mode: CurriculumViewMode.clusteredColumns,
                          label: 'Columns',
                          icon: Icons.bar_chart_rounded,
                        ),
                        _modeButton(
                          mode: CurriculumViewMode.rankedBars,
                          label: 'Ranked',
                          icon: Icons.view_agenda_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Stage Dropdown
                  _buildStageDropdown(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2. Sub-Header: Multi-Select Role Toggles & 75% Benchmark
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildAllRolesChip(),
                  _buildRoleToggleChip(
                    label: 'Panelist',
                    icon: Icons.gavel_rounded,
                    color: const Color(0xFF0284C7),
                    isSelected: _showPanel,
                    onTap: () {
                      setState(() {
                        _showPanel = !_showPanel;
                        if (!_showPanel && !_showAdviser && !_showPeer) {
                          _showPanel = true;
                        }
                      });
                    },
                  ),
                  _buildRoleToggleChip(
                    label: 'Adviser',
                    icon: Icons.school_outlined,
                    color: const Color(0xFF059669),
                    isSelected: _showAdviser,
                    onTap: () {
                      setState(() {
                        _showAdviser = !_showAdviser;
                        if (!_showPanel && !_showAdviser && !_showPeer) {
                          _showAdviser = true;
                        }
                      });
                    },
                  ),
                  _buildRoleToggleChip(
                    label: 'Peer',
                    icon: Icons.group_outlined,
                    color: const Color(0xFF7C3AED),
                    isSelected: _showPeer,
                    onTap: () {
                      setState(() {
                        _showPeer = !_showPeer;
                        if (!_showPanel && !_showAdviser && !_showPeer) {
                          _showPeer = true;
                        }
                      });
                    },
                  ),
                ],
              ),
              _buildBenchmarkChip(),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Main Chart Canvas
          if (_viewMode == CurriculumViewMode.clusteredColumns)
            _isOverall ? _buildOverallStageChart() : _buildSingleStageCriteriaChart()
          else
            _buildRankedBarsView(),
        ],
      ),
    );
  }

  Widget _buildStageDropdown() {
    final stages = widget.availableStages;

    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: 'all',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 14, color: DefensysTokens.maroonOf(context)),
            const SizedBox(width: 6),
            const Text('Overall (All Stages)'),
          ],
        ),
      ),
    ];
    final seenValues = <String>{'all'};

    for (final stg in stages) {
      final stageId = stg['id']?.toString() ??
          (stg['stage_id']?.toString() ?? '');
      final stageName = stg['stage_name']?.toString() ??
          (stg['label']?.toString() ?? 'Stage');
      final code = stg['code']?.toString() ?? '';

      final val = stageId.isNotEmpty ? stageId : stageName;
      if (seenValues.contains(val)) continue;
      seenValues.add(val);

      IconData icon = Icons.assignment_outlined;
      Color iconColor = const Color(0xFF0284C7);
      if (stageName.toLowerCase().contains('concept') ||
          code.toUpperCase() == 'CP') {
        icon = Icons.lightbulb_outline_rounded;
        iconColor = const Color(0xFFD97706);
      } else if (stageName.toLowerCase().contains('colloquium') ||
          code.toUpperCase() == 'COL') {
        icon = Icons.terminal_rounded;
        iconColor = const Color(0xFF0284C7);
      } else if (stageName.toLowerCase().contains('final') ||
          stageName.toLowerCase().contains('presentation') ||
          code.toUpperCase() == 'PP') {
        icon = Icons.school_outlined;
        iconColor = const Color(0xFF059669);
      }

      items.add(
        DropdownMenuItem(
          value: val,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(stageName),
            ],
          ),
        ),
      );
    }

    // Safely match value to available items
    String dropdownValue = 'all';
    if (seenValues.contains(widget.selectedStageId)) {
      dropdownValue = widget.selectedStageId;
    } else {
      for (final stg in stages) {
        final stageId = stg['id']?.toString() ?? (stg['stage_id']?.toString() ?? '');
        final stageName = stg['stage_name']?.toString() ?? (stg['label']?.toString() ?? '');
        if (stageName.toLowerCase() == widget.selectedStageId.toLowerCase() ||
            stageId == widget.selectedStageId) {
          final val = stageId.isNotEmpty ? stageId : stageName;
          if (seenValues.contains(val)) {
            dropdownValue = val;
            break;
          }
        }
      }
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: _isDark ? const Color(0x20000000) : const Color(0x04000000),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: dropdownValue,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: DefensysTokens.textSecondaryOf(context),
          ),
          dropdownColor: DefensysTokens.panelOf(context),
          style: TextStyle(
            color: DefensysTokens.textPrimaryOf(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          items: items,
          onChanged: (val) {
            if (val != null) {
              widget.onStageChanged(val);
            }
          },
        ),
      ),
    );
  }

  Widget _modeButton({
    required CurriculumViewMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () => setState(() => _viewMode = mode),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? DefensysTokens.panelOf(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: DefensysTokens.borderOf(context)) : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isDark ? 0.20 : 0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.textSecondaryOf(context),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllRolesChip() {
    return InkWell(
      onTap: _toggleAllRoles,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: _allSelected
              ? DefensysTokens.maroonOf(context).withValues(alpha: _isDark ? 0.22 : 0.10)
              : DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _allSelected
                ? DefensysTokens.maroonOf(context).withValues(alpha: 0.4)
                : DefensysTokens.borderOf(context),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.layers_outlined,
              size: 13,
              color: _allSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.textSecondaryOf(context),
            ),
            const SizedBox(width: 5),
            Text(
              'All Roles',
              style: TextStyle(
                fontSize: 11,
                fontWeight: _allSelected ? FontWeight.w700 : FontWeight.w500,
                color: _allSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleToggleChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: _isDark ? 0.20 : 0.10)
              : DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.4) : DefensysTokens.borderOf(context),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: isSelected ? color : DefensysTokens.textSecondaryOf(context),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenchmarkChip() {
    return InkWell(
      onTap: () => setState(() => _showBenchmark = !_showBenchmark),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _showBenchmark
              ? const Color(0xFFDC2626).withValues(alpha: _isDark ? 0.20 : 0.08)
              : DefensysTokens.surfaceHigherOf(context),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _showBenchmark
                ? const Color(0xFFDC2626).withValues(alpha: 0.45)
                : DefensysTokens.borderOf(context),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 2,
              color: _showBenchmark ? const Color(0xFFDC2626) : DefensysTokens.textSecondaryOf(context),
            ),
            const SizedBox(width: 5),
            Text(
              '75% Benchmark',
              style: TextStyle(
                fontSize: 11,
                fontWeight: _showBenchmark ? FontWeight.w700 : FontWeight.w500,
                color: _showBenchmark ? const Color(0xFFDC2626) : DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LEVEL 1: OVERALL VIEW - Clustered by Defense Stages
  // ---------------------------------------------------------------------------

  Widget _buildOverallStageChart() {
    final stages = widget.stageOverview;

    double? parseScore(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    final clusterData = stages.map((stg) {
      final name = stg['stage_name']?.toString() ??
          (stg['label']?.toString() ?? 'Stage');
      final evalBreakdown = stg['evaluator_breakdown'] as Map<String, dynamic>?;

      final panelVal = evalBreakdown != null && evalBreakdown['panel'] != null
          ? parseScore(evalBreakdown['panel']['score'])
          : null;
      final adviserVal = evalBreakdown != null && evalBreakdown['adviser'] != null
          ? parseScore(evalBreakdown['adviser']['score'])
          : null;
      final peerVal = evalBreakdown != null && evalBreakdown['peer'] != null
          ? parseScore(evalBreakdown['peer']['score'])
          : null;
      final avgVal = parseScore(stg['average_score']);

      return _StageClusterData(
        stageName: name,
        panelScore: panelVal,
        adviserScore: adviserVal,
        peerScore: peerVal,
        avgScore: avgVal,
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double minContentWidth =
            math.max(constraints.maxWidth, clusterData.length * 120.0);

        return Container(
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          padding: const EdgeInsets.only(top: 10, right: 12, bottom: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minContentWidth,
              height: 380,
              child: SfCartesianChart(
                tooltipBehavior: _tooltipBehavior,
                margin: const EdgeInsets.fromLTRB(10, 10, 16, 10),
                primaryXAxis: CategoryAxis(
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                  majorGridLines: const MajorGridLines(width: 0),
                  axisLine: AxisLine(color: DefensysTokens.borderOf(context), width: 1.0),
                ),
                primaryYAxis: NumericAxis(
                  minimum: 0,
                  maximum: 100,
                  interval: 25,
                  labelFormat: '{value}%',
                  labelStyle: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                  majorGridLines: MajorGridLines(
                    color: DefensysTokens.borderOf(context).withValues(alpha: _isDark ? 0.3 : 0.6),
                    width: 1.0,
                  ),
                  plotBands: <PlotBand>[
                    if (_showBenchmark)
                      PlotBand(
                        start: 75,
                        end: 75,
                        borderColor: const Color(0xFFDC2626),
                        borderWidth: 1.8,
                        dashArray: const <double>[4, 4],
                        text: '75.0% Passing Target',
                        textStyle: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                        verticalTextAlignment: TextAnchor.start,
                        horizontalTextAlignment: TextAnchor.end,
                      ),
                  ],
                ),
                series: <CartesianSeries<_StageClusterData, String>>[
                  if (_showPanel)
                    ColumnSeries<_StageClusterData, String>(
                      name: 'Panelist',
                      dataSource: clusterData,
                      xValueMapper: (_StageClusterData d, _) => d.stageName,
                      yValueMapper: (_StageClusterData d, _) => d.panelScore ?? 0,
                      color: const Color(0xFF0284C7),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      spacing: 0.12,
                      width: 0.65,
                    ),
                  if (_showAdviser)
                    ColumnSeries<_StageClusterData, String>(
                      name: 'Adviser',
                      dataSource: clusterData,
                      xValueMapper: (_StageClusterData d, _) => d.stageName,
                      yValueMapper: (_StageClusterData d, _) => d.adviserScore ?? 0,
                      color: const Color(0xFF059669),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      spacing: 0.12,
                      width: 0.65,
                    ),
                  if (_showPeer)
                    ColumnSeries<_StageClusterData, String>(
                      name: 'Peer',
                      dataSource: clusterData,
                      xValueMapper: (_StageClusterData d, _) => d.stageName,
                      yValueMapper: (_StageClusterData d, _) => d.peerScore ?? 0,
                      color: const Color(0xFF7C3AED),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      spacing: 0.12,
                      width: 0.65,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // LEVEL 2: SINGLE STAGE VIEW - All Criteria Presented
  // ---------------------------------------------------------------------------

  Widget _buildSingleStageCriteriaChart() {
    final validCriteria = widget.criteria.where((c) => c.name.trim().isNotEmpty).toList();

    // Map each criterion to its responsible role and filter by active role toggles
    final List<_SingleCriterionData> criteriaData = [];

    for (final c in validCriteria) {
      final cleanedName = c.name.replaceAll('Visuals & Aida', 'Presentation & Visual Aids');

      if (c.panelScore != null && c.panelScore! > 0) {
        if (_showPanel) {
          criteriaData.add(_SingleCriterionData(
            criterionName: cleanedName,
            score: c.panelScore!,
            roleName: 'Panelist',
            roleColor: const Color(0xFF0284C7),
          ));
        }
      } else if (c.adviserScore != null && c.adviserScore! > 0) {
        if (_showAdviser) {
          criteriaData.add(_SingleCriterionData(
            criterionName: cleanedName,
            score: c.adviserScore!,
            roleName: 'Adviser',
            roleColor: const Color(0xFF059669),
          ));
        }
      } else if (c.peerScore != null && c.peerScore! > 0) {
        if (_showPeer) {
          criteriaData.add(_SingleCriterionData(
            criterionName: cleanedName,
            score: c.peerScore!,
            roleName: 'Peer',
            roleColor: const Color(0xFF7C3AED),
          ));
        }
      } else if (c.combinedScore != null && c.combinedScore! > 0) {
        criteriaData.add(_SingleCriterionData(
          criterionName: cleanedName,
          score: c.combinedScore!,
          roleName: 'Evaluated',
          roleColor: DefensysTokens.maroonOf(context),
        ));
      }
    }

    if (criteriaData.isEmpty) {
      return Container(
        height: 380,
        alignment: Alignment.center,
        child: Text(
          'No criteria match the active evaluator role filters.',
          style: TextStyle(fontSize: 13, color: DefensysTokens.textSecondaryOf(context)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double minContentWidth =
            math.max(constraints.maxWidth, criteriaData.length * 75.0);

        return Container(
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          padding: const EdgeInsets.only(top: 10, right: 12, bottom: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minContentWidth,
              height: 380,
              child: SfCartesianChart(
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  canShowMarker: false,
                  header: '',
                  format: 'point.x\npoint.y%',
                ),
                margin: const EdgeInsets.fromLTRB(10, 10, 16, 10),
                primaryXAxis: CategoryAxis(
                  labelRotation: -25,
                  labelIntersectAction: AxisLabelIntersectAction.none,
                  labelStyle: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                  majorGridLines: const MajorGridLines(width: 0),
                  axisLine: AxisLine(color: DefensysTokens.borderOf(context), width: 1.0),
                ),
                primaryYAxis: NumericAxis(
                  minimum: 0,
                  maximum: 100,
                  interval: 25,
                  labelFormat: '{value}%',
                  labelStyle: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                  majorGridLines: MajorGridLines(
                    color: DefensysTokens.borderOf(context).withValues(alpha: _isDark ? 0.3 : 0.6),
                    width: 1.0,
                  ),
                  plotBands: <PlotBand>[
                    if (_showBenchmark)
                      PlotBand(
                        start: 75,
                        end: 75,
                        borderColor: const Color(0xFFDC2626),
                        borderWidth: 1.8,
                        dashArray: const <double>[4, 4],
                        text: '75.0% Target',
                        textStyle: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        verticalTextAlignment: TextAnchor.start,
                        horizontalTextAlignment: TextAnchor.end,
                      ),
                  ],
                ),
                series: <CartesianSeries<_SingleCriterionData, String>>[
                  ColumnSeries<_SingleCriterionData, String>(
                    name: 'Criterion Score',
                    dataSource: criteriaData,
                    xValueMapper: (_SingleCriterionData d, _) => d.criterionName,
                    yValueMapper: (_SingleCriterionData d, _) => d.score,
                    pointColorMapper: (_SingleCriterionData d, _) => d.roleColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                    width: 0.55,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // RANKED BREAKDOWN VIEW
  // ---------------------------------------------------------------------------

  Widget _buildRankedBarsView() {
    final validCriteria = widget.criteria.where((c) => c.name.trim().isNotEmpty).toList();

    // Filter by active roles
    final filtered = validCriteria.where((c) {
      if (!_showPanel && c.panelScore != null && c.panelScore! > 0) return false;
      if (!_showAdviser && c.adviserScore != null && c.adviserScore! > 0) return false;
      if (!_showPeer && c.peerScore != null && c.peerScore! > 0) return false;
      return true;
    }).toList();

    final sorted = List<RadarCriterionPoint>.from(filtered)
      ..sort((a, b) {
        final scoreA = a.combinedScore ?? 0;
        final scoreB = b.combinedScore ?? 0;
        return scoreA.compareTo(scoreB);
      });

    return Container(
      constraints: const BoxConstraints(maxHeight: 380),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        itemCount: sorted.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: DefensysTokens.borderOf(context).withValues(alpha: 0.5)),
        itemBuilder: (context, index) {
          final item = sorted[index];
          final score = item.combinedScore ?? 0;
          final isPassing = score >= item.benchmark;
          final delta = score - item.benchmark;
          final deltaText = delta >= 0
              ? '+${delta.toStringAsFixed(1)}%'
              : '${delta.toStringAsFixed(1)}%';

          final cleanedName =
              item.name.replaceAll('Visuals & Aida', 'Presentation & Visual Aids');

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cleanedName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isPassing
                            ? (_isDark ? const Color(0x20059669) : const Color(0xFFECFDF5))
                            : (_isDark ? const Color(0x20DC2626) : const Color(0xFFFEF2F2)),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: (isPassing ? const Color(0xFF059669) : const Color(0xFFDC2626)).withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        deltaText,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isPassing
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${score.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isPassing
                            ? DefensysTokens.textPrimaryOf(context)
                            : const Color(0xFFDC2626),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Horizontal Bar with 75% target line
                Stack(
                  children: [
                    Container(
                      height: 8,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: DefensysTokens.surfaceHigherOf(context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: (score / 100.0).clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: isPassing
                              ? const Color(0xFF059669)
                              : const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: const Alignment(-0.5, 0),
                        child: Container(
                          width: 2,
                          height: 8,
                          color: const Color(0xFFDC2626).withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),

                // Evaluator Sub-Stats
                Row(
                  children: [
                    if (item.panelScore != null)
                      _miniEvalScore('Panelist', item.panelScore!, const Color(0xFF0284C7)),
                    if (item.adviserScore != null) ...[
                      const SizedBox(width: 10),
                      _miniEvalScore('Adviser', item.adviserScore!, const Color(0xFF059669)),
                    ],
                    if (item.peerScore != null) ...[
                      const SizedBox(width: 10),
                      _miniEvalScore('Peer', item.peerScore!, const Color(0xFF7C3AED)),
                    ],
                    const Spacer(),
                    Text(
                      isPassing ? 'Target Met' : 'Remediation Alert',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isPassing
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _miniEvalScore(String role, double val, Color dotColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$role: ${val.toStringAsFixed(0)}%',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
