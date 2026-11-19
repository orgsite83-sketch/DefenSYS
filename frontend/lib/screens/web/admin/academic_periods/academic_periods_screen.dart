import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../widgets/defensys_admin_shell.dart';
import 'semester_detail_screen.dart';
import 'widgets/academic_cycle_card.dart';
import 'widgets/semester_transition_dialog.dart';
import 'widgets/add_semester_dialog.dart';
import 'widgets/add_school_year_dialog.dart';

class AcademicPeriodsScreen extends ConsumerStatefulWidget {
  const AcademicPeriodsScreen({super.key});

  @override
  ConsumerState<AcademicPeriodsScreen> createState() =>
      _AcademicPeriodsScreenState();
}

class _AcademicPeriodsScreenState extends ConsumerState<AcademicPeriodsScreen> {
  final Set<int> _expandedYearIds = {};
  bool _hasInitializedExpansion = false;
  int? _lastActiveYearId;
  static const _line = DefensysTokens.border;
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _borderColor => _isDark ? DefensysTokens.mistBorder : _line;
  Color get _surfaceColor =>
      _isDark ? DefensysTokens.mistSurface : Colors.white;
  Color get _inkColor => _isDark ? const Color(0xFFF4F4F5) : _ink;
  Color get _mutedColor => _isDark ? const Color(0xFFA1A1AA) : _muted;

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
  ) => DefensysShadcnScope(
    maroonActions: true,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final addYear = ShadButton.outline(
          enabled: !state.isSaving,
          leading: const Icon(LucideIcons.plus, size: 15),
          onPressed: _showAddYearDialog,
          child: const Text('Add school year'),
        );
        return SingleChildScrollView(
          key: const PageStorageKey('academic-periods-scroll'),
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            20,
            compact ? 16 : 24,
            36,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefensysPageHeader(
                title: 'Academic periods',
                subtitle: 'Manage school years and semesters.',
                actions: compact ? null : addYear,
              ),
              if (compact) ...[const SizedBox(height: 16), addYear],
              if (state.error != null) ...[
                const SizedBox(height: 16),
                _notice(state.error!, warning: true),
              ],
              if (!state.isLoading &&
                  state.schoolYears.isNotEmpty &&
                  state.activeSemester == null) ...[
                const SizedBox(height: 16),
                Text(
                  'No active semester. Open a semester to activate it.',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    color: _mutedColor,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (state.isLoading)
                const AcademicCycleSkeleton()
              else
                _academicCyclesSection(state, selectedYear),
            ],
          ),
        );
      },
    ),
  );

  Widget _academicCyclesSection(
    AcademicPeriodState state,
    Map<String, dynamic>? selectedYear,
  ) {
    if (state.schoolYears.isEmpty) {
      _hasInitializedExpansion = false;
      _lastActiveYearId = null;
      return ShadCard(
        width: double.infinity,
        padding: EdgeInsets.zero,
        radius: BorderRadius.circular(DefensysTokens.radiusLg),
        backgroundColor: DefensysTokens.surfaceOf(context),
        border: ShadBorder.all(
          color: DefensysTokens.borderOf(context),
          width: 1,
        ),
        child: DefensysEmptyState(
          icon: Icons.calendar_today_outlined,
          title: 'No school years yet',
          description: 'Add a school year, then create its semesters.',
          actions: ShadButton(
            enabled: !state.isSaving,
            backgroundColor: DefensysTokens.maroonOf(context),
            hoverBackgroundColor: _isDark
                ? DefensysTokens.maroonLight
                : DefensysTokens.maroonDark,
            foregroundColor: Colors.white,
            leading: const Icon(LucideIcons.plus, size: 16),
            onPressed: _showAddYearDialog,
            child: const Text('Add school year'),
          ),
        ),
      );
    }

    final activeYearId = _activeYearId(state);
    final defaultExpandId =
        activeYearId ??
        (selectedYear != null ? _asInt(selectedYear['id']) : null) ??
        _asInt(state.schoolYears.first['id']);
    if (!_hasInitializedExpansion && defaultExpandId != null) {
      _hasInitializedExpansion = true;
      _expandedYearIds.add(defaultExpandId);
    } else if (activeYearId != null && activeYearId != _lastActiveYearId) {
      _expandedYearIds.add(activeYearId);
    }
    _lastActiveYearId = activeYearId;
    // Keep the current year first without changing the order of other years.
    final years = [
      ...state.schoolYears.where((year) => _asInt(year['id']) == activeYearId),
      ...state.schoolYears.where((year) => _asInt(year['id']) != activeYearId),
    ];
    return Column(
      children: [
        for (var index = 0; index < years.length; index++) ...[
          if (index > 0) const SizedBox(height: 14),
          _academicYear(state, years[index]),
        ],
      ],
    );
  }

  Widget _academicYear(AcademicPeriodState state, Map<String, dynamic> year) {
    final yearId = _asInt(year['id']) ?? 0;
    final expanded = _expandedYearIds.contains(yearId);
    return AcademicCycleCard(
      year: year,
      isExpanded: expanded,
      isSaving: state.isSaving,
      onToggleExpand: () => setState(() {
        if (expanded) {
          _expandedYearIds.remove(yearId);
        } else {
          _expandedYearIds.add(yearId);
        }
      }),
      onAddSemester: () => _showAddSemesterDialog(year),
      onEditYear: () => _showEditYearDialog(year),
      onDeleteYear: () => _showDeleteYearDialog(year),
      onManageSemester: _navigateToSemesterDetail,
      onToggleSemesterActive: _handleSemesterSwitch,
      onDeleteSemester: _showDeleteSemesterDialog,
    );
  }

  int? _activeYearId(AcademicPeriodState state) {
    for (final year in state.schoolYears) {
      final semesters = year['semesters'];
      if (semesters is List &&
          semesters.whereType<Map>().any(
            (semester) => semester['is_active'] == true,
          )) {
        return _asInt(year['id']);
      }
    }
    return _asInt(state.activeSemester?['school_year_id']);
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
            warning
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded,
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
      builder: (dialogContext) => AddSchoolYearDialog(
        existingLabels: ref
            .read(academicPeriodProvider)
            .schoolYears
            .map((year) => year['label']?.toString() ?? ''),
      ),
    );

    if (label == null || label.trim().isEmpty) {
      return;
    }

    await ref.read(academicPeriodProvider.notifier).addSchoolYear(label);
  }

  Future<void> _showEditYearDialog(Map<String, dynamic> year) async {
    final semesters = year['semesters'];
    if (year['can_edit_label'] == false ||
        (semesters is List && semesters.isNotEmpty)) {
      return;
    }
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
            style: TextStyle(color: _mutedColor, fontSize: 13, height: 1.45),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: _inkColor,
                side: BorderSide(color: _borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
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
            style: TextStyle(color: _mutedColor, fontSize: 13, height: 1.45),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: _inkColor,
                side: BorderSide(color: _borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
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
    if (_asInt(year['id']) == null) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddSemesterDialog(year: year),
    );
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

    final changed = await showSemesterTransitionReview(
      context,
      ref,
      semesterId,
    );
    if (mounted && changed == true) context.go('/admin/student-teams');
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
    final borderColor = isDark
        ? DefensysTokens.mistBorder
        : DefensysTokens.border;
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
              color: isDark
                  ? DefensysTokens.mistMaroon
                  : DefensysUi.primaryMaroon,
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
              'Correct the academic year label before adding semesters. '
              'The label is locked once terms are added.',
              style: TextStyle(color: mutedColor, fontSize: 12.5, height: 1.35),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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
                  borderSide: BorderSide(
                    color: DefensysUi.primaryMaroon,
                    width: 1.5,
                  ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysUi.primaryMaroon,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
