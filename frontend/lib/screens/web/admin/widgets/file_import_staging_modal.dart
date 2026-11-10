import 'dart:async';
import 'dart:convert';

import 'package:excel/excel.dart' as xl;
import 'package:defensys/utils/excel_safe_decode.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../utils/csv_file_io.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../user_management/bulk_import/official_class_list_parser.dart';

/// Result containing staged files and user-confirmed import mode.
class StagedImportResult {
  final List<PickedTabularFile> files;
  final String importMode; // 'student' or 'general'

  const StagedImportResult({required this.files, required this.importMode});
}

/// Represents parsed inspection metadata for a staged tabular file.
class StagedFileInfo {
  final PickedTabularFile file;
  final String formatLabel;
  final bool isValid;
  final int rowCount;
  final String detectedImportMode; // 'student' or 'general'
  final String recordEntityLabel; // 'students', 'faculty', 'users', etc.
  final String? primaryRole;
  final String? section;
  final String? subjectCode;
  final String? subjectTitle;
  final String? yearLevel;
  final String? instructor;
  final String? academicTerm;
  final String? warning;
  final String? warningTitle;

  const StagedFileInfo({
    required this.file,
    required this.formatLabel,
    required this.isValid,
    required this.rowCount,
    this.detectedImportMode = 'student',
    this.recordEntityLabel = 'students',
    this.primaryRole,
    this.section,
    this.subjectCode,
    this.subjectTitle,
    this.yearLevel,
    this.instructor,
    this.academicTerm,
    this.warning,
    this.warningTitle,
  });

  String get fileName => file.name;
  String get extension => file.extension.toUpperCase();
  int get fileSizeBytes => file.bytes.length;

  String get formattedFileSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// Helper method to open the File Import Staging Modal dialog.
Future<StagedImportResult?> showFileImportStagingModal(
  BuildContext context, {
  required List<PickedTabularFile> initialFiles,
  String importMode = 'student',
  bool hasActiveSemester = true,
  Map<String, dynamic>? activeSemester,
}) async {
  return showDialog<StagedImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => FileImportStagingModal(
      initialFiles: initialFiles,
      importMode: importMode,
      hasActiveSemester: hasActiveSemester,
      activeSemester: activeSemester,
    ),
  );
}

/// A floating staging dialog that allows administrators to review, replace,
/// remove, and add tabular files before processing them into the full preview table.
class FileImportStagingModal extends StatefulWidget {
  const FileImportStagingModal({
    super.key,
    required this.initialFiles,
    this.importMode = 'student',
    this.hasActiveSemester = true,
    this.activeSemester,
  });

  final List<PickedTabularFile> initialFiles;
  final String importMode;
  final bool hasActiveSemester;
  final Map<String, dynamic>? activeSemester;

  @override
  State<FileImportStagingModal> createState() => _FileImportStagingModalState();
}

class _FileImportStagingModalState extends State<FileImportStagingModal> {
  final List<PickedTabularFile> _stagedFiles = [];
  final List<StagedFileInfo> _inspectedFiles = [];
  late String _activeImportMode;
  bool _isProcessing = false;
  int _totalValidRows = 0;

  StreamSubscription? _dropSubscription;
  bool _isDraggingFile = false;

  @override
  void initState() {
    super.initState();
    _stagedFiles.addAll(widget.initialFiles);
    _activeImportMode = widget.importMode;
    _reinspectAllFiles();

    _dropSubscription = setupDropzoneListener(
      _handleDroppedFiles,
      onDragStateChanged: (isDragging) {
        if (mounted && _isDraggingFile != isDragging) {
          setState(() => _isDraggingFile = isDragging);
        }
      },
    );
  }

  @override
  void dispose() {
    _dropSubscription?.cancel();
    super.dispose();
  }

