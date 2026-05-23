import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/academic_period_provider.dart';
import 'widgets/defensys_admin_shell.dart';

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

    return _buildContent(state, selectedYear);
  }

  Widget _buildContent(
    AcademicPeriodState state,
    Map<String, dynamic>? selectedYear,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DefensysPageHeader(
          icon: Icons.calendar_month_rounded,
          title: 'Academic Period Management',
          subtitle:
              'Configure school years and toggle active semesters to enforce read-only vault rules.',
        ),
        const SizedBox(height: 28),
        _statusBanner(state),
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
              child: CircularProgressIndicator(color: DefensysUi.primaryMaroon),
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
    );
  }

  Widget _statusBanner(AcademicPeriodState state) {
    final active = state.activeSemester;
    final isActive = active != null;
    final base = isActive ? DefensysUi.primaryMaroon : const Color(0xFF6B7280);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: isActive ? 0.14 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: isActive ? 0.12 : 0.08),
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
                      ? 'All uploads, evaluations, and peer rubrics are routing to this period.'
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
                  ? const Color(0xFF10B981)
                  : Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isActive ? 'LIVE' : 'INACTIVE',
              style: const TextStyle(
                color: Colors.white,
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
      return _emptyTableMessage('No school years yet. Add a year to continue.');
    }

    final rows = state.schoolYears
        .map((year) => _schoolYearRow(state, year))
        .toList();

    if (state.schoolYears.length > _schoolYearsScrollThreshold) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _schoolYearsScrollMaxHeight),
        child: ListView(
          shrinkWrap: true,
          children: rows,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
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
              _ColumnSpec('Term', 1.35),
              _ColumnSpec('System Status', 2.2),
              _ColumnSpec('Action', 1),
            ],
          ),
          if (selectedYear == null)
            _emptyTableMessage(
              'Select a school year to manage its semesters.',
            )
          else if (semesters.isEmpty)
            _emptyTableMessage(
              'No semesters yet. Add a semester to continue.',
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  style: const TextStyle(
                    color: _ink,
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
                  label: Text(
                    label.replaceFirst(RegExp(r'^\+\s*'), ''),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(
                      color: Color(0xFFD1D5DB),
                      width: 1,
                    ),
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
    return SizedBox(
      height: _emptyBodyMinHeight,
      width: double.infinity,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _tableHeader({required List<_ColumnSpec> columns}) {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(6),
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
                      style: const TextStyle(
                        color: Color(0xFF5D6678),
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
          color: selected ? const Color(0xFFFFF4F4) : Colors.white,
          border: Border(
            bottom: const BorderSide(color: _line),
            left: BorderSide(
              color: selected ? _maroon : Colors.transparent,
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
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    children: [
                      TextSpan(text: year['label']?.toString() ?? 'Unknown'),
                      if (hasActive)
                        const TextSpan(
                          text: ' • Active',
                          style: TextStyle(
                            color: _green,
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
                  style: const TextStyle(
                    color: _ink,
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
                      color: _ink,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      selected ? 'Managing' : 'Manage',
                      style: const TextStyle(
                        color: _ink,
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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 135,
            child: Text(
              semester['label']?.toString() ?? 'Unknown semester',
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 220,
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
              activeTrackColor: _maroon,
              onChanged: state.isSaving || semesterId == null
                  ? null
                  : (value) => ref
                        .read(academicPeriodProvider.notifier)
                        .setSemesterActive(semesterId, value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String message, {bool warning = false}) {
    final color = warning ? const Color(0xFFB45309) : const Color(0xFF047857);
    final background = warning
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFECFDF5);

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
