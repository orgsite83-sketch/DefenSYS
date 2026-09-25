import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../services/academic_period_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../widgets/defensys_admin_shell.dart';
import '../grade_center/grade_center_shared.dart'
    show showPeerGradingHelpDialog;

class AcademicPeriodsScreen extends ConsumerStatefulWidget {
  const AcademicPeriodsScreen({super.key});

  @override
  ConsumerState<AcademicPeriodsScreen> createState() =>
      _AcademicPeriodsScreenState();
}

class _AcademicPeriodsScreenState extends ConsumerState<AcademicPeriodsScreen> {
  static const _line = Color(0xFFE5E7EB);
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _green = Color(0xFF10B981);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _borderColor => _isDark ? DefensysTokens.mistBorder : _line;
  Color get _surfaceColor => _isDark ? DefensysTokens.mistSurface : Colors.white;
  Color get _inkColor => _isDark ? const Color(0xFFF4F4F5) : _ink;
  Color get _mutedColor => _isDark ? const Color(0xFFA1A1AA) : _muted;
  Color get _panelBgColor => _isDark ? const Color(0xFF1B1B1F) : const Color(0xFFF9FAFB);
  Color get _headerBgColor => _isDark ? const Color(0xFF18191E) : const Color(0xFFF0F1F4);
  Color get _headerTextColor => _isDark ? const Color(0xFFA1A1AA) : const Color(0xFF5D6678);

  static const _terms = ['1st Semester', '2nd Semester', 'Summer'];
  static const _rowHeight = 45.0;
  static const _emptyBodyMinHeight = 80.0;
  static const _schoolYearsScrollThreshold = 6;
  static const _schoolYearsScrollMaxHeight = 280.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(academicPeriodProvider);
    final selectedYear = _selectedYear(state);

