import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/file_import_staging_modal.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic/student_batch_draft_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/table/defensys_segmented_control.dart';
import 'package:defensys/widgets/feedback/action_banner.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/import/student_rollover_action.dart';
import 'package:flutter/services.dart';

import 'package:defensys/screens/web/admin/widgets/template_blueprint_models.dart';
import 'official_class_list_parser.dart';

enum StudentHubMode { freshIntake, semesterRollover }

enum RolloverFilterMode { all, bySection, byYearLevel }

enum _FreshReviewStatus {
  ready('Ready to enroll'),
  existingStudent('Existing student'),
  alreadyEnrolled('Already enrolled'),
  updatesSection('Updates section'),
  needsAttention('Needs attention');

  const _FreshReviewStatus(this.label);
  final String label;
}

/// Unified Batch Student Enrollment Hub combining Fresh Intake and Semester Rollover.
class StudentBatchEnrollmentHubView extends ConsumerStatefulWidget {
  const StudentBatchEnrollmentHubView({
    super.key,
    required this.userState,
    required this.academicState,
    required this.onBack,
    this.initialMode = StudentHubMode.freshIntake,
    required this.onDownloadSample,
    required this.onConfirmFreshImport,
    this.onPickFreshFiles,
    this.onPickFreshReplacement,
  });

  final UserManagementState userState;
  final AcademicPeriodState academicState;
  final VoidCallback onBack;
  final StudentHubMode initialMode;
  final VoidCallback? onDownloadSample;
  // Platform picker overrides keep file actions testable without changing staging.
  final Future<List<PickedTabularFile>> Function()? onPickFreshFiles;
  final Future<PickedTabularFile?> Function()? onPickFreshReplacement;
  final Future<bool> Function(
    List<Map<String, dynamic>> students,
    Map<String, dynamic>? studentContext,
  )
  onConfirmFreshImport;

  @override
  ConsumerState<StudentBatchEnrollmentHubView> createState() =>
      _StudentBatchEnrollmentHubViewState();
}

