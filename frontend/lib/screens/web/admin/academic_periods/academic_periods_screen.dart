import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../widgets/defensys_admin_shell.dart';
import 'semester_detail_screen.dart';
import 'widgets/academic_cycle_card.dart';

class AcademicPeriodsScreen extends ConsumerStatefulWidget {
  const AcademicPeriodsScreen({super.key});

  @override
  ConsumerState<AcademicPeriodsScreen> createState() =>
      _AcademicPeriodsScreenState();
}

class _AcademicPeriodsScreenState extends ConsumerState<AcademicPeriodsScreen> {
  final Set<int> _expandedYearIds = {};
  bool _hasInitializedExpansion = false;
  static const _line = DefensysTokens.border;
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
  Color get _headerBgColor => _isDark ? const Color(0xFF18191E) : const Color(0xFFF8FAFC);
  Color get _headerTextColor => _isDark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B);

  static const _terms = ['1st Semester', '2nd Semester', 'Summer'];
  static const _rowHeight = 48.0;
  static const _emptyBodyMinHeight = 80.0;
  static const _schoolYearsScrollThreshold = 6;
  static const _schoolYearsScrollMaxHeight = 288.0;

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
                'Configure academic cycles, terms, and drill into semester program tracks.',
          ),
          const SizedBox(height: 22),
          _statusBanner(state),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            _notice(state.error!, warning: true),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 12),
            _notice(state.message!),
          ],
          const SizedBox(height: 20),
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
            _academicCyclesSection(state, selectedYear),
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
        : (isDark ? const Color(0xFF1C1D22) : Colors.white);
    final borderColor = isDark
        ? (isActive ? const Color(0xFF7F1D1D) : DefensysTokens.mistBorder)
        : (isActive ? const Color(0xFF991B1B) : _borderColor);

    final titleColor = isActive ? Colors.white : _inkColor;
    final subtitleColor = isActive
        ? Colors.white.withValues(alpha: 0.88)
        : _mutedColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.15)
                  : (isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? Colors.white.withValues(alpha: 0.2)
                    : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFE2E8F0)),
              ),
            ),
            child: Icon(
              isActive ? Icons.verified_rounded : Icons.calendar_today_outlined,
              size: 20,
              color: isActive
                  ? Colors.white
                  : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive
                      ? 'Currently Active: ${active['display_name']}'
                      : 'No Active Semester',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isActive
                      ? _activeBannerSubtitle(active)
                      : 'Add a school year and activate a semester to begin.',
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? (isDark ? const Color(0xFF064E3B) : const Color(0xFF10B981))
                      : (isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isActive
                        ? (isDark ? const Color(0xFF059669) : const Color(0xFF059669))
                        : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive
                            ? (isDark ? const Color(0xFF34D399) : Colors.white)
                            : (isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8)),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isActive ? 'LIVE' : 'INACTIVE',
                      style: TextStyle(
                        color: isActive
                            ? (isDark ? const Color(0xFF34D399) : Colors.white)
                            : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569)),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                ElevatedButton.icon(
                  onPressed: () => _navigateToSemesterDetail(active),
                  icon: const Icon(Icons.tune_rounded, size: 14),
                  label: const Text('Manage Active Term ↗'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF3B181F)
                        : Colors.white,
                    foregroundColor: isDark
                        ? const Color(0xFFFCA5A5)
                        : _maroon,
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF7F1D1D)
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 8),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _academicCyclesSection(
    AcademicPeriodState state,
    Map<String, dynamic>? selectedYear,
  ) {
    if (state.schoolYears.isEmpty) {
      _hasInitializedExpansion = false;
      return _card(
        title: 'School Years',
        description:
            'Define and manage institutional academic cycles & semester terms',
        actionLabel: '+ Add Year',
        onActionTap: state.isSaving ? null : _showAddYearDialog,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DefensysEmptyState.table(
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
          ),
        ),
      );
    }

    final activeYearId = _activeYearId(state);
    final defaultExpandId = activeYearId ??
        (selectedYear != null ? _asInt(selectedYear['id']) : null) ??
        _asInt(state.schoolYears.first['id']);
    if (!_hasInitializedExpansion && defaultExpandId != null) {
      _hasInitializedExpansion = true;
      _expandedYearIds.add(defaultExpandId);
    }

    return _card(
      title: 'School Years',
      description:
          'Define and manage institutional academic cycles & semester terms',
      actionLabel: '+ Add Year',
      onActionTap: state.isSaving ? null : _showAddYearDialog,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          children: state.schoolYears.map((year) {
            final yearId = _asInt(year['id']) ?? 0;
            final isExpanded = _expandedYearIds.contains(yearId);

            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AcademicCycleCard(
                year: year,
                isExpanded: isExpanded,
                isSaving: state.isSaving,
                onToggleExpand: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedYearIds.remove(yearId);
                    } else {
                      _expandedYearIds.add(yearId);
                    }
                  });
                },
                onAddSemester: () => _showAddSemesterDialog(year),
                onEditYear: () => _showEditYearDialog(year),
                onDeleteYear: () => _showDeleteYearDialog(year),
                onManageSemester: (sem) => _navigateToSemesterDetail(sem),
                onToggleSemesterActive: (sem, active) =>
                    _handleSemesterSwitch(sem, active),
                onDeleteSemester: (sem) => _showDeleteSemesterDialog(sem),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  int? _activeYearId(AcademicPeriodState state) {
    final active = state.activeSemester;
    if (active == null) return null;
    return _asInt(active['school_year_id']);
  }

  void _navigateToSemesterDetail(Map<String, dynamic> semester) {
    final semesterId = _asInt(semester['id']);
    if (semesterId == null) return;
    try {
      context.push(AdminRoutes.academicPeriodDetail(semesterId));
    } catch (_) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SemesterDetailScreen(
            semesterId: semesterId,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
  }

  Widget _schoolYearsCard(AcademicPeriodState state) {
    return _card(
      title: 'School Years',
      description: 'Define and manage institutional academic cycles',
      actionLabel: '+ Add Year',
      onActionTap: state.isSaving ? null : _showAddYearDialog,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tableHeader(
            columns: const [
              _ColumnSpec('Academic Year', 1.8),
              _ColumnSpec('Semesters Created', 1.4),
              _ColumnSpec('Action', 1.8),
            ],
          ),
          _schoolYearsBody(state),
        ],
      ),
    );
  }

  Widget _schoolYearsBody(AcademicPeriodState state) {
    if (state.schoolYears.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: DefensysEmptyState.table(
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
      description: 'Active terms, status control, and workflow triggers',
      actionLabel: '+ Add Semester',
      onActionTap: selectedYear == null || state.isSaving
          ? null
          : () => _showAddSemesterDialog(selectedYear),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tableHeader(
            columns: const [
              _ColumnSpec('Term', 1.3),
              _ColumnSpec('System Status', 2.2),
              _ColumnSpec('Action', 1.2),
            ],
          ),
          if (selectedYear == null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: DefensysEmptyState.table(
                icon: Icons.touch_app_outlined,
                title: 'Select a School Year',
                description:
                    'Select an academic year on the left to view and manage its semesters.',
                size: DefensysEmptyStateSize.compact,
              ),
            )
          else if (semesters.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: DefensysEmptyState.table(
                icon: Icons.date_range_outlined,
                title: 'No Semesters Created',
                description:
                    'Add a semester to activate terms for A.Y. ${selectedLabel ?? ""}, or remove this school year if created by mistake.',
                size: DefensysEmptyStateSize.compact,
                primaryAction: DefensysEmptyAction(
                  label: 'Add Semester',
                  icon: Icons.add_rounded,
                  onPressed: state.isSaving
                      ? () {}
                      : () => _showAddSemesterDialog(selectedYear),
                ),
                secondaryAction: DefensysEmptyAction(
                  label: 'Delete School Year',
                  icon: Icons.delete_outline_rounded,
                  isOutlined: true,
                  onPressed: state.isSaving
                      ? () {}
                      : () => _showDeleteYearDialog(selectedYear),
                ),
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
    String? description,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.25 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _inkColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: TextStyle(
                            color: _mutedColor,
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actionLabel case final label?)
                  OutlinedButton.icon(
                    onPressed: onActionTap,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(label.replaceFirst(RegExp(r'^\+\s*'), '')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inkColor,
                      side: BorderSide(color: _borderColor),
                      backgroundColor: _isDark
                          ? const Color(0xFF27272A)
                          : const Color(0xFFF8FAFC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
      height: 40,
      decoration: BoxDecoration(
        color: _headerBgColor,
        border: Border(
          top: BorderSide(color: _borderColor),
          bottom: BorderSide(color: _borderColor),
        ),
      ),
      child: Row(
        children: columns
            .map(
              (column) => Expanded(
                flex: (column.flex * 100).round(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      column.label.toUpperCase(),
                      style: TextStyle(
                        color: _headerTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
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
              ? (_isDark ? const Color(0xFF28181A) : const Color(0xFFFFF5F5))
              : _surfaceColor,
          border: Border(
            bottom: BorderSide(color: _borderColor),
            left: BorderSide(
              color: selected
                  ? (_isDark ? DefensysTokens.mistMaroon : _maroon)
                  : Colors.transparent,
              width: selected ? 3 : 0,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 180,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        year['label']?.toString() ?? 'Unknown',
                        style: TextStyle(
                          color: _inkColor,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _isDark
                              ? const Color(0xFF064E3B).withValues(alpha: 0.4)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _isDark
                                ? const Color(0xFF059669).withValues(alpha: 0.5)
                                : const Color(0xFFA7F3D0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Active',
                              style: TextStyle(
                                color: _isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 140,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  semesters.length.toString(),
                  style: TextStyle(
                    color: _mutedColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 180,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: yearId == null
                          ? null
                          : () => ref
                              .read(academicPeriodProvider.notifier)
                              .selectSchoolYear(yearId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? (_isDark ? const Color(0xFF3C181D) : const Color(0xFFFEE2E2))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected
                                ? (_isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA))
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              selected ? Icons.check_circle_rounded : Icons.tune_rounded,
                              size: 13,
                              color: selected
                                  ? (_isDark ? const Color(0xFFFCA5A5) : _maroon)
                                  : _mutedColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              selected ? 'Managing' : 'Manage',
                              style: TextStyle(
                                color: selected
                                    ? (_isDark ? const Color(0xFFFCA5A5) : _maroon)
                                    : _inkColor,
                                fontSize: 12,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Edit school year',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: state.isSaving
                            ? null
                            : () => _showEditYearDialog(year),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 15,
                            color: _mutedColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Tooltip(
                      message: semesters.isEmpty
                          ? 'Delete school year'
                          : 'Delete all semesters first',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: semesters.isEmpty && !state.isSaving
                            ? () => _showDeleteYearDialog(year)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 15,
                            color: semesters.isEmpty
                                ? (_isDark
                                    ? const Color(0xFFF87171)
                                    : const Color(0xFFDC2626))
                                : (_isDark
                                    ? const Color(0xFF52525B)
                                    : const Color(0xFFCBD5E1)),
                          ),
                        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 130,
            child: Text(
              semester['label']?.toString() ?? 'Unknown semester',
              style: TextStyle(
                color: _inkColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 220,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: isActive
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isDark
                            ? const Color(0xFF064E3B).withValues(alpha: 0.4)
                            : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _isDark
                              ? const Color(0xFF059669).withValues(alpha: 0.5)
                              : const Color(0xFFA7F3D0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Active (Write-Enabled)',
                            style: TextStyle(
                              color: _isDark
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF047857),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isDark
                            ? const Color(0xFF27272A)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _isDark
                              ? const Color(0xFF3F3F46)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _isDark
                                  ? const Color(0xFF71717A)
                                  : const Color(0xFF94A3B8),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Inactive',
                            style: TextStyle(
                              color: _isDark
                                  ? const Color(0xFFA1A1AA)
                                  : const Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          Expanded(
            flex: 120,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: isActive
                      ? 'Active semester (activate another semester to switch)'
                      : 'Activate semester',
                  child: DefensysUi.flatSwitch(
                    value: isActive,
                    scale: 0.85,
                    activeTrackColor: _isDark ? const Color(0xFFE11D48) : _maroon,
                    onChanged: state.isSaving || semesterId == null
                        ? null
                        : (value) => _handleSemesterSwitch(semester, value),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: isActive
                      ? 'Cannot delete active semester'
                      : 'Delete semester',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: !isActive && !state.isSaving
                        ? () => _showDeleteSemesterDialog(semester)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: !isActive
                            ? (_isDark
                                ? const Color(0xFFF87171)
                                : const Color(0xFFDC2626))
                            : (_isDark
                                ? const Color(0xFF52525B)
                                : const Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _activeBannerSubtitle(Map<String, dynamic> active) {
    final mode = active['capstone_mode']?.toString();
    if (mode == 'capstone_1_intake') {
      return 'Capstone 1 Intake & PIT term: peer evaluation and adviser grading apply to this term.';
    }
    if (mode == 'capstone_2_continue') {
      return 'Capstone 2 & PIT term: manage existing teams and active PIT workflows.';
    }
    return 'All uploads, evaluations, and peer rubrics are routing to this period.';
  }

  Widget _notice(String message, {bool warning = false}) {
    final color = warning
        ? (_isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
        : (_isDark ? const Color(0xFF34D399) : const Color(0xFF047857));
    final background = warning
        ? (_isDark
            ? const Color(0xFF451A03).withValues(alpha: 0.4)
            : const Color(0xFFFFFBEB))
        : (_isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.3)
            : const Color(0xFFECFDF5));
    final border = warning
        ? (_isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A))
        : (_isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            warning ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddYearDialog() async {
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _AddSchoolYearDialog(),
    );

    if (label == null || label.trim().isEmpty) {
      return;
    }

    await ref.read(academicPeriodProvider.notifier).addSchoolYear(label);
  }

  Future<void> _showEditYearDialog(Map<String, dynamic> year) async {
    final yearId = _asInt(year['id']);
    final currentLabel = year['label']?.toString() ?? '';
    if (yearId == null) {
      return;
    }

    final newLabel = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _EditSchoolYearDialog(initialLabel: currentLabel),
    );

    if (newLabel == null ||
        newLabel.trim().isEmpty ||
        newLabel.trim() == currentLabel) {
      return;
    }

    await ref
        .read(academicPeriodProvider.notifier)
        .updateSchoolYear(yearId, newLabel.trim());
  }

  Future<void> _showDeleteYearDialog(Map<String, dynamic> year) async {
    final yearId = _asInt(year['id']);
    final label = year['label']?.toString() ?? 'this school year';
    if (yearId == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _borderColor),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 22),
          actionsPadding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Delete School Year',
                style: TextStyle(
                  color: _inkColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete Academic Year $label? This will remove the academic year from the system. This action cannot be undone.',
            style: TextStyle(
              color: _mutedColor,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: _inkColor,
                side: BorderSide(color: _borderColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ref.read(academicPeriodProvider.notifier).deleteSchoolYear(yearId);
    }
  }

  Future<void> _showDeleteSemesterDialog(Map<String, dynamic> semester) async {
    final semesterId = _asInt(semester['id']);
    final label = semester['label']?.toString() ?? 'this semester';
    if (semesterId == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _borderColor),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 22),
          actionsPadding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Delete Semester',
                style: TextStyle(
                  color: _inkColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete $label? This will remove the semester configuration from this academic year.',
            style: TextStyle(
              color: _mutedColor,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: _inkColor,
                side: BorderSide(color: _borderColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await ref
          .read(academicPeriodProvider.notifier)
          .deleteSemester(semesterId);
    }
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
              backgroundColor: _surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _borderColor),
              ),
              titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 22),
              actionsPadding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _borderColor),
                    ),
                    child: Icon(
                      Icons.add_chart_rounded,
                      size: 18,
                      color: _isDark ? DefensysTokens.mistMaroon : DefensysUi.primaryMaroon,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Add Semester',
                    style: TextStyle(
                      color: _inkColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adding term to Academic Year ${year['label']}.',
                      style: TextStyle(
                        color: _mutedColor,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedTerm,
                      dropdownColor: _surfaceColor,
                      style: TextStyle(color: _inkColor, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Select Term',
                        filled: true,
                        fillColor: _panelBgColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: _borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: _borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: DefensysUi.primaryMaroon, width: 1.5),
                        ),
                      ),
                      items: _terms
                          .map(
                            (term) => DropdownMenuItem(
                              value: term,
                              child: Text(term, style: TextStyle(color: _inkColor)),
                            ),
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
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _inkColor,
                    side: BorderSide(color: _borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DefensysUi.primaryMaroon,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _isDark
                        ? const Color(0xFF3F3F46)
                        : const Color(0xFFE2E8F0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
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
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _SemesterTransitionDialog(
        preview: preview,
        isDark: _isDark,
        panelBgColor: _panelBgColor,
        borderColor: _borderColor,
        inkColor: _inkColor,
        mutedColor: _mutedColor,
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
}

class _ColumnSpec {
  final String label;
  final double flex;

  const _ColumnSpec(this.label, this.flex);
}

class _AddSchoolYearDialog extends StatefulWidget {
  const _AddSchoolYearDialog();

  @override
  State<_AddSchoolYearDialog> createState() => _AddSchoolYearDialogState();
}

class _AddSchoolYearDialogState extends State<_AddSchoolYearDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? DefensysTokens.mistSurface : Colors.white;
    final borderColor = isDark ? DefensysTokens.mistBorder : DefensysTokens.border;
    final inkColor = isDark ? const Color(0xFFF4F4F5) : DefensysUi.textDark;
    final mutedColor = isDark ? const Color(0xFFA1A1AA) : DefensysUi.steelGrey;
    final panelBg = isDark ? const Color(0xFF28272D) : const Color(0xFFF8FAFC);

    return AlertDialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
      actionsPadding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Icon(
              Icons.calendar_month_outlined,
              size: 18,
              color: isDark ? DefensysTokens.mistMaroon : DefensysUi.primaryMaroon,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Add School Year',
            style: TextStyle(
              color: inkColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the academic year in YYYY-YYYY format (e.g. 2026-2027).',
              style: TextStyle(
                color: mutedColor,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: inkColor, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'School Year',
                hintText: '2026-2027',
                filled: true,
                fillColor: panelBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: DefensysUi.primaryMaroon, width: 1.5),
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: inkColor,
            side: BorderSide(color: borderColor),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysUi.primaryMaroon,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
          child: const Text('Add Year'),
        ),
      ],
    );
  }
}

class _EditSchoolYearDialog extends StatefulWidget {
  final String initialLabel;

  const _EditSchoolYearDialog({required this.initialLabel});

  @override
  State<_EditSchoolYearDialog> createState() => _EditSchoolYearDialogState();
}

class _EditSchoolYearDialogState extends State<_EditSchoolYearDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLabel);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? DefensysTokens.mistSurface : Colors.white;
    final borderColor = isDark ? DefensysTokens.mistBorder : DefensysTokens.border;
    final inkColor = isDark ? const Color(0xFFF4F4F5) : DefensysUi.textDark;
    final mutedColor = isDark ? const Color(0xFFA1A1AA) : DefensysUi.steelGrey;
    final panelBg = isDark ? const Color(0xFF28272D) : const Color(0xFFF8FAFC);

    return AlertDialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
      actionsPadding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Icon(
              Icons.edit_calendar_outlined,
              size: 18,
              color: isDark ? DefensysTokens.mistMaroon : DefensysUi.primaryMaroon,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Edit School Year',
            style: TextStyle(
              color: inkColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Update the academic year label.',
              style: TextStyle(
                color: mutedColor,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: inkColor, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'School Year',
                hintText: '2026-2027',
                filled: true,
                fillColor: panelBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: DefensysUi.primaryMaroon, width: 1.5),
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: inkColor,
            side: BorderSide(color: borderColor),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysUi.primaryMaroon,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SemesterTransitionDialog extends StatefulWidget {
  final Map<String, dynamic> preview;
  final bool isDark;
  final Color panelBgColor;
  final Color borderColor;
  final Color inkColor;
  final Color mutedColor;

  const _SemesterTransitionDialog({
    required this.preview,
    required this.isDark,
    required this.panelBgColor,
    required this.borderColor,
    required this.inkColor,
    required this.mutedColor,
  });

  @override
  State<_SemesterTransitionDialog> createState() =>
      _SemesterTransitionDialogState();
}

class _SemesterTransitionDialogState extends State<_SemesterTransitionDialog> {
  late final TextEditingController _reasonController;
  bool _force = false;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _semesterName(Map<String, dynamic>? semester) {
    return semester?['display_name']?.toString() ?? 'No active semester';
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final current = preview['current_semester'] is Map
        ? Map<String, dynamic>.from(preview['current_semester'])
        : null;
    final target = preview['target_semester'] is Map
        ? Map<String, dynamic>.from(preview['target_semester'])
        : null;
    final issues = _mapList(preview['issues']);
    final canSwitch = preview['can_switch'] == true;
    final canForce = _force && _reasonController.text.trim().isNotEmpty;
    final surfaceColor = widget.isDark ? DefensysTokens.mistSurface : Colors.white;

    return AlertDialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: widget.borderColor),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
      actionsPadding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.borderColor),
            ),
            child: Icon(
              Icons.swap_horiz_rounded,
              size: 18,
              color: widget.isDark ? DefensysTokens.mistMaroon : DefensysUi.primaryMaroon,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Switch active semester?',
            style: TextStyle(
              color: widget.inkColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are switching from ${_semesterName(current)} to ${_semesterName(target)}.',
                style: TextStyle(
                  color: widget.mutedColor,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (issues.isEmpty)
                _transitionEmptyState()
              else ...[
                Text(
                  'This current semester still has:',
                  style: TextStyle(
                    color: widget.inkColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 10),
                ...issues.map(
                  (issue) => _transitionIssueRow(
                    issue,
                    onRoute: (route) => Navigator.pop(
                      context,
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
                    color: widget.isDark
                        ? const Color(0xFF451A03).withValues(alpha: 0.35)
                        : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.isDark
                          ? const Color(0xFF78350F)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Normal switching is blocked until the unfinished workflows are resolved. Use forced override only when the transition was approved outside the system.',
                    style: TextStyle(
                      color: widget.isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _force,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Force switch with audit reason',
                    style: TextStyle(
                      color: widget.inkColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _force = value == true;
                    });
                  },
                ),
                if (_force)
                  TextField(
                    controller: _reasonController,
                    maxLines: 2,
                    style: TextStyle(color: widget.inkColor, fontSize: 13.5),
                    decoration: InputDecoration(
                      labelText: 'Override reason',
                      hintText: 'Example: Manual rollover approved.',
                      filled: true,
                      fillColor: widget.panelBgColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: widget.borderColor),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.inkColor,
            side: BorderSide(color: widget.borderColor),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysUi.primaryMaroon,
            foregroundColor: Colors.white,
            disabledBackgroundColor: widget.isDark
                ? const Color(0xFF3F3F46)
                : const Color(0xFFE2E8F0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
          onPressed: canSwitch || canForce
              ? () => Navigator.pop(context, {
                    'activate': true,
                    'force': !canSwitch && _force,
                    'reason': _reasonController.text.trim(),
                  })
              : null,
          child: Text(canSwitch ? 'Confirm switch' : 'Force switch'),
        ),
      ],
    );
  }

  Widget _transitionEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.3)
            : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.isDark
              ? const Color(0xFF059669).withValues(alpha: 0.5)
              : const Color(0xFFA7F3D0),
        ),
      ),
      child: Text(
        'No unfinished workflows were found. This switch can continue normally.',
        style: TextStyle(
          color: widget.isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
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
            ? (widget.isDark
                ? const Color(0xFF451A03).withValues(alpha: 0.35)
                : const Color(0xFFFFFBEB))
            : widget.panelBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: blocking
              ? (widget.isDark
                  ? const Color(0xFFB45309).withValues(alpha: 0.6)
                  : const Color(0xFFFDE68A))
              : widget.borderColor,
        ),
      ),
      child: Row(
        children: [
          Icon(
            blocking ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            color: blocking
                ? (widget.isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706))
                : widget.mutedColor,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              issue['message']?.toString() ?? 'Unfinished workflow',
              style: TextStyle(
                color: widget.inkColor,
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
}

