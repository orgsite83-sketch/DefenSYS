import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/grade_center_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import 'grade_center_shared.dart';
import '../widgets/defensys_admin_shell.dart';

class GradeCenterEventTeamsScreen extends ConsumerStatefulWidget {
  const GradeCenterEventTeamsScreen({
    super.key,
    required this.groupKey,
    required this.scope,
    required this.stageLabel,
    required this.title,
    required this.onBack,
    required this.onOpenTeamDetail,
  });

  final String groupKey;
  final String scope;
  final String stageLabel;
  final String title;
  final VoidCallback onBack;
  final void Function(int gradeId, bool isLocked) onOpenTeamDetail;

  @override
  ConsumerState<GradeCenterEventTeamsScreen> createState() =>
      _GradeCenterEventTeamsScreenState();
}

class _GradeCenterEventTeamsScreenState
    extends ConsumerState<GradeCenterEventTeamsScreen> {
  int _activeViewIndex = 0; // 0: Official University Master Grade Sheet (Initial Default), 1: Team Operations & Readiness

  // Pagination for Master Spreadsheet
  int _masterCurrentPage = 0;
  int _masterRowsPerPage = 10;

  // Pagination for Team Operations
  int _teamCurrentPage = 0;
  int _teamRowsPerPage = 10;

  static const List<int> _rowsPerPageOptions = [10, 25, 50, 100];
  final ScrollController _masterHorizontalScrollController = ScrollController();
  final ScrollController _teamHorizontalScrollController = ScrollController();

  @override
  void dispose() {
    _masterHorizontalScrollController.dispose();
    _teamHorizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gradeCenterProvider);
    ref.listen<GradeCenterState>(gradeCenterProvider, (previous, next) {
      if (next.incompleteTeams.isEmpty) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }
        showIncompleteGradingTeamsDialog(
          context,
          teams: next.incompleteTeams,
        );
        ref.read(gradeCenterProvider.notifier).clearIncompleteTeams();
      });
    });

    final settings = groupSettingsForKey(state, widget.groupKey);
    final isComplete = settings['is_officially_complete'] == true;
    final peerOpen = settings['peer_grading_enabled'] == true;
    final grades = gradesForGroup(state, widget.scope, widget.stageLabel);
    final isPit = widget.scope == 'pit';
    final showAdviser = !isPit;
    final closeBlocked = groupOfficialCloseBlocked(grades: grades);

    // Weights (fallback to standard capstone 50/30/20 or pit 80/20)
    final firstGrade = grades.isNotEmpty ? grades.first : null;
    final weightsMap = firstGrade != null && firstGrade['weights'] is Map
        ? (firstGrade['weights'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final double panelWeight = asDouble(weightsMap['panel']) ?? (isPit ? 80.0 : 50.0);
    final double adviserWeight = asDouble(weightsMap['adviser']) ?? (isPit ? 0.0 : 30.0);
    final double peerWeight = asDouble(weightsMap['peer']) ?? 20.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Navigation Page Header
          DefensysPageHeader(
            icon: Icons.star_rounded,
            title: widget.title,
            subtitle:
                '${grades.length} team${grades.length == 1 ? '' : 's'} · tap any row or student to view evaluation breakdown',
            actions: OutlinedButton.icon(
              onPressed: widget.onBack,
              icon: Icon(
                Icons.arrow_back_rounded,
                size: 16,
                color: DefensysUi.primaryMaroon,
              ),
              label: Text(
                'Back to Evaluation & Grades',
                style: TextStyle(
                  fontFamily: DefensysUi.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: DefensysUi.primaryMaroon,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: DefensysUi.primaryMaroon,
                side: BorderSide(
                  color: isDark ? DefensysTokens.mistBorder : const Color(0xFFD1D5DB),
                ),
                backgroundColor: isDark ? DefensysTokens.mistInputFill : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Stage Level Administrative Controls Banner
          Material(
            color: isDark ? DefensysTokens.mistSurface : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    color: gradeScopeAccentColor(widget.scope),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: gradeGroupStageControlsSection(
                        state: state,
                        scope: widget.scope,
                        isOfficiallyComplete: isComplete,
                        peerGradingEnabled: peerOpen,
                        showCapstonePeerTermBadge: false,
                        groupSettings: settings,
                        grades: grades,
                        officialCompleteToggleEnabled: !closeBlocked,
                        onOfficiallyCompleteChanged: (value) {
                          ref
                              .read(gradeCenterProvider.notifier)
                              .updateGroupSettings(
                                scope: widget.scope,
                                stageLabel: widget.stageLabel,
                                isOfficiallyComplete: value,
                                peerGradingEnabled: value ? false : null,
                              );
                        },
                        onPeerGradingChanged: (value) {
                          ref
                              .read(gradeCenterProvider.notifier)
                              .updateGroupSettings(
                                scope: widget.scope,
                                stageLabel: widget.stageLabel,
                                peerGradingEnabled: value,
                              );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (state.error != null) ...[
            const SizedBox(height: 14),
            Text(state.error!, style: const TextStyle(color: Color(0xFFDC2626))),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            Text(
              state.message!,
              style: const TextStyle(color: Color(0xFF10B981)),
            ),
          ],

          const SizedBox(height: 20),

          // Dual-Mode Segmented View Tabs
          _buildViewModeTabs(grades.length, isDark),

          const SizedBox(height: 16),

          // Content according to selected tab
          if (state.isLoading && grades.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(
                  color: DefensysUi.primaryMaroon,
                ),
              ),
            )
          else if (grades.isEmpty)
            const DefensysCard(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No teams found for this event.',
                  style: TextStyle(color: Color(0xFF98A2B3)),
                ),
              ),
            )
          else if (_activeViewIndex == 0)
            _buildStageMasterSpreadsheetView(
              grades: grades,
              isPit: isPit,
              panelWeight: panelWeight,
              adviserWeight: adviserWeight,
              peerWeight: peerWeight,
              isLocked: isComplete,
              isDark: isDark,
            )
          else
            _buildTeamOperationsView(
              grades: grades,
              showAdviser: showAdviser,
              isLocked: isComplete,
              isDark: isDark,
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW MODE SEGMENTED TABS
  // ==========================================
  Widget _buildViewModeTabs(int teamCount, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewModeTabItem(
            index: 0,
            icon: Icons.table_chart_rounded,
            label: 'Official University Master Grade Sheet',
            badge: 'Stage Matrix',
            isDark: isDark,
          ),
          const SizedBox(width: 4),
          _viewModeTabItem(
            index: 1,
            icon: Icons.dashboard_outlined,
            label: 'Team Operations & Readiness',
            badge: '$teamCount Teams',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _viewModeTabItem({
    required int index,
    required IconData icon,
    required String label,
    required String badge,
    required bool isDark,
  }) {
    final isSelected = _activeViewIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _activeViewIndex = index),
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? DefensysTokens.mistSurface : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isSelected
                ? (isDark
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x0C000000),
                          blurRadius: 4,
                          offset: Offset(0, 1.5),
                        ),
                      ])
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
                    : (isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? (isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A))
                      : (isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF))
                      : (isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? (isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB))
                        : (isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF64748B)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 0: TEAM OPERATIONS & READINESS OVERVIEW
  // ==========================================
  Widget _buildTeamOperationsView({
    required List<Map<String, dynamic>> grades,
    required bool showAdviser,
    required bool isLocked,
    required bool isDark,
  }) {
    final totalCount = grades.length;
    final totalPages = (totalCount / _teamRowsPerPage).ceil().clamp(1, double.infinity).toInt();
    final safePage = _teamCurrentPage.clamp(0, totalPages - 1);
    final startIndex = safePage * _teamRowsPerPage;
    final endIndex = (startIndex + _teamRowsPerPage).clamp(0, totalCount);
    final displayedGrades = totalCount > 0 ? grades.sublist(startIndex, endIndex) : <Map<String, dynamic>>[];

    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final minTableWidth = showAdviser ? 980.0 : 840.0;
              final tableWidth = constraints.maxWidth < minTableWidth ? minTableWidth : constraints.maxWidth;

              return Scrollbar(
                controller: _teamHorizontalScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  controller: _teamHorizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _teamsTableHeader(showAdviser: showAdviser, isDark: isDark),
                        ...displayedGrades.map(
                          (grade) => _teamRow(
                            grade,
                            showAdviser: showAdviser,
                            isLocked: isLocked,
                            isDark: isDark,
                            onTap: () {
                              final gradeId = asInt(grade['id']);
                              if (gradeId != null) {
                                widget.onOpenTeamDetail(gradeId, isLocked);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          _buildPaginationFooter(
            totalCount: totalCount,
            rowsPerPage: _teamRowsPerPage,
            currentPage: safePage,
            totalPages: totalPages,
            startIndex: startIndex,
            endIndex: endIndex,
            entityLabel: 'teams',
            isDark: isDark,
            onRowsPerPageChanged: (newRpp) => setState(() {
              _teamRowsPerPage = newRpp;
              _teamCurrentPage = 0;
            }),
            onPageChanged: (newPage) => setState(() {
              _teamCurrentPage = newPage;
            }),
          ),
        ],
      ),
    );
  }

  Widget _teamsTableHeader({required bool showAdviser, required bool isDark}) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF0F1F4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Team & Approved Concept',
              style: TextStyle(
                color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (showAdviser)
            Expanded(
              flex: 2,
              child: Text(
                'Adviser',
                style: TextStyle(
                  color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF5D6678),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          Expanded(
            child: Text(
              'Panel',
              style: TextStyle(
                color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (showAdviser)
            Expanded(
              child: Text(
                'Adviser Status',
                style: TextStyle(
                  color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF5D6678),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: Text(
              'Peer Evaluation',
              style: TextStyle(
                color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Final Grade',
              style: TextStyle(
                color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Status',
              style: TextStyle(
                color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF5D6678),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _teamRow(
    Map<String, dynamic> grade, {
    required bool showAdviser,
    required bool isLocked,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final adviserName = grade['adviser_name']?.toString().trim() ?? '';

    return Material(
      color: isDark ? DefensysTokens.mistSurface : Colors.white,
      child: InkWell(
        hoverColor: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF9FAFB),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(flex: 3, child: teamDetailsWidget(grade)),
              if (showAdviser)
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF064E3B)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.school_rounded,
                          size: 14,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          adviserName.isNotEmpty ? adviserName : 'Unassigned',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: adviserName.isNotEmpty
                                ? (isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF1E293B))
                                : (isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8)),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: panelGradingStatusWidget(grade)),
              if (showAdviser)
                Expanded(child: adviserGradingStatusWidget(grade)),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    scoreTextWidget(grade['peer_score']),
                    const SizedBox(width: 8),
                    Expanded(child: peerEvalFormsStatusWidget(grade)),
                  ],
                ),
              ),
              Expanded(child: finalGradeTextWidget(grade)),
              Expanded(
                flex: 2,
                child: gradeStatusChipWidget(grade),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF98A2B3),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: OFFICIAL UNIVERSITY STAGE MASTER GRADE SHEET
  // (No. · Team · Approved Concept · Adviser · Names · SCORES (Panelists) · Average · GRADE 50% · Advisers Rating 30% · Peer Rating 20% · TOTAL · FINAL GRADE)
  // ==========================================
  Widget _buildStageMasterSpreadsheetView({
    required List<Map<String, dynamic>> grades,
    required bool isPit,
    required double panelWeight,
    required double adviserWeight,
    required double peerWeight,
    required bool isLocked,
    required bool isDark,
  }) {
    // 1. Extract distinct panelists across all teams in this stage
    final stagePanelists = _extractStagePanelists(grades);

    // 2. Flatten all teams and students into table rows
    final allStudentRows = <_StageStudentRowData>[];
    for (final grade in grades) {
      final teamName = grade['team_name']?.toString() ?? 'Team';
      final projectTitle = grade['project_title']?.toString() ?? 'Approved Concept';
      final adviserName = grade['adviser_name']?.toString() ?? '—';
      final gradeId = asInt(grade['id']) ?? 0;

      final breakdowns = grade['breakdowns'] is List
          ? (grade['breakdowns'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      final peerPerStudent = grade['peer_per_student'] is List
          ? (grade['peer_per_student'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      final membersList = grade['members'] is List
          ? (grade['members'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      if (membersList.isNotEmpty) {
        for (final m in membersList) {
          final sName = m['name']?.toString() ?? 'Student';
          final sId = asInt(m['student_id'] ?? m['id']);
          final isLeader = m['is_leader'] == true;

          // Matching peer/final score
          final match = peerPerStudent.firstWhere(
            (p) => asInt(p['student_id']) == sId,
            orElse: () => <String, dynamic>{},
          );

          final panelScore = asDouble(match['panel_score']) ?? asDouble(grade['panel_score']);
          final adviserScore = asDouble(match['adviser_score']) ?? asDouble(grade['adviser_score']);
          final peerScore = asDouble(match['peer_score']) ?? asDouble(grade['peer_score']);
          final finalGrade = asDouble(match['final_grade']) ?? asDouble(grade['final_grade']);

          final panelContrib = panelScore != null ? panelScore * (panelWeight / 100.0) : null;
          final adviserContrib = adviserScore != null ? adviserScore * (adviserWeight / 100.0) : null;
          final peerContrib = peerScore != null ? peerScore * (peerWeight / 100.0) : null;

          final panScores = <String, double?>{};
          for (final pan in stagePanelists) {
            panScores[pan.key] = _getPanelistScoreForStudent(
              breakdowns: breakdowns,
              panelistKey: pan.key,
              studentId: sId,
            );
          }

          allStudentRows.add(
            _StageStudentRowData(
              teamName: teamName,
              projectTitle: projectTitle,
              adviserName: adviserName,
              gradeId: gradeId,
              studentId: sId,
              studentName: sName,
              isLeader: isLeader,
              panelistScores: panScores,
              panelScore: panelScore,
              panelContrib: panelContrib,
              adviserScore: adviserScore,
              adviserContrib: adviserContrib,
              peerScore: peerScore,
              peerContrib: peerContrib,
              finalGrade: finalGrade,
            ),
          );
        }
      } else {
        // Fallback if members are not explicitly listed
        final panelScore = asDouble(grade['panel_score']);
        final adviserScore = asDouble(grade['adviser_score']);
        final peerScore = asDouble(grade['peer_score']);
        final finalGrade = asDouble(grade['final_grade']);

        allStudentRows.add(
          _StageStudentRowData(
            teamName: teamName,
            projectTitle: projectTitle,
            adviserName: adviserName,
            gradeId: gradeId,
            studentId: null,
            studentName: 'Team Submission',
            isLeader: true,
            panelistScores: const {},
            panelScore: panelScore,
            panelContrib: panelScore != null ? panelScore * (panelWeight / 100.0) : null,
            adviserScore: adviserScore,
            adviserContrib: adviserScore != null ? adviserScore * (adviserWeight / 100.0) : null,
            peerScore: peerScore,
            peerContrib: peerScore != null ? peerScore * (peerWeight / 100.0) : null,
            finalGrade: finalGrade,
          ),
        );
      }
    }

    // 3. Pagination calculations for Master Spreadsheet
    final totalCount = allStudentRows.length;
    final totalPages = (totalCount / _masterRowsPerPage).ceil().clamp(1, double.infinity).toInt();
    final safePage = _masterCurrentPage.clamp(0, totalPages - 1);
    final startIndex = safePage * _masterRowsPerPage;
    final endIndex = (startIndex + _masterRowsPerPage).clamp(0, totalCount);
    final displayedStudents = totalCount > 0 ? allStudentRows.sublist(startIndex, endIndex) : <_StageStudentRowData>[];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
        ),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x05000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.table_chart_rounded,
                    size: 16,
                    color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Official Stage Master Grade Sheet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        isPit
                            ? 'Complete University Grade Matrix · ${allStudentRows.length} Students across ${grades.length} Teams · Panel (${panelWeight.toStringAsFixed(0)}%) + Peer (${peerWeight.toStringAsFixed(0)}%)'
                            : 'Complete University Grade Matrix · ${allStudentRows.length} Students across ${grades.length} Teams · Panel (${panelWeight.toStringAsFixed(0)}%) + Adviser (${adviserWeight.toStringAsFixed(0)}%) + Peer (${peerWeight.toStringAsFixed(0)}%)',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Master Spreadsheet DataTable with Horizontal Scrollbar & Full Expansion
          LayoutBuilder(
            builder: (context, constraints) {
              final totalCols = 8 + stagePanelists.length + (!isPit && adviserWeight > 0 ? 2 : 0);
              final dynamicSpacing = ((constraints.maxWidth - 700) / totalCols).clamp(16.0, 38.0);

              return Scrollbar(
                controller: _masterHorizontalScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  controller: _masterHorizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                    ),
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
                      ),
                      dataRowColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return isDark ? DefensysTokens.mistInputFill : const Color(0xFFF9FAFB);
                        }
                        return Colors.transparent;
                      }),
                      dataRowMinHeight: 56,
                      dataRowMaxHeight: 64,
                      columnSpacing: dynamicSpacing,
                      horizontalMargin: 20,
                      dividerThickness: 1,
                      columns: [
                        // 1. No.
                        DataColumn(
                          label: Text(
                            'No.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF475569),
                            ),
                          ),
                        ),
                        // 2. Team
                        DataColumn(
                          label: Text(
                            'Team',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF475569),
                            ),
                          ),
                        ),
                        // 3. Approved Concept
                        DataColumn(
                          label: Text(
                            'Approved Concept',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF475569),
                            ),
                          ),
                        ),
                        // 4. Adviser
                        if (!isPit)
                          DataColumn(
                            label: Text(
                              'Adviser',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        // 5. Names
                        DataColumn(
                          label: Text(
                            'Names',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF475569),
                            ),
                          ),
                        ),
                        // 6. SCORES -> Panelists
                        ...stagePanelists.asMap().entries.map((entry) {
                          final idx = entry.key + 1;
                          final pan = entry.value;
                          return DataColumn(
                            label: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Panel $idx',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                                  ),
                                ),
                                Text(
                                  pan.displayName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        // 7. Average
                        DataColumn(
                          label: Text(
                            'Average',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        // 8. GRADE 50% (DefenSYS Blue)
                        DataColumn(
                          label: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF2563EB).withValues(alpha: isDark ? 0.5 : 0.25),
                              ),
                            ),
                            child: Text(
                              'GRADE ${panelWeight.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ),
                        // 9. Advisers Rating & 30% (DefenSYS Emerald)
                        if (!isPit && adviserWeight > 0) ...[
                          DataColumn(
                            label: Text(
                              "Adviser's Rating",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFF059669).withValues(alpha: isDark ? 0.5 : 0.25),
                                ),
                              ),
                              child: Text(
                                '${adviserWeight.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669),
                                ),
                              ),
                            ),
                          ),
                        ],
                        // 10. Peer Rating & 20% (Sky Blue)
                        DataColumn(
                          label: Text(
                            'Peer Rating',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF075985) : const Color(0xFFF0F9FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF0284C7).withValues(alpha: isDark ? 0.5 : 0.25),
                              ),
                            ),
                            child: Text(
                              '${peerWeight.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7),
                              ),
                            ),
                          ),
                        ),
                        // 11. TOTAL
                        DataColumn(
                          label: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? DefensysTokens.mistSurface : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isDark ? DefensysTokens.mistBorder : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Text(
                              'TOTAL',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                        // 12. FINAL GRADE
                        DataColumn(
                          label: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? DefensysTokens.mistInputFill : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(4),
                              border: isDark ? Border.all(color: DefensysTokens.mistBorder) : null,
                            ),
                            child: const Text(
                              'FINAL GRADE',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                      rows: displayedStudents.asMap().entries.map((studentEntry) {
                        final no = startIndex + studentEntry.key + 1;
                        final s = studentEntry.value;
                        final isPassed = s.finalGrade != null && s.finalGrade! >= 75.0;

                        return DataRow(
                          onSelectChanged: (_) {
                            widget.onOpenTeamDetail(s.gradeId, isLocked);
                          },
                          cells: [
                            // 1. No.
                            DataCell(
                              Text(
                                '$no',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                            // 2. Team
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Text(
                                  s.teamName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ),
                            // 3. Approved Concept
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 180),
                                child: Text(
                                  s.projectTitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF334155),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            // 4. Adviser
                            if (!isPit)
                              DataCell(
                                Text(
                                  s.adviserName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF475569),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            // 5. Names
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    s.studentName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  if (s.isLeader) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.5 : 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        'LEADER',
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // 6. Panelist Individual Scores
                            ...stagePanelists.map((pan) {
                              final score = s.panelistScores[pan.key];
                              return DataCell(
                                score != null
                                    ? Text(
                                        '${score.toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF334155),
                                        ),
                                      )
                                    : Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8))),
                              );
                            }),
                            // 7. Panel Average
                            DataCell(
                              s.panelScore != null
                                  ? Text(
                                      '${s.panelScore!.toStringAsFixed(2)}%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                        color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF1E293B),
                                      ),
                                    )
                                  : Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8))),
                            ),
                            // 8. GRADE 50% (DefenSYS Blue Pill)
                            DataCell(
                              s.panelContrib != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFF2563EB).withValues(alpha: isDark ? 0.5 : 0.25),
                                        ),
                                      ),
                                      child: Text(
                                        s.panelContrib!.toStringAsFixed(2),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                                        ),
                                      ),
                                    )
                                  : Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8))),
                            ),
                            // 9. Advisers Rating & 30% (DefenSYS Emerald Pill)
                            if (!isPit && adviserWeight > 0) ...[
                              DataCell(
                                s.adviserScore != null
                                    ? Text(
                                        '${s.adviserScore!.toStringAsFixed(2)}%',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF334155),
                                        ),
                                      )
                                    : Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8))),
                              ),
                              DataCell(
                                s.adviserContrib != null
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: const Color(0xFF059669).withValues(alpha: isDark ? 0.5 : 0.25),
                                          ),
                                        ),
                                        child: Text(
                                          s.adviserContrib!.toStringAsFixed(2),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF059669),
                                          ),
                                        ),
                                      )
                                    : Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8))),
                              ),
                            ],
                            // 10. Peer Rating & 20% (Sky Blue Pill)
                            DataCell(
                              s.peerScore != null
                                  ? Text(
                                      '${s.peerScore!.toStringAsFixed(2)}%',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF334155),
                                      ),
                                    )
                                  : Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8))),
                            ),
                            DataCell(
                              s.peerContrib != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF075985) : const Color(0xFFF0F9FF),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFF0284C7).withValues(alpha: isDark ? 0.5 : 0.25),
                                        ),
                                      ),
                                      child: Text(
                                        s.peerContrib!.toStringAsFixed(2),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7),
                                        ),
                                      ),
                                    )
                                  : Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8))),
                            ),
                            // 11. TOTAL
                            DataCell(
                              s.finalGrade != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Text(
                                        s.finalGrade!.toStringAsFixed(2),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                          color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    )
                                  : Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8))),
                            ),
                            // 12. FINAL GRADE & STATUS
                            DataCell(
                              s.finalGrade != null
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${s.finalGrade!.toStringAsFixed(2)}%',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildStatusBadgeCell(isPassed, s.finalGrade, isDark),
                                      ],
                                    )
                                  : Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8))),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );
            },
          ),

          // Bottom Pagination Footer
          _buildPaginationFooter(
            totalCount: totalCount,
            rowsPerPage: _masterRowsPerPage,
            currentPage: safePage,
            totalPages: totalPages,
            startIndex: startIndex,
            endIndex: endIndex,
            entityLabel: 'students',
            isDark: isDark,
            onRowsPerPageChanged: (newRpp) => setState(() {
              _masterRowsPerPage = newRpp;
              _masterCurrentPage = 0;
            }),
            onPageChanged: (newPage) => setState(() {
              _masterCurrentPage = newPage;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter({
    required int totalCount,
    required int rowsPerPage,
    required int currentPage,
    required int totalPages,
    required int startIndex,
    required int endIndex,
    required String entityLabel,
    required bool isDark,
    required ValueChanged<int> onRowsPerPageChanged,
    required ValueChanged<int> onPageChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
        border: Border(
          top: BorderSide(
            color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          // Left: Rows per page + Showing X - Y of Z
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rows per page:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? DefensysTokens.mistSurface : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? DefensysTokens.mistBorder : const Color(0xFFCBD5E1),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: rowsPerPage,
                    dropdownColor: isDark ? DefensysTokens.mistSurface : Colors.white,
                    isDense: true,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                    ),
                    items: _rowsPerPageOptions.map((n) {
                      return DropdownMenuItem<int>(
                        value: n,
                        child: Text('$n'),
                      );
                    }).toList(),
                    onChanged: (newVal) {
                      if (newVal != null) onRowsPerPageChanged(newVal);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                totalCount == 0
                    ? 'Showing 0 of 0 $entityLabel'
                    : 'Showing ${startIndex + 1} - $endIndex of $totalCount $entityLabel',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Right: Page Navigator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous page',
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                onPressed: currentPage > 0
                    ? () => onPageChanged(currentPage - 1)
                    : null,
                color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                disabledColor: isDark
                    ? DefensysTokens.mistTextSecondary.withValues(alpha: 0.3)
                    : const Color(0xFFCBD5E1),
              ),
              const SizedBox(width: 4),
              Text(
                'Page ${currentPage + 1} of $totalPages',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Next page',
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                onPressed: currentPage < totalPages - 1
                    ? () => onPageChanged(currentPage + 1)
                    : null,
                color: isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF0F172A),
                disabledColor: isDark
                    ? DefensysTokens.mistTextSecondary.withValues(alpha: 0.3)
                    : const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadgeCell(bool isPassed, double? finalGrade, bool isDark) {
    if (finalGrade == null) return Text('—', style: TextStyle(color: isDark ? DefensysTokens.mistTextSecondary : const Color(0xFF94A3B8)));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: isPassed
            ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
            : (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEF2F2)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isPassed
              ? const Color(0xFF059669).withValues(alpha: isDark ? 0.5 : 0.25)
              : const Color(0xFFDC2626).withValues(alpha: isDark ? 0.5 : 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPassed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 12,
            color: isPassed
                ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                : (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626)),
          ),
          const SizedBox(width: 4),
          Text(
            isPassed ? 'PASSED' : 'FAILED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isPassed
                  ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                  : (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
  }

  List<_PanelistColumnDef> _extractStagePanelists(List<Map<String, dynamic>> grades) {
    final result = <_PanelistColumnDef>[];
    final seenKeys = <String>{};

    for (final grade in grades) {
      final panelistList = grade['panelists'] is List ? (grade['panelists'] as List) : [];
      for (final p in panelistList) {
        if (p is Map) {
          final u = p['username']?.toString().trim() ?? '';
          final n = p['name']?.toString().trim() ?? '';
          if (u.isNotEmpty && !seenKeys.contains(u)) {
            seenKeys.add(u);
            result.add(_PanelistColumnDef(key: u, displayName: n.isNotEmpty ? n : u));
          }
        }
      }

      final breakdowns = grade['breakdowns'] is List
          ? (grade['breakdowns'] as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      for (final b in breakdowns) {
        if (b['evaluation_type'] != 'panel') continue;
        final raw = b['remarks']?.toString() ?? '';
        final firstLine = raw.split('\n').first.trim();
        if (firstLine.startsWith('Panelist:')) {
          final key = firstLine.substring('Panelist:'.length).trim();
          if (key.isNotEmpty && !seenKeys.contains(key)) {
            seenKeys.add(key);
            result.add(_PanelistColumnDef(key: key, displayName: 'Panelist $key'));
          }
        } else if (firstLine.startsWith('Guest panelist:')) {
          final key = firstLine.substring('Guest panelist:'.length).trim();
          if (key.isNotEmpty && !seenKeys.contains(key)) {
            seenKeys.add(key);
            result.add(_PanelistColumnDef(key: key, displayName: key));
          }
        }
      }
    }

    return result;
  }

  double? _getPanelistScoreForStudent({
    required List<Map<String, dynamic>> breakdowns,
    required String panelistKey,
    required int? studentId,
  }) {
    final rows = breakdowns.where((b) {
      if (b['evaluation_type'] != 'panel') return false;

      final raw = b['remarks']?.toString() ?? '';
      final firstLine = raw.split('\n').first.trim();
      bool isMatch = false;
      if (firstLine.startsWith('Panelist:')) {
        final key = firstLine.substring('Panelist:'.length).trim();
        isMatch = key == panelistKey;
      } else if (firstLine.startsWith('Guest panelist:')) {
        final key = firstLine.substring('Guest panelist:'.length).trim();
        isMatch = key == panelistKey;
      }

      if (!isMatch) return false;

      final bSid = asInt(b['student_id'] ?? b['student']);
      if (bSid != null && studentId != null) {
        return bSid == studentId;
      }
      return true;
    }).toList();

    if (rows.isEmpty) return null;

    double totalScore = 0;
    double totalMax = 0;
    for (final r in rows) {
      final s = asDouble(r['score']);
      final m = asDouble(r['max_score']) ?? 10.0;
      if (s != null && m > 0) {
        totalScore += s;
        totalMax += m;
      }
    }

    if (totalMax <= 0) return null;
    return (totalScore / totalMax * 100.0).clamp(0.0, 100.0);
  }
}

class _PanelistColumnDef {
  final String key;
  final String displayName;

  const _PanelistColumnDef({required this.key, required this.displayName});
}

class _StageStudentRowData {
  final String teamName;
  final String projectTitle;
  final String adviserName;
  final int gradeId;
  final int? studentId;
  final String studentName;
  final bool isLeader;
  final Map<String, double?> panelistScores;
  final double? panelScore;
  final double? panelContrib;
  final double? adviserScore;
  final double? adviserContrib;
  final double? peerScore;
  final double? peerContrib;
  final double? finalGrade;

  const _StageStudentRowData({
    required this.teamName,
    required this.projectTitle,
    required this.adviserName,
    required this.gradeId,
    this.studentId,
    required this.studentName,
    this.isLeader = false,
    this.panelistScores = const {},
    this.panelScore,
    this.panelContrib,
    this.adviserScore,
    this.adviserContrib,
    this.peerScore,
    this.peerContrib,
    this.finalGrade,
  });
}
