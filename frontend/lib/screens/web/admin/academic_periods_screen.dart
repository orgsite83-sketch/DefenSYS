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
  static const _line = Color(0xFFF3F4F6);
  static const _ink = DefensysUi.textDark;
  static const _green = Color(0xFF10B981);
  static const _blue = DefensysUi.techBlue;

  static const _terms = ['1st Semester', '2nd Semester', 'Summer'];

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
        const SizedBox(height: 20),
        _statusBanner(state),
        if (state.error != null) ...[
          const SizedBox(height: 12),
          _notice(state.error!, warning: true),
        ],
        if (state.message != null) ...[
          const SizedBox(height: 12),
          _notice(state.message!),
        ],
        const SizedBox(height: 30),
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
              Expanded(child: _schoolYearsCard(state)),
              const SizedBox(width: 24),
              Expanded(child: _semestersCard(state, selectedYear)),
            ],
          ),
      ],
    );
  }

  Widget _statusBanner(AcademicPeriodState state) {
    final active = state.activeSemester;
    final isActive = active != null;

    return Container(
      width: double.infinity,
      height: 92,
      padding: const EdgeInsets.fromLTRB(30, 18, 29, 18),
      decoration: BoxDecoration(
        color: isActive ? DefensysUi.primaryMaroon : const Color(0xFF737B8A),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: DefensysUi.primaryMaroon.withValues(
              alpha: isActive ? 0.18 : 0.11,
            ),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive
                      ? 'Currently Active: ${active['display_name']}'
                      : 'No Active Semester',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isActive
                      ? 'All uploads, evaluations, and peer rubrics are routing to this period.'
                      : 'Add a school year and activate a semester to begin.',
                  style: const TextStyle(
                    color: Color(0xFFFFD0D0),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF13C690)
                  : Colors.white.withValues(alpha: 0.19),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isActive ? 'LIVE' : 'INACTIVE',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _schoolYearsCard(AcademicPeriodState state) {
    return _card(
      height: 196,
      title: 'School Years',
      actionLabel: '+ Add Year',
      onActionTap: state.isSaving ? null : _showAddYearDialog,
      child: Column(
        children: [
          _tableHeader(
            columns: const [
              _ColumnSpec('Academic Year', 2),
              _ColumnSpec('Semesters Created', 2),
              _ColumnSpec('Action', 1.5),
            ],
          ),
          if (state.schoolYears.isEmpty)
            const Expanded(child: SizedBox.shrink())
          else
            ...state.schoolYears.map((year) => _schoolYearRow(state, year)),
        ],
      ),
    );
  }

  Widget _semestersCard(
    AcademicPeriodState state,
    Map<String, dynamic>? selectedYear,
  ) {
    final selectedLabel = selectedYear?['label']?.toString();
    final semesters = _semesterList(selectedYear?['semesters']);

    return _card(
      height: 196,
      title: selectedLabel == null
          ? 'Semesters'
          : 'Semesters (A.Y. $selectedLabel)',
      actionLabel: '+ Add Semester',
      onActionTap: selectedYear == null || state.isSaving
          ? null
          : () => _showAddSemesterDialog(selectedYear),
      child: Column(
        children: [
          _tableHeader(
            columns: const [
              _ColumnSpec('Term', 1.35),
              _ColumnSpec('System Status', 2.2),
              _ColumnSpec('Action', 1),
            ],
          ),
          if (selectedYear == null)
            const Expanded(
              child: Center(
                child: Text(
                  'Select a school year to manage its semesters.',
                  style: TextStyle(color: Color(0xFF9AA1B4), fontSize: 14),
                ),
              ),
            )
          else if (semesters.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No semesters yet. Add a semester to continue.',
                  style: TextStyle(color: Color(0xFF9AA1B4), fontSize: 14),
                ),
              ),
            )
          else
            ...semesters.map((semester) => _semesterRow(state, semester)),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    required double height,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(25, 25, 25, 27),
      decoration: DefensysUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.15,
                  ),
                ),
              ),
              if (actionLabel != null)
                OutlinedButton(
                  onPressed: onActionTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _blue,
                    side: const BorderSide(color: _blue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 13,
                    ),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(actionLabel),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _tableHeader({required List<_ColumnSpec> columns}) {
    return Container(
      height: 43,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
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
                        fontSize: 13,
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
        height: 45,
        color: selected ? const Color(0xFFFFF2BC) : Colors.white,
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
                            fontWeight: FontWeight.w900,
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
                child: Text(
                  selected ? '✎ Managing' : 'Manage',
                  style: const TextStyle(
                    color: _blue,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
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
      height: 47,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 135,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Text(
                semester['label']?.toString() ?? 'Unknown semester',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 220,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _statusChip(
                  isActive ? 'Active (Write-Enabled)' : 'Inactive',
                  isActive,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Transform.scale(
                  scale: 0.82,
                  alignment: Alignment.centerLeft,
                  child: Switch(
                    value: isActive,
                    activeThumbColor: Colors.white,
                    activeTrackColor: _green,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFFD1D5DB),
                    trackOutlineColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    onChanged: state.isSaving || semesterId == null
                        ? null
                        : (value) => ref
                              .read(academicPeriodProvider.notifier)
                              .setSemesterActive(semesterId, value),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFD6F5E7) : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF006B45) : const Color(0xFF6B7280),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
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