  void _handleDroppedFiles(List<PickedTabularFile> files) {
    if (!mounted || files.isEmpty) return;
    int addedCount = 0;
    setState(() {
      for (final f in files) {
        final exists = _stagedFiles.any(
          (existing) =>
              existing.name == f.name &&
              existing.bytes.length == f.bytes.length,
        );
        if (!exists) {
          _stagedFiles.add(f);
          addedCount++;
        }
      }
      _reinspectAllFiles();
    });

    if (mounted && addedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$addedCount file(s) added to staged imports.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _reinspectAllFiles() {
    _inspectedFiles.clear();
    _activeImportMode = widget.importMode;

    int totalRows = 0;
    for (final file in _stagedFiles) {
      final info = _inspectFile(file, _activeImportMode);
      _inspectedFiles.add(info);
      if (info.isValid) {
        totalRows += info.rowCount;
      }
    }

    _totalValidRows = totalRows;
  }

  StagedFileInfo _inspectFile(PickedTabularFile file, String importMode) {
    try {
      if (file.isXlsx) {
        return _inspectXlsxFile(file, importMode);
      } else if (file.isCsv) {
        return _inspectCsvFile(file, importMode);
      } else {
        final extLabel = file.extension.isNotEmpty
            ? file.extension.toUpperCase()
            : 'Unsupported';
        final isStudent = importMode == 'student';
        return StagedFileInfo(
          file: file,
          formatLabel: '$extLabel File',
          isValid: false,
          rowCount: 0,
          detectedImportMode: importMode,
          warning: isStudent
              ? 'Unsupported file format (.${file.extension.toLowerCase()}). DefenSYS requires official student class lists in .csv or .xlsx format.'
              : 'Unsupported file format (.${file.extension.toLowerCase()}). DefenSYS requires faculty spreadsheets in .csv or .xlsx format.',
        );
      }
    } catch (e) {
      return StagedFileInfo(
        file: file,
        formatLabel: 'Unrecognized File',
        isValid: false,
        rowCount: 0,
        detectedImportMode: importMode,
        warning: 'Could not parse file structure: $e',
      );
    }
  }

  StagedFileInfo _inspectXlsxFile(PickedTabularFile file, String importMode) {
    try {
      final workbook = safeDecodeExcel(file.bytes);
      if (workbook.tables.isEmpty) {
        return StagedFileInfo(
          file: file,
          formatLabel: 'Empty Spreadsheet',
          isValid: false,
          rowCount: 0,
          detectedImportMode: importMode,
          warning: 'No sheets found in Excel file.',
        );
      }

      final sheet = workbook.tables.values.first;
      final rows = sheet.rows
          .map((row) => row.map((cell) => _excelCellText(cell?.value)).toList())
          .where((row) => row.any((cell) => cell.trim().isNotEmpty))
          .toList();

      return _inspectExtractedRows(file, rows, importMode, isXlsx: true);
    } catch (e) {
      return StagedFileInfo(
        file: file,
        formatLabel: 'Excel (XLSX)',
        isValid: false,
        rowCount: 0,
        detectedImportMode: importMode,
        warning: 'Failed to read Excel workbook: $e',
      );
    }
  }

  StagedFileInfo _inspectCsvFile(PickedTabularFile file, String importMode) {
    final csvText = file.text ?? utf8.decode(file.bytes, allowMalformed: true);
    final rows = csvText
        .split(RegExp(r'\r?\n'))
        .map(_splitCsvLine)
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();

    return _inspectExtractedRows(file, rows, importMode, isXlsx: false);
  }

  String? _checkAcademicTermMismatch(Map<String, dynamic> fileMeta) {
    final active = widget.activeSemester;
    if (active == null || _activeImportMode != 'student') return null;

    final targetSy = (active['school_year'] ?? '').toString().trim();
    final targetSem = (active['label'] ?? '').toString().trim();
    if (targetSy.isEmpty && targetSem.isEmpty) return null;

    final fileSy = (fileMeta['school_year'] ?? '').toString().trim();
    final fileSem = (fileMeta['semester'] ?? '').toString().trim();
    // Plain CSV without preamble is allowed.
    if (fileSy.isEmpty && fileSem.isEmpty) {
      return null;
    }

    final syMismatch =
        fileSy.isNotEmpty && targetSy.isNotEmpty && fileSy != targetSy;
    final semMismatch =
        fileSem.isNotEmpty &&
        targetSem.isNotEmpty &&
        fileSem.toLowerCase() != targetSem.toLowerCase();

    if (syMismatch || semMismatch) {
      final fileTerm = [
        if (fileSem.isNotEmpty) fileSem,
        if (fileSy.isNotEmpty) 'A.Y. $fileSy',
      ].join(', ');
      final targetTerm = [
        if (targetSem.isNotEmpty) targetSem,
        if (targetSy.isNotEmpty) 'A.Y. $targetSy',
      ].join(', ');
      return 'File term: $fileTerm\nActive term: $targetTerm\nUpload a class list for the active term, or change the active semester in Academic Periods.';
    }
    return null;
  }

  StagedFileInfo _inspectExtractedRows(
    PickedTabularFile file,
    List<List<String>> rows,
    String importMode, {
    required bool isXlsx,
  }) {
    if (rows.isEmpty) {
      return StagedFileInfo(
        file: file,
        formatLabel: isXlsx ? 'Excel Spreadsheet' : 'CSV Document',
        isValid: false,
        rowCount: 0,
        detectedImportMode: importMode,
        warning: 'File is empty.',
      );
    }

    // 1. Check for Official Class List header signatures
    bool isOfficialClassList = false;
    String? subjectCode;
    String? subjectTitle;
    String? section;
    String? yearLevel;
    String? instructor;

    final headerScanLimit = rows.length < 20 ? rows.length : 20;
    for (var i = 0; i < headerScanLimit; i++) {
      final line = rows[i].join(' ').toLowerCase();
      if (line.contains('official list of enrolled students')) {
        isOfficialClassList = true;
      }
      for (var j = 0; j < rows[i].length; j++) {
        final cell = rows[i][j].trim();
        final lower = cell.toLowerCase();

        if (lower == 'subject code' && j + 1 < rows[i].length) {
          subjectCode = rows[i][j + 1].trim();
          isOfficialClassList = true;
        } else if (lower.startsWith('subject code,') ||
            lower.startsWith('subject code:')) {
          final parts = cell.split(RegExp(r'[,:]'));
          if (parts.length > 1) subjectCode = parts[1].trim();
          isOfficialClassList = true;
        }

        if (lower == 'subject title' && j + 1 < rows[i].length) {
          subjectTitle = rows[i][j + 1].trim();
        }
        if (lower == 'class section' && j + 1 < rows[i].length) {
          section = rows[i][j + 1].trim();
        }
        if (lower == 'year level' && j + 1 < rows[i].length) {
          yearLevel = rows[i][j + 1].trim();
        }
        if (lower == 'instructor' && j + 1 < rows[i].length) {
          instructor = rows[i][j + 1].trim();
        }
      }
    }

    if (isOfficialClassList) {
      final parsed = parseOfficialClassListRows(rows);
      int studentCount = parsed.students.isNotEmpty
          ? parsed.students.length
          : 0;
      if (studentCount == 0) {
        bool inStudentTable = false;
        for (final row in rows) {
          final line = row.join(' ').toLowerCase();
          if (line.contains('student number') ||
              line.contains('student no') ||
              line.contains('student id') ||
              line.contains('id number') ||
              (line.contains('student') && line.contains('name'))) {
            inStudentTable = true;
            continue;
          }
          if (inStudentTable && row.isNotEmpty) {
            final nonEmpty = row.where((c) => c.trim().isNotEmpty).toList();
            if (nonEmpty.length >= 2) {
              studentCount++;
            }
          }
        }
      }

      if (studentCount == 0) {
        studentCount = rows.length > 12 ? rows.length - 12 : 0;
      }

      final termMismatch = _checkAcademicTermMismatch(parsed.metadata);
      final detectedTerm = [
        if (parsed.metadata['semester'] != null &&
            parsed.metadata['semester'].toString().trim().isNotEmpty)
          parsed.metadata['semester'].toString().trim(),
        if (parsed.metadata['school_year'] != null &&
            parsed.metadata['school_year'].toString().trim().isNotEmpty)
          parsed.metadata['school_year'].toString().trim(),
      ].join(' • ');

      final isGeneralMode = importMode == 'general';
      if (isGeneralMode) {
        return StagedFileInfo(
          file: file,
          formatLabel: 'Official Class List (Student)',
          isValid: false,
          rowCount: 0,
          detectedImportMode: 'student',
          recordEntityLabel: 'students',
          primaryRole: 'Student',
          section: section?.isNotEmpty == true
              ? section
              : 'Auto-detected Section',
          subjectCode: subjectCode,
          subjectTitle: subjectTitle,
          yearLevel: yearLevel,
          instructor: instructor,
          academicTerm: detectedTerm.isNotEmpty ? detectedTerm : null,
          warning:
              'This file is a Student Class List. It cannot be imported into Faculty & Staff. Please use the Batch Student Enrollment Hub instead.',
        );
      }

      if (termMismatch != null) {
        return StagedFileInfo(
          file: file,
          formatLabel: 'Official Class List',
          isValid: false,
          rowCount: 0,
          detectedImportMode: 'student',
          recordEntityLabel: 'students',
          primaryRole: 'Student',
          section: section?.isNotEmpty == true
              ? section
              : 'Auto-detected Section',
          subjectCode: subjectCode,
          subjectTitle: subjectTitle,
          yearLevel: yearLevel,
          instructor: instructor,
          academicTerm: detectedTerm.isNotEmpty ? detectedTerm : null,
          warning: termMismatch,
          warningTitle: 'Academic term mismatch',
        );
      }

      return StagedFileInfo(
        file: file,
        formatLabel: 'Official Class List',
        isValid: studentCount > 0,
        rowCount: studentCount,
        detectedImportMode: 'student',
        recordEntityLabel: 'students',
        primaryRole: 'Student',
        section: section?.isNotEmpty == true
            ? section
            : 'Auto-detected Section',
        subjectCode: subjectCode,
        subjectTitle: subjectTitle,
        yearLevel: yearLevel,
        instructor: instructor,
        academicTerm: detectedTerm.isNotEmpty ? detectedTerm : null,
        warning: studentCount == 0
            ? 'No enrolled student records found in template.'
            : null,
      );
    }

    // 1b. Check for Official University Registrar List of Enrollment (By Year Level)
    bool isByYearEnrollmentList = false;
    for (var i = 0; i < headerScanLimit; i++) {
      final line = rows[i].join(' ').toLowerCase();
      if (line.contains('list of enrollment') ||
          (line.contains('officially enrolled') &&
              line.contains('registered'))) {
        isByYearEnrollmentList = true;
        break;
      }
    }

    if (isByYearEnrollmentList) {
      final parsed = parseOfficialClassListRows(rows);
      final studentCount = parsed.students.length;
      final detectedYear = parsed.metadata['year_level']?.toString();

      final termMismatch = _checkAcademicTermMismatch(parsed.metadata);
      final detectedTerm = [
        if (parsed.metadata['semester'] != null &&
            parsed.metadata['semester'].toString().trim().isNotEmpty)
          parsed.metadata['semester'].toString().trim(),
        if (parsed.metadata['school_year'] != null &&
            parsed.metadata['school_year'].toString().trim().isNotEmpty)
          parsed.metadata['school_year'].toString().trim(),
      ].join(' • ');

      final isGeneralMode = importMode == 'general';
      if (isGeneralMode) {
        return StagedFileInfo(
          file: file,
          formatLabel: 'Official Class List (By Year Level)',
          isValid: false,
          rowCount: 0,
          detectedImportMode: 'student',
          recordEntityLabel: 'students',
          primaryRole: 'Student',
          yearLevel: detectedYear,
          academicTerm: detectedTerm.isNotEmpty ? detectedTerm : null,
          warning:
              'This file is a Student Class List (By Year Level). It cannot be imported into Faculty & Staff. Please use the Batch Student Enrollment Hub instead.',
        );
      }

      if (termMismatch != null) {
        return StagedFileInfo(
          file: file,
          formatLabel: 'Official Class List (By Year Level)',
          isValid: false,
          rowCount: 0,
          detectedImportMode: 'student',
          recordEntityLabel: 'students',
          primaryRole: 'Student',
          section: null,
          yearLevel: detectedYear,
          academicTerm: detectedTerm.isNotEmpty ? detectedTerm : null,
          warning: termMismatch,
          warningTitle: 'Academic term mismatch',
        );
      }

      return StagedFileInfo(
        file: file,
        formatLabel: 'Official Class List (By Year Level)',
        isValid: studentCount > 0,
        rowCount: studentCount,
        detectedImportMode: 'student',
        recordEntityLabel: 'students',
        primaryRole: 'Student',
        section: null,
        yearLevel: detectedYear,
        academicTerm: detectedTerm.isNotEmpty ? detectedTerm : null,
        warning: studentCount == 0
            ? 'No enrolled student records found in template.'
            : null,
      );
    }

    // 2. Standard CSV / Header-based format check
    final headers = rows.first
        .map(
          (h) => h
              .trim()
              .toLowerCase()
              .replaceAll('"', '')
              .replaceFirst('\ufeff', ''),
        )
        .toList();

    final hasId =
        headers.contains('id_number') ||
        headers.contains('student_number') ||
        headers.contains('id');
    final hasEmail = headers.contains('email');
    final hasName =
        headers.contains('first_name') ||
        headers.contains('name') ||
        headers.contains('full_name');
    final roleIndex = headers.indexWhere(
      (h) => h == 'role' || h == 'roles' || h == 'user_role' || h == 'type',
    );
    final hasStudentHeaders =
        headers.contains('student_number') ||
        headers.contains('year_level') ||
        headers.contains('section');

    if (hasId || hasEmail || hasName) {
      final rowCount = (rows.length - 1).clamp(0, 999999);
      final roleCounts = <String, int>{};

      if (roleIndex != -1) {
        for (var i = 1; i < rows.length; i++) {
          if (roleIndex < rows[i].length) {
            final role = rows[i][roleIndex].trim().toLowerCase();
            if (role.isNotEmpty) {
              roleCounts[role] = (roleCounts[role] ?? 0) + 1;
            }
          }
        }
      }

      final facultyCount =
          (roleCounts['faculty'] ?? 0) +
          (roleCounts['instructor'] ?? 0) +
          (roleCounts['teacher'] ?? 0) +
          (roleCounts['professor'] ?? 0) +
          (roleCounts['chairperson'] ?? 0) +
          (roleCounts['panelist'] ?? 0) +
          (roleCounts['coordinator'] ?? 0) +
          (roleCounts['dean'] ?? 0);
      final adminCount =
          (roleCounts['admin'] ?? 0) +
          (roleCounts['staff'] ?? 0) +
          (roleCounts['user'] ?? 0);
      final studentCount = roleCounts['student'] ?? 0;

      final lowerName = file.name.toLowerCase();
      final hasFacultyInName =
          lowerName.contains('faculty') ||
          lowerName.contains('instructor') ||
          lowerName.contains('teacher') ||
          lowerName.contains('prof');
      final hasAdminInName =
          lowerName.contains('admin') ||
          lowerName.contains('staff') ||
          lowerName.contains('user');
      final hasStudentInName =
          lowerName.contains('student') ||
          lowerName.contains('section') ||
          lowerName.contains('class');

      final isFacultyTarget = importMode == 'general';
      final isStudentTarget = importMode == 'student';

      final isPurelyStudent =
          (studentCount > 0 && facultyCount == 0 && adminCount == 0) ||
          (hasStudentHeaders && facultyCount == 0 && adminCount == 0) ||
          (hasStudentInName && studentCount > 0);
      final isPurelyFacultyOrAdmin =
          ((facultyCount + adminCount) > 0 && studentCount == 0) ||
          (hasFacultyInName && studentCount == 0);

      if (isFacultyTarget && isPurelyStudent) {
        return StagedFileInfo(
          file: file,
          formatLabel: 'Student Accounts CSV',
          isValid: false,
          rowCount: 0,
          detectedImportMode: 'student',
          recordEntityLabel: 'students',
          primaryRole: 'Student',
          warning:
              'This file contains student records. It cannot be imported into Faculty & Staff. Please use the Batch Student Enrollment Hub instead.',
        );
      }

      if (isStudentTarget && isPurelyFacultyOrAdmin) {
        return StagedFileInfo(
          file: file,
          formatLabel: 'Faculty Accounts CSV',
          isValid: false,
          rowCount: 0,
          detectedImportMode: 'general',
          recordEntityLabel: 'faculty',
          primaryRole: 'Faculty',
          warning:
              'This file is a Faculty & Staff template. It cannot be imported into Student Intake.',
        );
      }

      String detectedMode;
      String formatLabel;
      String entityLabel;
      String primaryRole;

      if ((facultyCount > 0 && studentCount == 0 && adminCount == 0) ||
          (hasFacultyInName && studentCount == 0)) {
        detectedMode = 'general';
        formatLabel = 'Faculty Accounts CSV';
        entityLabel = 'faculty';
        primaryRole = 'Faculty';
      } else if (((facultyCount + adminCount) > 0 && studentCount == 0) ||
          (hasAdminInName && studentCount == 0)) {
        detectedMode = 'general';
        formatLabel = 'User Accounts CSV';
        entityLabel = 'users';
        primaryRole = adminCount > 0 ? 'Admin / Staff' : 'User';
      } else if ((facultyCount + adminCount) > 0 && studentCount > 0) {
        detectedMode = 'general';
        formatLabel = 'Multi-Role User CSV';
        entityLabel = 'users';
        primaryRole = 'Multi-Role';
      } else if (studentCount > 0 || hasStudentHeaders || hasStudentInName) {
        detectedMode = 'student';
        formatLabel = 'Standard Student CSV';
        entityLabel = 'students';
        primaryRole = 'Student';
      } else {
        // Fallback according to active modal mode
        final isModeStudent = importMode == 'student';
        detectedMode = isModeStudent ? 'student' : 'general';
        formatLabel = isModeStudent
            ? 'Standard Student CSV'
            : 'User Account CSV';
        entityLabel = isModeStudent ? 'students' : 'users';
        primaryRole = isModeStudent ? 'Student' : 'General User';
      }

      return StagedFileInfo(
        file: file,
        formatLabel: formatLabel,
        isValid: rowCount > 0,
        rowCount: rowCount,
        detectedImportMode: detectedMode,
        recordEntityLabel: entityLabel,
        primaryRole: primaryRole,
        warning: rowCount == 0
            ? 'File has header columns but no data rows.'
            : null,
      );
    }

    final lowerFileName = file.name.toLowerCase();
    String detectedHint = '';
    if (lowerFileName.contains('defense') ||
        lowerFileName.contains('schedule')) {
      detectedHint = ' (appears to be a defense schedule file)';
    } else if (lowerFileName.contains('team') ||
        lowerFileName.contains('group')) {
      detectedHint = ' (appears to be a student team file)';
    } else if (lowerFileName.contains('grade') ||
        lowerFileName.contains('score')) {
      detectedHint = ' (appears to be a grading/score file)';
    }

    return StagedFileInfo(
      file: file,
      formatLabel: isXlsx ? 'Incompatible Spreadsheet' : 'Incompatible File',
      isValid: false,
      rowCount: 0,
      detectedImportMode: importMode,
      recordEntityLabel: 'incompatible',
      warning:
          'Columns not recognized for ${importMode == 'student' ? 'Student Intake' : 'Faculty & Staff Import'}$detectedHint. This file will be skipped unless replaced.',
    );
  }

  String _excelCellText(xl.CellValue? value) {
    if (value == null) return '';
    if (value is xl.TextCellValue) {
      return (value.value.text ?? '').trim();
    }
    if (value is xl.IntCellValue) return value.value.toString();
    if (value is xl.DoubleCellValue) {
      final number = value.value;
      if (number == number.roundToDouble()) {
        return number.round().toString();
      }
      return number.toString();
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

  Future<void> _handleReplaceFile(int index) async {
    setState(() => _isProcessing = true);
    try {
      final newFile = await pickSingleTabularDataFile();
      if (!mounted || newFile == null) {
        return;
      }

      setState(() {
        _stagedFiles[index] = newFile;
        _reinspectAllFiles();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not replace file: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleAddMoreFiles() async {
    setState(() => _isProcessing = true);
    try {
      final newFiles = await pickMultipleTabularDataFiles();
      if (!mounted || newFiles.isEmpty) {
        return;
      }

      setState(() {
        for (final f in newFiles) {
          final exists = _stagedFiles.any(
            (existing) =>
                existing.name == f.name &&
                existing.bytes.length == f.bytes.length,
          );
          if (!exists) {
            _stagedFiles.add(f);
          }
        }
        _reinspectAllFiles();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add file(s): $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleRemoveFile(int index) {
    setState(() {
      _stagedFiles.removeAt(index);
      _reinspectAllFiles();
    });
  }

  void _handleClearAll() {
    setState(() {
      _stagedFiles.clear();
      _reinspectAllFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasValidFiles = _inspectedFiles.any((f) => f.isValid);
    return DefensysShadcnScope(
      maroonActions: true,
      neutralActionText: true,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: Container(
            width: 680,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height - 48,
            ),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceOf(context),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
              border: Border.all(color: DefensysTokens.borderOf(context)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                if (_isDraggingFile)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Drop files to add to staging',
                      style: _textStyle(),
                    ),
                  ),
                Divider(height: 1, color: DefensysTokens.borderOf(context)),
                if (_stagedFiles.isNotEmpty) _buildSummaryBar(),
                Flexible(
                  child: _stagedFiles.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                          shrinkWrap: true,
                          itemCount: _inspectedFiles.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => _buildFileCard(
                            context,
                            index,
                            _inspectedFiles[index],
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: _buildAddMoreButton(),
                ),
                Divider(height: 1, color: DefensysTokens.borderOf(context)),
                _buildFooter(context, hasValidFiles),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _textStyle({bool secondary = false, bool bold = false}) =>
      TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        fontSize: 12,
        height: 1.45,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: secondary
            ? DefensysTokens.textSecondaryOf(context)
            : DefensysTokens.textPrimaryOf(context),
      );

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Staged Import Files',
                style: _textStyle(bold: true).copyWith(fontSize: 16),
              ),
              const SizedBox(height: 3),
              Text(
                'Review files before generating the preview.',
                style: _textStyle(secondary: true),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Cancel & Close',
          child: ShadButton.ghost(
            width: 36,
            height: 36,
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(null),
            child: const Icon(Icons.close_rounded, size: 18),
          ),
        ),
      ],
    ),
  );

  Widget _buildSummaryBar() {
    final validCount = _inspectedFiles.where((f) => f.isValid).length;
    final invalidCount = _inspectedFiles.length - validCount;
    final semesterBlocked =
        _activeImportMode == 'student' && !widget.hasActiveSemester;
    final modeLabel = _activeImportMode == 'student'
        ? 'Student Batch'
        : 'Faculty / General Users';
    final summary = semesterBlocked
        ? 'Set an active semester in Academic Periods to continue.'
        : invalidCount > 0
        ? '$validCount ready · $invalidCount ${invalidCount == 1 ? 'file needs' : 'files need'} attention${validCount > 0 ? ' · Only ready files will be imported' : ''}'
        : '$validCount ${validCount == 1 ? 'file' : 'files'} staged · $_totalValidRows ${_totalValidRows == 1 ? 'record' : 'records'} ready ($modeLabel)';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          Expanded(child: Text(summary, style: _textStyle(secondary: true))),
          if (_stagedFiles.length > 1)
            ShadButton.ghost(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              enabled: !_isProcessing,
              onPressed: _handleClearAll,
              child: const Text('Clear All'),
            ),
        ],
      ),
    );
  }

  Widget _buildFileCard(BuildContext context, int index, StagedFileInfo info) {
    final hasWarning = info.warning != null;
    final warningTitle =
        info.warningTitle ??
        (!info.isValid
            ? (!info.file.isCsv && !info.file.isXlsx
                  ? 'Unsupported file format'
                  : 'Cannot import this file')
            : 'Review before importing');
    final metadata = <String>[
      if (info.academicTerm?.isNotEmpty == true) info.academicTerm!,
      if (info.section?.isNotEmpty == true) 'Section: ${info.section}',
      if (info.yearLevel?.isNotEmpty == true) info.yearLevel!,
      if (info.subjectCode?.isNotEmpty == true) info.subjectCode!,
      if (info.isValid)
        '${info.rowCount} ${info.recordEntityLabel == 'faculty'
            ? 'faculty'
            : info.rowCount == 1
            ? info.recordEntityLabel.replaceFirst(RegExp(r's$'), '')
            : info.recordEntityLabel}',
      if (info.isValid &&
          info.primaryRole != null &&
          !info.formatLabel.startsWith('Official Class List'))
        'Role: ${info.primaryRole}',
    ];
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShadButton.outline(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          enabled: !_isProcessing,
          onPressed: () => _handleReplaceFile(index),
          leading: const Icon(Icons.sync_rounded, size: 14),
          child: const Text('Replace'),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Remove File',
          child: ShadButton.ghost(
            width: 32,
            height: 32,
            padding: EdgeInsets.zero,
            enabled: !_isProcessing,
            onPressed: () => _handleRemoveFile(index),
            child: const Icon(Icons.delete_outline_rounded, size: 17),
          ),
        ),
      ],
    );
    return Container(
      key: ObjectKey(info.file),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 460 ||
                  MediaQuery.textScalerOf(context).scale(12) > 15;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: DefensysTokens.surfaceHigherOf(context),
                          borderRadius: BorderRadius.circular(
                            DefensysTokens.radiusSm,
                          ),
                        ),
                        child: Text(
                          info.extension,
                          style: _textStyle(secondary: true, bold: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Tooltip(
                              message: info.fileName,
                              child: Text(
                                info.fileName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _textStyle(
                                  bold: true,
                                ).copyWith(fontSize: 13),
                              ),
                            ),
                            Text(
                              '${info.formattedFileSize} · ${info.formatLabel}',
                              style: _textStyle(
                                secondary: true,
                              ).copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (!compact) ...[const SizedBox(width: 12), actions],
                    ],
                  ),
                  if (compact) ...[
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                ],
              );
            },
          ),
          if (metadata.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final label in metadata)
                  Text(label, style: _textStyle(secondary: true)),
              ],
            ),
          ],
          if (hasWarning) ...[
            const SizedBox(height: 6),
            ShadAccordion<String>(
              key: ObjectKey(info.file),
              children: [
                ShadAccordionItem<String>(
                  value: 'warning',
                  separator: const SizedBox.shrink(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  title: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: DefensysTokens.maroonTextOf(context),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            warningTitle,
                            style: _textStyle(bold: true).copyWith(
                              color: DefensysTokens.maroonTextOf(context),
                            ),
                          ),
                        ),
                        if (constraints.maxWidth >= 340) ...[
                          const SizedBox(width: 8),
                          Text(
                            'View details',
                            style: _textStyle(
                              secondary: true,
                            ).copyWith(fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      info.warning!,
                      style: _textStyle(secondary: true),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() => DefensysEmptyState(
    icon: Icons.folder_open_rounded,
    title: 'No Files Currently Staged',
    description: _activeImportMode == 'student'
        ? 'Add a student class list (.csv / .xlsx).'
        : 'Add a faculty & staff spreadsheet (.csv / .xlsx).',
    size: DefensysEmptyStateSize.compact,
  );

  Widget _buildAddMoreButton() => ShadButton.outline(
    enabled: !_isProcessing,
    onPressed: _handleAddMoreFiles,
    height: null,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    leading: const Icon(Icons.add_rounded, size: 16),
    child: Flexible(
      child: Text(
        _isDraggingFile
            ? 'Drop files to add to staging'
            : _stagedFiles.isEmpty
            ? 'Select file(s) to import'
            : _activeImportMode == 'student'
            ? 'Add another class section or file'
            : 'Add another faculty/staff file',
        textAlign: TextAlign.center,
      ),
    ),
  );

  Widget _buildFooter(BuildContext context, bool hasValidFiles) {
    final semesterBlocked =
        _activeImportMode == 'student' && !widget.hasActiveSemester;
    final enabled = hasValidFiles && !_isProcessing && !semesterBlocked;
    final previewLabel = semesterBlocked
        ? 'Active Semester Required'
        : _totalValidRows > 0
        ? 'Generate Preview Table ($_totalValidRows rows)'
        : 'Generate Preview Table';
    final cancel = ShadButton.ghost(
      onPressed: () => Navigator.of(context).pop(null),
      child: const Text('Cancel'),
    );
    final preview = ShadButton(
      enabled: enabled,
      backgroundColor: enabled
          ? DefensysTokens.maroonOf(context)
          : DefensysTokens.surfaceHigherOf(context),
      foregroundColor: enabled
          ? Colors.white
          : DefensysTokens.textSecondaryOf(context),
      onPressed: enabled
          ? () => Navigator.of(context).pop(
              StagedImportResult(
                files: _inspectedFiles
                    .where((f) => f.isValid)
                    .map((f) => f.file)
                    .toList(),
                importMode: _activeImportMode,
              ),
            )
          : null,
      child: Text(previewLabel),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(12) > 15) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [preview, const SizedBox(height: 4), cancel],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [cancel, preview],
          );
        },
      ),
    );
  }
}