    ref.listen(academicPeriodProvider, (previous, next) {
      final error = next.error;
      if (error != null && error.isNotEmpty && error != previous?.error) {
        showErrorToast(context, error);
      }

      final message = next.message;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.message) {
        showSuccessToast(context, message);
      }
    });

    return _buildContent(state, selectedYear);
  }

  Widget _buildContent(
    AcademicPeriodState state,
    Map<String, dynamic>? selectedYear,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DefensysPageHeader(
            icon: Icons.calendar_month_rounded,
            title: 'Academic Period Management',
            subtitle:
                'Configure school years, capstone intake, and active semesters.',
          ),
          const SizedBox(height: 28),
          _statusBanner(state),
          if (state.activeSemester != null) ...[
            const SizedBox(height: 16),
            _capstoneProgramCard(state),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 12),
            _notice(state.error!, warning: true),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 12),
            _notice(state.message!),
          ],
          const SizedBox(height: 22),
          if (state.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(
                  color: DefensysUi.primaryMaroon,
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1, child: _schoolYearsCard(state)),
                const SizedBox(width: 20),
                Expanded(flex: 1, child: _semestersCard(state, selectedYear)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _statusBanner(AcademicPeriodState state) {
    final active = state.activeSemester;
    final isActive = active != null;
    final isDark = _isDark;

    final base = isActive
        ? (isDark ? const Color(0xFF2E1014) : DefensysUi.primaryMaroon)
        : (isDark ? const Color(0xFF1C1D22) : const Color(0xFF6B7280));
    final borderColor = isDark
        ? (isActive ? const Color(0xFF7F1D1D) : DefensysTokens.mistBorder)
        : Colors.white.withValues(alpha: isActive ? 0.14 : 0.12);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? (isDark ? const Color(0x66000000) : base.withValues(alpha: 0.12))
                : (isDark ? const Color(0x44000000) : base.withValues(alpha: 0.08)),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive
                      ? 'Currently Active: ${active['display_name']}'
                      : 'No Active Semester',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isActive
                      ? _activeBannerSubtitle(active)
                      : 'Add a school year and activate a semester to begin.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? (isDark ? const Color(0xFF064E3B) : const Color(0xFF10B981))
                  : Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: isDark && isActive
                  ? Border.all(color: const Color(0xFF059669))
                  : null,
            ),
            child: Text(
              isActive ? 'LIVE' : 'INACTIVE',
              style: TextStyle(
                color: isDark && isActive ? const Color(0xFF34D399) : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _schoolYearsCard(AcademicPeriodState state) {
    return _card(
      title: 'School Years',
      actionLabel: '+ Add Year',
      onActionTap: state.isSaving ? null : _showAddYearDialog,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tableHeader(
            columns: const [
              _ColumnSpec('Academic Year', 2),
              _ColumnSpec('Semesters Created', 2),
              _ColumnSpec('Action', 1.5),
            ],
          ),
          _schoolYearsBody(state),
        ],
      ),
    );
  }

  Widget _schoolYearsBody(AcademicPeriodState state) {
    if (state.schoolYears.isEmpty) {
      return DefensysEmptyState.table(
        icon: Icons.calendar_today_outlined,
        title: 'No School Years Configured',
        description:
            'Add an academic year to start configuring terms and active semesters.',
        size: DefensysEmptyStateSize.compact,
        primaryAction: DefensysEmptyAction(
          label: 'Add School Year',
          icon: Icons.add_rounded,
          onPressed: state.isSaving ? () {} : _showAddYearDialog,
        ),
      );
    }

    final rows = state.schoolYears
        .map((year) => _schoolYearRow(state, year))
        .toList();

    if (state.schoolYears.length > _schoolYearsScrollThreshold) {
      return ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: _schoolYearsScrollMaxHeight,
        ),
        child: ListView(shrinkWrap: true, children: rows),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _semestersCard(
    AcademicPeriodState state,
    Map<String, dynamic>? selectedYear,
  ) {
    final selectedLabel = selectedYear?['label']?.toString();
    final semesters = _semesterList(selectedYear?['semesters']);

    return _card(
      title: selectedLabel == null
          ? 'Semesters'
          : 'Semesters (A.Y. $selectedLabel)',
      actionLabel: '+ Add Semester',
      onActionTap: selectedYear == null || state.isSaving
          ? null
          : () => _showAddSemesterDialog(selectedYear),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tableHeader(
            columns: const [
              _ColumnSpec('Term', 1.5),
              _ColumnSpec('System Status', 2.0),
              _ColumnSpec('Action', 1.0),
            ],
          ),
          if (selectedYear == null)
            DefensysEmptyState.table(
              icon: Icons.touch_app_outlined,
              title: 'Select a School Year',
              description:
                  'Select an academic year on the left to view and manage its semesters.',
              size: DefensysEmptyStateSize.compact,
            )
          else if (semesters.isEmpty)
            DefensysEmptyState.table(
              icon: Icons.date_range_outlined,
              title: 'No Semesters Created',
              description:
                  'Add a semester to activate terms for A.Y. ${selectedLabel ?? ""}.',
              size: DefensysEmptyStateSize.compact,
              primaryAction: DefensysEmptyAction(
                label: 'Add Semester',
                icon: Icons.add_rounded,
                onPressed: state.isSaving
                    ? () {}
                    : () => _showAddSemesterDialog(selectedYear),
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: semesters
                  .map((semester) => _semesterRow(state, semester))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.15,
                    height: 1.2,
                  ),
                ),
              ),
              if (actionLabel case final label?)
                OutlinedButton.icon(
                  onPressed: onActionTap,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(label.replaceFirst(RegExp(r'^\+\s*'), '')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _inkColor,
                    side: BorderSide(
                      color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFD1D5DB),
                      width: 1,
                    ),
                    backgroundColor: _isDark ? const Color(0xFF28272D) : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 40),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _emptyTableMessage(String message) {
    return DefensysEmptyState.table(
      icon: Icons.inbox_outlined,
      title: message,
      size: DefensysEmptyStateSize.compact,
    );
  }

  Widget _tableHeader({required List<_ColumnSpec> columns}) {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: _headerBgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _isDark
              ? DefensysTokens.mistBorder.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: columns
            .map(
              (column) => Expanded(
                flex: (column.flex * 100).round(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      column.label,
                      style: TextStyle(
                        color: _headerTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _schoolYearRow(AcademicPeriodState state, Map<String, dynamic> year) {
    final yearId = _asInt(year['id']);
    final semesters = _semesterList(year['semesters']);
    final hasActive = semesters.any(
      (semester) => semester['is_active'] == true,
    );
    final selected = yearId != null && yearId == state.selectedSchoolYearId;

    return InkWell(
      onTap: yearId == null
          ? null
          : () => ref
                .read(academicPeriodProvider.notifier)
                .selectSchoolYear(yearId),
      child: Container(
        height: _rowHeight,
        decoration: BoxDecoration(
          color: selected
              ? (_isDark ? const Color(0xFF2C1619) : const Color(0xFFFFF4F4))
              : _surfaceColor,
          border: Border(
            bottom: BorderSide(color: _borderColor),
            left: BorderSide(
              color: selected
                  ? (_isDark ? const Color(0xFFF87171) : _maroon)
                  : Colors.transparent,
              width: selected ? 3 : 0,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 200,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: _inkColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    children: [
                      TextSpan(text: year['label']?.toString() ?? 'Unknown'),
                      if (hasActive)
                        TextSpan(
                          text: ' • Active',
                          style: TextStyle(
                            color: _isDark ? const Color(0xFF34D399) : _green,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 200,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Text(
                  semesters.length.toString(),
                  style: TextStyle(
                    color: _inkColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 150,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.build_outlined,
                      size: 16,
                      color: selected && _isDark
                          ? const Color(0xFFFCA5A5)
                          : _inkColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      selected ? 'Managing' : 'Manage',
                      style: TextStyle(
                        color: selected && _isDark
                            ? const Color(0xFFFCA5A5)
                            : _inkColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _semesterRow(
    AcademicPeriodState state,
    Map<String, dynamic> semester,
  ) {
    final semesterId = _asInt(semester['id']);
    final isActive = semester['is_active'] == true;

    return Container(
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 150,
            child: Text(
              semester['label']?.toString() ?? 'Unknown semester',
              style: TextStyle(
                color: _inkColor,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 200,
            child: isActive
                ? const DefensysStatusBadge.success(
                    label: 'Active (Write-Enabled)',
                    showDot: false,
                  )
                : const DefensysStatusBadge.inactive(label: 'Inactive'),
          ),
          Expanded(
            flex: 100,
            child: DefensysUi.flatSwitch(
              value: isActive,
              scale: 0.88,
              activeTrackColor: _isDark ? const Color(0xFFE11D48) : _maroon,
              onChanged: state.isSaving || semesterId == null
                  ? null
                  : (value) => _handleSemesterSwitch(semester, value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _capstoneProgramCard(AcademicPeriodState state) {
    final active = state.activeSemester!;
    final semesterId = _asInt(active['id']);
    final phaseLabel = _capstonePhaseLabel(
      active['capstone_program_phase']?.toString(),
    );
    final teamCreationOn = active['capstone_team_creation_enabled'] == true;
    final peerOn = active['capstone_peer_evaluation_enabled'] != false;
    final adviserOn = active['capstone_adviser_grading_enabled'] != false;
    final saving = state.isSaving;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.rocket_launch_rounded,
                color: _isDark ? const Color(0xFFF87171) : _maroon,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Capstone program',
                style: TextStyle(
                  color: _inkColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _capstoneSettingRow(
            label: 'Program phase',
            child: Row(
              children: [
                _capstoneChip(phaseLabel, emphasized: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Capstone-specific phase. PIT for 1st–3rd year cohorts is active during both terms.',
                    style: TextStyle(
                      color: _mutedColor,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _capstoneSettingRow(
            label: 'Team creation',
            child: Row(
              children: [
                _capstoneChip(
                  teamCreationOn ? 'Open' : 'Closed',
                  emphasized: teamCreationOn,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    active['capstone_mode_message']?.toString() ??
                        (teamCreationOn
                            ? 'New capstone teams can be created on Student Teams.'
                            : 'Team creation follows the active term calendar.'),
                    style: TextStyle(
                      color: _mutedColor,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: _borderColor),
          ),
          Text(
            'Evaluation (term-wide)',
            style: TextStyle(
              color: _inkColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 720;
              final peerPanel = _evaluationTogglePanel(
                title: 'Peer evaluation',
                subtitle: 'Student Peer Eval tab for Capstone teams.',
                value: peerOn,
                enabled: !saving && semesterId != null,
                helpTooltip: 'Click for Capstone Peer Evaluation Workflow Guide',
                onHelpTap: () =>
                    showPeerGradingHelpDialog(context, isPit: false),
                onChanged: (value) {
                  if (semesterId == null) return;
                  ref
                      .read(academicPeriodProvider.notifier)
                      .updateSemesterEvaluationSettings(
                        semesterId,
                        peerEvaluationEnabled: value,
                      );
                },
              );
              final adviserPanel = _evaluationTogglePanel(
                title: 'Adviser grading',
                subtitle: 'Advisers can submit scores for teams they advise.',
                value: adviserOn,
                enabled: !saving && semesterId != null,
                onChanged: (value) {
                  if (semesterId == null) return;
                  ref
                      .read(academicPeriodProvider.notifier)
                      .updateSemesterEvaluationSettings(
                        semesterId,
                        adviserGradingEnabled: value,
                      );
                },
              );
              if (stacked) {
                return Column(
                  children: [
                    peerPanel,
                    const SizedBox(height: 10),
                    adviserPanel,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: peerPanel),
                  const SizedBox(width: 12),
                  Expanded(child: adviserPanel),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _capstoneSettingRow({required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: _mutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _evaluationTogglePanel({
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    VoidCallback? onHelpTap,
    String? helpTooltip,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: _panelBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: _inkColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onHelpTap != null) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: helpTooltip ?? 'View Guide',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: onHelpTap,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.help_outline_rounded,
                              size: 15,
                              color: _isDark
                                  ? const Color(0xFF71717A)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _mutedColor,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: _isDark ? const Color(0xFFF87171) : _maroon,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _capstoneChip(String label, {bool emphasized = false}) {
    final isOpen = label == 'Capstone 1' || label == 'Open';
    Color bg;
    Color fg;
    Color border;

    if (_isDark) {
      if (emphasized && isOpen) {
        bg = const Color(0xFF064E3B).withValues(alpha: 0.4);
        fg = const Color(0xFF34D399);
        border = const Color(0xFF059669).withValues(alpha: 0.6);
      } else {
        bg = const Color(0xFF27272A);
        fg = const Color(0xFFA1A1AA);
        border = const Color(0xFF3F3F46);
      }
    } else {
      bg = emphasized && isOpen
          ? const Color(0xFFECFDF5)
          : const Color(0xFFF3F4F6);
      fg = emphasized && isOpen
          ? const Color(0xFF047857)
          : const Color(0xFF5D6678);
      border = emphasized && isOpen
          ? const Color(0xFF86EFAC)
          : const Color(0xFFE5E7EB);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  String _capstonePhaseLabel(String? phase) {
    switch (phase) {
      case 'capstone_1':
        return 'Capstone 1';
      case 'capstone_2':
        return 'Capstone 2';
      case 'none':
      default:
        return 'Closed';
    }
  }

  String _activeBannerSubtitle(Map<String, dynamic> active) {
    final mode = active['capstone_mode']?.toString();
    if (mode == 'capstone_1_intake') {
      return 'Capstone 1 Intake & PIT term — peer evaluation and adviser grading apply to this term.';
    }
    if (mode == 'capstone_2_continue') {
      return 'Capstone 2 & PIT term — manage existing teams and active PIT workflows.';
    }
    return 'All uploads, evaluations, and peer rubrics are routing to this period.';
  }

  Widget _notice(String message, {bool warning = false}) {
    final color = warning
        ? (_isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
        : (_isDark ? const Color(0xFF34D399) : const Color(0xFF047857));
    final background = warning
        ? (_isDark
            ? const Color(0xFF451A03).withValues(alpha: 0.5)
            : const Color(0xFFFFF7ED))
        : (_isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.4)
            : const Color(0xFFECFDF5));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _showAddYearDialog() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add School Year'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'School Year',
              hintText: '2026-2027',
              helperText: 'Format: YYYY-YYYY',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) =>
                Navigator.pop(dialogContext, controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Add Year'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (label == null || label.trim().isEmpty) {
      return;
    }

    await ref.read(academicPeriodProvider.notifier).addSchoolYear(label);
  }

  Future<void> _showAddSemesterDialog(Map<String, dynamic> year) async {
    final yearId = _asInt(year['id']);
    if (yearId == null) {
      return;
    }

    String? selectedTerm;
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Semester'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Adding to A.Y. ${year['label']}'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTerm,
                    decoration: const InputDecoration(labelText: 'Term'),
                    items: _terms
                        .map(
                          (term) =>
                              DropdownMenuItem(value: term, child: Text(term)),
                        )
                        .toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedTerm = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedTerm == null
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Add Semester'),
                ),
              ],
            );
          },
        );
      },
    );

    if (added != true || selectedTerm == null) {
      return;
    }

    await ref
        .read(academicPeriodProvider.notifier)
        .addSemester(yearId, selectedTerm!);
  }

  Future<void> _handleSemesterSwitch(
    Map<String, dynamic> semester,
    bool value,
  ) async {
    final semesterId = _asInt(semester['id']);
    if (semesterId == null) {
      return;
    }

    final notifier = ref.read(academicPeriodProvider.notifier);
    if (!value) {
      await notifier.setSemesterActive(semesterId, false);
      return;
    }

    final preview = await notifier.fetchTransitionPreview(semesterId);
    if (!mounted || preview == null) {
      return;
    }

    final result = await _showSemesterTransitionDialog(preview);
    if (!mounted || result == null) {
      return;
    }

    final route = result['route']?.toString();
    if (route != null && route.isNotEmpty) {
      context.go(route);
      return;
    }

    if (result['activate'] == true) {
      await notifier.activateSemester(
        semesterId,
        force: result['force'] == true,
        reason: result['reason']?.toString() ?? '',
      );
    }
  }

  Future<Map<String, dynamic>?> _showSemesterTransitionDialog(
    Map<String, dynamic> preview,
  ) async {
    final current = preview['current_semester'] is Map
        ? Map<String, dynamic>.from(preview['current_semester'])
        : null;
    final target = preview['target_semester'] is Map
        ? Map<String, dynamic>.from(preview['target_semester'])
        : null;
    final issues = _mapList(preview['issues']);
    final canSwitch = preview['can_switch'] == true;
    final reasonController = TextEditingController();
    var force = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canForce = force && reasonController.text.trim().isNotEmpty;
            return AlertDialog(
              title: const Text('Switch active semester?'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You are switching from ${_semesterName(current)} to ${_semesterName(target)}.',
                        style: const TextStyle(height: 1.35),
                      ),
                      const SizedBox(height: 16),
                      if (issues.isEmpty)
                        _transitionEmptyState()
                      else ...[
                        const Text(
                          'This current semester still has:',
                          style: TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...issues.map(
                          (issue) => _transitionIssueRow(
                            issue,
                            onRoute: (route) => Navigator.pop(
                              dialogContext,
                              {'route': route},
                            ),
                          ),
                        ),
                      ],
                      if (!canSwitch) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'Normal switching is blocked until the unfinished workflows are resolved. Use forced override only when the transition was approved outside the system.',
                            style: TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: force,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Force switch with audit reason'),
                          onChanged: (value) {
                            setDialogState(() {
                              force = value == true;
                            });
                          },
                        ),
                        if (force)
                          TextField(
                            controller: reasonController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Override reason',
                              hintText: 'Example: Manual rollover approved.',
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: canSwitch || canForce
                      ? () => Navigator.pop(dialogContext, {
                            'activate': true,
                            'force': !canSwitch && force,
                            'reason': reasonController.text.trim(),
                          })
                      : null,
                  child: Text(canSwitch ? 'Confirm switch' : 'Force switch'),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();
    return result;
  }

  Widget _transitionEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.3)
            : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDark
              ? const Color(0xFF059669).withValues(alpha: 0.5)
              : const Color(0xFFA7F3D0),
        ),
      ),
      child: Text(
        'No unfinished workflows were found. This switch can continue normally.',
        style: TextStyle(
          color: _isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _transitionIssueRow(
    Map<String, dynamic> issue, {
    required ValueChanged<String> onRoute,
  }) {
    final route = issue['route']?.toString() ?? '';
    final blocking = issue['blocking'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: blocking
            ? (_isDark
                ? const Color(0xFF451A03).withValues(alpha: 0.35)
                : const Color(0xFFFFFBEB))
            : _panelBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: blocking
              ? (_isDark
                  ? const Color(0xFFB45309).withValues(alpha: 0.6)
                  : const Color(0xFFFDE68A))
              : _borderColor,
        ),
      ),
      child: Row(
        children: [
          Icon(
            blocking ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            color: blocking
                ? (_isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706))
                : _mutedColor,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              issue['message']?.toString() ?? 'Unfinished workflow',
              style: TextStyle(
                color: _inkColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: route.isEmpty ? null : () => onRoute(route),
            child: Text(issue['action_label']?.toString() ?? 'Review'),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _selectedYear(AcademicPeriodState state) {
    for (final year in state.schoolYears) {
      if (_asInt(year['id']) == state.selectedSchoolYearId) {
        return year;
      }
    }

    if (state.schoolYears.isEmpty) {
      return null;
    }
    return state.schoolYears.first;
  }

  List<Map<String, dynamic>> _semesterList(dynamic value) {
    return _mapList(value);
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  String _semesterName(Map<String, dynamic>? semester) {
    return semester?['display_name']?.toString() ?? 'No active semester';
  }
}

class _ColumnSpec {
  final String label;
  final double flex;

  const _ColumnSpec(this.label, this.flex);
}
