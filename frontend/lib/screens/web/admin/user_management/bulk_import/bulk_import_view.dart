import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/file_import_staging_modal.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/import/student_bulk_import_csv.dart';
import 'package:defensys/utils/import/user_bulk_import_draft.dart';
import 'official_class_list_parser.dart';

/// Full Bulk CSV / XLSX Import view matching the canonical design and behavior.
class BulkImportView extends StatefulWidget {
  const BulkImportView({
    super.key,
    required this.state,
    required this.academicState,
    required this.onBack,
    this.onPickFile,
    this.onDownloadSample,
    required this.onConfirmUpload,
  });

  final UserManagementState state;
  final AcademicPeriodState academicState;
  final VoidCallback onBack;
  final VoidCallback? onPickFile;
  final VoidCallback? onDownloadSample;
  final void Function(
    List<Map<String, dynamic>> students,
    Map<String, dynamic>? studentContext,
  ) onConfirmUpload;

  @override
  State<BulkImportView> createState() => _BulkImportViewState();
}

class _BulkImportViewState extends State<BulkImportView> {
  static const Color _ink = DefensysUi.textDark;
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _maroon = DefensysUi.primaryMaroon;
  static const Color _gold = Color(0xFFF6C343);
  static const Color _muted = DefensysUi.steelGrey;

  String _bulkImportType = 'student';
  String _studentPeriodSource = 'explicit';
  String _targetSemesterId = '';
  String _batchYearLevel = '';
  String _bulkCsv = '';
  List<PickedTabularFile> _stagedSourceFiles = [];
  UserBulkImportDraft? _savedBulkDraft;
  Timer? _bulkDraftDebounce;

  final TextEditingController _bulkReviewSearchController =
      TextEditingController();
  int _bulkReviewPage = 0;
  int _bulkReviewRowsPerPage = 10;
  static const List<int> _bulkReviewRowsPerPageOptions = [10, 25, 50, 100];
  String _selectedReviewSection = 'ALL';

  String get _selectedBulkImportType => _bulkImportType;
  String get _selectedStudentPeriodSource => _studentPeriodSource;
  String get _selectedTargetSemesterId => _targetSemesterId;
  String get _selectedBatchYearLevel => _batchYearLevel;
  String get _csvDraft => _bulkCsv;

  bool get _isBulkImportDirty {
    if (_savedBulkDraft == null) {
      return _csvDraft.trim().isNotEmpty ||
          _selectedBulkImportType != 'student' ||
          _selectedStudentPeriodSource != 'explicit' ||
          _selectedTargetSemesterId.isNotEmpty ||
          _selectedBatchYearLevel.isNotEmpty;
    }

    return _savedBulkDraft!.csv != _csvDraft ||
        _savedBulkDraft!.importType != _selectedBulkImportType ||
        _savedBulkDraft!.studentPeriodSource != _selectedStudentPeriodSource ||
        _savedBulkDraft!.targetSemesterId != _selectedTargetSemesterId ||
        _savedBulkDraft!.batchYearLevel != _selectedBatchYearLevel;
  }

  @override
  void initState() {
    super.initState();
    _loadBulkDraft();
  }

