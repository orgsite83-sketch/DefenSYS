import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/file_import_staging_modal.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/academic/student_batch_draft_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';

import 'official_class_list_parser.dart';

enum StudentHubMode {
  freshIntake,
  semesterRollover,
}

enum RolloverFilterMode {
  all,
  bySection,
  byYearLevel,
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
  });

  final UserManagementState userState;
  final AcademicPeriodState academicState;
  final VoidCallback onBack;
  final StudentHubMode initialMode;
  final VoidCallback? onDownloadSample;
  final void Function(
    List<Map<String, dynamic>> students,
    Map<String, dynamic>? studentContext,
  ) onConfirmFreshImport;

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
  RolloverFilterMode _rolloverFilterMode = RolloverFilterMode.all;
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
  int _freshPage = 0;
  int _freshRowsPerPage = 10;

  static const List<int> _rowsPerPageOptions = [10, 25, 50, 100];

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;

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
    _rolloverSearchCtrl.dispose();
    _freshSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialRolloverData() async {
    await ref
        .read(studentAcademicRecordsProvider.notifier)
        .fetchRolloverPreview(students: []);
  }

  Future<void> _reprocessStagedRolloverDraft(List<PickedTabularFile> files) async {
    final allStudents = <Map<String, dynamic>>[];
    for (final file in files) {
      if (file.isXlsx) {
        final official = parseOfficialClassListXlsx(file.bytes);
        if (official.students.isNotEmpty) {
          allStudents.addAll(official.students);
        }
        continue;
      }
      final text = file.text ?? utf8.decode(file.bytes, allowMalformed: true);
      final official = parseOfficialClassListCsv(text);
      if (official.students.isNotEmpty) {
        allStudents.addAll(official.students);
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
    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          DefensysPageHeader(
            icon: Icons.dynamic_feed_rounded,
            title: 'Batch Student Enrollment Hub',
            subtitle:
                'Manage semester student intake and cohort transitions in one unified workspace.',
            actions: OutlinedButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Students'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _line),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Top Mode Switcher (Pill Tabs)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModePill(
                  mode: StudentHubMode.freshIntake,
                  label: 'Fresh Student Intake (Import)',
                  subtitle: 'New Cohorts & Class Lists',
                  icon: Icons.file_upload_outlined,
                ),
                const SizedBox(width: 8),
                _buildModePill(
                  mode: StudentHubMode.semesterRollover,
                  label: 'Semester Rollover & Promotion',
                  subtitle: 'Transition Returning Cohorts',
                  icon: Icons.rotate_right_rounded,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Active Mode Content
          if (_currentMode == StudentHubMode.freshIntake)
            _buildFreshIntakeView()
          else
            _buildSemesterRolloverView(),
        ],
      ),
    );
  }

  Widget _buildModePill({
    required StudentHubMode mode,
    required String label,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _currentMode == mode;
    return InkWell(
      onTap: () {
        if (_currentMode == mode) return;
        setState(() => _currentMode = mode);
        if (mode == StudentHubMode.semesterRollover) {
          if (_stagedRolloverFiles.isNotEmpty) {
            _reprocessStagedRolloverDraft(_stagedRolloverFiles);
          } else {
            _loadInitialRolloverData();
          }
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _maroon : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : _muted,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.85)
                        : _muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Mode 1: Fresh Student Intake View (Zero-Fillup 2-Column + Preflight)
  // -------------------------------------------------------------
  Widget _buildFreshIntakeView() {
    final activeSem = ref.watch(academicPeriodProvider).activeSemester ??
        widget.academicState.activeSemester ??
        ref.watch(studentAcademicRecordsProvider).activeSemester;
    final activeSemLabel = activeSem?['display_name'] ??
        '${activeSem?['school_year'] ?? 'Current Year'} - ${activeSem?['label'] ?? 'Active Term'}';

    final sectionCounts = <String, int>{};
    for (final s in _parsedFreshStudents) {
      final sec = s['section']?.toString().trim() ?? '';
      final label = sec.isEmpty ? 'Unassigned' : sec;
      sectionCounts[label] = (sectionCounts[label] ?? 0) + 1;
    }

    final filtered = _parsedFreshStudents.where((s) {
      final q = _freshSearchCtrl.text.trim().toLowerCase();
      final idNum = s['id_number']?.toString().toLowerCase() ?? '';
      final name = '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.toLowerCase();
      final email = s['email']?.toString().toLowerCase() ?? '';
      final matchQuery =
          q.isEmpty || idNum.contains(q) || name.contains(q) || email.contains(q);
      if (!matchQuery) return false;

      if (_selectedFreshSectionFilter != 'ALL') {
        final sec = s['section']?.toString().trim() ?? '';
        final label = sec.isEmpty ? 'Unassigned' : sec;
        if (label != _selectedFreshSectionFilter) return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeSem == null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block_rounded, color: Color(0xFFDC2626), size: 22),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Academic Semester Required for Student Enrollment',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'No active semester is currently configured in the system. Student class lists cannot be imported or enrolled until an Academic Period is created and set to Active under Setup & Configuration > Academic Periods.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF7F1D1D),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Top 2-Column Section: Left is Smart Format Guide, Right is Primary Upload Action
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 960;
            if (!isWide) {
              return Column(
                children: [
                  _buildFreshFormatCard(activeSemLabel),
                  const SizedBox(height: 18),
                  _buildFreshUploadCard(),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: _buildFreshFormatCard(activeSemLabel),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 6,
                  child: _buildFreshUploadCard(),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // Bottom Full-Width Preflight Review Table Card
        _buildFreshReviewTableCard(
          filtered: filtered,
          sectionCounts: sectionCounts,
          totalStudents: _parsedFreshStudents.length,
          activeSem: activeSem,
        ),
      ],
    );
  }

  Widget _buildSpecChip(String label, Color bg, Color fg, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: fg.withValues(alpha: 0.15)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildFreshFormatCard(String activeSemLabel) {
    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 240),
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
                  child: const Icon(Icons.fact_check_outlined, color: _maroon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Official Class List Template',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Target Term: $activeSemLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Smart Spec Badges Group
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Detected Preamble Headers
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.auto_awesome_rounded, size: 14, color: _maroon),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Auto-Detected Preamble Headers (Rows 2, 9, 10, 11):',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _buildSpecChip('Instructor (PIT Only)', const Color(0xFFFEE2E2), _maroon),
                                _buildSpecChip('Academic Term', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
                                _buildSpecChip('Class Section', const Color(0xFFDCFCE7), const Color(0xFF15803D)),
                                _buildSpecChip('Year Level', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 10),

                  // Row 2: Required Student Columns
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.table_chart_outlined, size: 14, color: Color(0xFF475569)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Required Student Table Columns (Row 14+):',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _buildSpecChip('Student Number *', const Color(0xFFF1F5F9), _ink, isBold: true),
                                _buildSpecChip('Full Name *', const Color(0xFFF1F5F9), _ink, isBold: true),
                                _buildSpecChip('Email *', const Color(0xFFF1F5F9), _ink, isBold: true),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Tip note
            const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: _muted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Extra university preamble headers & table columns are safely ignored.',
                    style: TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Action Buttons Row: View Blueprint Modal & Download Template
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showClassListFormatGuideModal(
                    context,
                    isRollover: false,
                    activeSemLabel: activeSemLabel,
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: const Text('View Sheet Layout Blueprint'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _maroon,
                    side: BorderSide(color: _maroon.withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    side: const BorderSide(color: _line),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  void _showClassListFormatGuideModal(
    BuildContext context, {
    required bool isRollover,
    required String activeSemLabel,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
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
                                  : 'Official University Class List Blueprint (Fresh Intake)',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Target Term: $activeSemLabel • Visual guide for required preamble metadata and student columns',
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

                // Scrollable Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Preamble Info Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB45309)),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.4),
                                    children: [
                                      TextSpan(
                                        text: 'Preamble Metadata Needed: ',
                                        style: TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      TextSpan(
                                        text: 'DefenSYS automatically reads ',
                                      ),
                                      TextSpan(
                                        text: 'Instructor (PIT), Term (S.Y. & Semester), Section, and Year Level ',
                                        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF78350F)),
                                      ),
                                      TextSpan(
                                        text: 'from Rows 2, 9, 10, 11, and imports ',
                                      ),
                                      TextSpan(
                                        text: 'Student Number, Full Name, and Email ',
                                        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF78350F)),
                                      ),
                                      TextSpan(
                                        text: 'from the table. Extra university headers and columns are safely ignored.',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Spreadsheet Preview
                        _buildSampleClassListPreview(isRollover: isRollover),
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
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          widget.onDownloadSample?.call();
                        },
                        icon: const Icon(Icons.download_rounded, size: 15),
                        label: const Text('Download Sample Template (.csv)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: const BorderSide(color: _line),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
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
  }

  Widget _buildSampleClassListPreview({bool isRollover = false}) {
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
                      const Icon(Icons.insert_drive_file_outlined, size: 12, color: Color(0xFF16A34A)),
                      const SizedBox(width: 5),
                      Text(
                        isRollover ? 'official_class_list_rollover.csv' : 'official_class_list_fresh.csv',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildMiniBadge('⭐ 4 Required Headers Highlighted', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
              ],
            ),
          ),

          // Row 1: Document Title (Standard)
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
            badgeText: 'Term (Required)',
            badgeBg: const Color(0xFFEFF6FF),
            badgeFg: const Color(0xFF1D4ED8),
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

          // Row 9: Instructor / Faculty (PIT Required, Capstone Assigns Advisers to Teams)
          _buildOfficialHeaderRow(
            rowNumber: '9',
            keyName: isRollover ? 'Adviser / Faculty' : 'Instructor',
            valueText: isRollover ? 'Prof. Ricardo Fontanilla' : 'Maricel Suarez',
            badgeText: isRollover
                ? 'Optional for Capstone (Advisers Assigned to Teams)'
                : 'Instructor (Required for PIT)',
            badgeBg: isRollover ? const Color(0xFFF1F5F9) : const Color(0xFFFEE2E2),
            badgeFg: isRollover ? const Color(0xFF475569) : _maroon,
            isRequired: !isRollover,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Row 10: Class Section (HIGHLIGHTED - REQUIRED)
          _buildOfficialHeaderRow(
            rowNumber: '10',
            keyName: 'Class Section',
            valueText: isRollover ? 'BSIT-4A' : 'BSIT-1A',
            badgeText: 'Section (Required)',
            badgeBg: const Color(0xFFDCFCE7),
            badgeFg: const Color(0xFF15803D),
            isRequired: true,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Row 11: Year Level (HIGHLIGHTED - REQUIRED)
          _buildOfficialHeaderRow(
            rowNumber: '11',
            keyName: 'Year Level',
            valueText: isRollover ? '4th Year' : '1st Year',
            badgeText: 'Year Level (Required)',
            badgeBg: const Color(0xFFFEF3C7),
            badgeFg: const Color(0xFF92400E),
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
            id: isRollover ? '2023-00101' : '1011',
            name: 'RIVERA, James',
            prog: 'BSIT',
            gen: 'M',
            level: isRollover ? '4th Yr.' : '1st Yr.',
            email: isRollover ? 'j.rivera@ustp.edu.ph' : '1011@ustp.edu.ph',
            contact: '09170001011',
            isAlt: false,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildOfficialStudentRow(
            rowNumber: '16',
            index: '2',
            id: isRollover ? '2023-00102' : '1012',
            name: 'LIM, Sofia',
            prog: 'BSIT',
            gen: 'F',
            level: isRollover ? '4th Yr.' : '1st Yr.',
            email: isRollover ? 's.lim@ustp.edu.ph' : '1012@ustp.edu.ph',
            contact: '09170001012',
            isAlt: true,
          ),
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
      color: isRequired ? const Color(0xFFFFFBEB).withValues(alpha: 0.6) : Colors.white,
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
                      color: isRequired ? _maroon : const Color(0xFF64748B),
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

  Widget _buildFreshUploadCard() {
    final hasFiles = _stagedFreshFiles.isNotEmpty;
    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 240),
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
                    color: hasFiles
                        ? const Color(0xFFDCFCE7)
                        : _maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasFiles
                        ? Icons.task_alt_rounded
                        : Icons.cloud_upload_outlined,
                    color: hasFiles ? _green : _maroon,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasFiles
                            ? 'Staged Class List Source Files'
                            : 'Upload Class List Files',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasFiles
                            ? '${_stagedFreshFiles.length} file(s) staged • ${_parsedFreshStudents.length} students ready'
                            : 'Supports official university CSV and XLSX formats',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasFiles) ...[
                  OutlinedButton.icon(
                    onPressed: () => _openFreshStagingModal(_stagedFreshFiles),
                    icon: const Icon(Icons.folder_open_rounded, size: 15),
                    label: const Text('Review Files'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _maroon,
                      side: const BorderSide(color: _maroon),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () {
                if (hasFiles) {
                  _openFreshStagingModal(_stagedFreshFiles);
                } else {
                  _pickFreshFiles();
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  color: hasFiles ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasFiles ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1),
                    width: hasFiles ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasFiles
                          ? Icons.inventory_2_outlined
                          : Icons.cloud_upload_outlined,
                      size: 30,
                      color: hasFiles ? _green : _maroon,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasFiles
                          ? '${_stagedFreshFiles.length} Class List File(s) Staged (Click to View / Add)'
                          : 'Click to choose official class list (.csv / .xlsx)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: hasFiles ? const Color(0xFF15803D) : _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasFiles
                          ? 'Review sections, replace, or add more class section files'
                          : 'Supports staging multiple class section files at once',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: hasFiles ? const Color(0xFF166534) : _muted,
                      ),
                    ),
                    if (!hasFiles) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSpecChip('CSV', const Color(0xFFF1F5F9), const Color(0xFF475569)),
                          const SizedBox(width: 6),
                          _buildSpecChip('XLSX', const Color(0xFFF1F5F9), const Color(0xFF475569)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (hasFiles) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _stagedFreshFiles.clear();
                      _parsedFreshStudents.clear();
                      _selectedFreshSectionFilter = 'ALL';
                    });
                    ref.read(studentBatchDraftProvider.notifier).clearFreshDraft();
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 15),
                  label: const Text('Clear all staged files'),
                  style: TextButton.styleFrom(
                    foregroundColor: _muted,
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFreshReviewTableCard({
    required List<Map<String, dynamic>> filtered,
    required Map<String, int> sectionCounts,
    required int totalStudents,
    required Map<String, dynamic>? activeSem,
  }) {
    final totalCount = filtered.length;
    final totalPages = (totalCount / _freshRowsPerPage).ceil();
    if (_freshPage >= totalPages && totalPages > 0) {
      _freshPage = totalPages - 1;
    }
    final startIndex = _freshPage * _freshRowsPerPage;
    final endIndex = (startIndex + _freshRowsPerPage).clamp(0, totalCount);
    final pageRows = totalCount == 0
        ? <Map<String, dynamic>>[]
        : filtered.sublist(startIndex, endIndex);

    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Toolbar
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Preflight Student Intake Review',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const Spacer(),
                    _buildSummaryBadge(
                      'Total Students: $totalStudents',
                      const Color(0xFFDCFCE7),
                      _green,
                    ),
                    if (sectionCounts.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _buildSummaryBadge(
                        'Sections: ${sectionCounts.length}',
                        const Color(0xFFE0E7FF),
                        const Color(0xFF3730A3),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                // Section Filter Tabs
                if (sectionCounts.length > 1) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSectionPill('ALL', 'All Sections ($totalStudents)'),
                        ...sectionCounts.entries
                            .map((e) => _buildSectionPill(e.key, '${e.key} (${e.value})')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _freshSearchCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 18, color: _muted),
                            hintText: 'Search by student ID, name, or email...',
                            hintStyle: const TextStyle(fontSize: 12.5, color: _muted),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _line),
                            ),
                          ),
                          onChanged: (_) => setState(() {
                            _freshPage = 0;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),

          // Table Content
          if (totalStudents == 0)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.upload_file_rounded, size: 36, color: _muted),
                    SizedBox(height: 10),
                    Text(
                      'No student class list files uploaded yet.',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Upload official class list (.csv / .xlsx) files above to generate the preflight review table.',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text('No students match the current search or section filter.'),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pageRows.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
              itemBuilder: (context, index) {
                final s = pageRows[index];
                final idNum =
                    s['id_number']?.toString() ?? s['username']?.toString() ?? '';
                final firstName = s['first_name']?.toString() ?? '';
                final lastName = s['last_name']?.toString() ?? '';
                final fullName = '$lastName, $firstName'.trim();
                final displayName =
                    fullName == ',' ? (s['name']?.toString() ?? 'Student') : fullName;
                final email = s['email']?.toString() ?? '';
                final year = s['year_level']?.toString() ?? 'Unassigned';
                final sec = s['section']?.toString() ?? 'Unassigned';

                final instructor = (s['faculty'] ?? s['instructor'] ?? s['instructor_name'] ?? '').toString().trim();
                final isCapstoneStudent = year.contains('4th') ||
                    (year.contains('3rd') &&
                        (activeSem?['label']?.toString().contains('2nd') ?? false));

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  color: index.isEven ? Colors.white : const Color(0xFFF9FAFB),
                  child: Row(
                    children: [
                      // Student ID and Name
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: $idNum • $email',
                              style: const TextStyle(fontSize: 12, color: _muted),
                            ),
                          ],
                        ),
                      ),

                      // Section & Year Level Badges
                      Expanded(
                        flex: 4,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Text(
                                'Section: $sec',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Text(
                                year,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                            ),
                            if (!isCapstoneStudent && instructor.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFBBF7D0)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.co_present_rounded, size: 12, color: Color(0xFF16A34A)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Instructor: $instructor',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Intake Status Badge
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: activeSem == null
                                ? const Color(0xFFFEE2E2)
                                : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            activeSem == null
                                ? 'Blocked (No Active Term)'
                                : 'Ready to Enroll',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: activeSem == null
                                  ? const Color(0xFFDC2626)
                                  : _green,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Pagination Controls
          if (totalStudents > 0 && filtered.isNotEmpty) ...[
            const Divider(height: 1, color: _line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: _buildPaginationControls(
                totalCount: filtered.length,
                currentPage: _freshPage,
                rowsPerPage: _freshRowsPerPage,
                onPageChanged: (newPage) => setState(() => _freshPage = newPage),
                onRowsPerPageChanged: (newRpp) => setState(() {
                  _freshRowsPerPage = newRpp;
                  _freshPage = 0;
                }),
              ),
            ),
          ],

          const Divider(height: 1, color: _line),
          // Bottom Actions
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _line),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _parsedFreshStudents.isEmpty ||
                          widget.userState.isSaving ||
                          activeSem == null
                      ? null
                      : _confirmFreshIntake,
                  icon: Icon(
                    activeSem == null
                        ? Icons.block_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(
                    activeSem == null
                        ? 'Active Semester Required (Import Blocked)'
                        : 'Confirm Student Intake (${_parsedFreshStudents.length} students)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeSem == null
                        ? Colors.grey
                        : _maroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionPill(String id, String label) {
    final isSelected = _selectedFreshSectionFilter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() {
          _selectedFreshSectionFilter = id;
          _freshPage = 0;
        }),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? _maroon : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? _maroon : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFreshFiles() async {
    try {
      final files = await pickMultipleTabularDataFiles();
      if (!mounted || files.isEmpty) return;
      await _openFreshStagingModal(files);
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Could not read file(s): $e');
      }
    }
  }

  Future<void> _openFreshStagingModal(List<PickedTabularFile> initialFiles) async {
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
      );
      if (!mounted || result == null) return;
      if (result.files.isEmpty) {
        setState(() {
          _stagedFreshFiles.clear();
          _parsedFreshStudents.clear();
          _selectedFreshSectionFilter = 'ALL';
        });
        ref.read(studentBatchDraftProvider.notifier).clearFreshDraft();
        return;
      }

      await _processFreshFiles(result.files);
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Error staging fresh intake file(s): $e');
      }
    }
  }

  Future<void> _processFreshFiles(List<PickedTabularFile> files) async {
    if (!mounted || files.isEmpty) return;
    try {
      final allStudents = <Map<String, dynamic>>[];
      final validFiles = <PickedTabularFile>[];

      for (final file in files) {
        if (file.isXlsx) {
          final official = parseOfficialClassListXlsx(file.bytes);
          if (official.students.isNotEmpty) {
            allStudents.addAll(official.students);
            validFiles.add(file);
          }
          continue;
        }

        final text = file.text ?? utf8.decode(file.bytes, allowMalformed: true);
        final official = parseOfficialClassListCsv(text);
        if (official.students.isNotEmpty) {
          allStudents.addAll(official.students);
          validFiles.add(file);
        }
      }

      if (allStudents.isEmpty) {
        if (mounted) {
          showErrorToast(context, 'No valid student rows found in staged file(s).');
        }
        return;
      }

      final skippedCount = files.length - validFiles.length;

      setState(() {
        _stagedFreshFiles = List.from(validFiles);
        _parsedFreshStudents = List.from(allStudents);
        _selectedFreshSectionFilter = 'ALL';
      });

      ref.read(studentBatchDraftProvider.notifier).saveFreshDraft(
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
    if (_parsedFreshStudents.isEmpty) return;
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
    ref.read(studentBatchDraftProvider.notifier).clearFreshDraft();
    widget.onConfirmFreshImport(
      _parsedFreshStudents,
      {'semester_id': activeSem['id']},
    );
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
        ),
      ],
    );
  }

  Widget _buildRolloverRulesCard(String activeSemLabel) {
    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 240),
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
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Target Term: $activeSemLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
              padding: const EdgeInsets.all(12),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.trending_up_rounded, size: 14, color: _maroon),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Standard Year Level Progression:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              '• 1st Sem advances to 2nd Sem (Same Year Level)\n• 2nd Sem advances to next Year Level (1st Yr → 2nd Yr → 3rd Yr → 4th Yr)',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: _muted,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 10),

                  // Row 2: Capstone Stages in DefenSYS
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.school_rounded, size: 14, color: _green),
                          const SizedBox(width: 6),
                          const Text(
                            'Capstone Stages:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                      _buildMilestoneTag('3rd Yr (2nd Sem)', 'Capstone 1', const Color(0xFFDCFCE7), _green),
                      const Icon(Icons.arrow_forward_rounded, size: 12, color: _muted),
                      _buildMilestoneTag('4th Yr (1st Sem)', 'Capstone 2 (Final)', const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 13, color: _maroon),
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
              spacing: 8,
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
                    foregroundColor: _maroon,
                    side: BorderSide(color: _maroon.withValues(alpha: 0.35)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    side: const BorderSide(color: _line),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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


  Widget _buildMilestoneTag(String term, String stage, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
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
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              stage,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRolloverSourceCard(StudentAcademicRecordsState state) {
    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 240),
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
                    color: _hasCsvUploaded
                        ? const Color(0xFFDCFCE7)
                        : _maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _hasCsvUploaded
                        ? Icons.task_alt_rounded
                        : Icons.cloud_upload_outlined,
                    color: _hasCsvUploaded ? _green : _maroon,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasCsvUploaded
                            ? 'Staged Class List Source Files'
                            : 'Cohort Source & Class List Matching',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _hasCsvUploaded
                            ? '${_stagedRolloverFiles.length} file(s) currently staged for cohort review'
                            : 'Matches active student IDs & skips non-enrolled',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_hasCsvUploaded) ...[
                  OutlinedButton.icon(
                    onPressed: state.isSaving
                        ? null
                        : () => _openRolloverStagingModal(_stagedRolloverFiles),
                    icon: const Icon(Icons.folder_open_rounded, size: 15),
                    label: const Text('Review Files'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _maroon,
                      side: const BorderSide(color: _maroon),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  color: _hasCsvUploaded
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _hasCsvUploaded
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFCBD5E1),
                    width: _hasCsvUploaded ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _hasCsvUploaded
                          ? Icons.inventory_2_outlined
                          : Icons.cloud_upload_outlined,
                      size: 30,
                      color: _hasCsvUploaded ? _green : _maroon,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hasCsvUploaded
                          ? '${_stagedRolloverFiles.length} Class List File(s) Staged (Click to View / Add)'
                          : 'Click to choose official class list (.csv / .xlsx)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _hasCsvUploaded ? const Color(0xFF15803D) : _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hasCsvUploaded
                          ? 'Review sections, replace, or add more class section files'
                          : 'Supports staging multiple class section files at once',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _hasCsvUploaded
                            ? const Color(0xFF166534)
                            : _muted,
                      ),
                    ),
                    if (!_hasCsvUploaded) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSpecChip('CSV', const Color(0xFFF1F5F9), const Color(0xFF475569)),
                          const SizedBox(width: 6),
                          _buildSpecChip('XLSX', const Color(0xFFF1F5F9), const Color(0xFF475569)),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Toolbar
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Preflight Cohort Review',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const Spacer(),
                    // Summary counts
                    if (createCount > 0) ...[
                      _buildSummaryBadge('New Enrollees: $createCount', const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
                      const SizedBox(width: 8),
                    ],
                    _buildSummaryBadge('Promote: $promoteCount', const Color(0xFFDCFCE7), _green),
                    const SizedBox(width: 8),
                    _buildSummaryBadge('Retain / Repeaters: $retainCount', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
                    const SizedBox(width: 8),
                    _buildSummaryBadge('Skip / Dropped: $dropCount', const Color(0xFFF3F4F6), _muted),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
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
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: _line),
                            ),
                          ),
                          onChanged: (_) => setState(() {
                            _rolloverPage = 0;
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
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
                      style: FilledButton.styleFrom(
                        backgroundColor: _maroon,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      child: const Text('Promote All'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
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
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF3F4F6),
                        foregroundColor: _ink,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      child: const Text('Retain All'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),

          // Table Content
          if (state.isSaving || state.isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text('No student records found for rollover review.'),
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
                            border: Border.all(color: _line),
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
            const Divider(height: 1, color: _line),
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

          const Divider(height: 1, color: _line),
          // Bottom Actions
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _line),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: state.isSaving ? null : _confirmRolloverCommit,
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Confirm Semester Rollover'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _maroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

  Widget _buildSummaryBadge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  Widget _buildTargetStandingPreview(
    String action,
    Map<dynamic, dynamic> pr,
    Map<dynamic, dynamic> rec,
  ) {
    if (action == 'drop') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Excluded from Term',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _muted),
        ),
      );
    }

    if (action == 'create') {
      final targetYear = pr['year_level']?.toString() ?? rec['year_level']?.toString() ?? 'Enrolled Level';
      final targetSection = pr['section']?.toString() ?? rec['section']?.toString() ?? 'Assigned Section';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE0E7FF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'New Enrollee → $targetYear ($targetSection)',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3730A3),
          ),
        ),
      );
    }

    if (action == 'retain') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Repeats ${rec['year_level'] ?? 'Standing'} (Retained)',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF92400E),
          ),
        ),
      );
    }

    final targetYear = pr['year_level']?.toString() ?? 'Next Level';
    final targetSection = pr['section']?.toString() ?? 'Assigned Section';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Promoted → $targetYear ($targetSection)',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: _green,
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
      final allStudents = <Map<String, dynamic>>[];
      final validFiles = <PickedTabularFile>[];

      for (final file in files) {
        if (file.isXlsx) {
          final official = parseOfficialClassListXlsx(file.bytes);
          if (official.students.isNotEmpty) {
            allStudents.addAll(official.students);
            validFiles.add(file);
          }
          continue;
        }

        final text = file.text ?? utf8.decode(file.bytes, allowMalformed: true);
        final official = parseOfficialClassListCsv(text);
        if (official.students.isNotEmpty) {
          allStudents.addAll(official.students);
          validFiles.add(file);
        }
      }

      if (allStudents.isEmpty) {
        if (mounted) {
          showErrorToast(context, 'No valid student rows found in staged file(s).');
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
      final pr = row['promote_result'] as Map? ?? {};

      confirmActions.add({
        'record_id': rec['id'],
        'username': rec['student_username'],
        'first_name': rec['first_name'],
        'last_name': rec['last_name'],
        'email': rec['student_email'],
        'action': act,
        'year_level': pr['year_level'],
        'section': pr['section'],
      });
    }

    final ok = await ref
        .read(studentAcademicRecordsProvider.notifier)
        .confirmRollover(confirmActions);

    if (ok && mounted) {
      ref.read(studentBatchDraftProvider.notifier).clearRolloverDraft();
      showSuccessToast(context, 'Semester rollover completed successfully.');
      ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
      ref.read(userManagementProvider.notifier).fetchUsers();
      widget.onBack();
    }
  }
}