class _StudentBatchEnrollmentHubViewState
    extends ConsumerState<StudentBatchEnrollmentHubView> {
  static const Color _ink = DefensysUi.textDark;
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _maroon = DefensysUi.primaryMaroon;
  static const Color _muted = DefensysUi.steelGrey;
  static const Color _green = Color(0xFF15803D);

  late StudentHubMode _currentMode;

  // Rollover state
  final TextEditingController _rolloverSearchCtrl = TextEditingController();
  final RolloverFilterMode _rolloverFilterMode = RolloverFilterMode.all;
  final Map<String, String> _rolloverActions = {};
  List<PickedTabularFile> _stagedRolloverFiles = [];
  bool _hasCsvUploaded = false;
  String _selectedSectionFilter = 'ALL';
  String _selectedYearFilter = 'ALL';
  int _rolloverPage = 0;
  int _rolloverRowsPerPage = 10;

  // Fresh Intake state
  final TextEditingController _freshSearchCtrl = TextEditingController();
  List<PickedTabularFile> _stagedFreshFiles = [];
  List<Map<String, dynamic>> _parsedFreshStudents = [];
  String _selectedFreshSectionFilter = 'ALL';
  String _selectedFreshYearFilter = 'ALL';
  String _selectedFreshStatusFilter = 'ALL';
  int _freshPage = 0;
  int _freshRowsPerPage = 10;

  static const List<int> _rowsPerPageOptions = [10, 25, 50, 100];

  StreamSubscription? _dropSubscription;
  bool _isDraggingFile = false;
  bool _freshImportPending = false;
  bool _freshFilesPending = false;

  bool get _freshControlsBusy =>
      _freshImportPending || _freshFilesPending || widget.userState.isSaving;

  String _freshSection(Map<String, dynamic> student) =>
      ((student['_section_resolution'] as Map?)?['section'] ??
              student['section'] ?? '')
          .toString().trim();

  Future<void> _resolveFreshSections(List<Map<String, dynamic>> students) async {
    final active = ref.read(academicPeriodProvider).activeSemester ??
        widget.academicState.activeSemester ??
        ref.read(studentAcademicRecordsProvider).activeSemester;
    if (active == null || students.isEmpty) return;
    final resolutions = await ref.read(userManagementProvider.notifier)
        .previewEnrollmentSections(students, active['id'] as int);
    final byId = {
      for (final row in resolutions)
        (row['id_number'] ?? '').toString().trim(): row,
    };
    for (var i = 0; i < students.length; i++) {
      final student = students[i];
      final trimmedId = (student['id_number'] ?? '').toString().trim();
      if (i < resolutions.length &&
          (resolutions[i]['id_number'] ?? '').toString().trim() == trimmedId) {
        student['_section_resolution'] = resolutions[i];
      } else {
        student['_section_resolution'] = byId[trimmedId];
      }
    }
  }

  Future<void> _editFreshSection(Map<String, dynamic> student) async {
    final controller = TextEditingController(text: _freshSection(student));
    final section = await showDialog<String>(context: context, builder: (context) =>
      AlertDialog(
        title: const Text('Enrollment section'),
        content: TextField(controller: controller, autofocus: true, maxLength: 80,
          decoration: const InputDecoration(labelText: 'Official section',
            hintText: 'BSIT-4A', helperText: 'Leave blank to use an available continuation default.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply')),
        ],
      ));
    // The closing route may still reference its TextField during animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (section == null || !mounted) return;
    final targetId = (student['id_number'] ?? '').toString().trim();
    final revised = _parsedFreshStudents.map((s) => Map<String, dynamic>.from(s)).toList();
    for (final row in revised) {
      if ((row['id_number'] ?? '').toString().trim() == targetId) {
        row['section'] = section;
        row.remove('_client_validation_error');
      }
    }
    try {
      await _resolveFreshSections(revised);
      if (!mounted) return;
      setState(() => _parsedFreshStudents = revised);
      ref.read(studentBatchDraftProvider.notifier).saveFreshDraft(
        stagedFiles: _stagedFreshFiles, parsedStudents: revised,
        sectionFilter: _selectedFreshSectionFilter);
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not review sections: $e');
    }
  }

  void _removeFreshStudentRow(Map<String, dynamic> student) {
    final targetId = (student['id_number'] ?? '').toString().trim();
    setState(() {
      _parsedFreshStudents.removeWhere(
        (s) => identical(s, student) || (s['id_number'] ?? '').toString().trim() == targetId,
      );
      if (_parsedFreshStudents.isEmpty) {
        _stagedFreshFiles.clear();
        _selectedFreshSectionFilter = 'ALL';
      }
    });
    if (_parsedFreshStudents.isEmpty) {
      ref.read(studentBatchDraftProvider.notifier).clearFreshDraft();
    } else {
      ref.read(studentBatchDraftProvider.notifier).saveFreshDraft(
        stagedFiles: _stagedFreshFiles,
        parsedStudents: _parsedFreshStudents,
        sectionFilter: _selectedFreshSectionFilter,
      );
    }
  }

  void _removeAllBlockedFreshRows([Map<String, dynamic>? activeSem]) {
    setState(() {
      _parsedFreshStudents.removeWhere((s) => _isFreshRowBlocking(s, activeSem));
      if (_parsedFreshStudents.isEmpty) {
        _stagedFreshFiles.clear();
        _selectedFreshSectionFilter = 'ALL';
      }
    });
    if (_parsedFreshStudents.isEmpty) {
      ref.read(studentBatchDraftProvider.notifier).clearFreshDraft();
    } else {
      ref.read(studentBatchDraftProvider.notifier).saveFreshDraft(
        stagedFiles: _stagedFreshFiles,
        parsedStudents: _parsedFreshStudents,
        sectionFilter: _selectedFreshSectionFilter,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;

    _dropSubscription = setupDropzoneListener(
      _handleFilesDropped,
      onDragStateChanged: (isDragging) {
        if (mounted && _isDraggingFile != isDragging) {
          setState(() => _isDraggingFile = isDragging);
        }
      },
    );

    // Restore draft state if available
    final draft = ref.read(studentBatchDraftProvider);
    if (draft.hasFreshDraft) {
      _stagedFreshFiles = List.from(draft.freshStagedFiles);
      _parsedFreshStudents = List.from(draft.freshParsedStudents);
      _selectedFreshSectionFilter = draft.freshSectionFilter;
    }
    if (draft.hasRolloverDraft) {
      _stagedRolloverFiles = List.from(draft.rolloverStagedFiles);
      _rolloverActions.addAll(draft.rolloverActions);
      _selectedSectionFilter = draft.rolloverSectionFilter;
      _selectedYearFilter = draft.rolloverYearFilter;
      _hasCsvUploaded = draft.hasRolloverCsv;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_parsedFreshStudents.isNotEmpty) {
        _resolveFreshSections(_parsedFreshStudents).then((_) {
          if (mounted) setState(() {});
        }).catchError((_) {});
      }
      if (_currentMode == StudentHubMode.semesterRollover) {
        if (_stagedRolloverFiles.isNotEmpty) {
          _reprocessStagedRolloverDraft(_stagedRolloverFiles);
        } else {
          _loadInitialRolloverData();
        }
      }
    });
  }

  @override
  void dispose() {
    _dropSubscription?.cancel();
    _rolloverSearchCtrl.dispose();
    _freshSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleFilesDropped(List<PickedTabularFile> files) async {
    if (!mounted || files.isEmpty) return;
    try {
      if (_currentMode == StudentHubMode.freshIntake) {
        final merged = List<PickedTabularFile>.from(_stagedFreshFiles);
        for (final file in files) {
          final exists = merged.any(
            (existing) => existing.name == file.name && existing.bytes.length == file.bytes.length,
          );
          if (!exists) {
            merged.add(file);
          }
        }
        await _openFreshStagingModal(merged);
      } else {
        final merged = List<PickedTabularFile>.from(_stagedRolloverFiles);
        for (final file in files) {
          final exists = merged.any(
            (existing) => existing.name == file.name && existing.bytes.length == file.bytes.length,
          );
          if (!exists) {
            merged.add(file);
          }
        }
        await _openRolloverStagingModal(merged);
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Could not process dropped file(s): $e');
      }
    }
  }

  Future<void> _loadInitialRolloverData() async {
    await ref
        .read(studentAcademicRecordsProvider.notifier)
        .fetchRolloverPreview(students: []);
  }

  Future<void> _reprocessStagedRolloverDraft(List<PickedTabularFile> files) async {
    final activeSem = ref.read(academicPeriodProvider).activeSemester ??
        widget.academicState.activeSemester ??
        ref.read(studentAcademicRecordsProvider).activeSemester;
    final allStudents = <Map<String, dynamic>>[];
    final byStudentId = <String, Map<String, dynamic>>{};
    for (final file in files) {
      final official = file.isXlsx
          ? parseOfficialClassListXlsx(file.bytes)
          : parseOfficialClassListCsv(file.text ?? utf8.decode(file.bytes, allowMalformed: true));
      if (_validateParsedFileTerm(official.metadata, activeSem) != null) {
        continue;
      }
      for (final s in official.students) {
        final idKey = (s['id_number'] ?? s['student_number'] ?? '').toString().trim().toLowerCase();
        if (idKey.isNotEmpty && byStudentId.containsKey(idKey)) continue;
        if (idKey.isNotEmpty) byStudentId[idKey] = s;
        allStudents.add(s);
      }
    }
    if (allStudents.isNotEmpty) {
      await ref
          .read(studentAcademicRecordsProvider.notifier)
          .fetchRolloverPreview(students: allStudents);
    } else {
      await _loadInitialRolloverData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSem =
        ref.watch(academicPeriodProvider).activeSemester ??
        widget.academicState.activeSemester ??
        ref.watch(studentAcademicRecordsProvider).activeSemester;
    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          LayoutBuilder(
            builder: (context, constraints) {
              final back = DefensysShadcnScope(
                child: ShadButton.outline(
                  onPressed: widget.onBack,
                  leading: const Icon(Icons.arrow_back_rounded, size: 16),
                  child: const Text('Back to Students'),
                ),
              );
              final narrow = constraints.maxWidth < 600;
              final header = DefensysPageHeader(
                icon: Icons.dynamic_feed_rounded,
                title: 'Student enrollment',
                subtitle:
                    'Import university class lists and review enrollment details.',
                actions: narrow ? null : back,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  if (narrow) ...[const SizedBox(height: 12), back],
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Active drag-and-drop indicator banner
          if (_isDraggingFile) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _maroon, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _maroon.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _maroon.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.file_download_rounded,
                      color: _maroon,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentMode == StudentHubMode.freshIntake
                              ? 'Drop Class List Source File(s) to Stage'
                              : 'Drop Rollover Class List File(s) to Stage',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: _maroon,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Release mouse anywhere to automatically stage and inspect class lists (.csv / .xlsx)',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: DefensysUi.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Top Mode Switcher (Segmented Control)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 420) {
                return DefensysShadcnScope(
                  maroonActions: true,
                  neutralActionText: true,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in StudentHubMode.values)
                        Semantics(
                          selected: _currentMode == mode,
                          child: ShadButton.raw(
                            variant: _currentMode == mode
                                ? ShadButtonVariant.primary
                                : ShadButtonVariant.outline,
                            onPressed: () => _changeMode(mode),
                            child: Text(
                              mode == StudentHubMode.freshIntake
                                  ? 'Import class lists'
                                  : 'Semester rollover',
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }
              return DefensysSegmentedControl<StudentHubMode>(
                value: _currentMode,
                height: 50,
                items: const [
                  DefensysSegmentItem(
                    value: StudentHubMode.freshIntake,
                    label: 'Import class lists',
                    icon: Icons.file_upload_outlined,
                  ),
                  DefensysSegmentItem(
                    value: StudentHubMode.semesterRollover,
                    label: 'Semester rollover',
                    icon: Icons.rotate_right_rounded,
                  ),
                ],
                onChanged: _changeMode,
              );
            },
          ),

          const SizedBox(height: 24),

          if (activeSem == null) ...[
            DefensysActionBanner(
              title: 'Active Academic Semester Required for Student Enrollment',
              description:
                  'No semester is currently active. Create and activate an academic semester in Academic Periods to enroll students or roll over returning cohorts.',
              actionLabel: 'Open Academic Periods',
              onAction: () => context.go(AdminRoutes.academicPeriods),
              isBlocking: true,
            ),
            const SizedBox(height: 20),
          ],

          // Active Mode Content
          if (_currentMode == StudentHubMode.freshIntake)
            _buildFreshIntakeView()
          else
            _buildSemesterRolloverView(),
        ],
      ),
    );
  }

  Widget _headerPill(
    String text, {
    Color? textColor,
    Color? bgColor,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor ?? const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor ?? const Color(0xFFE5E7EB)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor ?? const Color(0xFF5D6678),
        ),
      ),
    );
  }

  void _changeMode(StudentHubMode mode) {
    if (_currentMode == mode) return;
    setState(() => _currentMode = mode);
    if (mode == StudentHubMode.semesterRollover) {
      if (_stagedRolloverFiles.isNotEmpty) {
        _reprocessStagedRolloverDraft(_stagedRolloverFiles);
      } else {
        _loadInitialRolloverData();
      }
    }
  }

  // -------------------------------------------------------------
  // Mode 1: Fresh Student Intake View (Zero-Fillup 2-Column + Preflight)
  // -------------------------------------------------------------
  Widget _buildFreshIntakeView() {
    final activeSem =
        ref.watch(academicPeriodProvider).activeSemester ??
        widget.academicState.activeSemester ??
        ref.watch(studentAcademicRecordsProvider).activeSemester;
    final activeSemLabel =
        activeSem?['display_name'] ??
        '${activeSem?['school_year'] ?? 'Current Year'} - ${activeSem?['label'] ?? 'Active Term'}';

    final sectionCounts = <String, int>{};
    for (final s in _parsedFreshStudents) {
      final label = _freshSectionLabel(s);
      sectionCounts[label] = (sectionCounts[label] ?? 0) + 1;
    }

    _reconcileFreshFilters();
    final filtered = _parsedFreshStudents.where((s) {
      final q = _freshSearchCtrl.text.trim().toLowerCase();
      final idNum = s['id_number']?.toString().toLowerCase() ?? '';
      final name = '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'
          .toLowerCase();
      final email = s['email']?.toString().toLowerCase() ?? '';
      final matchQuery =
          q.isEmpty ||
          idNum.contains(q) ||
          name.contains(q) ||
          email.contains(q);
      if (!matchQuery) return false;

      if (_selectedFreshSectionFilter != 'ALL') {
        final label = _freshSectionLabel(s);
        if (label != _selectedFreshSectionFilter) return false;
      }
      if (_selectedFreshYearFilter != 'ALL' &&
          _freshYear(s) != _selectedFreshYearFilter) {
        return false;
      }
      if (_selectedFreshStatusFilter != 'ALL' &&
          _freshStatus(s, activeSem).name != _selectedFreshStatusFilter) {
        return false;
      }
      return true;
    }).toList();

    return DefensysShadcnScope(
      maroonActions: true,
      neutralActionText: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enrollment term: ${activeSem == null ? 'No active semester' : activeSemLabel}',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontSize: 13,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          _buildFreshUploadCard(),
          const SizedBox(height: 24),
          _buildFreshReviewTableCard(
            filtered: filtered,
            sectionCounts: sectionCounts,
            totalStudents: _parsedFreshStudents.length,
            activeSem: activeSem,
          ),
        ],
      ),
    );
  }

  void _showClassListFormatGuideModal(
    BuildContext context, {
    required bool isRollover,
    required String activeSemLabel,
  }) {
    int selectedTab = 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final bp = studentIntakeBlueprints[selectedTab];

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880, maxHeight: 740),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Modal Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _maroon.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.grid_on_rounded, color: _maroon, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isRollover
                                      ? 'Official University Class List Blueprint (Rollover / Continuing)'
                                      : 'Official University Class List Blueprint (Student Intake)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: _ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Target Term: $activeSemLabel • Interactive guide for supported intake layouts',
                                  style: const TextStyle(fontSize: 12, color: _muted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20, color: _muted),
                            splashRadius: 18,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: _line),

                    // Interactive Tab Switcher
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      color: const Color(0xFFF8FAFC),
                      child: Row(
                        children: [
                          for (int i = 0; i < studentIntakeBlueprints.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () => setModalState(() => selectedTab = i),
                                borderRadius: BorderRadius.circular(8),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selectedTab == i ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: selectedTab == i ? _maroon : const Color(0xFFCBD5E1),
                                      width: selectedTab == i ? 1.5 : 1,
                                    ),
                                    boxShadow: selectedTab == i
                                        ? const [
                                            BoxShadow(
                                              color: Color(0x0A000000),
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        studentIntakeBlueprints[i].icon,
                                        size: 16,
                                        color: selectedTab == i ? _maroon : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          studentIntakeBlueprints[i].shortLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: selectedTab == i ? FontWeight.w800 : FontWeight.w600,
                                            color: selectedTab == i ? _ink : const Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: studentIntakeBlueprints[i].badgeBg,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          studentIntakeBlueprints[i].badgeText,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: studentIntakeBlueprints[i].badgeFg,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: _line),

                    // Scrollable Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Compact, Minimal Guidance Bar
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      selectedTab == 0
                                          ? 'Official USTP LIST OF ENROLLMENT format. Multi-page intervals, repeated headers, and cohorts across all pages are read directly with no editing required.'
                                          : 'Class-specific intake. Students are enrolled directly into the section specified in Row 10.',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: const Text(
                                      'Auto-Detected',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Spreadsheet Preview
                            _buildSampleClassListPreview(
                              isRollover: isRollover,
                              selectedTab: selectedTab,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Divider(height: 1, color: _line),
                    // Modal Footer
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await downloadTextFile(
                                    filename: bp.filename,
                                    content: bp.rawCsv,
                                  );
                                  if (context.mounted) {
                                    showSuccessToast(context, 'Sample ${bp.shortLabel} template downloaded.');
                                  }
                                },
                                icon: const Icon(Icons.download_rounded, size: 15),
                                label: Text('Download ${bp.shortLabel} Template (.csv)'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _ink,
                                  side: const BorderSide(color: _line),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: bp.rawCsv));
                                  if (context.mounted) {
                                    showSuccessToast(context, 'Copied ${bp.shortLabel} sample CSV to clipboard!');
                                  }
                                },
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                label: const Text('Copy Sample CSV'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _ink,
                                  side: const BorderSide(color: _line),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _maroon,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSampleClassListPreview({
    bool isRollover = false,
    int selectedTab = 0,
  }) {
    final bp = studentIntakeBlueprints[selectedTab];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spreadsheet Window Titlebar & Sheet Tab
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1))),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 12, color: Color(0xFF475569)),
                      const SizedBox(width: 5),
                      Text(
                        bp.filename,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildMiniBadge(bp.badgeText, bp.badgeBg, bp.badgeFg),
              ],
            ),
          ),

          if (selectedTab == 0) ...[
            // USTP LIST OF ENROLLMENT Layout (Authentic Client Format)
            _buildOfficialHeaderRow(
              rowNumber: '1',
              keyName: 'LIST OF ENROLLMENT',
              valueText: '',
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildOfficialHeaderRow(
              rowNumber: '2',
              keyName: 'Academic Term',
              valueText: '2026-2027 1st Semester',
              badgeText: 'Auto-Detected Term',
              badgeBg: const Color(0xFFF1F5F9),
              badgeFg: const Color(0xFF334155),
              isRequired: true,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildOfficialHeaderRow(
              rowNumber: '3',
              keyName: 'Program',
              valueText: 'Bachelor of Science in Information Technology',
              secondaryKey: 'Officially Enrolled',
              secondaryValue: '143',
              badgeText: 'Enrollment Summary (Auto-Skipped)',
              badgeBg: const Color(0xFFF1F5F9),
              badgeFg: const Color(0xFF64748B),
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildOfficialHeaderRow(
              rowNumber: '5',
              keyName: 'TOTAL',
              valueText: '143 Officially Enrolled',
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildOfficialHeaderRow(
              rowNumber: '7',
              keyName: 'LIST OF ENROLLMENT',
              valueText: '',
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildOfficialHeaderRow(
              rowNumber: '8',
              keyName: 'Academic Term',
              valueText: '2026-2027 1st Semester',
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildOfficialHeaderRow(
              rowNumber: '9',
              keyName: 'Program',
              valueText: 'Bachelor of Science in Information Technology',
              badgeText: 'Auto-Detected Degree',
              badgeBg: const Color(0xFFF1F5F9),
              badgeFg: const Color(0xFF334155),
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFCBD5E1)),

            // Row 10: Column Headers
            Container(
              color: const Color(0xFFE2E8F0),
              child: Row(
                children: [
                  _buildGutterCell('10', isHeader: true),
                  _buildColumnHeaderCell('#', flex: 1),
                  _buildColumnHeaderCell('Student No', flex: 3, isRequired: true),
                  _buildColumnHeaderCell('Name', flex: 4, isRequired: true),
                  _buildColumnHeaderCell('Program', flex: 2),
                  _buildColumnHeaderCell('Major', flex: 2),
                  _buildColumnHeaderCell('Level', flex: 2, isRequired: true),
                  _buildColumnHeaderCell('Gender', flex: 2),
                  _buildColumnHeaderCell('Status', flex: 3),
                  _buildColumnHeaderCell('Date', flex: 2),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFCBD5E1)),

            // Sample Student rows
            _buildUstpEnrollmentStudentRow(
              rowNumber: '11',
              index: '1',
              id: '2024-00001',
              name: 'DELA CRUZ, Juan',
              prog: 'BSIT',
              major: '',
              level: '2nd Year',
              gen: 'M',
              status: 'Officially Enrolled',
              date: '06/22/2026',
              isAlt: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildUstpEnrollmentStudentRow(
              rowNumber: '12',
              index: '2',
              id: '2024-00002',
              name: 'SANTOS, Maria',
              prog: 'BSIT',
              major: '',
              level: '2nd Year',
              gen: 'F',
              status: 'Officially Enrolled',
              date: '06/22/2026',
              isAlt: true,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildUstpEnrollmentStudentRow(
              rowNumber: '13',
              index: '3',
              id: '2024-00003',
              name: 'REYES, Mark',
              prog: 'BSIT',
              major: '',
              level: '2nd Year',
              gen: 'M',
              status: 'Officially Enrolled',
              date: '06/22/2026',
              isAlt: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Page Interval Indicator (Images 2 & 3)
            _buildPageIntervalIndicatorRow(
              rowNumber: '54',
              title: 'Print Info: Page 2 of 4  •  Monday 22 June 2026',
              badgeText: 'Auto-Skipped Page Interval',
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildOfficialHeaderRow(
              rowNumber: '57',
              keyName: 'LIST OF ENROLLMENT',
              valueText: '2026-2027 1st Semester • BSIT',
              badgeText: 'Repeated Header (Auto-Skipped)',
              badgeBg: const Color(0xFFFEF3C7),
              badgeFg: const Color(0xFF92400E),
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Sample Student row from Page 2
            _buildUstpEnrollmentStudentRow(
              rowNumber: '59',
              index: '51',
              id: '2024-00051',
              name: 'TORRES, Miguel',
              prog: 'BSIT',
              major: '',
              level: '2nd Year',
              gen: 'M',
              status: 'Officially Enrolled',
              date: '06/22/2026',
              isAlt: false,
            ),
          ] else ...[
            // Existing By-Section Layout (UNTOUCHED)
            _buildOfficialHeaderRow(
              rowNumber: '1',
              keyName: 'OFFICIAL LIST OF ENROLLED STUDENTS',
              valueText: '',
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Row 2: Term (HIGHLIGHTED - REQUIRED)
            _buildOfficialHeaderRow(
              rowNumber: '2',
              keyName: 'Academic Term',
              valueText: '2026-2027 1st Semester',
              badgeText: 'Auto-Detected Term',
              badgeBg: const Color(0xFFF1F5F9),
              badgeFg: const Color(0xFF334155),
              isRequired: true,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Row 4 & 5: Subject Code & Title (Standard Metadata)
            _buildOfficialHeaderRow(
              rowNumber: '4',
              keyName: 'Subject Code',
              valueText: isRollover ? 'CAP402' : 'IT111',
              secondaryKey: 'Subject Title',
              secondaryValue: isRollover ? 'Capstone Project 2' : 'Introduction to Computing',
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Row 6 & 8: Units & Mode (Standard Metadata)
            _buildOfficialHeaderRow(
              rowNumber: '6',
              keyName: 'Academic Units',
              valueText: '3 (Lab Units: 1)',
              secondaryKey: 'Mode',
              secondaryValue: 'Lecture and Laboratory',
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Row 9: Instructor (For By-Section)
            _buildOfficialHeaderRow(
              rowNumber: '9',
              keyName: isRollover ? 'Adviser / Faculty' : 'Instructor',
              valueText: isRollover ? 'Prof. Alex Santos' : 'Prof. Maria Santos',
              badgeText: isRollover ? 'Optional for Capstone' : 'Auto-Detected Instructor',
              badgeBg: const Color(0xFFF1F5F9),
              badgeFg: const Color(0xFF334155),
              isRequired: !isRollover,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Row 10: Class Section (For By-Section)
            _buildOfficialHeaderRow(
              rowNumber: '10',
              keyName: 'Class Section',
              valueText: isRollover ? 'BSIT-4A' : 'BSIT-1A',
              badgeText: 'Auto-Detected Section',
              badgeBg: const Color(0xFFF1F5F9),
              badgeFg: const Color(0xFF334155),
              isRequired: true,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Row 11: Year Level
            _buildOfficialHeaderRow(
              rowNumber: '11',
              keyName: 'Year Level',
              valueText: isRollover ? '4th Year' : '1st Year',
              badgeText: 'Auto-Detected Year Level',
              badgeBg: const Color(0xFFF1F5F9),
              badgeFg: const Color(0xFF334155),
              isRequired: true,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Row 12: Schedule (Standard Metadata)
            _buildOfficialHeaderRow(
              rowNumber: '12',
              keyName: 'Schedule(s)',
              valueText: 'M 1:00 PM - 3:00 PM',
              isRequired: false,
            ),
            const Divider(height: 1, color: Color(0xFFCBD5E1)),

            // Row 14: Column Headers (with Required column highlights)
            Container(
              color: const Color(0xFFE2E8F0),
              child: Row(
                children: [
                  _buildGutterCell('14', isHeader: true),
                  _buildColumnHeaderCell('#', flex: 1),
                  _buildColumnHeaderCell('Student Number', flex: 3, isRequired: true),
                  _buildColumnHeaderCell('Full Name', flex: 4, isRequired: true),
                  _buildColumnHeaderCell('Program', flex: 2),
                  _buildColumnHeaderCell('Gender', flex: 2),
                  _buildColumnHeaderCell('Level', flex: 2),
                  _buildColumnHeaderCell('Email', flex: 4, isRequired: true),
                  _buildColumnHeaderCell('Contact', flex: 3),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFCBD5E1)),

            // Rows 15 & 16: Sample Student Records
            _buildOfficialStudentRow(
              rowNumber: '15',
              index: '1',
              id: '2024-00001',
              name: 'DELA CRUZ, Juan',
              prog: 'BSIT',
              gen: 'M',
              level: isRollover ? '4th Yr.' : '1st Yr.',
              email: '202400001@university.edu.ph',
              contact: '09170000001',
              isAlt: false,
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            _buildOfficialStudentRow(
              rowNumber: '16',
              index: '2',
              id: '2024-00002',
              name: 'SANTOS, Maria',
              prog: 'BSIT',
              gen: 'F',
              level: isRollover ? '4th Yr.' : '1st Yr.',
              email: '202400002@university.edu.ph',
              contact: '09170000002',
              isAlt: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOfficialHeaderRow({
    required String rowNumber,
    required String keyName,
    required String valueText,
    String? secondaryKey,
    String? secondaryValue,
    String? badgeText,
    Color? badgeBg,
    Color? badgeFg,
    required bool isRequired,
  }) {
    return Container(
      color: isRequired ? const Color(0xFFF8FAFC) : Colors.white,
      child: Row(
        children: [
          _buildGutterCell(rowNumber),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    valueText.isEmpty ? keyName : '$keyName: ',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isRequired ? FontWeight.w800 : FontWeight.w600,
                      color: isRequired ? _ink : const Color(0xFF64748B),
                    ),
                  ),
                  if (valueText.isNotEmpty)
                    Text(
                      valueText,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: isRequired ? FontWeight.w800 : FontWeight.w600,
                        color: isRequired ? const Color(0xFF1E293B) : const Color(0xFF475569),
                      ),
                    ),
                  if (secondaryKey != null && secondaryValue != null) ...[
                    const Text('   |   ', style: TextStyle(fontSize: 10, color: Color(0xFFCBD5E1))),
                    Text(
                      '$secondaryKey: ',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                    ),
                    Text(
                      secondaryValue,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (badgeText != null && badgeBg != null && badgeFg != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildMiniBadge(badgeText, badgeBg, badgeFg),
            ),
        ],
      ),
    );
  }

  Widget _buildColumnHeaderCell(String title, {required int flex, bool isRequired = false}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isRequired ? FontWeight.w900 : FontWeight.w700,
                  color: isRequired ? _maroon : const Color(0xFF475569),
                ),
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 2),
              const Text(
                '*',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _maroon),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOfficialStudentRow({
    required String rowNumber,
    required String index,
    required String id,
    required String name,
    required String prog,
    required String gen,
    required String level,
    required String email,
    required String contact,
    bool isAlt = false,
  }) {
    return Container(
      color: isAlt ? const Color(0xFFF8FAFC) : Colors.white,
      child: Row(
        children: [
          _buildGutterCell(rowNumber),
          Expanded(flex: 1, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(index, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(id, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _ink)))),
          Expanded(flex: 4, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(name, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _ink)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(prog, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(gen, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(level, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
          Expanded(flex: 4, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: _muted)))),
          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(contact, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
        ],
      ),
    );
  }

  Widget _buildUstpEnrollmentStudentRow({
    required String rowNumber,
    required String index,
    required String id,
    required String name,
    required String prog,
    required String major,
    required String level,
    required String gen,
    required String status,
    required String date,
    bool isAlt = false,
  }) {
    return Container(
      color: isAlt ? const Color(0xFFF8FAFC) : Colors.white,
      child: Row(
        children: [
          _buildGutterCell(rowNumber),
          Expanded(flex: 1, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(index, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(id, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _ink)))),
          Expanded(flex: 4, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(name, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _ink)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(prog, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(major, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(level, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF334155))))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(gen, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF047857), fontWeight: FontWeight.w600)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: Text(date, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))))),
        ],
      ),
    );
  }

  Widget _buildPageIntervalIndicatorRow({
    required String rowNumber,
    required String title,
    required String badgeText,
  }) {
    return Container(
      color: const Color(0xFFFFFBEB),
      child: Row(
        children: [
          _buildGutterCell(rowNumber),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildMiniBadge(
              badgeText,
              const Color(0xFFFEF3C7),
              const Color(0xFF92400E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGutterCell(String rowNum, {bool isHeader = false}) {
    return Container(
      width: 26,
      padding: const EdgeInsets.symmetric(vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isHeader ? const Color(0xFFCBD5E1) : const Color(0xFFF8FAFC),
        border: const Border(right: BorderSide(color: Color(0xFFCBD5E1))),
      ),
      child: Text(
        rowNum,
        style: TextStyle(
          fontSize: 10,
          fontWeight: isHeader ? FontWeight.w900 : FontWeight.w600,
          color: isHeader ? const Color(0xFF334155) : const Color(0xFF94A3B8),
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildFormatPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildFreshUploadCard() {
    final hasFiles = _stagedFreshFiles.isNotEmpty;
    final primary = DefensysTokens.textPrimaryOf(context);
    final secondary = DefensysTokens.textSecondaryOf(context);
    return DefensysCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasFiles) ...[
            Text(
              'Upload university class lists',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceHigherOf(context),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                border: Border.all(
                  color: _isDraggingFile
                      ? DefensysTokens.maroonOf(context)
                      : DefensysTokens.borderOf(context),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Text(
                    _isDraggingFile
                        ? 'Release files to review them.'
                        : 'Drop CSV or XLSX files here, or choose files.',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 13,
                      color: secondary,
                    ),
                  ),
                  ShadButton(
                    enabled: !_freshControlsBusy,
                    onPressed: _freshControlsBusy ? null : _pickFreshFiles,
                    leading: const Icon(Icons.upload_file_outlined, size: 16),
                    child: const Text('Choose files'),
                  ),
                ],
              ),
            ),
          ] else ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  '${_stagedFreshFiles.length} ${_stagedFreshFiles.length == 1 ? 'file' : 'files'} added',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ShadButton.outline(
                      enabled: !_freshControlsBusy,
                      onPressed: _freshControlsBusy ? null : _pickFreshFiles,
                      leading: const Icon(Icons.add, size: 16),
                      child: const Text('Add files'),
                    ),
                    ShadButton.outline(
                      enabled: !_freshControlsBusy,
                      onPressed: _freshControlsBusy
                          ? null
                          : () => _openFreshStagingModal(_stagedFreshFiles),
                      child: const Text('Review files'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < _stagedFreshFiles.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final file = _stagedFreshFiles[index];
                    final name = Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: secondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Tooltip(
                            message: file.name,
                            child: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                                fontSize: 13,
                                color: primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                    final actions = Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ShadButton.ghost(
                          size: ShadButtonSize.sm,
                          enabled: !_freshControlsBusy,
                          onPressed: _freshControlsBusy
                              ? null
                              : () => _replaceFreshFile(index),
                          child: const Text('Replace'),
                        ),
                        ShadButton.ghost(
                          size: ShadButtonSize.sm,
                          enabled: !_freshControlsBusy,
                          onPressed: _freshControlsBusy
                              ? null
                              : () => _removeFreshFile(index),
                          child: const Text('Remove'),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [name, const SizedBox(height: 6), actions],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: name),
                        const SizedBox(width: 12),
                        actions,
                      ],
                    );
                  },
                ),
              ),
          ],
          if (hasFiles || _parsedFreshStudents.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                enabled: !_freshControlsBusy,
                onPressed: _freshControlsBusy ? null : _clearFreshFiles,
                child: const Text('Clear files'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _validateParsedFileTerm(Map<String, dynamic> metadata, Map<String, dynamic>? activeSem) {
    if (activeSem == null) return null;
    final targetSy = (activeSem['school_year'] ?? '').toString().trim();
    final targetSem = (activeSem['label'] ?? '').toString().trim();
    if (targetSy.isEmpty && targetSem.isEmpty) return null;

    final fileSy = (metadata['school_year'] ?? '').toString().trim();
    final fileSem = (metadata['semester'] ?? '').toString().trim();
    if (fileSy.isEmpty && fileSem.isEmpty) return null; // Custom CSV without preamble is allowed

    final syMismatch = fileSy.isNotEmpty && targetSy.isNotEmpty && fileSy != targetSy;
    final semMismatch = fileSem.isNotEmpty && targetSem.isNotEmpty && fileSem.toLowerCase() != targetSem.toLowerCase();

    if (syMismatch || semMismatch) {
      final fileTerm = [if (fileSem.isNotEmpty) fileSem, if (fileSy.isNotEmpty) 'A.Y. $fileSy'].join(', ');
      final targetTerm = [if (targetSem.isNotEmpty) targetSem, if (targetSy.isNotEmpty) 'A.Y. $targetSy'].join(', ');
      return 'Academic term mismatch: Staged file is for $fileTerm, but the active semester is $targetTerm.';
    }
    return null;
  }

  String? _freshRowTermMismatchError(Map<String, dynamic> s, [Map<String, dynamic>? activeSem]) {
    final meta = s['_fileMetadata'];
    if (meta is Map) {
      return _validateParsedFileTerm(Map<String, dynamic>.from(meta), activeSem);
    }
    return null;
  }

  bool _isFreshRowBlocking(Map<String, dynamic> s, [Map<String, dynamic>? activeSem]) {
    if (_freshRowTermMismatchError(s, activeSem) != null) return true;
    if ((s['_client_validation_error'] ?? '').toString().trim().isNotEmpty) return true;
    final res = s['_section_resolution'] as Map?;
    if (res == null) return false;
    if (res['blocking'] == true) return true;
    if (res['source'] == 'review') return true;
    return false;
  }

  String _freshSectionLabel(Map<String, dynamic> student) {
    final section = _freshSection(student);
    return section.isEmpty ||
            ['unassigned', 'null'].contains(section.toLowerCase())
        ? 'Unassigned'
        : section;
  }

  String _freshYear(Map<String, dynamic> student) {
    final year = normalizeYearLevel((student['year_level'] ?? '').toString());
    return year.isEmpty ? 'Unspecified' : year;
  }

  _FreshReviewStatus _freshStatus(
    Map<String, dynamic> student,
    Map<String, dynamic>? activeSem,
  ) {
    if (activeSem == null || _isFreshRowBlocking(student, activeSem)) {
      return _FreshReviewStatus.needsAttention;
    }
    return switch ((student['_section_resolution'] as Map?)?['status_code']) {
      'already_enrolled' => _FreshReviewStatus.alreadyEnrolled,
      'update_section' => _FreshReviewStatus.updatesSection,
      'existing_student' => _FreshReviewStatus.existingStudent,
      _ => _FreshReviewStatus.ready,
    };
  }

  void _reconcileFreshFilters() {
    final years = _parsedFreshStudents.map(_freshYear).toSet();
    final sections = _parsedFreshStudents.map(_freshSectionLabel).toSet();
    // These are local view selections; no draft writes or notifications in build.
    if (years.length <= 1 || !years.contains(_selectedFreshYearFilter)) {
      _selectedFreshYearFilter = 'ALL';
    }
    if (sections.length <= 1 ||
        !sections.contains(_selectedFreshSectionFilter)) {
      _selectedFreshSectionFilter = 'ALL';
    }
  }

  bool get _hasFreshFilters =>
      _freshSearchCtrl.text.trim().isNotEmpty ||
      _selectedFreshYearFilter != 'ALL' ||
      _selectedFreshSectionFilter != 'ALL' ||
      _selectedFreshStatusFilter != 'ALL';

  void _clearFreshFilters() {
    setState(() {
      _freshSearchCtrl.clear();
      _selectedFreshYearFilter = 'ALL';
      _selectedFreshSectionFilter = 'ALL';
      _selectedFreshStatusFilter = 'ALL';
      _freshPage = 0;
    });
  }

  Widget _buildFreshFilter({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Semantics(
      label: label,
      child: ShadSelect<String>(
        key: ValueKey(
          'fresh-${label.toLowerCase().replaceAll(' ', '-')}-filter',
        ),
        initialValue: value,
        minWidth: label == 'Status' ? 192 : 145,
        maxWidth: label == 'Status' ? 240 : 200,
        options: [
          for (final entry in options.entries)
            ShadOption(value: entry.key, child: Text(entry.value)),
        ],
        selectedOptionBuilder: (_, selected) => Tooltip(
          message: options[selected] ?? options['ALL']!,
          child: Text(
            options[selected] ?? options['ALL']!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        onChanged: (next) {
          if (next == null) return;
          setState(() {
            onChanged(next);
            _freshPage = 0;
          });
        },
      ),
    );
  }

  Widget _buildFreshFilterToolbar(
    Map<String, int> sectionCounts,
    Map<_FreshReviewStatus, int> statusCounts,
    int matchingCount,
  ) {
    final yearCounts = <String, int>{};
    for (final student in _parsedFreshStudents) {
      yearCounts.update(_freshYear(student), (n) => n + 1, ifAbsent: () => 1);
    }
    const recognizedYears = ['1st Year', '2nd Year', '3rd Year', '4th Year'];
    final years = yearCounts.keys.toList()
      ..sort((a, b) {
        final ai = recognizedYears.indexOf(a);
        final bi = recognizedYears.indexOf(b);
        if (ai >= 0 || bi >= 0) {
          return (ai < 0 ? 4 : ai).compareTo(bi < 0 ? 4 : bi);
        }
        return a.compareTo(b);
      });
    final sections = sectionCounts.keys.toList()..sort();
    final search = ShadInput(
      controller: _freshSearchCtrl,
      leading: Icon(
        Icons.search_rounded,
        size: 18,
        color: DefensysTokens.textSecondaryOf(context),
      ),
      placeholder: const Text('Search by student ID, name, or email...'),
      onChanged: (_) => setState(() => _freshPage = 0),
    );
    final dropdowns = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (years.length > 1)
          _buildFreshFilter(
            label: 'Year level',
            value: _selectedFreshYearFilter,
            options: {
              'ALL': 'All years',
              for (final year in years) year: '$year (${yearCounts[year]})',
            },
            onChanged: (value) => _selectedFreshYearFilter = value,
          ),
        if (sections.length > 1)
          _buildFreshFilter(
            label: 'Section',
            value: _selectedFreshSectionFilter,
            options: {
              'ALL': 'All sections',
              for (final section in sections)
                section: '$section (${sectionCounts[section]})',
            },
            onChanged: (value) => _selectedFreshSectionFilter = value,
          ),
        if (_parsedFreshStudents.isNotEmpty)
          _buildFreshFilter(
            label: 'Status',
            value: _selectedFreshStatusFilter,
            options: {
              'ALL': 'All statuses',
              for (final status in _FreshReviewStatus.values)
                status.name: '${status.label} (${statusCounts[status] ?? 0})',
            },
            onChanged: (value) => _selectedFreshStatusFilter = value,
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 1000) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [search, const SizedBox(height: 8), dropdowns],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  dropdowns,
                ],
              );
            },
          ),
          if (_hasFreshFilters) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'Showing $matchingCount of ${_parsedFreshStudents.length} students',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: _clearFreshFilters,
                  child: const Text('Clear filters'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Use the same column widths for the header and every data row.
  Widget _freshTableColumns(List<Widget> cells) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      for (var i = 0; i < 4; i++)
        Expanded(
          flex: [4, 1, 3, 3][i],
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: cells[i],
          ),
        ),
      SizedBox(width: 32, child: cells[4]),
    ],
  );

  Widget _buildFreshStatusBadge(
    Map<String, dynamic> student,
    Map<String, dynamic>? activeSem,
  ) {
    final status = _freshStatus(student, activeSem);
    final resolution = student['_section_resolution'] as Map?;
    final termMismatch = _freshRowTermMismatchError(student, activeSem);
    final clientError = (student['_client_validation_error'] ?? '')
        .toString()
        .trim();
    final dark = DefensysTokens.isDark(context);
    final (accent, foreground) = switch (status) {
      _FreshReviewStatus.needsAttention => (
        DefensysTokens.danger,
        dark ? DefensysTokens.danger : DefensysTokens.dangerText,
      ),
      _FreshReviewStatus.alreadyEnrolled ||
      _FreshReviewStatus.updatesSection => (
        DefensysTokens.warning,
        dark ? DefensysTokens.warning : DefensysTokens.warningText,
      ),
      _FreshReviewStatus.existingStudent => (
        DefensysTokens.techBlue,
        dark ? Colors.lightBlueAccent : DefensysTokens.infoText,
      ),
      _ => (
        DefensysTokens.success,
        dark ? DefensysTokens.success : DefensysTokens.successText,
      ),
    };
    final String label;
    final String reason;
    if (activeSem == null) {
      label = 'Blocked (No Active Term)';
      reason =
          'Configure an active semester in Academic Periods before enrollment.';
    } else if (status == _FreshReviewStatus.needsAttention) {
      label = termMismatch != null
          ? 'Blocked (Term Mismatch)'
          : (resolution?['status_label'] ??
                    (clientError.isNotEmpty
                        ? 'Blocked (File Conflict)'
                        : 'Needs Review'))
                .toString();
      reason =
          termMismatch ??
          (clientError.isNotEmpty
              ? clientError
              : (resolution?['message'] ?? 'Review required before importing.')
                    .toString());
    } else {
      label =
          (resolution?['status_label'] ??
                  switch (status) {
                    _FreshReviewStatus.alreadyEnrolled => 'Already Enrolled',
                    _FreshReviewStatus.updatesSection =>
                      'Already Enrolled (Updates Section)',
                    _FreshReviewStatus.existingStudent =>
                      'Existing Student — Ready',
                    _ => 'Ready to Enroll',
                  })
              .toString();
      reason = (resolution?['message'] ?? '').toString();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: reason.isEmpty ? label : reason,
        excludeFromSemantics: true,
        child: Focus(
          child: Semantics(
            label: '$label. $reason',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: dark ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
              ),
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFreshStudentRow(
    Map<String, dynamic> student,
    Map<String, dynamic>? activeSem,
  ) {
    final primary = DefensysTokens.textPrimaryOf(context);
    final secondary = DefensysTokens.textSecondaryOf(context);
    final id = (student['id_number'] ?? student['username'] ?? '').toString();
    final fullName =
        '${student['last_name'] ?? ''}, ${student['first_name'] ?? ''}'.trim();
    final name = fullName == ','
        ? (student['name'] ?? 'Student').toString()
        : fullName;
    final year = _freshYear(student);
    final rawSection = _freshSection(student);
    final section =
        rawSection.isEmpty ||
            ['unassigned', 'null'].contains(rawSection.toLowerCase())
        ? 'Unassigned'
        : rawSection;
    final resolution = student['_section_resolution'] as Map?;
    final inferred = resolution?['source'] == 'inferred';
    final instructor =
        (student['faculty'] ??
                student['instructor'] ??
                student['instructor_name'] ??
                '')
            .toString()
            .trim();
    final capstone =
        year.contains('4th') ||
        (year.contains('3rd') &&
            (activeSem?['label']?.toString().contains('2nd') ?? false));
    return Container(
      key: ValueKey('fresh-student-row-$id'),
      color: DefensysTokens.surfaceOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: _freshTableColumns([
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: primary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'ID: $id · ${student['email'] ?? ''}',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 12,
                color: secondary,
              ),
            ),
          ],
        ),
        Text(
          year,
          style: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 12,
            color: primary,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message:
                        (resolution?['message'] ??
                                'Enter the official section or assign it through the existing roster flow.')
                            .toString(),
                    child: Text(
                      '$section${inferred && section != 'Unassigned' ? ' (inferred)' : ''}',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 12,
                        color: primary,
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Edit enrollment section',
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    width: 28,
                    height: 28,
                    padding: EdgeInsets.zero,
                    enabled: !_freshControlsBusy,
                    onPressed: _freshControlsBusy
                        ? null
                        : () => _editFreshSection(student),
                    child: const Icon(Icons.edit_outlined, size: 15),
                  ),
                ),
              ],
            ),
            if (!capstone && instructor.isNotEmpty)
              Tooltip(
                message: 'Instructor: $instructor',
                child: Text(
                  'Instructor: $instructor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 11.5,
                    color: secondary,
                  ),
                ),
              ),
          ],
        ),
        _buildFreshStatusBadge(student, activeSem),
        Tooltip(
          message: 'Exclude student from intake',
          child: ShadButton.ghost(
            size: ShadButtonSize.sm,
            width: 28,
            height: 28,
            padding: EdgeInsets.zero,
            enabled: !_freshControlsBusy,
            onPressed: _freshControlsBusy
                ? null
                : () => _removeFreshStudentRow(student),
            child: const Icon(Icons.close_rounded, size: 15),
          ),
        ),
      ]),
    );
  }

  Widget _buildFreshReviewTableCard({
    required List<Map<String, dynamic>> filtered,
    required Map<String, int> sectionCounts,
    required int totalStudents,
    required Map<String, dynamic>? activeSem,
  }) {
    final primary = DefensysTokens.textPrimaryOf(context);
    final secondary = DefensysTokens.textSecondaryOf(context);
    final border = DefensysTokens.borderOf(context);
    final blockingCount = _parsedFreshStudents
        .where((s) => _isFreshRowBlocking(s, activeSem))
        .length;
    final statusCounts = <_FreshReviewStatus, int>{};
    for (final student in _parsedFreshStudents) {
      statusCounts.update(
        _freshStatus(student, activeSem),
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    final attentionCount = statusCounts[_FreshReviewStatus.needsAttention] ?? 0;
    final totalPages = (filtered.length / _freshRowsPerPage).ceil();
    _freshPage = _freshPage.clamp(0, totalPages > 0 ? totalPages - 1 : 0);
    final pageRows = filtered
        .skip(_freshPage * _freshRowsPerPage)
        .take(_freshRowsPerPage)
        .toList();
    final allViaTeams =
        sectionCounts.isEmpty ||
        (sectionCounts.length == 1 && sectionCounts.containsKey('Unassigned'));
    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review students',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  allViaTeams
                      ? 'Section defaults apply only to confirmed Capstone 2 continuations; other sections remain unassigned.'
                      : 'Verify student details and section assignments before enrollment.',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12.5,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '$totalStudents ${totalStudents == 1 ? 'student' : 'students'}',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                    Text(
                      '${totalStudents - attentionCount} ready',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 12,
                        color: secondary,
                      ),
                    ),
                    Text(
                      '$attentionCount ${attentionCount == 1 ? 'needs' : 'need'} attention',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 12,
                        color: attentionCount > 0
                            ? (DefensysTokens.isDark(context)
                                  ? DefensysTokens.danger
                                  : DefensysTokens.dangerText)
                            : secondary,
                      ),
                    ),
                    if (blockingCount > 0 && blockingCount < totalStudents)
                      ShadButton.ghost(
                        size: ShadButtonSize.sm,
                        enabled: !_freshControlsBusy,
                        onPressed: _freshControlsBusy
                            ? null
                            : () => _removeAllBlockedFreshRows(activeSem),
                        child: Text('Exclude all $blockingCount blocked'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: border),
          _buildFreshFilterToolbar(
            sectionCounts,
            statusCounts,
            filtered.length,
          ),
          Divider(height: 1, color: border),
          if (totalStudents == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Text(
                'Upload a university class list to review students here.',
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 12,
                  color: secondary,
                ),
              ),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Text('No students match these filters.'),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: constraints.maxWidth < 960
                      ? 960
                      : constraints.maxWidth,
                  child: Column(
                    children: [
                      Padding(
                        key: const ValueKey('fresh-review-header'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: _freshTableColumns([
                          for (final title in [
                            'Student',
                            'Year level',
                            'Section',
                            'Status',
                          ])
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: secondary,
                                ),
                              ),
                            ),
                          Semantics(
                            label: 'Actions',
                            header: true,
                            child: SizedBox.shrink(),
                          ),
                        ]),
                      ),
                      Divider(height: 1, color: border),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pageRows.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: border),
                        itemBuilder: (_, index) =>
                            _buildFreshStudentRow(pageRows[index], activeSem),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (filtered.isNotEmpty) ...[
            Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: _buildFreshPaginationControls(filtered.length),
            ),
          ],
          Divider(height: 1, color: border),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                if (_hasFreshFilters)
                  Text(
                    'Applies to all $totalStudents students',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 12,
                      color: secondary,
                    ),
                  ),
                ShadButton.outline(
                  onPressed: widget.onBack,
                  child: const Text('Cancel'),
                ),
                ShadButton(
                  key: const ValueKey('confirm-student-enrollment'),
                  enabled:
                      totalStudents > 0 &&
                      !_freshControlsBusy &&
                      activeSem != null &&
                      blockingCount == 0,
                  onPressed:
                      totalStudents == 0 ||
                          _freshControlsBusy ||
                          activeSem == null ||
                          blockingCount > 0
                      ? null
                      : _confirmFreshIntake,
                  leading: _freshImportPending || widget.userState.isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                        ),
                  child: Text(
                    activeSem == null
                        ? 'Active semester required'
                        : blockingCount > 0
                        ? 'Resolve $blockingCount ${blockingCount == 1 ? 'issue' : 'issues'}'
                        : _freshImportPending || widget.userState.isSaving
                        ? 'Importing $totalStudents ${totalStudents == 1 ? 'student' : 'students'}...'
                        : 'Confirm enrollment ($totalStudents)',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreshPaginationControls(int totalCount) {
    final totalPages = (totalCount / _freshRowsPerPage).ceil();
    final start = _freshPage * _freshRowsPerPage + 1;
    final end = ((_freshPage + 1) * _freshRowsPerPage).clamp(0, totalCount);
    final secondary = DefensysTokens.textSecondaryOf(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Rows per page:',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 12,
                color: secondary,
              ),
            ),
            ShadSelect<int>(
              initialValue: _freshRowsPerPage,
              options: [
                for (final n in _rowsPerPageOptions)
                  ShadOption(value: n, child: Text('$n')),
              ],
              selectedOptionBuilder: (_, n) => Text('$n'),
              onChanged: (n) {
                if (n == null) return;
                setState(() {
                  _freshRowsPerPage = n;
                  _freshPage = 0;
                });
              },
            ),
            Text(
              '$start - $end of $totalCount',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 12,
                color: secondary,
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Previous page',
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                enabled: _freshPage > 0,
                onPressed: _freshPage > 0
                    ? () => setState(() => _freshPage--)
                    : null,
                child: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
            ),
            Text(
              '${_freshPage + 1} / ${totalPages == 0 ? 1 : totalPages}',
              style: const TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 12,
              ),
            ),
            Tooltip(
              message: 'Next page',
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                enabled: _freshPage < totalPages - 1,
                onPressed: _freshPage < totalPages - 1
                    ? () => setState(() => _freshPage++)
                    : null,
                child: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _clearFreshFiles() {
    setState(() {
      _stagedFreshFiles.clear();
      _parsedFreshStudents.clear();
      _selectedFreshSectionFilter = 'ALL';
      _selectedFreshYearFilter = 'ALL';
      _selectedFreshStatusFilter = 'ALL';
      _freshPage = 0;
    });
    ref.read(studentBatchDraftProvider.notifier).clearFreshDraft();
  }

  Future<void> _pickFreshFiles() async {
    if (_freshControlsBusy) return;
    try {
      final files =
          await (widget.onPickFreshFiles ?? pickMultipleTabularDataFiles)();
      if (!mounted || files.isEmpty) return;
      final merged = List<PickedTabularFile>.from(_stagedFreshFiles);
      for (final file in files) {
        if (!merged.any(
          (existing) =>
              existing.name == file.name &&
              existing.bytes.length == file.bytes.length,
        )) {
          merged.add(file);
        }
      }
      await _openFreshStagingModal(merged);
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not read file(s): $e');
    }
  }

  Future<void> _replaceFreshFile(int index) async {
    if (_freshControlsBusy) return;
    try {
      final file =
          await (widget.onPickFreshReplacement ?? pickSingleTabularDataFile)();
      if (!mounted || file == null) return;
      final candidate = List<PickedTabularFile>.from(_stagedFreshFiles);
      candidate[index] = file;
      await _openFreshStagingModal(candidate);
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not replace file: $e');
    }
  }

  Future<void> _removeFreshFile(int index) async {
    if (_freshControlsBusy) return;
    final remaining = List<PickedTabularFile>.from(_stagedFreshFiles)
      ..removeAt(index);
    if (remaining.isEmpty) {
      _clearFreshFiles();
      return;
    }
    setState(() => _freshFilesPending = true);
    try {
      await _processFreshFiles(remaining);
    } finally {
      if (mounted) setState(() => _freshFilesPending = false);
    }
  }

  Future<void> _openFreshStagingModal(
    List<PickedTabularFile> initialFiles,
  ) async {
    if (!mounted || _freshControlsBusy) return;
    setState(() => _freshFilesPending = true);
    try {
      final activeSem =
          ref.read(academicPeriodProvider).activeSemester ??
          widget.academicState.activeSemester ??
          ref.read(studentAcademicRecordsProvider).activeSemester;
      final result = await showFileImportStagingModal(
        context,
        initialFiles: List<PickedTabularFile>.from(initialFiles),
        importMode: 'student',
        hasActiveSemester: activeSem != null,
        activeSemester: activeSem,
      );
      if (!mounted || result == null) return;
      if (result.files.isEmpty) {
        _clearFreshFiles();
        return;
      }
      await _processFreshFiles(result.files);
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Error staging fresh intake file(s): $e');
      }
    } finally {
      if (mounted) setState(() => _freshFilesPending = false);
    }
  }

  Future<void> _processFreshFiles(List<PickedTabularFile> files) async {
    if (!mounted || files.isEmpty) return;
    try {
      final activeSem =
          ref.read(academicPeriodProvider).activeSemester ??
          widget.academicState.activeSemester ??
          ref.read(studentAcademicRecordsProvider).activeSemester;

      final allStudents = <Map<String, dynamic>>[];
      final validFiles = <PickedTabularFile>[];
      final byStudentId = <String, Map<String, dynamic>>{};
      String? lastTermMismatchError;

      for (final file in files) {
        final official = file.isXlsx
            ? parseOfficialClassListXlsx(file.bytes)
            : parseOfficialClassListCsv(
                file.text ?? utf8.decode(file.bytes, allowMalformed: true),
              );

        final termError = _validateParsedFileTerm(official.metadata, activeSem);
        if (termError != null) {
          lastTermMismatchError = termError;
          continue;
        }

        if (official.students.isNotEmpty) {
          validFiles.add(file);
          for (final s in official.students) {
            final idKey = (s['id_number'] ?? s['student_number'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (idKey.isEmpty) {
              allStudents.add(s);
              continue;
            }
            if (byStudentId.containsKey(idKey)) {
              final existing = byStudentId[idKey]!;
              final existingYr = (existing['year_level'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              final newYr = (s['year_level'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              final existingSec = (existing['section'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              final newSec = (s['section'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (existingYr == newYr && existingSec == newSec) {
                continue; // Identical duplicate row deduplicated
              } else {
                existing['_client_validation_error'] =
                    'Conflicting year level or section across staged files.';
                continue;
              }
            }
            byStudentId[idKey] = s;
            allStudents.add(s);
          }
        }
      }

      if (allStudents.isEmpty) {
        if (mounted) {
          showErrorToast(
            context,
            lastTermMismatchError ??
                'No valid student rows found in staged file(s).',
          );
        }
        return;
      }

      final skippedCount = files.length - validFiles.length;
      await _resolveFreshSections(allStudents);
      if (!mounted) return;

      setState(() {
        _stagedFreshFiles = List.from(validFiles);
        _parsedFreshStudents = List.from(allStudents);
        _selectedFreshSectionFilter = 'ALL';
        _selectedFreshYearFilter = 'ALL';
        _selectedFreshStatusFilter = 'ALL';
        _freshPage = 0;
      });

      ref
          .read(studentBatchDraftProvider.notifier)
          .saveFreshDraft(
            stagedFiles: validFiles,
            parsedStudents: allStudents,
            sectionFilter: 'ALL',
          );

      if (mounted) {
        if (skippedCount > 0) {
          ToastService.warning(
            context,
            '${validFiles.length} valid file(s) staged • ${allStudents.length} students ready. ($skippedCount incompatible file(s) skipped)',
          );
        } else {
          showSuccessToast(
            context,
            '${validFiles.length} file(s) staged • ${allStudents.length} student records ready for review.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Failed to process staged files: $e');
      }
    }
  }

  Future<void> _confirmFreshIntake() async {
    if (_parsedFreshStudents.isEmpty ||
        _freshImportPending ||
        widget.userState.isSaving) {
      return;
    }
    final activeSem = ref.read(academicPeriodProvider).activeSemester ??
        widget.academicState.activeSemester ??
        ref.read(studentAcademicRecordsProvider).activeSemester;
    if (activeSem == null) {
      showErrorToast(
        context,
        'Cannot enroll students: No active academic semester is configured. Please configure an active semester in Academic Periods first.',
      );
      return;
    }
    final draft = ref.read(studentBatchDraftProvider.notifier);
    setState(() => _freshImportPending = true);
    try {
      final reviewed = _parsedFreshStudents.map((s) => Map<String, dynamic>.from(s)).toList();
      await _resolveFreshSections(reviewed);
      if (!mounted) return;
      if (reviewed.any((s) => _isFreshRowBlocking(s, activeSem))) {
        setState(() => _parsedFreshStudents = reviewed);
        showErrorToast(context, 'Cannot import: One or more student rows have blocking validation issues.');
        return;
      }
      List<Object> sectionSummary(List<Map<String, dynamic>> rows) => rows.map((s) => [
        _freshSection(s), (s['_section_resolution'] as Map?)?['source'] == 'review',
      ]).toList();
      final before = sectionSummary(_parsedFreshStudents);
      final after = sectionSummary(reviewed);
      if (jsonEncode(before) != jsonEncode(after)) {
        setState(() => _parsedFreshStudents = reviewed);
        ToastService.warning(context, 'Section assignments updated. Review the preview, then confirm enrollment.');
        return;
      }
      final firstMeta = reviewed.first['_fileMetadata'] as Map?;
      final success = await widget.onConfirmFreshImport(
        reviewed,
        {
          'semester_id': activeSem['id'],
          if (firstMeta?['school_year'] != null) 'school_year': firstMeta!['school_year'],
          if (firstMeta?['semester'] != null) 'semester': firstMeta!['semester'],
        },
      );
      if (success) draft.clearFreshDraft();
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not verify enrollment sections: $e');
    } finally {
      if (mounted) setState(() => _freshImportPending = false);
    }
  }

  // -------------------------------------------------------------
  // Mode 2: Semester Rollover & Promotion View
  // -------------------------------------------------------------
  Widget _buildSemesterRolloverView() {
    final state = ref.watch(studentAcademicRecordsProvider);
    final activeSem = ref.watch(academicPeriodProvider).activeSemester ??
        widget.academicState.activeSemester ??
        state.activeSemester;
    final activeSemLabel = activeSem?['display_name'] ??
        '${activeSem?['school_year'] ?? 'Current Year'} - ${activeSem?['label'] ?? 'Active Term'}';

    final filtered = state.rolloverRows.where((row) {
      final q = _rolloverSearchCtrl.text.trim().toLowerCase();
      final rec = row['record'] as Map? ?? {};
      final name = rec['student_name']?.toString().toLowerCase() ?? '';
      final user = rec['student_username']?.toString().toLowerCase() ?? '';
      final matchQuery = q.isEmpty || name.contains(q) || user.contains(q);
      if (!matchQuery) return false;

      if (_rolloverFilterMode == RolloverFilterMode.bySection &&
          _selectedSectionFilter != 'ALL') {
        final sec = rec['section']?.toString().trim() ?? '';
        if (sec != _selectedSectionFilter) return false;
      }

      if (_rolloverFilterMode == RolloverFilterMode.byYearLevel &&
          _selectedYearFilter != 'ALL') {
        final yr = rec['year_level']?.toString().trim() ?? '';
        if (yr != _selectedYearFilter) return false;
      }

      return true;
    }).toList();

    int promoteCount = 0;
    int retainCount = 0;
    int dropCount = 0;
    int createCount = 0;

    for (final row in state.rolloverRows) {
      final rec = row['record'] as Map? ?? {};
      final isNew = row['is_new_student'] == true;
      final key = rec['id'] != null
          ? rec['id'].toString()
          : rec['student_username']?.toString() ?? '';
      final act = _rolloverActions[key] ?? row['action_default'] ?? (isNew ? 'create' : 'promote');
      if (act == 'promote') promoteCount++;
      if (act == 'retain') retainCount++;
      if (act == 'drop') dropCount++;
      if (act == 'create') createCount++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top 2-Column Section: Left is Rules Guide, Right is Primary Source & Upload
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 960;
            if (!isWide) {
              return Column(
                children: [
                  _buildRolloverRulesCard(activeSemLabel),
                  const SizedBox(height: 18),
                  _buildRolloverSourceCard(state),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: _buildRolloverRulesCard(activeSemLabel),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 6,
                  child: _buildRolloverSourceCard(state),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // Bottom Full-Width Preflight Review Table Card
        _buildRolloverReviewTableCard(
          state: state,
          filtered: filtered,
          promoteCount: promoteCount,
          retainCount: retainCount,
          dropCount: dropCount,
          createCount: createCount,
          activeSemLabel: activeSemLabel,
        ),
      ],
    );
  }

  Widget _buildRolloverRulesCard(String activeSemLabel) {
    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 280),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, color: _maroon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Semester Rollover & Transition Rules',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Target Term: $activeSemLabel • Automated Cohort Progression',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Cohort Progression & Capstone Rules
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Standard Year Level Progression
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.trending_up_rounded, size: 14, color: Color(0xFF475569)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'COHORT PROGRESSION SPECIFICATION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Text(
                          'Auto-Calculated',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• 1st Sem advances to 2nd Sem (Same Year Level)\n• 2nd Sem advances to next Year Level (1st Yr → 2nd Yr → 3rd Yr → 4th Yr)',
                    style: TextStyle(
                      fontSize: 11,
                      color: _ink,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 12),

                  // Row 2: Capstone Stages in DefenSYS
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.school_outlined, size: 14, color: _maroon),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'DEFENSYS CAPSTONE STAGES',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildMilestoneTag('3rd Yr (2nd Sem)', 'Capstone 1'),
                      const Icon(Icons.arrow_forward_rounded, size: 12, color: _muted),
                      _buildMilestoneTag('4th Yr (1st Sem)', 'Capstone 2 (Final)'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: _muted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Best for continuing cohorts. Auto-advances students, detects repeaters, and manages dropouts.',
                    style: TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Action Buttons Row: View Blueprint Modal & Download Template
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showClassListFormatGuideModal(
                    context,
                    isRollover: true,
                    activeSemLabel: activeSemLabel,
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: const Text('View Sheet Layout Blueprint'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onDownloadSample,
                  icon: const Icon(Icons.download_rounded, size: 14),
                  label: const Text('Download Sample Template'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneTag(String term, String stage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            term,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              stage,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRolloverSourceCard(StudentAcademicRecordsState state) {
    final hasFiles = _stagedRolloverFiles.isNotEmpty || _hasCsvUploaded;
    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 280),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isDraggingFile
                        ? _maroon.withValues(alpha: 0.15)
                        : (hasFiles
                            ? const Color(0xFFDCFCE7)
                            : _maroon.withValues(alpha: 0.08)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isDraggingFile
                        ? Icons.file_download_rounded
                        : (hasFiles
                            ? Icons.task_alt_rounded
                            : Icons.cloud_upload_outlined),
                    color: _isDraggingFile
                        ? _maroon
                        : (hasFiles ? _green : _maroon),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isDraggingFile
                            ? 'Drop Rollover Class List Files'
                            : (hasFiles
                                ? 'Staged Class List Source Files'
                                : 'Cohort Source & Class List Matching'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isDraggingFile
                            ? 'Release files to stage into rollover cohort review'
                            : (hasFiles
                                ? '${_stagedRolloverFiles.length} file(s) staged • Matches active student IDs'
                                : 'Matches active student IDs & skips non-enrolled'),
                        style: TextStyle(
                          fontSize: 12,
                          color: _isDraggingFile ? _maroon : _muted,
                          fontWeight: _isDraggingFile ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasFiles && !_isDraggingFile) ...[
                  OutlinedButton.icon(
                    onPressed: state.isSaving
                        ? null
                        : () => _openRolloverStagingModal(_stagedRolloverFiles),
                    icon: const Icon(Icons.folder_open_rounded, size: 14),
                    label: const Text('Review Files'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _maroon,
                      side: const BorderSide(color: _maroon),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: state.isSaving
                  ? null
                  : () {
                      if (_stagedRolloverFiles.isNotEmpty) {
                        _openRolloverStagingModal(_stagedRolloverFiles);
                      } else {
                        _pickRolloverFiles();
                      }
                    },
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
                decoration: BoxDecoration(
                  color: _isDraggingFile
                      ? const Color(0xFFFEF2F2)
                      : (hasFiles ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isDraggingFile
                        ? _maroon
                        : (hasFiles ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1)),
                    width: _isDraggingFile ? 2.0 : (hasFiles ? 1.5 : 1),
                  ),
                  boxShadow: _isDraggingFile
                      ? [
                          BoxShadow(
                            color: _maroon.withValues(alpha: 0.15),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isDraggingFile
                          ? Icons.file_download_rounded
                          : (hasFiles
                              ? Icons.inventory_2_outlined
                              : Icons.cloud_upload_outlined),
                      size: _isDraggingFile ? 36 : 30,
                      color: _isDraggingFile
                          ? _maroon
                          : (hasFiles ? _green : _maroon),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isDraggingFile
                          ? 'Drop official class list (.csv / .xlsx) here'
                          : (hasFiles
                              ? '${_stagedRolloverFiles.length} Class List File(s) Staged (Click or Drop to Add)'
                              : 'Drag & drop or click to choose official class list (.csv / .xlsx)'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _isDraggingFile
                            ? _maroon
                            : (hasFiles ? const Color(0xFF15803D) : _ink),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isDraggingFile
                          ? 'Release to automatically stage multiple class section files at once'
                          : (hasFiles
                              ? 'Review sections, replace, or drop more class section files'
                              : 'Supports staging multiple class section files simultaneously'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _isDraggingFile
                            ? _maroon
                            : (hasFiles ? const Color(0xFF166534) : _muted),
                      ),
                    ),
                    if (!hasFiles || _isDraggingFile) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildFormatPill('CSV'),
                          const SizedBox(width: 6),
                          _buildFormatPill('XLSX'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: state.isSaving
                    ? null
                    : () async {
                        setState(() {
                          _hasCsvUploaded = false;
                          _stagedRolloverFiles.clear();
                          _rolloverActions.clear();
                        });
                        ref.read(studentBatchDraftProvider.notifier).clearRolloverDraft();
                        await ref
                            .read(studentAcademicRecordsProvider.notifier)
                            .fetchRolloverPreview(students: []);
                      },
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Or load active students from previous term without file'),
                style: TextButton.styleFrom(
                  foregroundColor: _muted,
                  textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRolloverReviewTableCard({
    required StudentAcademicRecordsState state,
    required List<Map<String, dynamic>> filtered,
    required int promoteCount,
    required int retainCount,
    required int dropCount,
    required int createCount,
    required String activeSemLabel,
  }) {
    final totalCount = filtered.length;
    final totalPages = (totalCount / _rolloverRowsPerPage).ceil();
    if (_rolloverPage >= totalPages && totalPages > 0) {
      _rolloverPage = totalPages - 1;
    }
    final startIndex = _rolloverPage * _rolloverRowsPerPage;
    final endIndex = (startIndex + _rolloverRowsPerPage).clamp(0, totalCount);
    final pageRows = totalCount == 0
        ? <Map<String, dynamic>>[]
        : filtered.sublist(startIndex, endIndex);

    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Header (Unified with Capstone Stages style)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.table_chart_outlined,
                  color: DefensysUi.primaryMaroon,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preflight Cohort Rollover Review',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: DefensysUi.textDark,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Verify student progression actions, section reassignments, and retention statuses before committing.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: DefensysUi.steelGrey,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (activeSemLabel.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _headerPill(activeSemLabel),
                ],
                const SizedBox(width: 8),
                _headerPill(
                  totalCount == 0
                      ? '0 students'
                      : '$totalCount students in cohort',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Transition Distribution Status Strip
          if (totalCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.analytics_outlined, size: 15, color: Color(0xFF475569)),
                    const SizedBox(width: 8),
                    const Text(
                      'Transition Snapshot:',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(width: 14),
                    _buildCohortStatItem('Promote', promoteCount, const Color(0xFF16A34A)),
                    _buildCohortStatDivider(),
                    _buildCohortStatItem('Retain', retainCount, const Color(0xFFD97706)),
                    _buildCohortStatDivider(),
                    _buildCohortStatItem('Skip / Drop', dropCount, const Color(0xFF64748B)),
                    if (createCount > 0) ...[
                      _buildCohortStatDivider(),
                      _buildCohortStatItem('New Intake', createCount, const Color(0xFF4F46E5)),
                    ],
                  ],
                ),
              ),
            ),

          // Search + Bulk Actions Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _rolloverSearchCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _muted),
                        hintText: 'Search by student ID or name...',
                        hintStyle: const TextStyle(fontSize: 12.5, color: _muted),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(color: _maroon),
                        ),
                      ),
                      onChanged: (_) => setState(() {
                        _rolloverPage = 0;
                      }),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      for (final row in state.rolloverRows) {
                        final rec = row['record'] as Map? ?? {};
                        final key = rec['id'] != null
                            ? rec['id'].toString()
                            : rec['student_username']?.toString() ?? '';
                        _rolloverActions[key] = 'promote';
                      }
                    });
                    ref.read(studentBatchDraftProvider.notifier).saveRolloverDraft(
                      stagedFiles: _stagedRolloverFiles,
                      actions: _rolloverActions,
                      sectionFilter: _selectedSectionFilter,
                      yearFilter: _selectedYearFilter,
                      hasRolloverCsv: _hasCsvUploaded,
                    );
                  },
                  icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                  label: const Text('Promote All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _maroon,
                    side: BorderSide(color: _maroon.withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      for (final row in state.rolloverRows) {
                        final rec = row['record'] as Map? ?? {};
                        final key = rec['id'] != null
                            ? rec['id'].toString()
                            : rec['student_username']?.toString() ?? '';
                        _rolloverActions[key] = 'retain';
                      }
                    });
                    ref.read(studentBatchDraftProvider.notifier).saveRolloverDraft(
                      stagedFiles: _stagedRolloverFiles,
                      actions: _rolloverActions,
                      sectionFilter: _selectedSectionFilter,
                      yearFilter: _selectedYearFilter,
                      hasRolloverCsv: _hasCsvUploaded,
                    );
                  },
                  icon: const Icon(Icons.replay_rounded, size: 14),
                  label: const Text('Retain All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Text(
              'Review student progression actions and standings. You can customize individual actions per student below.',
              style: TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Table Content
          if (state.isSaving || state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline_rounded, size: 38, color: Color(0xFF98A2B3)),
                    SizedBox(height: 10),
                    Text(
                      'No student records found for rollover review.',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Stage rollover class list files or load continuing students from the previous term above.',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pageRows.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
              itemBuilder: (context, index) {
                final row = pageRows[index];
                final rec = row['record'] as Map? ?? {};
                final isNew = row['is_new_student'] == true;
                final key = rec['id'] != null
                    ? rec['id'].toString()
                    : rec['student_username']?.toString() ?? '';
                final rawAction =
                    _rolloverActions[key] ?? row['action_default'] ?? (isNew ? 'create' : 'promote');
                final pr = row['promote_result'] as Map? ?? {};

                final currentAction = rawAction.toString().toLowerCase();
                final dropdownItems = <DropdownMenuItem<String>>[
                  if (isNew || currentAction == 'create')
                    const DropdownMenuItem(
                      value: 'create',
                      child: Text('Create & Enroll'),
                    ),
                  if (!isNew || currentAction == 'promote')
                    const DropdownMenuItem(
                      value: 'promote',
                      child: Text('Promote'),
                    ),
                  if (!isNew || currentAction == 'retain')
                    const DropdownMenuItem(
                      value: 'retain',
                      child: Text('Retain'),
                    ),
                  const DropdownMenuItem(
                    value: 'drop',
                    child: Text('Skip / Drop'),
                  ),
                ];

                final knownValues = dropdownItems.map((i) => i.value).toSet();
                final safeValue = knownValues.contains(currentAction)
                    ? currentAction
                    : (isNew ? 'create' : 'promote');

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  color: index.isEven ? Colors.white : const Color(0xFFF9FAFB),
                  child: Row(
                    children: [
                      // Student ID and Name
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rec['student_name']?.toString() ?? 'Unnamed Student',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: ${rec['student_username'] ?? ''} • ${rec['student_email'] ?? ''}',
                              style: const TextStyle(fontSize: 12, color: _muted),
                            ),
                          ],
                        ),
                      ),

                      // Current Standing
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rec['year_level']?.toString() ?? 'Unassigned',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _ink,
                              ),
                            ),
                            Text(
                              'Section: ${rec['section']?.toString().isEmpty ?? true ? 'None' : rec['section']}',
                              style: const TextStyle(fontSize: 11.5, color: _muted),
                            ),
                          ],
                        ),
                      ),

                      // Action Selector
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD1D5DB)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: safeValue,
                              isDense: true,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                              items: dropdownItems,
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _rolloverActions[key] = val);
                                  ref.read(studentBatchDraftProvider.notifier).saveRolloverDraft(
                                    stagedFiles: _stagedRolloverFiles,
                                    actions: _rolloverActions,
                                    sectionFilter: _selectedSectionFilter,
                                    yearFilter: _selectedYearFilter,
                                    hasRolloverCsv: _hasCsvUploaded,
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Target Standing Preview
                      Expanded(
                        flex: 3,
                        child: _buildTargetStandingPreview(safeValue, pr, rec),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Pagination Controls
          if (state.rolloverRows.isNotEmpty && filtered.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: _buildPaginationControls(
                totalCount: filtered.length,
                currentPage: _rolloverPage,
                rowsPerPage: _rolloverRowsPerPage,
                onPageChanged: (newPage) => setState(() => _rolloverPage = newPage),
                onRowsPerPageChanged: (newRpp) => setState(() {
                  _rolloverRowsPerPage = newRpp;
                  _rolloverPage = 0;
                }),
              ),
            ),
          ],

          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // Bottom Actions Bar (Matching Image 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF667085)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Confirming rollover will advance cohorts, apply retained repeaters, and enroll students into the active term.',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: Color(0xFFD0D5DD)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: state.isSaving || filtered.isEmpty
                      ? null
                      : _confirmRolloverCommit,
                  icon: state.isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: Text(
                    state.isSaving ? 'Processing Rollover...' : 'Confirm Semester Rollover',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _maroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls({
    required int totalCount,
    required int currentPage,
    required int rowsPerPage,
    required void Function(int newPage) onPageChanged,
    required void Function(int newRowsPerPage) onRowsPerPageChanged,
  }) {
    final totalPages = (totalCount / rowsPerPage).ceil();
    final startItem = totalCount == 0 ? 0 : currentPage * rowsPerPage + 1;
    final endItem = ((currentPage + 1) * rowsPerPage).clamp(0, totalCount);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text(
              'Rows per page: ',
              style: TextStyle(fontSize: 12.5, color: _muted),
            ),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _line),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: rowsPerPage,
                  isDense: true,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                  items: _rowsPerPageOptions.map((n) {
                    return DropdownMenuItem(
                      value: n,
                      child: Text('$n'),
                    );
                  }).toList(),
                  onChanged: (n) {
                    if (n != null) {
                      onRowsPerPageChanged(n);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              '$startItem - $endItem of $totalCount',
              style: const TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              color: _ink,
              splashRadius: 18,
              onPressed: currentPage > 0
                  ? () => onPageChanged(currentPage - 1)
                  : null,
            ),
            Text(
              '${currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _ink),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              color: _ink,
              splashRadius: 18,
              onPressed: currentPage < totalPages - 1
                  ? () => onPageChanged(currentPage + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCohortStatItem(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCohortStatDivider() {
    return Container(
      height: 14,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFFCBD5E1),
    );
  }

  Widget _buildTargetStandingPreview(
    String action,
    Map<dynamic, dynamic> pr,
    Map<dynamic, dynamic> rec,
  ) {
    if (action == 'drop') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: const Text(
          'Excluded from Term',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
        ),
      );
    }

    if (action == 'create') {
      final targetYear = pr['year_level']?.toString() ?? rec['year_level']?.toString() ?? 'Enrolled Level';
      final targetSection = pr['section']?.toString() ?? rec['section']?.toString() ?? 'Assigned Section';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFC7D2FE)),
        ),
        child: Text(
          'New Enrollee → $targetYear ($targetSection)',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4338CA),
          ),
        ),
      );
    }

    if (action == 'retain') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Text(
          'Repeats ${rec['year_level'] ?? 'Standing'} (Retained)',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFFB45309),
          ),
        ),
      );
    }

    final targetYear = pr['year_level']?.toString() ?? 'Next Level';
    final targetSection = pr['section']?.toString() ?? 'Assigned Section';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Text(
        'Promoted → $targetYear ($targetSection)',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF15803D),
        ),
      ),
    );
  }

  Future<void> _pickRolloverFiles() async {
    try {
      final files = await pickMultipleTabularDataFiles();
      if (!mounted || files.isEmpty) return;
      await _openRolloverStagingModal(files);
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Could not read file(s): $e');
      }
    }
  }

  Future<void> _openRolloverStagingModal(List<PickedTabularFile> initialFiles) async {
    if (!mounted) return;
    try {
      final activeSem = ref.read(academicPeriodProvider).activeSemester ??
          widget.academicState.activeSemester ??
          ref.read(studentAcademicRecordsProvider).activeSemester;
      final result = await showFileImportStagingModal(
        context,
        initialFiles: initialFiles,
        importMode: 'student',
        hasActiveSemester: activeSem != null,
        activeSemester: activeSem,
      );
      if (!mounted || result == null) return;
      if (result.files.isEmpty) {
        setState(() {
          _stagedRolloverFiles.clear();
          _hasCsvUploaded = false;
          _rolloverActions.clear();
        });
        ref.read(studentBatchDraftProvider.notifier).clearRolloverDraft();
        await ref
            .read(studentAcademicRecordsProvider.notifier)
            .fetchRolloverPreview(students: []);
        return;
      }

      await _processRolloverFiles(result.files);
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Error staging rollover file(s): $e');
      }
    }
  }

  Future<void> _processRolloverFiles(List<PickedTabularFile> files) async {
    if (!mounted || files.isEmpty) return;
    try {
      final activeSem = ref.read(academicPeriodProvider).activeSemester ??
          widget.academicState.activeSemester ??
          ref.read(studentAcademicRecordsProvider).activeSemester;

      final allStudents = <Map<String, dynamic>>[];
      final validFiles = <PickedTabularFile>[];
      final byStudentId = <String, Map<String, dynamic>>{};
      String? lastTermMismatchError;

      for (final file in files) {
        final official = file.isXlsx
            ? parseOfficialClassListXlsx(file.bytes)
            : parseOfficialClassListCsv(file.text ?? utf8.decode(file.bytes, allowMalformed: true));

        final termError = _validateParsedFileTerm(official.metadata, activeSem);
        if (termError != null) {
          lastTermMismatchError = termError;
          continue;
        }

        if (official.students.isNotEmpty) {
          validFiles.add(file);
          for (final s in official.students) {
            final idKey = (s['id_number'] ?? s['student_number'] ?? '').toString().trim().toLowerCase();
            if (idKey.isEmpty) {
              allStudents.add(s);
              continue;
            }
            if (byStudentId.containsKey(idKey)) {
              final existing = byStudentId[idKey]!;
              final existingYr = (existing['year_level'] ?? '').toString().trim().toLowerCase();
              final newYr = (s['year_level'] ?? '').toString().trim().toLowerCase();
              final existingSec = (existing['section'] ?? '').toString().trim().toLowerCase();
              final newSec = (s['section'] ?? '').toString().trim().toLowerCase();
              if (existingYr == newYr && existingSec == newSec) {
                continue;
              } else {
                existing['_client_validation_error'] = 'Conflicting year level or section across staged files.';
                continue;
              }
            }
            byStudentId[idKey] = s;
            allStudents.add(s);
          }
        }
      }

      if (allStudents.isEmpty) {
        if (mounted) {
          showErrorToast(
            context,
            lastTermMismatchError ?? 'No valid student rows found in staged file(s).',
          );
        }
        return;
      }

      final skippedCount = files.length - validFiles.length;

      setState(() {
        _stagedRolloverFiles = List.from(validFiles);
        _hasCsvUploaded = true;
      });

      ref.read(studentBatchDraftProvider.notifier).saveRolloverDraft(
        stagedFiles: validFiles,
        actions: _rolloverActions,
        sectionFilter: _selectedSectionFilter,
        yearFilter: _selectedYearFilter,
        hasRolloverCsv: true,
      );

      await ref
          .read(studentAcademicRecordsProvider.notifier)
          .fetchRolloverPreview(students: allStudents);

      if (mounted) {
        if (skippedCount > 0) {
          ToastService.warning(
            context,
            '${validFiles.length} valid file(s) staged • ${allStudents.length} students loaded. ($skippedCount incompatible file(s) skipped)',
          );
        } else {
          showSuccessToast(
            context,
            '${validFiles.length} file(s) staged • ${allStudents.length} student records loaded for review.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Failed to process staged files: $e');
      }
    }
  }

  Future<void> _confirmRolloverCommit() async {
    final state = ref.read(studentAcademicRecordsProvider);
    final confirmActions = <Map<String, dynamic>>[];

    for (final row in state.rolloverRows) {
      final rec = row['record'] as Map? ?? {};
      final key = rec['id'] != null
          ? rec['id'].toString()
          : rec['student_username']?.toString() ?? '';
      final act = _rolloverActions[key] ?? row['action_default'] ?? 'promote';
      confirmActions.add(buildStudentRolloverAction(row, act));
    }

    final ok = await ref
        .read(studentAcademicRecordsProvider.notifier)
        .confirmRollover(confirmActions);

    if (ok && mounted) {
      ref.read(studentBatchDraftProvider.notifier).clearRolloverDraft();
      showSuccessToast(context, 'Semester rollover completed successfully.');
      ref.read(userManagementProvider.notifier).fetchUsers();
      widget.onBack();
    }
  }
}