  @override
  void dispose() {
    _bulkDraftDebounce?.cancel();
    _bulkReviewSearchController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadBulkDraft() async {
    final draft = await loadUserBulkImportDraft();
    if (!mounted || draft == null) return;
    setState(() {
      _savedBulkDraft = draft;
      _bulkCsv = draft.csv;
      _bulkImportType = draft.importType;
      _studentPeriodSource = draft.studentPeriodSource;
      _targetSemesterId = draft.targetSemesterId;
      _batchYearLevel = draft.batchYearLevel;
    });
  }

  void _scheduleBulkDraftSave() {
    _bulkDraftDebounce?.cancel();
    _bulkDraftDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final rows = _parseCsv(_csvDraft);
      final official = _selectedBulkImportType == 'student'
          ? parseOfficialClassListCsv(_csvDraft)
          : const AdminOfficialClassListParseResult(metadata: {}, students: []);
      final warnings = _bulkImportWarnings(rows, official);

      final draft = UserBulkImportDraft(
        csv: _csvDraft,
        importType: _selectedBulkImportType,
        studentPeriodSource: _selectedStudentPeriodSource,
        targetSemesterId: _selectedTargetSemesterId,
        batchYearLevel: _selectedBatchYearLevel,
        savedAt: DateTime.now(),
        rowCount: rows.length,
        warningCount: warnings.length,
      );

      await saveUserBulkImportDraft(draft);
      if (mounted) {
        setState(() => _savedBulkDraft = draft);
      }
    });
  }

  Future<bool> _requestCloseBulkImport() async {
    if (!_isBulkImportDirty) {
      widget.onBack();
      return true;
    }

    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Discard import draft?'),
        content: const Text(
          'You have unimported CSV data or configuration changes. Leaving now will discard your current draft.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard & Leave'),
          ),
        ],
      ),
    );

    if (leave == true) {
      await clearUserBulkImportDraft();
      widget.onBack();
      return true;
    }
    return false;
  }

  List<_SemesterOption> _semesterOptions(AcademicPeriodState academicState) {
    final options = <_SemesterOption>[];
    for (final period in academicState.schoolYears) {
      final periodName =
          period['name']?.toString() ?? period['year']?.toString() ?? 'Period';
      final sems = period['semesters'] as List? ?? [];
      for (final sem in sems) {
        if (sem is Map) {
          final id = sem['id']?.toString() ?? '';
          final name = sem['name']?.toString() ?? 'Semester';
          options.add(_SemesterOption(id: id, label: '$periodName - $name'));
        }
      }
    }
    return options;
  }

  String _resolvedSemesterLabel(
    AcademicPeriodState academicState,
    List<_SemesterOption> semesterOptions,
  ) {
    if (_selectedBulkImportType != 'student') {
      return 'Not applicable';
    }

    if (_selectedStudentPeriodSource == 'active') {
      final active = academicState.activeSemester;
      if (active == null) {
        return 'No active semester set';
      }
      return '${active['academic_period_name'] ?? 'Period'} - ${active['name'] ?? 'Active Semester'}';
    }

    if (_selectedTargetSemesterId.isEmpty) {
      return 'No target semester selected';
    }

    final match = semesterOptions.firstWhere(
      (opt) => opt.id == _selectedTargetSemesterId,
      orElse: () => const _SemesterOption(id: '', label: 'Unknown semester'),
    );
    return match.label;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBulkImportDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestCloseBulkImport();
      },
      child: SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefensysPageHeader(
              icon: Icons.output_rounded,
              title: 'Bulk Import Users',
              subtitle:
                  'Upload a CSV file to create multiple users at once. Default password is set to their ID number.',
              actions: _secondaryButton(
                icon: Icons.arrow_back_rounded,
                label: 'Back to Users',
                onTap: widget.state.isSaving ? null : _requestCloseBulkImport,
              ),
            ),
            const SizedBox(height: 28),
            _csvFormatCard(),
            const SizedBox(height: 20),
            _uploadCsvCard(widget.state, widget.academicState),
          ],
        ),
      ),
    );
  }

  Widget _csvFormatCard() {
    final studentBatch = _selectedBulkImportType == 'student';
    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CSV Format',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  studentBatch
                      ? 'Student Batch uses the official class list template, including section and year-level metadata.'
                      : 'Faculty / General Users uses the account-import template. Column order matters.',
                  style: const TextStyle(
                    color: Color(0xFF536079),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sampleCsvTable(),
                const SizedBox(height: 14),
                _infoBanner(
                  icon: Icons.info_rounded,
                  message: studentBatch
                      ? 'Use the official class list template for student cohorts. The importer detects Class Section and Year Level from the file, while semester remains controlled by the Student Batch settings.'
                      : 'Use Faculty / General Users for non-student imports so student-only academic setup does not interfere.',
                ),
                const SizedBox(height: 16),
                _secondaryButton(
                  icon: Icons.file_download_rounded,
                  label: 'Download Sample Template',
                  onTap: _downloadCsvTemplate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleCsvTable() {
    final studentBatch = _selectedBulkImportType == 'student';

    if (!studentBatch) {
      final columns = const [
        'id_number',
        'first_name',
        'last_name',
        'email',
        'role',
      ];
      final values = const [
        'FAC-0001',
        'Ada',
        'Lovelace',
        'ada@ustp.edu.ph',
        'faculty',
      ];

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFDDE2EA)),
        ),
        child: Column(
          children: [
            Container(
              height: 38,
              color: const Color(0xFFF0F1F4),
              child: Row(
                children: columns
                    .map((column) => _sampleCsvCell(column, header: true))
                    .toList(),
              ),
            ),
            Container(
              height: 38,
              color: Colors.white,
              child: Row(
                children: values.map((value) => _sampleCsvCell(value)).toList(),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: const Row(
              children: [
                Icon(Icons.description_outlined, size: 16, color: _maroon),
                SizedBox(width: 8),
                Text(
                  'Official Class List Structure (CSV / XLSX)',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. REQUIRED FILE HEADERS',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _templateHeaderBadge(
                      'Instructor',
                      'Maricel Suarez',
                      isExtracted: true,
                    ),
                    _templateHeaderBadge(
                      'Class Section',
                      'BSIT-1A',
                      isExtracted: true,
                    ),
                    _templateHeaderBadge(
                      'Year Level',
                      '1st Year',
                      isExtracted: true,
                    ),
                    _templateHeaderBadge(
                      'Subject / Schedule / Units',
                      'Optional',
                      isExtracted: false,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  '2. STUDENT TABLE COLUMNS',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 34,
                          color: const Color(0xFFF8FAFC),
                          child: const Row(
                            children: [
                              _MiniCell(
                                'Student Number',
                                isHeader: true,
                                flex: 2,
                                isUsed: true,
                              ),
                              _MiniCell(
                                'Full Name',
                                isHeader: true,
                                flex: 3,
                                isUsed: true,
                              ),
                              _MiniCell(
                                'Email',
                                isHeader: true,
                                flex: 3,
                                isUsed: true,
                              ),
                              _MiniCell(
                                'Level',
                                isHeader: true,
                                flex: 1,
                                isUsed: true,
                              ),
                              _MiniCell(
                                'OR / Contact / Units',
                                isHeader: true,
                                flex: 2,
                                isUsed: false,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 32,
                          color: Colors.white,
                          child: const Row(
                            children: [
                              _MiniCell('1011', flex: 2, isUsed: true),
                              _MiniCell('RIVERA, James', flex: 3, isUsed: true),
                              _MiniCell(
                                '1011@ustp.edu.ph',
                                flex: 3,
                                isUsed: true,
                              ),
                              _MiniCell('1st Yr.', flex: 1, isUsed: true),
                              _MiniCell(
                                'OR-1011 (Skipped)',
                                flex: 2,
                                isUsed: false,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 32,
                          color: const Color(0xFFF8FAFC),
                          child: const Row(
                            children: [
                              _MiniCell('1012', flex: 2, isUsed: true),
                              _MiniCell('LIM, Sofia', flex: 3, isUsed: true),
                              _MiniCell(
                                '1012@ustp.edu.ph',
                                flex: 3,
                                isUsed: true,
                              ),
                              _MiniCell('1st Yr.', flex: 1, isUsed: true),
                              _MiniCell(
                                'OR-1012 (Skipped)',
                                flex: 2,
                                isUsed: false,
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _templateHeaderBadge(
    String key,
    String example, {
    required bool isExtracted,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isExtracted ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isExtracted
              ? const Color(0xFFBBF7D0)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isExtracted
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            size: 13,
            color: isExtracted
                ? const Color(0xFF16A34A)
                : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 6),
          Text(
            '$key: ',
            style: TextStyle(
              color: isExtracted
                  ? const Color(0xFF15803D)
                  : const Color(0xFF64748B),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            example,
            style: TextStyle(
              color: isExtracted
                  ? const Color(0xFF166534)
                  : const Color(0xFF475569),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleCsvCell(String value, {bool header = false}) {
    return Expanded(
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFDDE2EA))),
        ),
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: header ? _ink : const Color(0xFF536079),
            fontSize: 13,
            fontWeight: header ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _uploadCsvCard(
    UserManagementState state,
    AcademicPeriodState academicState,
  ) {
    final semesterOptions = _semesterOptions(academicState);
    final semesterValues = semesterOptions.map((option) => option.id);
    final safeSemesterValue = semesterValues.contains(_selectedTargetSemesterId)
        ? _selectedTargetSemesterId
        : null;
    final reviewRows = _parseCsv(_csvDraft);
    final importBlockers = _bulkImportBlockingIssues(reviewRows);
    final canConfirmImport =
        _csvDraft.trim().isNotEmpty &&
        reviewRows.isNotEmpty &&
        importBlockers.isEmpty;

    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upload CSV',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Choose the import type first. Student-only options below are used only when you are importing a student batch.',
                  style: TextStyle(
                    color: Color(0xFF536079),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('IMPORT BATCH TYPE'),
                const SizedBox(height: 8),
                _dropdownBox(
                  value: _selectedBulkImportType,
                  hint: 'Select import type',
                  onChanged: state.isSaving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _bulkImportType = value;
                            if (value != 'student') {
                              _targetSemesterId = '';
                              _batchYearLevel = '';
                            }
                            _resetBulkReviewPaging();
                          });
                          _scheduleBulkDraftSave();
                        },
                  items: const [
                    DropdownMenuItem(
                      value: 'student',
                      child: Text('Student Batch'),
                    ),
                    DropdownMenuItem(
                      value: 'general',
                      child: Text('Faculty / General Users'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _helper(
                  _selectedBulkImportType == 'student'
                      ? 'Student Batch: rows will receive shared academic context.'
                      : 'Faculty / General Users: imports only accounts and roles.',
                ),
                if (_selectedBulkImportType == 'student') ...[
                  const SizedBox(height: 18),
                  _studentBatchOptions(
                    state: state,
                    semesterOptions: semesterOptions,
                    safeSemesterValue: safeSemesterValue,
                  ),
                ],
                const SizedBox(height: 20),
                _preflightReview(academicState, semesterOptions),
                const SizedBox(height: 20),
                _fieldLabel('CSV FILE'),
                const SizedBox(height: 8),
                _uploadDropZone(state),
                const SizedBox(height: 8),
                Text(
                  _selectedBulkImportType == 'student'
                      ? 'Student Batch accepts the official class list CSV template.'
                      : 'Columns: id_number, first_name, last_name, email, role',
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_csvDraft.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _bulkImportReview(),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    _primaryButton(
                      icon: Icons.system_update_alt_rounded,
                      label: state.isSaving
                          ? 'Importing...'
                          : _csvDraft.trim().isEmpty
                          ? 'Import Users'
                          : 'Confirm Import',
                      onTap: state.isSaving
                          ? null
                          : canConfirmImport
                          ? () => _importBulkUsers(academicState)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    _secondaryButton(
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      onTap: state.isSaving ? null : _requestCloseBulkImport,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentBatchOptions({
    required UserManagementState state,
    required List<_SemesterOption> semesterOptions,
    required String? safeSemesterValue,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Student Batch Options',
            style: TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'These settings apply only to imported Student rows and reuse the current import flow safely. For best results, upload one student year-level batch per CSV.',
            style: TextStyle(
              color: Color(0xFF536079),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('STUDENT PERIOD SOURCE'),
                    const SizedBox(height: 8),
                    _dropdownBox(
                      value: _selectedStudentPeriodSource,
                      hint: 'Select source',
                      onChanged: state.isSaving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _studentPeriodSource = value;
                                if (value == 'active') {
                                  _targetSemesterId = '';
                                }
                                _resetBulkReviewPaging();
                              });
                              _scheduleBulkDraftSave();
                            },
                      items: const [
                        DropdownMenuItem(
                          value: 'explicit',
                          child: Text('Explicit Target Semester'),
                        ),
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Use Active Semester'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _helper('Only used for Student Batch imports.'),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('TARGET SEMESTER'),
                    const SizedBox(height: 8),
                    _dropdownBox(
                      value: safeSemesterValue,
                      hint: '- Select semester -',
                      onChanged:
                          state.isSaving ||
                              _selectedStudentPeriodSource == 'active'
                          ? null
                          : (value) {
                              setState(() {
                                _targetSemesterId = value ?? '';
                                _resetBulkReviewPaging();
                              });
                              _scheduleBulkDraftSave();
                            },
                      items: semesterOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option.id,
                              child: Text(option.label),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 6),
                    _helper(
                      'Required only when Student Period Source is set to Explicit Target Semester.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _fieldLabel('BATCH YEAR LEVEL'),
          const SizedBox(height: 8),
          _dropdownBox(
            value: _selectedBatchYearLevel.isEmpty
                ? null
                : _selectedBatchYearLevel,
            hint: '- Select year level -',
            onChanged: state.isSaving
                ? null
                : (value) {
                    setState(() {
                      _batchYearLevel = value ?? '';
                      _resetBulkReviewPaging();
                    });
                    _scheduleBulkDraftSave();
                  },
            items: const [
              DropdownMenuItem(value: '1st Year', child: Text('1st Year')),
              DropdownMenuItem(value: '2nd Year', child: Text('2nd Year')),
              DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
              DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
            ],
          ),
          const SizedBox(height: 6),
          _helper(
            'Optional when the official class list includes Year Level. If selected, it must match the file.',
          ),
        ],
      ),
    );
  }

  Widget _preflightReview(
    AcademicPeriodState academicState,
    List<_SemesterOption> semesterOptions,
  ) {
    final officialContext = parseOfficialClassListCsv(_csvDraft).metadata;
    final detectedYear = officialContext['year_level']?.toString() ?? '';
    final detectedSection = officialContext['section']?.toString() ?? '';
    final resolvedYear = _selectedBatchYearLevel.isNotEmpty
        ? _selectedBatchYearLevel
        : detectedYear;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.search_rounded, color: _maroon, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Preflight Review',
                style: TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_stagedSourceFiles.isNotEmpty) ...[
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _maroon,
                    side: const BorderSide(color: Color(0xFFDDE2EA)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () => _openStagingModal(_stagedSourceFiles),
                  icon: const Icon(Icons.inventory_2_outlined, size: 14),
                  label: Text(
                    'Manage Source Files (${_stagedSourceFiles.length})',
                    style: const TextStyle(
                      fontFamily: DefensysTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Review the batch context below before importing. This helps prevent mixed student cohorts or the wrong target semester from being applied.',
            style: TextStyle(
              color: Color(0xFF536079),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _preflightMetric(
                  'IMPORT MODE',
                  _selectedBulkImportType == 'student'
                      ? 'Student Batch'
                      : 'Faculty / General Users',
                ),
              ),
              Expanded(
                child: _preflightMetric(
                  'RESOLVED SEMESTER',
                  _resolvedSemesterLabel(academicState, semesterOptions),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _preflightMetric(
                  'BATCH YEAR LEVEL',
                  _selectedBulkImportType == 'student' && resolvedYear.isNotEmpty
                      ? resolvedYear
                      : '-',
                ),
              ),
              Expanded(
                child: _preflightMetric(
                  'CLASS SECTION',
                  _selectedBulkImportType == 'student' &&
                          detectedSection.isNotEmpty
                      ? detectedSection
                      : '-',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFF93C5FD)),
            ),
            child: Text(
              _selectedBulkImportType == 'student'
                  ? 'Imported student rows automatically generate initial academic records tied to the selected semester and their respective class section/year level.'
                  : 'Faculty / General imports create accounts only. Student academic records are skipped for this import mode.',
              style: const TextStyle(
                color: Color(0xFF1D4ED8),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preflightMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
            color: _ink,
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _uploadDropZone(UserManagementState state) {
    final csv = _csvDraft;
    final parsedRows = _parseCsv(csv).length;
    final fileCount = _stagedSourceFiles.length;

    return InkWell(
      onTap: state.isSaving
          ? null
          : () {
              if (_stagedSourceFiles.isNotEmpty) {
                _openStagingModal(_stagedSourceFiles);
              } else {
                _pickCsvFile();
              }
            },
      borderRadius: BorderRadius.circular(8),
      child: DashedBorder(
        color: const Color(0xFFCBD5E1),
        radius: 8,
        child: Container(
          width: double.infinity,
          height: 136,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                csv.trim().isEmpty
                    ? Icons.cloud_upload_rounded
                    : Icons.inventory_2_rounded,
                color: csv.trim().isEmpty
                    ? const Color(0xFF98A2B3)
                    : DefensysTokens.maroon,
                size: 34,
              ),
              const SizedBox(height: 10),
              Text(
                csv.trim().isEmpty
                    ? 'Click to choose file or drag & drop'
                    : fileCount > 0
                    ? 'CSV content ready ($fileCount staged file${fileCount == 1 ? '' : 's'})'
                    : 'CSV content ready to import',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                csv.trim().isEmpty
                    ? 'Accepts .csv and .xlsx files'
                    : '$parsedRows valid row${parsedRows == 1 ? '' : 's'} detected • Click to review or replace files',
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bulkImportReview() {
    final rows = _parseCsv(_csvDraft);
    final official = _selectedBulkImportType == 'student'
        ? parseOfficialClassListCsv(_csvDraft)
        : const AdminOfficialClassListParseResult(metadata: {}, students: []);
    final blockers = _bulkImportBlockingIssues(rows);
    final warnings = _bulkImportWarnings(rows, official);

    final sectionCounts = <String, int>{};
    final sectionInstructors = <String, String>{};
    for (final r in rows) {
      final sec = (r['section']?.toString() ?? '').trim();
      final key = sec.isEmpty ? 'Unassigned' : sec;
      sectionCounts[key] = (sectionCounts[key] ?? 0) + 1;
      final inst = _rowInstructor(r);
      if (inst.isNotEmpty && !sectionInstructors.containsKey(key)) {
        sectionInstructors[key] = inst;
      }
    }

    final filteredRows = _filteredBulkReviewRows(rows);
    final previewRows = _pageBulkReviewRows(filteredRows);

    final rowYears = rows
        .map((r) => r['year_level']?.toString().trim() ?? '')
        .where((y) => y.isNotEmpty)
        .toSet();
    final rowSections = rows
        .map((r) => r['section']?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    final rowFaculties = rows
        .map((r) => _rowInstructor(r))
        .where((f) => f.isNotEmpty)
        .toSet();

    final officialYear = official.metadata['year_level']?.toString() ?? '';
    final officialSection = official.metadata['section']?.toString() ?? '';
    final officialFaculty = official.metadata['faculty']?.toString() ?? '';

    final detectedYear = officialYear.isNotEmpty
        ? officialYear
        : (rowYears.length == 1
            ? rowYears.first
            : (rowYears.length > 1 ? '${rowYears.length} Years' : ''));
    final detectedSection = officialSection.isNotEmpty
        ? officialSection
        : (rowSections.length == 1
            ? rowSections.first
            : (rowSections.length > 1
                ? '${rowSections.length} Sections'
                : ''));
    final detectedFaculty = officialFaculty.isNotEmpty
        ? officialFaculty
        : (rowFaculties.length == 1
            ? rowFaculties.first
            : (rowFaculties.length > 1
                ? '${rowFaculties.length} Instructors'
                : ''));

    final isSpecificSectionTab = _selectedReviewSection != 'ALL';
    final tabRows = isSpecificSectionTab
        ? rows.where((r) {
            final sec = (r['section']?.toString() ?? '').trim();
            if (_selectedReviewSection == 'Unassigned') return sec.isEmpty;
            return sec.toLowerCase() == _selectedReviewSection.toLowerCase();
          }).toList()
        : rows;

    final tabYears = tabRows
        .map((r) => r['year_level']?.toString().trim() ?? '')
        .where((y) => y.isNotEmpty)
        .toSet();
    final tabInstructors = tabRows
        .map((r) => _rowInstructor(r))
        .where((f) => f.isNotEmpty)
        .toSet();

    final cardRowsText = tabRows.length.toString();
    final cardSectionText = isSpecificSectionTab
        ? _selectedReviewSection
        : (detectedSection.isEmpty ? '-' : detectedSection);
    final cardInstructorText = isSpecificSectionTab
        ? (tabInstructors.isNotEmpty
            ? tabInstructors.join(', ')
            : (sectionInstructors[_selectedReviewSection] ?? '-'))
        : (detectedFaculty.isEmpty ? '-' : detectedFaculty);
    final cardYearText = _selectedBatchYearLevel.isNotEmpty
        ? _selectedBatchYearLevel
        : (tabYears.length == 1
            ? tabYears.first
            : (detectedYear.isEmpty ? '-' : detectedYear));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: _maroon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Review Import',
                  style: DefensysUi.sectionTitle.copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Check the detected context and parsed rows before committing this import.',
            style: TextStyle(
              color: Color(0xFF536079),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _reviewSectionTabs(sectionCounts, sectionInstructors, rows.length),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _reviewMetric('Rows', cardRowsText),
              _reviewMetric(
                'Mode',
                _selectedBulkImportType == 'student'
                    ? 'Student Batch'
                    : 'Faculty / General',
              ),
              if (_selectedBulkImportType == 'student')
                _reviewMetric('Year Level', cardYearText),
              if (_selectedBulkImportType == 'student')
                _reviewMetric('Section', cardSectionText),
              if (_selectedBulkImportType == 'student')
                _reviewMetric('Instructor', cardInstructorText),
              if (blockers.isNotEmpty)
                _reviewMetric('Blocked', blockers.length.toString()),
            ],
          ),
          if (blockers.isNotEmpty) ...[
            const SizedBox(height: 16),
            _reviewBlockingIssues(blockers),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _reviewWarnings(warnings),
          ],
          const SizedBox(height: 16),
          _bulkReviewControls(rows.length, filteredRows.length),
          const SizedBox(height: 12),
          _reviewRowsTable(previewRows),
          const SizedBox(height: 12),
          _bulkReviewPagination(filteredRows.length),
        ],
      ),
    );
  }

  Widget _reviewSectionTabs(
    Map<String, int> sectionCounts,
    Map<String, String> sectionInstructors,
    int totalRows,
  ) {
    if (sectionCounts.length <= 1) return const SizedBox.shrink();

    final tabs = <Map<String, dynamic>>[
      {'id': 'ALL', 'label': 'All Sections', 'count': totalRows},
      ...sectionCounts.entries.map((e) {
        final inst = sectionInstructors[e.key] ?? '';
        final label = inst.isNotEmpty ? '${e.key} • $inst' : e.key;
        return {'id': e.key, 'label': label, 'count': e.value};
      }),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((tab) {
            final id = tab['id'] as String;
            final label = tab['label'] as String;
            final count = tab['count'] as int;
            final isSelected =
                _selectedReviewSection == id ||
                (_selectedReviewSection == 'ALL' && id == 'ALL');

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedReviewSection = id;
                    _resetBulkReviewPaging();
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? _maroon : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? _maroon : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF334155),
                          fontSize: 12.5,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.2)
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF475569),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _reviewMetric(String label, String value) {
    return Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewWarnings(List<String> warnings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DefensysUi.warningBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: DefensysUi.warningBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: warnings
            .map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: DefensysUi.warningText,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style: const TextStyle(
                          color: DefensysUi.warningText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _reviewBlockingIssues(List<String> issues) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: issues
            .map(
              (issue) {
                final isSwitchToGeneral = issue
                    .toLowerCase()
                    .contains('faculty / general users');
                final isSwitchToStudent = issue
                    .toLowerCase()
                    .contains('student batch');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFDC2626),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              issue,
                              style: const TextStyle(
                                color: Color(0xFF991B1B),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isSwitchToGeneral) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _bulkImportType = 'general';
                                _targetSemesterId = '';
                                _batchYearLevel = '';
                                _resetBulkReviewPaging();
                              });
                              _scheduleBulkDraftSave();
                            },
                            icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                            label: const Text('Switch to Faculty / General Users Mode'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: DefensysTokens.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ] else if (isSwitchToStudent) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _bulkImportType = 'student';
                                _resetBulkReviewPaging();
                              });
                              _scheduleBulkDraftSave();
                            },
                            icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                            label: const Text('Switch to Student Batch Mode'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: DefensysTokens.fontFamily,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            )
            .toList(),
      ),
    );
  }

  Widget _bulkReviewControls(int totalRows, int filteredRows) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _bulkReviewSearchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _muted,
                  size: 19,
                ),
                hintText: 'Search parsed rows...',
                hintStyle: const TextStyle(color: _muted, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE2EA)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE2EA)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _maroon),
                ),
                suffixIcon: _bulkReviewSearchController.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          setState(() {
                            _bulkReviewSearchController.clear();
                            _resetBulkReviewPaging();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (_) {
                setState(_resetBulkReviewPaging);
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          filteredRows == totalRows
              ? '$totalRows row${totalRows == 1 ? '' : 's'}'
              : '$filteredRows of $totalRows rows',
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _bulkReviewPagination(int filteredRows) {
    final total = filteredRows;
    final pages = total == 0 ? 1 : (total / _bulkReviewRowsPerPage).ceil();
    final safePage = _bulkReviewPage.clamp(0, pages - 1);
    final start = total == 0 ? 0 : safePage * _bulkReviewRowsPerPage + 1;
    final end = total == 0
        ? 0
        : ((safePage + 1) * _bulkReviewRowsPerPage).clamp(0, total);

    return Row(
      children: [
        Text(
          'Showing $start-$end of $total rows',
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 16),
        const Text(
          'Rows per page',
          style: TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFDDE2EA)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _bulkReviewRowsPerPage,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: DefensysUi.fontFamily,
              ),
              items: _bulkReviewRowsPerPageOptions
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _bulkReviewRowsPerPage = value;
                  _resetBulkReviewPaging();
                });
              },
            ),
          ),
        ),
        const Spacer(),
        _bulkReviewPageButton(
          Icons.chevron_left_rounded,
          safePage > 0,
          () => setState(() => _bulkReviewPage = safePage - 1),
        ),
        const SizedBox(width: 8),
        Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 36),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _maroon),
          ),
          child: Text(
            '${safePage + 1}',
            style: const TextStyle(
              color: _maroon,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _bulkReviewPageButton(
          Icons.chevron_right_rounded,
          safePage < pages - 1,
          () => setState(() => _bulkReviewPage = safePage + 1),
        ),
      ],
    );
  }

  Widget _bulkReviewPageButton(
    IconData icon,
    bool enabled,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: 36,
      height: 36,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0xFFDDE2EA)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }

  String _rowInstructor(Map<String, dynamic> row) {
    final direct =
        (row['faculty'] ?? row['instructor'] ?? row['instructor_name'])
            ?.toString()
            .trim() ??
        '';
    if (direct.isNotEmpty) return direct;
    final meta = row['_fileMetadata'] as Map<String, dynamic>?;
    if (meta != null) {
      final metaFac =
          (meta['faculty'] ?? meta['instructor'] ?? meta['instructor_name'])
              ?.toString()
              .trim() ??
          '';
      if (metaFac.isNotEmpty) return metaFac;
    }
    return '';
  }

  Widget _reviewRowsTable(List<Map<String, dynamic>> rows) {
    final studentBatch = _selectedBulkImportType == 'student';
    final columns = studentBatch
        ? const [
            'Student ID',
            'Full Name',
            'Email',
            'Year Level',
            'Section',
            'Instructor',
            'Status',
          ]
        : const ['User ID', 'Full Name', 'Email', 'Role', 'Status'];

    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Text(
          'No rows could be parsed for review.',
          style: TextStyle(color: Color(0xFF667085)),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        constraints: BoxConstraints(minWidth: studentBatch ? 1120 : 920),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Column(
          children: [
            Container(
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFF0F1F4),
                borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              ),
              child: Row(
                children: columns
                    .map((column) => _reviewCell(column, header: true))
                    .toList(),
              ),
            ),
            ...rows.map((row) {
              final blocked = _bulkImportRowBlockingIssues(row).isNotEmpty;
              final values = studentBatch
                  ? [
                      _rowText(row, 'id_number'),
                      _rowName(row),
                      _rowText(row, 'email'),
                      _rowText(row, 'year_level'),
                      _rowText(row, 'section'),
                      _rowInstructor(row),
                      blocked ? 'Blocked' : 'Ready',
                    ]
                  : [
                      _rowText(row, 'id_number'),
                      _rowName(row),
                      _rowText(row, 'email'),
                      _rowText(row, 'role'),
                      blocked ? 'Blocked' : 'Ready',
                    ];
              return Container(
                height: 42,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(
                  children: values.map((value) => _reviewCell(value)).toList(),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _reviewCell(String value, {bool header = false}) {
    return SizedBox(
      width: 160,
      child: Container(
        height: double.infinity,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Text(
          value.isEmpty ? '-' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: header ? _ink : const Color(0xFF536079),
            fontSize: 12.5,
            fontWeight: header ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  List<String> _bulkImportBlockingIssues(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const ['No valid rows were detected in the selected CSV.'];
    }

    final issues = <String>[];
    if (_selectedBulkImportType == 'student') {
      final wrongModeRows = rows
          .where((row) => _bulkImportRowBlockingIssues(row).isNotEmpty)
          .length;
      if (wrongModeRows > 0) {
        issues.add(
          '$wrongModeRows row${wrongModeRows == 1 ? '' : 's'} look like Faculty / General users. Switch the import mode to Faculty / General Users or fix the role column to student before importing.',
        );
      }
      if (_selectedStudentPeriodSource == 'explicit' &&
          _selectedTargetSemesterId.isEmpty) {
        issues.add('Select the target semester for this student batch.');
      }
      final hasDetectedYear = rows.any(
        (row) => _rowText(row, 'year_level').isNotEmpty,
      );
      if (_selectedBatchYearLevel.isEmpty && !hasDetectedYear) {
        issues.add('Select the student batch year level before importing.');
      }
    }

    return issues;
  }

  List<String> _bulkImportRowBlockingIssues(Map<String, dynamic> row) {
    if (_selectedBulkImportType != 'student') {
      return const [];
    }

    final role = _rowText(row, 'role').trim().toLowerCase();
    if (role.isEmpty || role == 'student') {
      return const [];
    }

    return const ['Wrong import mode'];
  }

  List<String> _bulkImportWarnings(
    List<Map<String, dynamic>> rows,
    AdminOfficialClassListParseResult official,
  ) {
    final warnings = <String>[];
    if (rows.isEmpty) {
      return const [];
    }

    final seen = <String>{};
    final duplicates = <String>{};
    for (final row in rows) {
      final id = _rowText(row, 'id_number');
      if (id.isEmpty) continue;
      if (!seen.add(id)) duplicates.add(id);
    }
    if (duplicates.isNotEmpty) {
      warnings.add(
        'Duplicate ID numbers in this file: ${duplicates.take(5).join(', ')}.',
      );
    }

    final missingEmailCount = rows
        .where((row) => _rowText(row, 'email').isEmpty)
        .length;
    if (missingEmailCount > 0) {
      warnings.add(
        '$missingEmailCount row${missingEmailCount == 1 ? '' : 's'} have no email address.',
      );
    }

    if (_selectedBulkImportType == 'student') {
      final normalizedRowYears = rows
          .map((row) => normalizeYearLevel(_rowText(row, 'year_level')))
          .where((value) => value.isNotEmpty)
          .toSet();
      final rowSections = rows
          .map((row) => _rowText(row, 'section'))
          .where((value) => value.isNotEmpty)
          .toSet();

      final officialYear = official.metadata['year_level']?.toString() ?? '';
      final normalizedOfficialYear = officialYear.isNotEmpty
          ? normalizeYearLevel(officialYear)
          : '';
      final officialSection = official.metadata['section']?.toString() ?? '';
      final officialFaculty = official.metadata['faculty']?.toString() ?? '';

      final detectedYear = normalizedOfficialYear.isNotEmpty
          ? normalizedOfficialYear
          : (normalizedRowYears.length == 1 ? normalizedRowYears.first : '');
      final detectedSection = officialSection.isNotEmpty
          ? officialSection
          : (rowSections.length == 1 ? rowSections.first : '');

      if (_selectedBatchYearLevel.isNotEmpty &&
          detectedYear.isNotEmpty &&
          normalizeYearLevel(_selectedBatchYearLevel) !=
              normalizeYearLevel(detectedYear)) {
        warnings.add(
          'Selected year level does not match the detected class list year level ($detectedYear).',
        );
      }
      if (detectedSection.isEmpty && rowSections.isEmpty) {
        warnings.add(
          'No class section was detected. Academic records may be created without section context.',
        );
      }
      if (official.students.isNotEmpty && officialFaculty.isEmpty) {
        warnings.add(
          'No instructor was detected. Official class list imports require a matching active faculty account before students can be imported.',
        );
      }
    }

    return warnings;
  }

  String _rowText(Map<String, dynamic> row, String key) =>
      row[key]?.toString().trim() ?? '';

  String _rowName(Map<String, dynamic> row) {
    final first = _rowText(row, 'first_name');
    final last = _rowText(row, 'last_name');
    final full = _rowText(row, 'full_name');
    if (first.isNotEmpty || last.isNotEmpty) {
      return '$first $last'.trim();
    }
    return full;
  }

  Widget _dropdownBox({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: onChanged == null ? const Color(0xFFF3F4F6) : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
          style: const TextStyle(
            color: _ink,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF667085),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _helper(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF667085),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _infoBanner({required IconData icon, required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAE8),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _gold),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DefensysUi.warningText, size: 15),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: DefensysUi.warningText,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _maroon,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontFamily: DefensysTokens.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _maroon,
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: const Color(0xFFF3F4F6),
          disabledForegroundColor: const Color(0xFF98A2B3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontFamily: DefensysTokens.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Future<void> _pickCsvFile() async {
    try {
      final files = await pickMultipleTabularDataFiles();
      if (!mounted || files.isEmpty) return;
      await _openStagingModal(files);
    } catch (e) {
      _snack('Could not read file(s): $e');
    }
  }

  Future<void> _openStagingModal(List<PickedTabularFile> initialFiles) async {
    if (!mounted) return;
    try {
      final result = await showFileImportStagingModal(
        context,
        initialFiles: initialFiles,
        importMode: _selectedBulkImportType,
      );
      if (!mounted || result == null) return;
      if (result.files.isEmpty) {
        setState(() {
          _stagedSourceFiles.clear();
          _bulkCsv = '';
          _selectedReviewSection = 'ALL';
          _bulkReviewSearchController.clear();
          _resetBulkReviewPaging();
        });
        _scheduleBulkDraftSave();
        return;
      }

      if (result.importMode != _selectedBulkImportType) {
        setState(() {
          _bulkImportType = result.importMode;
          if (result.importMode != 'student') {
            _targetSemesterId = '';
            _batchYearLevel = '';
          }
        });
      }

      await _processImportFiles(result.files);
    } catch (e) {
      _snack('Error staging file(s): $e');
    }
  }

  Future<void> _processImportFiles(List<PickedTabularFile> files) async {
    if (!mounted || files.isEmpty) return;
    try {
      final allStudents = <Map<String, dynamic>>[];

      for (final file in files) {
        if (file.isXlsx) {
          final official = parseOfficialClassListXlsx(file.bytes);
          if (official.students.isNotEmpty) {
            allStudents.addAll(official.students);
          }
          continue;
        }

        final csvText =
            file.text ?? utf8.decode(file.bytes, allowMalformed: true);
        final official = parseOfficialClassListCsv(csvText);
        if (official.students.isNotEmpty) {
          allStudents.addAll(official.students);
          continue;
        }

        final standardRows = _parseStandardCsvRows(csvText);
        if (standardRows.isNotEmpty) {
          allStudents.addAll(standardRows);
        }
      }

      if (allStudents.isEmpty) {
        _snack(
          'The selected file(s) do not contain valid records or CSV templates.',
        );
        return;
      }

      // If all imported rows are non-student (e.g. faculty/admin) and mode is still student, auto-switch to general
      final allNonStudent = allStudents.isNotEmpty &&
          allStudents.every((s) {
            final role = (s['role'] ?? '').toString().trim().toLowerCase();
            return role.isNotEmpty && role != 'student';
          });
      if (allNonStudent && _bulkImportType == 'student') {
        _bulkImportType = 'general';
        _targetSemesterId = '';
        _batchYearLevel = '';
      }

      final combinedCsv = _studentsToStandardCsv(allStudents);

      setState(() {
        _stagedSourceFiles = List.from(files);
        _bulkCsv = combinedCsv;
        _selectedReviewSection = 'ALL';
        _bulkReviewSearchController.clear();
        _resetBulkReviewPaging();
      });
      _scheduleBulkDraftSave();
    } catch (e) {
      _snack('Could not read file(s): $e');
    }
  }

  List<Map<String, dynamic>> _parseStandardCsvRows(String csvText) {
    final lines = csvText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.length < 2) return [];

    final headers = splitCsvLine(lines.first)
        .map(
          (header) => header
              .trim()
              .toLowerCase()
              .replaceAll('"', '')
              .replaceFirst('\ufeff', ''),
        )
        .toList();

    final idIndex = headers.indexOf('id_number');
    final firstIndex = headers.indexOf('first_name');
    final lastIndex = headers.indexOf('last_name');
    final emailIndex = headers.indexOf('email');
    final roleIndex = headers.indexOf('role');
    final yearLevelIndex = headers.indexOf('year_level');
    final sectionIndex = headers.indexOf('section');
    final facultyIndex = headers.indexWhere(
      (h) => h == 'faculty' || h == 'instructor' || h == 'instructor_name',
    );

    if ([idIndex, firstIndex, lastIndex, emailIndex].contains(-1)) {
      return [];
    }

    return lines
        .skip(1)
        .map((line) {
          final columns = splitCsvLine(
            line,
          ).map((cell) => cell.trim().replaceAll('"', '')).toList();
          String read(int index) =>
              (index >= 0 && index < columns.length) ? columns[index] : '';

          final role = roleIndex != -1 ? read(roleIndex) : '';
          return {
            'id_number': read(idIndex),
            'first_name': read(firstIndex),
            'last_name': read(lastIndex),
            'email': read(emailIndex),
            'role': role.isNotEmpty ? role : 'student',
            if (yearLevelIndex != -1 && read(yearLevelIndex).isNotEmpty)
              'year_level': read(yearLevelIndex),
            if (sectionIndex != -1 && read(sectionIndex).isNotEmpty)
              'section': read(sectionIndex),
            if (facultyIndex != -1 && read(facultyIndex).isNotEmpty)
              'faculty': read(facultyIndex),
          };
        })
        .where((row) => row['id_number']!.isNotEmpty)
        .toList();
  }

  String _studentsToStandardCsv(List<Map<String, dynamic>> students) {
    final sb = StringBuffer();
    sb.writeln(
      'id_number,first_name,last_name,email,role,year_level,section,faculty',
    );
    for (final s in students) {
      final id = (s['id_number'] ?? '').toString().trim();
      final first = (s['first_name'] ?? '').toString().trim();
      final last = (s['last_name'] ?? '').toString().trim();
      final email = (s['email'] ?? '').toString().trim();
      final role = (s['role'] ?? 'student').toString().trim();
      final yl = (s['year_level'] ?? '').toString().trim();
      final sec = (s['section'] ?? '').toString().trim();
      final fac =
          (s['faculty'] ??
                  (s['_fileMetadata'] as Map?)?['faculty'] ??
                  '')
              .toString()
              .trim();
      sb.writeln(
        '"$id","$first","$last","$email","$role","$yl","$sec","$fac"',
      );
    }
    return sb.toString();
  }

  Future<void> _downloadCsvTemplate() async {
    if (_selectedBulkImportType == 'student') {
      final yearLevel = await _pickStudentSampleYear();
      if (yearLevel == null || !mounted) return;
      await downloadTextFile(
        filename: sampleStudentCsvFilenameForYear(yearLevel),
        content: sampleStudentCsvForYear(yearLevel),
      );
      return;
    }

    await downloadTextFile(
      filename: 'defensys-user-import-template.csv',
      content: sampleFacultyCsvTemplate,
    );
  }

  Future<String?> _pickStudentSampleYear() async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Download official class list sample'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Each file follows the official class list shape and includes '
                'one section plus four students for the chosen year level.',
                style: TextStyle(fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 16),
              for (final year in studentSampleYearLevels)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(year),
                    child: Text(year),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _importBulkUsers(AcademicPeriodState academicState) async {
    final csv = _csvDraft;
    if (csv.trim().isEmpty) {
      _snack('Choose or paste a CSV file first.');
      return;
    }

    final rows = _parseCsv(csv);
    if (rows.isEmpty) {
      _snack('CSV has no valid rows.');
      return;
    }
    final blockers = _bulkImportBlockingIssues(rows);
    if (blockers.isNotEmpty) {
      _snack(blockers.first);
      return;
    }
    if (_selectedBulkImportType == 'student') {
      final official = parseOfficialClassListCsv(csv);
      final detectedFaculty = official.metadata['faculty']?.toString() ?? '';
      if (official.students.isNotEmpty && detectedFaculty.trim().isEmpty) {
        _snack('Official class list imports require a Faculty value.');
        return;
      }
    }

    final studentContext = _studentContext(academicState);
    if (_selectedBulkImportType == 'student' && studentContext == null) {
      return;
    }

    widget.onConfirmUpload(rows, studentContext);
  }

  Map<String, dynamic>? _studentContext(AcademicPeriodState academicState) {
    if (_selectedBulkImportType != 'student') {
      return null;
    }

    final rows = _parseCsv(_csvDraft);
    final rowYears = rows
        .map((r) => r['year_level']?.toString().trim() ?? '')
        .where((y) => y.isNotEmpty)
        .toSet();
    final rowSections = rows
        .map((r) => r['section']?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();

    final officialContext = parseOfficialClassListCsv(_csvDraft).metadata;
    final detectedYear = officialContext['year_level']?.toString() ??
        (rowYears.length == 1 ? rowYears.first : '');
    final detectedSection = officialContext['section']?.toString() ??
        (rowSections.length == 1 ? rowSections.first : '');
    final detectedFaculty = officialContext['faculty']?.toString() ?? '';
    final isOfficialClassList = parseOfficialClassListCsv(
      _csvDraft,
    ).students.isNotEmpty;
    final selectedYear = _selectedBatchYearLevel.isNotEmpty
        ? _selectedBatchYearLevel
        : detectedYear;

    if (_selectedBatchYearLevel.isNotEmpty &&
        detectedYear.isNotEmpty &&
        normalizeYearLevel(_selectedBatchYearLevel) !=
            normalizeYearLevel(detectedYear)) {
      _snack(
        'The selected year level does not match the official class list year.',
      );
      return null;
    }

    if (selectedYear.isEmpty && rowYears.isEmpty) {
      _snack('Select the student batch year level first.');
      return null;
    }

    if (_selectedStudentPeriodSource == 'active') {
      if (academicState.activeSemester == null) {
        _snack('There is no active semester to use for this import.');
        return null;
      }

      return {
        'use_active_semester': true,
        if (selectedYear.isNotEmpty)
          'year_level': normalizeYearLevel(selectedYear),
        if (detectedSection.isNotEmpty) 'section': detectedSection,
        if (detectedFaculty.isNotEmpty) 'instructor_name': detectedFaculty,
        if (isOfficialClassList) 'require_faculty_match': true,
      };
    }

    final semesterId = int.tryParse(_selectedTargetSemesterId);
    if (semesterId == null) {
      _snack('Select the target semester first.');
      return null;
    }

    return {
      'semester_id': semesterId,
      if (selectedYear.isNotEmpty)
        'year_level': normalizeYearLevel(selectedYear),
      if (detectedSection.isNotEmpty) 'section': detectedSection,
      if (detectedFaculty.isNotEmpty) 'instructor_name': detectedFaculty,
      if (isOfficialClassList) 'require_faculty_match': true,
    };
  }

  List<Map<String, dynamic>> _parseCsv(String csv) {
    if (_selectedBulkImportType == 'student') {
      final official = parseOfficialClassListCsv(csv);
      if (official.students.isNotEmpty) {
        return official.students;
      }
    }

    final lines = csv
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.length < 2) return [];

    final headers = splitCsvLine(lines.first)
        .map(
          (header) => header
              .trim()
              .toLowerCase()
              .replaceAll('"', '')
              .replaceFirst('\ufeff', ''),
        )
        .toList();

    final idIndex = headers.indexOf('id_number');
    final firstIndex = headers.indexOf('first_name');
    final lastIndex = headers.indexOf('last_name');
    final emailIndex = headers.indexOf('email');
    final roleIndex = headers.indexOf('role');
    final yearLevelIndex = headers.indexOf('year_level');
    final sectionIndex = headers.indexOf('section');
    final facultyIndex = headers.indexWhere(
      (h) => h == 'faculty' || h == 'instructor' || h == 'instructor_name',
    );

    if ([idIndex, firstIndex, lastIndex, emailIndex].contains(-1)) {
      return [];
    }

    return lines
        .skip(1)
        .map((line) {
          final columns = splitCsvLine(
            line,
          ).map((cell) => cell.trim().replaceAll('"', '')).toList();
          String read(int index) =>
              (index >= 0 && index < columns.length) ? columns[index] : '';

          final role = roleIndex != -1 ? read(roleIndex) : '';
          return {
            'id_number': read(idIndex),
            'first_name': read(firstIndex),
            'last_name': read(lastIndex),
            'email': read(emailIndex),
            'role': role.isNotEmpty ? role : 'student',
            if (yearLevelIndex != -1 && read(yearLevelIndex).isNotEmpty)
              'year_level': read(yearLevelIndex),
            if (sectionIndex != -1 && read(sectionIndex).isNotEmpty)
              'section': read(sectionIndex),
            if (facultyIndex != -1 && read(facultyIndex).isNotEmpty)
              'faculty': read(facultyIndex),
          };
        })
        .where((row) => row['id_number']!.isNotEmpty)
        .toList();
  }

  void _resetBulkReviewPaging() {
    _bulkReviewPage = 0;
  }

  List<Map<String, dynamic>> _filteredBulkReviewRows(
    List<Map<String, dynamic>> rows,
  ) {
    var result = rows;

    if (_selectedReviewSection != 'ALL') {
      result = result.where((row) {
        final sec = (row['section']?.toString() ?? '').trim();
        if (_selectedReviewSection == 'Unassigned') {
          return sec.isEmpty;
        }
        return sec.toLowerCase() == _selectedReviewSection.toLowerCase();
      }).toList();
    }

    final query = _bulkReviewSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return result;
    }
    return result.where((row) {
      final id = _rowText(row, 'id_number').toLowerCase();
      final name = _rowName(row).toLowerCase();
      final email = _rowText(row, 'email').toLowerCase();
      final role = _rowText(row, 'role').toLowerCase();
      final year = _rowText(row, 'year_level').toLowerCase();
      final sec = _rowText(row, 'section').toLowerCase();
      final fac = _rowInstructor(row).toLowerCase();
      return id.contains(query) ||
          name.contains(query) ||
          email.contains(query) ||
          role.contains(query) ||
          year.contains(query) ||
          sec.contains(query) ||
          fac.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> _pageBulkReviewRows(
    List<Map<String, dynamic>> rows,
  ) {
    final start = _bulkReviewPage * _bulkReviewRowsPerPage;
    if (start >= rows.length) return [];
    final end = (start + _bulkReviewRowsPerPage).clamp(0, rows.length);
    return rows.sublist(start, end);
  }
}

class _SemesterOption {
  const _SemesterOption({required this.id, required this.label});
  final String id;
  final String label;
}

class _MiniCell extends StatelessWidget {
  const _MiniCell(
    this.text, {
    this.isHeader = false,
    required this.flex,
    required this.isUsed,
  });

  final String text;
  final bool isHeader;
  final int flex;
  final bool isUsed;

  @override
  Widget build(BuildContext context) {
    final textColor = isHeader
        ? (isUsed ? const Color(0xFF1E293B) : const Color(0xFF94A3B8))
        : (isUsed ? const Color(0xFF334155) : const Color(0xFF94A3B8));

    return Expanded(
      flex: flex,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontSize: isHeader ? 11.5 : 12,
            fontWeight: isHeader ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
