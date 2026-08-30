import 'dart:async';
import 'dart:convert';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/widgets/file_import_staging_modal.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/import/faculty_role_parser.dart';
import 'package:defensys/utils/import/student_bulk_import_csv.dart';
import 'package:defensys/utils/import/user_bulk_import_draft.dart';
import 'official_class_list_parser.dart';

/// Clean, zero-fillup Faculty & Staff Bulk Import view.
/// Features a modern 2-column top section (Template Guide & File Staging)
/// and a full-width Preflight Intake Review Table with search, pagination, and role validation.
class BulkImportView extends StatefulWidget {
  const BulkImportView({
    super.key,
    required this.state,
    required this.academicState,
    required this.onBack,
    this.onPickFile,
    this.onDownloadSample,
    required this.onConfirmUpload,
    this.initialImportType = 'faculty',
    this.showHeader = true,
    this.wrapScrollable = true,
  });

  final UserManagementState state;
  final AcademicPeriodState academicState;
  final VoidCallback onBack;
  final VoidCallback? onPickFile;
  final VoidCallback? onDownloadSample;
  final String initialImportType;
  final bool showHeader;
  final bool wrapScrollable;
  final void Function(
    List<Map<String, dynamic>> users,
    Map<String, dynamic>? studentContext,
  ) onConfirmUpload;

  @override
  State<BulkImportView> createState() => _BulkImportViewState();
}

class _BulkImportViewState extends State<BulkImportView> {
  static const Color _ink = DefensysUi.textDark;
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _maroon = DefensysUi.primaryMaroon;
  static const Color _muted = DefensysUi.steelGrey;
  static const Color _green = Color(0xFF16A34A);

  final List<PickedTabularFile> _stagedFiles = [];
  final List<Map<String, dynamic>> _parsedFacultyRows = [];

  final TextEditingController _searchCtrl = TextEditingController();
  int _currentPage = 0;
  int _rowsPerPage = 10;
  static const List<int> _rowsPerPageOptions = [10, 25, 50, 100];

  UserBulkImportDraft? _savedDraft;
  Timer? _draftDebounce;
  bool _draftRestoredBannerVisible = false;

  bool get _isDirty => _stagedFiles.isNotEmpty || _parsedFacultyRows.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final draft = await loadUserBulkImportDraft();
    if (!mounted || draft == null) return;
    if (draft.csv.trim().isNotEmpty) {
      final rows = _parseRawCsvContent(draft.csv);
      if (rows.isNotEmpty) {
        setState(() {
          _savedDraft = draft;
          _parsedFacultyRows.clear();
          _parsedFacultyRows.addAll(rows);
          _draftRestoredBannerVisible = true;
        });
      }
    }
  }

  Future<bool> _saveDraftNow({bool showToast = true}) async {
    _draftDebounce?.cancel();
    if (_parsedFacultyRows.isEmpty) {
      await clearUserBulkImportDraft();
      if (mounted) {
        setState(() => _savedDraft = null);
        if (showToast) {
          ToastService.info(context, 'Draft cleared (no staged records).');
        }
      }
      return true;
    }

    final csvBuffer = StringBuffer();
    csvBuffer.writeln('id_number,first_name,last_name,email,role');
    for (final r in _parsedFacultyRows) {
      final role = (r['raw_role'] ?? r['role'] ?? 'faculty').toString().replaceAll('"', '""');
      csvBuffer.writeln(
        '${r['id_number'] ?? r['username'] ?? ''},${r['first_name'] ?? ''},${r['last_name'] ?? ''},${r['email'] ?? ''},"$role"',
      );
    }

    final draft = UserBulkImportDraft(
      csv: csvBuffer.toString(),
      importType: 'faculty',
      studentPeriodSource: 'explicit',
      targetSemesterId: '',
      batchYearLevel: '',
      savedAt: DateTime.now(),
      rowCount: _parsedFacultyRows.length,
      warningCount: 0,
    );

    await saveUserBulkImportDraft(draft);
    if (mounted) {
      setState(() => _savedDraft = draft);
      if (showToast) {
        ToastService.success(
          context,
          'Draft saved (${_parsedFacultyRows.length} faculty records). You can safely leave or return anytime.',
        );
      }
    }
    return true;
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      if (_parsedFacultyRows.isEmpty) {
        await clearUserBulkImportDraft();
        if (mounted) setState(() => _savedDraft = null);
        return;
      }

      final csvBuffer = StringBuffer();
      csvBuffer.writeln('id_number,first_name,last_name,email,role');
      for (final r in _parsedFacultyRows) {
        final role = (r['raw_role'] ?? r['role'] ?? 'faculty').toString().replaceAll('"', '""');
        csvBuffer.writeln(
          '${r['id_number'] ?? r['username'] ?? ''},${r['first_name'] ?? ''},${r['last_name'] ?? ''},${r['email'] ?? ''},"$role"',
        );
      }

      final draft = UserBulkImportDraft(
        csv: csvBuffer.toString(),
        importType: 'faculty',
        studentPeriodSource: 'explicit',
        targetSemesterId: '',
        batchYearLevel: '',
        savedAt: DateTime.now(),
        rowCount: _parsedFacultyRows.length,
        warningCount: 0,
      );

      await saveUserBulkImportDraft(draft);
      if (mounted) {
        setState(() => _savedDraft = draft);
      }
    });
  }

  Future<bool> _requestClose() async {
    if (!_isDirty) {
      widget.onBack();
      return true;
    }

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DefensysTokens.maroon.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              ),
              child: const Icon(
                Icons.bookmark_border_rounded,
                color: DefensysTokens.maroon,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Unsaved Faculty Import',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: DefensysTokens.steelGrey,
              splashRadius: 18,
              tooltip: 'Close & Stay',
              onPressed: () => Navigator.of(dialogCtx).pop('stay'),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have ${_parsedFacultyRows.length} staged faculty record${_parsedFacultyRows.length == 1 ? '' : 's'} ready for intake.',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Would you like to save your draft to resume later, or discard your staged records?',
              style: TextStyle(
                fontSize: 12.5,
                color: _muted,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              IconButton(
                style: IconButton.styleFrom(
                  foregroundColor: DefensysTokens.danger,
                  hoverColor: DefensysTokens.dangerBg,
                  padding: const EdgeInsets.all(8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                  ),
                ),
                onPressed: () => Navigator.of(dialogCtx).pop('discard'),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                tooltip: 'Discard & Leave',
              ),
              const Spacer(),
              FilledButton.icon(
                style: DefensysTokens.saveButtonStyle(
                  isPill: false,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () => Navigator.of(dialogCtx).pop('save'),
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Draft'),
              ),
            ],
          ),
        ],
      ),
    );

    if (action == 'save') {
      await _saveDraftNow(showToast: false);
      if (mounted) {
        ToastService.info(
          context,
          'Draft saved (${_parsedFacultyRows.length} records). You can resume anytime.',
        );
      }
      widget.onBack();
      return true;
    } else if (action == 'discard') {
      _draftDebounce?.cancel();
      await clearUserBulkImportDraft();
      if (mounted) {
        setState(() {
          _savedDraft = null;
          _parsedFacultyRows.clear();
          _stagedFiles.clear();
        });
        ToastService.info(context, 'Faculty import draft discarded.');
      }
      widget.onBack();
      return true;
    }

    return false;
  }

  void _downloadTemplate() {
    if (widget.onDownloadSample != null) {
      widget.onDownloadSample!();
    } else {
      downloadTextFile(
        filename: 'faculty_staff_template.csv',
        content: sampleFacultyCsvTemplate,
      );
    }
  }

  bool _isPickingFiles = false;

  Future<void> _openStagingModal(List<PickedTabularFile> files) async {
    final result = await showFileImportStagingModal(
      context,
      initialFiles: files,
      importMode: 'general',
      hasActiveSemester: widget.academicState.activeSemester != null,
    );

    if (result != null && result.files.isNotEmpty) {
      _processPickedFiles(result.files);
    }
  }

  Future<void> _pickFiles() async {
    if (_isPickingFiles) return;
    _isPickingFiles = true;
    try {
      final files = await pickMultipleTabularDataFiles();
      if (!mounted || files.isEmpty) return;
      await _openStagingModal(files);
    } catch (e) {
      if (mounted) {
        ToastService.error(context, 'Failed to select files: $e');
      }
    } finally {
      if (mounted) {
        _isPickingFiles = false;
      }
    }
  }

  void _processPickedFiles(List<PickedTabularFile> files) {
    final allRows = <Map<String, dynamic>>[];
    final validFiles = <PickedTabularFile>[];
    int studentFileCount = 0;

    for (final file in files) {
      final matrix = file.isXlsx
          ? _extractXlsxMatrix(file.bytes)
          : const LineSplitter()
              .convert(file.text ?? utf8.decode(file.bytes, allowMalformed: true))
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .map(_splitCsvLine)
              .toList();

      if (_isStudentClassListOrTemplate(matrix)) {
        studentFileCount++;
        continue;
      }

      final rows = file.isXlsx
          ? _parseXlsxBytes(file.bytes, file.name)
          : _parseRawCsvContent(
              file.text ?? utf8.decode(file.bytes, allowMalformed: true),
              fileName: file.name,
            );

      if (rows.isNotEmpty) {
        allRows.addAll(rows);
        validFiles.add(file);
      }
    }

    if (allRows.isEmpty) {
      if (studentFileCount > 0) {
        ToastService.error(
          context,
          'Student template detected. Please use the Batch Student Enrollment Hub to import students.',
        );
      } else {
        ToastService.error(
          context,
          'No valid faculty records recognized in staged files.',
        );
      }
      return;
    }

    setState(() {
      _stagedFiles.clear();
      _stagedFiles.addAll(validFiles);
      _parsedFacultyRows.clear();
      _parsedFacultyRows.addAll(allRows);
      _currentPage = 0;
    });

    _scheduleDraftSave();

    final skipped = files.length - validFiles.length;
    if (skipped > 0) {
      if (studentFileCount > 0) {
        ToastService.warning(
          context,
          '${validFiles.length} faculty file(s) loaded • ${allRows.length} records. ($studentFileCount student file(s) skipped — use Student Hub instead)',
        );
      } else {
        ToastService.warning(
          context,
          '${validFiles.length} file(s) loaded • ${allRows.length} faculty records. ($skipped incompatible file(s) skipped)',
        );
      }
    } else {
      ToastService.success(
        context,
        '${validFiles.length} file(s) staged • ${allRows.length} faculty records loaded for review.',
      );
    }
  }

  void _removeStagedFile(int index) {
    if (index < 0 || index >= _stagedFiles.length) return;
    final removed = _stagedFiles.removeAt(index);
    _parsedFacultyRows.removeWhere((r) => r['source_file'] == removed.name);
    _currentPage = 0;
    setState(() {});
    _scheduleDraftSave();
  }

  void _clearAllFiles() {
    setState(() {
      _stagedFiles.clear();
      _parsedFacultyRows.clear();
      _currentPage = 0;
    });
    _scheduleDraftSave();
  }

  bool _isStudentClassListOrTemplate(List<List<String>> matrix) {
    if (matrix.isEmpty) return false;

    // Check preambles and cells for Official Class List markers
    final headerScanLimit = matrix.length < 25 ? matrix.length : 25;
    for (var i = 0; i < headerScanLimit; i++) {
      final line = matrix[i].join(' ').toLowerCase();
      if (line.contains('official list of enrolled students') ||
          line.contains('official list of students') ||
          line.contains('class section') ||
          line.contains('subject code') ||
          line.contains('subject title') ||
          line.contains('student number') ||
          line.contains('student no') ||
          line.contains('student id') ||
          line.contains('validation date') ||
          line.contains('or no')) {
        return true;
      }
    }

    // Check for standard student CSV headers or roles
    if (matrix.isNotEmpty) {
      final headers = matrix.first.map((c) => c.toLowerCase().trim().replaceAll('"', '')).toList();
      if (headers.contains('student_number') ||
          headers.contains('student id') ||
          headers.contains('year_level') ||
          headers.contains('section')) {
        return true;
      }

      final roleIdx = headers.indexWhere((h) => h == 'role' || h == 'roles' || h == 'user_role');
      if (roleIdx != -1) {
        int studentCount = 0;
        int facultyCount = 0;
        for (var i = 1; i < matrix.length; i++) {
          if (roleIdx < matrix[i].length) {
            final role = matrix[i][roleIdx].toLowerCase().trim().replaceAll('"', '');
            if (role == 'student') studentCount++;
            if (role.contains('faculty') ||
                role.contains('admin') ||
                role.contains('panelist') ||
                role.contains('adviser') ||
                role.contains('instructor') ||
                role.contains('pit')) {
              facultyCount++;
            }
          }
        }
        if (studentCount > 0 && facultyCount == 0) {
          return true;
        }
      }
    }

    return false;
  }

  List<List<String>> _extractXlsxMatrix(List<int> bytes) {
    try {
      final excel = xl.Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return [];
      final sheet = excel.tables.values.first;
      return sheet.rows
          .map((row) => row.map((cell) => _excelCellText(cell?.value)).toList())
          .where((row) => row.any((cell) => cell.trim().isNotEmpty))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _parseFacultyRowsFromMatrix(List<List<String>> matrix, String fileName) {
    final rows = <Map<String, dynamic>>[];
    if (matrix.isEmpty) return rows;

    if (_isStudentClassListOrTemplate(matrix)) {
      return rows;
    }

    int headerIdx = -1;
    int idCol = -1;
    int firstCol = -1;
    int lastCol = -1;
    int nameCol = -1;
    int emailCol = -1;
    int roleCol = -1;

    for (var i = 0; i < matrix.length; i++) {
      final cells = matrix[i].map((c) => c.toLowerCase().trim().replaceAll('"', '').replaceFirst('\ufeff', '')).toList();

      int curId = -1;
      int curFirst = -1;
      int curLast = -1;
      int curName = -1;
      int curEmail = -1;
      int curRole = -1;

      for (var c = 0; c < cells.length; c++) {
        final col = cells[c];
        if (col.isEmpty) continue;

        if (col == 'id' ||
            col == 'id_number' ||
            col == 'id number' ||
            col == 'id_no' ||
            col == 'faculty_id' ||
            col == 'faculty id' ||
            col == 'employee_id' ||
            col == 'employee id' ||
            col == 'emp_id' ||
            col == 'fac_id' ||
            col == 'username' ||
            col == 'user_id' ||
            col == 'user id') {
          curId = c;
        } else if (col == 'first_name' ||
            col == 'first name' ||
            col == 'first' ||
            col == 'fname' ||
            col == 'given_name' ||
            col == 'given name') {
          curFirst = c;
        } else if (col == 'last_name' ||
            col == 'last name' ||
            col == 'last' ||
            col == 'lname' ||
            col == 'surname' ||
            col == 'family_name' ||
            col == 'family name') {
          curLast = c;
        } else if (col == 'name' ||
            col == 'full_name' ||
            col == 'full name' ||
            col == 'faculty_name' ||
            col == 'faculty name') {
          curName = c;
        } else if (col == 'email' ||
            col == 'email_address' ||
            col == 'email address' ||
            col == 'mail' ||
            col == 'e-mail') {
          curEmail = c;
        } else if (col == 'role' ||
            col == 'roles' ||
            col == 'position' ||
            col == 'designation' ||
            col == 'user_role' ||
            col == 'type') {
          curRole = c;
        }
      }

      final hasValidIdOrEmail = curId != -1 || curEmail != -1;
      final hasValidName = (curFirst != -1 && curLast != -1) || curName != -1 || curFirst != -1;

      if (hasValidIdOrEmail && hasValidName) {
        headerIdx = i;
        idCol = curId;
        firstCol = curFirst;
        lastCol = curLast;
        nameCol = curName;
        emailCol = curEmail;
        roleCol = curRole;
        break;
      }
    }

    if (headerIdx == -1) return rows;

    for (var i = headerIdx + 1; i < matrix.length; i++) {
      final r = matrix[i];
      final idVal = idCol >= 0 && idCol < r.length ? r[idCol].trim() : '';
      var firstVal = firstCol >= 0 && firstCol < r.length ? r[firstCol].trim() : '';
      var lastVal = lastCol >= 0 && lastCol < r.length ? r[lastCol].trim() : '';
      final emailVal = emailCol >= 0 && emailCol < r.length ? r[emailCol].trim() : '';
      final roleVal = roleCol >= 0 && roleCol < r.length ? r[roleCol].trim() : '';

      if (firstVal.isEmpty && lastVal.isEmpty && nameCol >= 0 && nameCol < r.length) {
        final fullName = r[nameCol].trim();
        if (fullName.isNotEmpty) {
          final parts = splitOfficialFullName(fullName);
          firstVal = parts.firstName;
          lastVal = parts.lastName;
        }
      }

      if (idVal.isEmpty && emailVal.isEmpty) continue;
      if (firstVal.isEmpty && lastVal.isEmpty && idVal.isEmpty) continue;

      final parsedRoles = parseFacultyRoles(roleVal);
      // Skip student records in faculty bulk import
      if (parsedRoles.baseRole == 'student' || roleVal.toLowerCase().trim() == 'student') {
        continue;
      }

      rows.add({
        'id_number': idVal.isNotEmpty ? idVal : emailVal.split('@').first,
        'username': idVal.isNotEmpty ? idVal : emailVal.split('@').first,
        'first_name': firstVal,
        'last_name': lastVal,
        'email': emailVal,
        'role': parsedRoles.baseRole,
        'raw_role': roleVal.isNotEmpty ? roleVal : parsedRoles.baseRole,
        'is_panelist': parsedRoles.isPanelist,
        'is_adviser': parsedRoles.isAdviser,
        'is_pit_lead': parsedRoles.isPitLead,
        'pit_lead_year': parsedRoles.pitLeadYear,
        'is_documenter': parsedRoles.isDocumenter,
        'is_uploader': parsedRoles.isUploader,
        'source_file': fileName,
      });
    }

    return rows;
  }

  List<Map<String, dynamic>> _parseXlsxBytes(List<int> bytes, String fileName) {
    final rows = <Map<String, dynamic>>[];
    try {
      final excel = xl.Excel.decodeBytes(bytes);
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null || sheet.rows.isEmpty) continue;
        final matrix = sheet.rows
            .map((row) => row.map((cell) => _excelCellText(cell?.value)).toList())
            .where((row) => row.any((cell) => cell.trim().isNotEmpty))
            .toList();
        final parsed = _parseFacultyRowsFromMatrix(matrix, fileName);
        if (parsed.isNotEmpty) {
          rows.addAll(parsed);
        }
      }
    } catch (_) {}
    return rows;
  }

  String _excelCellText(xl.CellValue? value) {
    if (value == null) return '';
    if (value is xl.TextCellValue) {
      return (value.value.text ?? '').trim();
    }
    if (value is xl.IntCellValue) return value.value.toString();
    if (value is xl.DoubleCellValue) {
      final n = value.value;
      return n == n.roundToDouble() ? n.round().toString() : n.toString();
    }
    if (value is xl.FormulaCellValue) return value.formula.trim();
    if (value is xl.BoolCellValue) return value.value ? 'true' : 'false';
    if (value is xl.DateCellValue) {
      final dt = value.asDateTimeLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (value is xl.DateTimeCellValue) {
      final dt = value.asDateTimeLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (value is xl.TimeCellValue) {
      final d = value.asDuration();
      final h = (d.inHours % 24).toString().padLeft(2, '0');
      final m = (d.inMinutes % 60).toString().padLeft(2, '0');
      return '$h:$m';
    }
    return value.toString().trim();
  }

  List<Map<String, dynamic>> _parseRawCsvContent(String content, {String fileName = 'Staged CSV'}) {
    final lines = const LineSplitter().convert(content).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return <Map<String, dynamic>>[];
    final matrix = lines.map(_splitCsvLine).toList();
    return _parseFacultyRowsFromMatrix(matrix, fileName);
  }

  List<String> _splitCsvLine(String line) {
    final result = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

  bool _isExistingUser(String? idNumber, String? email) {
    final cleanId = idNumber?.trim().toLowerCase() ?? '';
    final cleanEmail = email?.trim().toLowerCase() ?? '';
    for (final u in widget.state.users) {
      final uid = u['username']?.toString().toLowerCase() ?? '';
      final umail = u['email']?.toString().toLowerCase() ?? '';
      if (cleanId.isNotEmpty && uid == cleanId) return true;
      if (cleanEmail.isNotEmpty && umail == cleanEmail) return true;
    }
    return false;
  }

  Future<void> _confirmUpload() async {
    if (_parsedFacultyRows.isEmpty) return;

    final usersToImport = _parsedFacultyRows.map((r) {
      final id = (r['id_number'] ?? r['username'] ?? '').toString().trim();
      final roleStr = (r['raw_role'] ?? r['role'] ?? 'faculty').toString().trim();
      final parsed = parseFacultyRoles(roleStr);
      return {
        'id_number': id,
        'username': id,
        'first_name': (r['first_name'] ?? '').toString().trim(),
        'last_name': (r['last_name'] ?? '').toString().trim(),
        'email': (r['email'] ?? '').toString().trim(),
        'role': (r['role'] ?? parsed.baseRole).toString().trim(),
        'raw_role': roleStr,
        'is_panelist': r['is_panelist'] ?? parsed.isPanelist,
        'is_adviser': r['is_adviser'] ?? parsed.isAdviser,
        'is_pit_lead': r['is_pit_lead'] ?? parsed.isPitLead,
        'pit_lead_year': r['pit_lead_year'] ?? parsed.pitLeadYear,
        'is_documenter': r['is_documenter'] ?? parsed.isDocumenter,
        'is_uploader': r['is_uploader'] ?? parsed.isUploader,
      };
    }).toList();

    widget.onConfirmUpload(usersToImport, null);
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          DefensysPageHeader(
            title: 'Bulk Import Faculty & Staff',
            subtitle: 'Upload CSV or XLSX spreadsheets to create and onboard institutional faculty and staff accounts.',
            actions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_parsedFacultyRows.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: widget.state.isSaving ? null : () => _saveDraftNow(showToast: true),
                    icon: const Icon(Icons.bookmark_outline_rounded, size: 15),
                    label: const Text('Save Draft'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: _line),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                OutlinedButton.icon(
                  onPressed: widget.state.isSaving ? null : _requestClose,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Back to Faculty'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _line),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Draft restored notification banner
        if (_draftRestoredBannerVisible && _savedDraft != null && _parsedFacultyRows.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 18, color: Color(0xFF1D4ED8)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Draft restored: ${_parsedFacultyRows.length} faculty records loaded from your previous session.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E40AF),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    _draftDebounce?.cancel();
                    await clearUserBulkImportDraft();
                    if (mounted) {
                      setState(() {
                        _savedDraft = null;
                        _parsedFacultyRows.clear();
                        _stagedFiles.clear();
                        _draftRestoredBannerVisible = false;
                      });
                      ToastService.info(context, 'Draft discarded.');
                    }
                  },
                  child: const Text(
                    'Discard Draft',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.danger,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
                  splashRadius: 16,
                  onPressed: () => setState(() => _draftRestoredBannerVisible = false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 2-Column Top Section: Left is Format Guide, Right is File Staging & Upload
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            if (!isWide) {
              return Column(
                children: [
                  _buildFormatGuideCard(),
                  const SizedBox(height: 20),
                  _buildUploadCard(),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _buildFormatGuideCard()),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: _buildUploadCard()),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // Bottom Full-Width Preflight Intake Review Table Card
        _buildPreflightReviewCard(),
      ],
    );

    if (!widget.wrapScrollable) {
      return content;
    }

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestClose();
      },
      child: SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: content,
      ),
    );
  }

  Widget _buildFormatGuideCard() {
    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 235),
        padding: const EdgeInsets.all(22),
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
                  child: const Icon(Icons.badge_outlined, color: _maroon, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CSV Format',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Official Faculty & Staff Template • Institutional Accounts',
                        style: TextStyle(
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

            // Sample Table Structure
            Container(
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
                  // Titlebar
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
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.insert_drive_file_outlined, size: 12, color: Color(0xFF16A34A)),
                              SizedBox(width: 5),
                              Text(
                                'defensys_faculty_import_template.csv',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildMiniBadge('Faculty & Staff Template', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
                      ],
                    ),
                  ),

                  // Table Header (Row 1)
                  Container(
                    color: const Color(0xFFE2E8F0),
                    child: Row(
                      children: [
                        _buildGutterCell('1', isHeader: true),
                        Expanded(flex: 3, child: _buildHeaderCell('id_number')),
                        Expanded(flex: 2, child: _buildHeaderCell('first_name')),
                        Expanded(flex: 2, child: _buildHeaderCell('last_name')),
                        Expanded(flex: 3, child: _buildHeaderCell('email')),
                        Expanded(flex: 4, child: _buildHeaderCell('role')),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFCBD5E1)),

                  // Sample Rows
                  _buildSampleRow('2', 'FAC-0001', 'Ada', 'Lovelace', 'ada@ustp.edu.ph', 'faculty', false),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  _buildSampleRow('3', 'FAC-0002', 'Alan', 'Turing', 'a.turing@ustp.edu.ph', 'Panelist, Adviser', true),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  _buildSampleRow('4', 'FAC-0003', 'Grace', 'Hopper', 'g.hopper@ustp.edu.ph', 'PIT Lead 1st Year, Panelist', false),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  _buildSampleRow('5', 'FAC-0004', 'Dennis', 'Ritchie', 'd.ritchie@ustp.edu.ph', 'admin', true),
                ],
              ),
            ),
            const SizedBox(height: 12),

            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: _maroon),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Best for onboarding faculty, advisers, and panelist accounts. Roles, PIT leads, and institutional emails are auto-detected. For multiple roles, separate them with commas or slashes (e.g., "Panelist, Adviser" or "PIT Lead 1st Year / Panelist").',
                    style: TextStyle(fontSize: 11.5, color: _muted, fontWeight: FontWeight.w500, height: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            OutlinedButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download_rounded, size: 14),
              label: const Text('Download Sample Template'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _line),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
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

  Widget _buildHeaderCell(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF334155),
        ),
      ),
    );
  }

  Widget _buildSampleRow(String rowNum, String id, String first, String last, String email, String role, bool isAlt) {
    return Container(
      color: isAlt ? const Color(0xFFF8FAFC) : Colors.white,
      child: Row(
        children: [
          _buildGutterCell(rowNum),
          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), child: Text(id, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _ink)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), child: Text(first, style: const TextStyle(fontSize: 10.5, color: _ink)))),
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), child: Text(last, style: const TextStyle(fontSize: 10.5, color: _ink)))),
          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), child: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: _muted)))),
          Expanded(flex: 4, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), child: Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _maroon)))),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildUploadCard() {
    return DefensysCard(
      child: Container(
        constraints: const BoxConstraints(minHeight: 235),
        padding: const EdgeInsets.all(22),
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
                  child: const Icon(Icons.upload_file_rounded, color: _maroon, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload CSV',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Stage and upload faculty spreadsheets (.csv, .xlsx)',
                        style: TextStyle(
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

            // Staged Files Container or Dropzone
            if (_stagedFiles.isEmpty)
              InkWell(
                onTap: widget.state.isSaving ? null : _pickFiles,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _line, style: BorderStyle.solid),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _maroon.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_upload_outlined, color: _maroon, size: 24),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Click to Stage Faculty Spreadsheets',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Supports .csv and .xlsx spreadsheets. Multi-file staging supported.',
                        style: TextStyle(fontSize: 11.5, color: _muted),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _line),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _stagedFiles.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
                      itemBuilder: (context, index) {
                        final file = _stagedFiles[index];
                        final rowCount = _parsedFacultyRows.where((r) => r['source_file'] == file.name).length;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                file.isXlsx ? Icons.table_view_rounded : Icons.description_rounded,
                                color: _maroon,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  file.name,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$rowCount Faculty Records',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF166534),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16, color: _muted),
                                splashRadius: 16,
                                onPressed: () => _removeStagedFile(index),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.state.isSaving ? null : _pickFiles,
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Stage More Files'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: const BorderSide(color: _line),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: widget.state.isSaving ? null : _clearAllFiles,
                        icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                        label: const Text('Clear All', style: TextStyle(color: Color(0xFFDC2626))),
                        style: TextButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreflightReviewCard() {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _parsedFacultyRows.where((r) {
      if (query.isEmpty) return true;
      final id = r['id_number']?.toString().toLowerCase() ?? '';
      final first = r['first_name']?.toString().toLowerCase() ?? '';
      final last = r['last_name']?.toString().toLowerCase() ?? '';
      final email = r['email']?.toString().toLowerCase() ?? '';
      final role = r['role']?.toString().toLowerCase() ?? '';
      final rawRole = r['raw_role']?.toString().toLowerCase() ?? '';
      return id.contains(query) || first.contains(query) || last.contains(query) || email.contains(query) || role.contains(query) || rawRole.contains(query);
    }).toList();

    int duplicateCount = 0;
    int readyCount = 0;

    for (final r in _parsedFacultyRows) {
      final isDup = _isExistingUser(r['id_number']?.toString(), r['email']?.toString());
      if (isDup) {
        duplicateCount++;
      } else {
        readyCount++;
      }
    }

    final totalCount = filtered.length;
    final totalPages = (totalCount / _rowsPerPage).ceil();
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalCount);
    final pageRows = totalCount == 0 ? <Map<String, dynamic>>[] : filtered.sublist(startIndex, endIndex);

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
                      'Preflight Faculty Intake Review',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const Spacer(),
                    _buildSummaryBadge('Ready: $readyCount', const Color(0xFFDCFCE7), _green),
                    const SizedBox(width: 8),
                    if (duplicateCount > 0) ...[
                      _buildSummaryBadge('Duplicates: $duplicateCount', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
                      const SizedBox(width: 8),
                    ],
                    _buildSummaryBadge('Total: ${_parsedFacultyRows.length}', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _muted),
                      hintText: 'Search by faculty ID, name, email, or role...',
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
                      _currentPage = 0;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),

          // Table Content
          if (_parsedFacultyRows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.badge_outlined, size: 36, color: _muted.withValues(alpha: 0.5)),
                    const SizedBox(height: 10),
                    const Text(
                      'No faculty spreadsheets staged yet.',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Upload or stage a faculty CSV/XLSX file above to preview accounts before importing.',
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
                child: Text('No faculty records match your search filter.'),
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
                final id = row['id_number']?.toString() ?? '';
                final first = row['first_name']?.toString() ?? '';
                final last = row['last_name']?.toString() ?? '';
                final email = row['email']?.toString() ?? '';
                final rawRole = (row['raw_role'] ?? row['role'] ?? 'faculty').toString();
                final parsedRoles = parseFacultyRoles(rawRole);
                final isDup = _isExistingUser(id, email);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  color: index.isEven ? Colors.white : const Color(0xFFF9FAFB),
                  child: Row(
                    children: [
                      // Faculty ID & Name
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$first $last'.trim().isEmpty ? 'Unnamed Faculty' : '$first $last',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: $id',
                              style: const TextStyle(fontSize: 12, color: _muted),
                            ),
                          ],
                        ),
                      ),

                      // Email
                      Expanded(
                        flex: 3,
                        child: Text(
                          email.isEmpty ? 'No institutional email' : email,
                          style: const TextStyle(fontSize: 12.5, color: _ink),
                        ),
                      ),

                      // Role Badges
                      Expanded(
                        flex: 3,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: parsedRoles.badges.map((b) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: b.bg,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              b.label,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: b.fg,
                              ),
                            ),
                          )).toList(),
                        ),
                      ),

                      // Status
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            if (isDup)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Existing Account',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Ready to Import',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF166534),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Pagination Controls
          if (_parsedFacultyRows.isNotEmpty && filtered.isNotEmpty) ...[
            const Divider(height: 1, color: _line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: _buildPaginationControls(
                totalCount: filtered.length,
                currentPage: _currentPage,
                rowsPerPage: _rowsPerPage,
                onPageChanged: (p) => setState(() => _currentPage = p),
                onRowsPerPageChanged: (r) => setState(() {
                  _rowsPerPage = r;
                  _currentPage = 0;
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
                if (_parsedFacultyRows.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: widget.state.isSaving ? null : () => _saveDraftNow(showToast: true),
                    icon: const Icon(Icons.bookmark_outline_rounded, size: 16),
                    label: const Text('Save as Draft'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ink,
                      side: const BorderSide(color: _line),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                OutlinedButton(
                  onPressed: _requestClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _line),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: widget.state.isSaving || _parsedFacultyRows.isEmpty ? null : _confirmUpload,
                  icon: widget.state.isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(
                    widget.state.isSaving
                        ? 'Importing...'
                        : 'Confirm Import (${_parsedFacultyRows.length} Faculty)',
                  ),
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
              onPressed: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
            ),
            Text(
              '${totalPages == 0 ? 0 : currentPage + 1} / $totalPages',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _ink),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              color: _ink,
              splashRadius: 18,
              onPressed: currentPage < totalPages - 1 ? () => onPageChanged(currentPage + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}
