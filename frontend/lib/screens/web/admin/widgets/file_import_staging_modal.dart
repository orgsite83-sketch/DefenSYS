import 'dart:convert';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../utils/csv_file_io.dart';

/// Result containing staged files and user-confirmed import mode.
class StagedImportResult {
  final List<PickedTabularFile> files;
  final String importMode; // 'student' or 'general'

  const StagedImportResult({
    required this.files,
    required this.importMode,
  });
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
  final String? warning;

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
    this.warning,
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
}) async {
  return showDialog<StagedImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => FileImportStagingModal(
      initialFiles: initialFiles,
      importMode: importMode,
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
  });

  final List<PickedTabularFile> initialFiles;
  final String importMode;

  @override
  State<FileImportStagingModal> createState() => _FileImportStagingModalState();
}

class _FileImportStagingModalState extends State<FileImportStagingModal> {
  final List<PickedTabularFile> _stagedFiles = [];
  final List<StagedFileInfo> _inspectedFiles = [];
  late String _activeImportMode;
  String? _autoSwitchedModeNotice;
  bool _isProcessing = false;
  int _totalValidRows = 0;

  @override
  void initState() {
    super.initState();
    _stagedFiles.addAll(widget.initialFiles);
    _activeImportMode = widget.importMode;

    // Check initial files to see if mode should be auto-detected
    if (_stagedFiles.isNotEmpty) {
      final initialInspected = _stagedFiles.map((f) => _inspectFile(f, widget.importMode)).toList();
      final allGeneral = initialInspected.every((f) => f.detectedImportMode == 'general' && f.isValid);
      final allStudent = initialInspected.every((f) => f.detectedImportMode == 'student' && f.isValid);

      if (allGeneral && widget.importMode == 'student') {
        _activeImportMode = 'general';
        _autoSwitchedModeNotice = 'Detected Faculty / General User CSV — Import Mode set to Faculty / General Users.';
      } else if (allStudent && widget.importMode == 'general') {
        _activeImportMode = 'student';
        _autoSwitchedModeNotice = 'Detected Student Class List / CSV — Import Mode set to Student Batch.';
      }
    }

    _reinspectAllFiles();
  }

  void _reinspectAllFiles() {
    _inspectedFiles.clear();
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
      } else {
        return _inspectCsvFile(file, importMode);
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
      final workbook = xl.Excel.decodeBytes(file.bytes);
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
        } else if (lower.startsWith('subject code,') || lower.startsWith('subject code:')) {
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
      int studentCount = 0;
      bool inStudentTable = false;
      for (final row in rows) {
        final line = row.join(' ').toLowerCase();
        if (line.contains('student number') || line.contains('student no')) {
          inStudentTable = true;
          continue;
        }
        if (inStudentTable && row.isNotEmpty) {
          final firstNonEmpty = row.firstWhere((c) => c.trim().isNotEmpty, orElse: () => '');
          if (firstNonEmpty.isNotEmpty && RegExp(r'^\d+$').hasMatch(firstNonEmpty)) {
            studentCount++;
          }
        }
      }

      if (studentCount == 0) {
        studentCount = rows.length > 12 ? rows.length - 12 : 0;
      }

      return StagedFileInfo(
        file: file,
        formatLabel: 'Official Class List',
        isValid: studentCount > 0,
        rowCount: studentCount,
        detectedImportMode: 'student',
        recordEntityLabel: 'students',
        primaryRole: 'Student',
        section: section?.isNotEmpty == true ? section : 'Auto-detected Section',
        subjectCode: subjectCode,
        subjectTitle: subjectTitle,
        yearLevel: yearLevel,
        instructor: instructor,
        warning: studentCount == 0 ? 'No enrolled student records found in template.' : null,
      );
    }

    // 2. Standard CSV / Header-based format check
    final headers = rows.first
        .map((h) => h.trim().toLowerCase().replaceAll('"', '').replaceFirst('\ufeff', ''))
        .toList();

    final hasId = headers.contains('id_number') || headers.contains('student_number') || headers.contains('id');
    final hasEmail = headers.contains('email');
    final hasName = headers.contains('first_name') || headers.contains('name') || headers.contains('full_name');
    final roleIndex = headers.indexWhere((h) => h == 'role' || h == 'roles' || h == 'user_role' || h == 'type');
    final hasStudentHeaders = headers.contains('student_number') || headers.contains('year_level') || headers.contains('section');

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

      final facultyCount = (roleCounts['faculty'] ?? 0) +
          (roleCounts['instructor'] ?? 0) +
          (roleCounts['teacher'] ?? 0) +
          (roleCounts['professor'] ?? 0) +
          (roleCounts['chairperson'] ?? 0) +
          (roleCounts['panelist'] ?? 0) +
          (roleCounts['coordinator'] ?? 0) +
          (roleCounts['dean'] ?? 0);
      final adminCount = (roleCounts['admin'] ?? 0) + (roleCounts['staff'] ?? 0) + (roleCounts['user'] ?? 0);
      final studentCount = roleCounts['student'] ?? 0;

      final lowerName = file.name.toLowerCase();
      final hasFacultyInName = lowerName.contains('faculty') || lowerName.contains('instructor') || lowerName.contains('teacher') || lowerName.contains('prof');
      final hasAdminInName = lowerName.contains('admin') || lowerName.contains('staff') || lowerName.contains('user');
      final hasStudentInName = lowerName.contains('student') || lowerName.contains('section') || lowerName.contains('class');

      String detectedMode;
      String formatLabel;
      String entityLabel;
      String primaryRole;

      if ((facultyCount > 0 && studentCount == 0 && adminCount == 0) || (hasFacultyInName && studentCount == 0)) {
        detectedMode = 'general';
        formatLabel = 'Faculty Accounts CSV';
        entityLabel = 'faculty';
        primaryRole = 'Faculty';
      } else if (((facultyCount + adminCount) > 0 && studentCount == 0) || (hasAdminInName && studentCount == 0)) {
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
        formatLabel = isModeStudent ? 'Standard Student CSV' : 'User Account CSV';
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
        warning: rowCount == 0 ? 'File has header columns but no data rows.' : null,
      );
    }

    return StagedFileInfo(
      file: file,
      formatLabel: isXlsx ? 'Spreadsheet (.xlsx)' : 'Delimited File (.csv)',
      isValid: rows.length > 1,
      rowCount: (rows.length - 1).clamp(0, 999999),
      detectedImportMode: importMode,
      recordEntityLabel: 'records',
      warning: 'Template columns not recognized. May need column mapping.',
    );
  }

  String _excelCellText(xl.CellValue? value) {
    if (value == null) return '';
    if (value is xl.TextCellValue) return value.value.toString().trim();
    if (value is xl.IntCellValue) return value.value.toString();
    if (value is xl.DoubleCellValue) {
      final number = value.value;
      if (number == number.roundToDouble()) {
        return number.round().toString();
      }
      return number.toString();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not replace file: $e')),
        );
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
            (existing) => existing.name == f.name && existing.bytes.length == f.bytes.length,
          );
          if (!exists) {
            _stagedFiles.add(f);
          }
        }
        _reinspectAllFiles();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add file(s): $e')),
        );
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
    final hasValidFiles = _stagedFiles.isNotEmpty && _inspectedFiles.any((f) => f.isValid);
    final isStudent = _activeImportMode == 'student';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Container(
          width: 680,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.90,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
            border: Border.all(color: DefensysTokens.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header
              _buildHeader(context),

              const Divider(height: 1, color: DefensysTokens.border),

              // 2. Import Mode Selector Tab
              _buildModeSelector(),

              // 3. Auto-switch notification banner (if triggered)
              if (_autoSwitchedModeNotice != null) _buildAutoSwitchNotice(),

              // 4. Summary Info Bar
              if (_stagedFiles.isNotEmpty) _buildSummaryBar(),

              // 5. Staged Files List
              Flexible(
                child: _stagedFiles.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        shrinkWrap: true,
                        itemCount: _inspectedFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return _buildFileCard(context, index, _inspectedFiles[index]);
                        },
                      ),
              ),

              // 6. Add more file area
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildAddMoreButton(),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, color: DefensysTokens.border),

              // 7. Footer Actions
              _buildFooter(context, hasValidFiles, isStudent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: DefensysTokens.maroon.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.15)),
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: DefensysTokens.maroon,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Staged Import Files',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: DefensysTokens.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Review or replace your source files before generating the preview table.',
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(null),
            icon: const Icon(Icons.close_rounded, size: 20),
            color: DefensysTokens.steelGrey,
            splashRadius: 18,
            tooltip: 'Cancel & Close',
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeTab(
              mode: 'student',
              label: 'Student Batch',
              icon: Icons.school_rounded,
              isSelected: _activeImportMode == 'student',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildModeTab(
              mode: 'general',
              label: 'Faculty / General Users',
              icon: Icons.badge_rounded,
              isSelected: _activeImportMode == 'general',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required String mode,
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        if (_activeImportMode != mode) {
          setState(() {
            _activeImportMode = mode;
            _autoSwitchedModeNotice = null;
            _reinspectAllFiles();
          });
        }
      },
      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? DefensysTokens.maroon : DefensysTokens.steelGrey,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  color: isSelected ? DefensysTokens.maroon : DefensysTokens.textSecondary,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoSwitchNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _autoSwitchedModeNotice!,
              style: const TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                color: Color(0xFF1E40AF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _autoSwitchedModeNotice = null),
            icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF6B7280)),
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    final fileCount = _stagedFiles.length;
    final fileWord = fileCount == 1 ? 'file' : 'files';
    final rowWord = _totalValidRows == 1 ? 'record' : 'records';
    final modeLabel = _activeImportMode == 'student' ? 'Student Batch' : 'Faculty / General';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: DefensysTokens.background,
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
            color: DefensysTokens.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$fileCount $fileWord staged  •  $_totalValidRows total $rowWord ready ($modeLabel)',
              style: const TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                color: DefensysTokens.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (fileCount > 1)
            InkWell(
              onTap: _handleClearAll,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'Clear All',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: DefensysTokens.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileCard(BuildContext context, int index, StagedFileInfo info) {
    final isCsv = info.file.isCsv;

    // Determine badge theme based on entity type
    final isFaculty = info.recordEntityLabel == 'faculty';
    final isUsers = info.recordEntityLabel == 'users';
    final isStudents = info.recordEntityLabel == 'students';

    final Color entityBg;
    final Color entityFg;
    final Color entityBorder;
    final IconData entityIcon;

    if (isFaculty) {
      entityBg = const Color(0xFFFDF2F4);
      entityFg = DefensysTokens.maroon;
      entityBorder = const Color(0xFFFECDD3);
      entityIcon = Icons.badge_outlined;
    } else if (isUsers) {
      entityBg = DefensysTokens.infoBg;
      entityFg = DefensysTokens.infoText;
      entityBorder = DefensysTokens.infoBorder;
      entityIcon = Icons.manage_accounts_outlined;
    } else {
      entityBg = info.isValid ? DefensysTokens.successBg : DefensysTokens.warningBg;
      entityFg = info.isValid ? DefensysTokens.successText : DefensysTokens.warningText;
      entityBorder = info.isValid ? DefensysTokens.successBorder : DefensysTokens.warningBorder;
      entityIcon = Icons.school_outlined;
    }

    String entityCountText;
    if (isFaculty) {
      entityCountText = '${info.rowCount} ${info.rowCount == 1 ? 'faculty' : 'faculty'}';
    } else if (isUsers) {
      entityCountText = '${info.rowCount} ${info.rowCount == 1 ? 'user' : 'users'}';
    } else if (isStudents) {
      entityCountText = '${info.rowCount} ${info.rowCount == 1 ? 'student' : 'students'}';
    } else {
      entityCountText = '${info.rowCount} ${info.rowCount == 1 ? 'record' : 'records'}';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(
          color: info.warning != null ? DefensysTokens.warningBorder : DefensysTokens.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: File icon badge, name, size, replace/remove buttons
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Extension Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isCsv ? DefensysTokens.successBg : DefensysTokens.infoBg,
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                  border: Border.all(
                    color: isCsv ? DefensysTokens.successBorder : DefensysTokens.infoBorder,
                  ),
                ),
                child: Text(
                  info.extension,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    color: isCsv ? DefensysTokens.successText : DefensysTokens.infoText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // File Name & Size
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        color: DefensysTokens.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${info.formattedFileSize}  •  ${info.formatLabel}',
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        color: DefensysTokens.steelGrey,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Replace Action Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: DefensysTokens.textPrimary,
                  side: const BorderSide(color: DefensysTokens.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                  ),
                ),
                onPressed: _isProcessing ? null : () => _handleReplaceFile(index),
                icon: const Icon(Icons.sync_rounded, size: 14, color: DefensysTokens.textSecondary),
                label: const Text(
                  'Replace',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Remove Action Button
              IconButton(
                style: IconButton.styleFrom(
                  foregroundColor: DefensysTokens.danger,
                  hoverColor: DefensysTokens.dangerBg,
                  padding: const EdgeInsets.all(6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                  ),
                ),
                onPressed: () => _handleRemoveFile(index),
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                tooltip: 'Remove File',
              ),
            ],
          ),

          // Row 2: Detected Metadata Chips / Pills
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (info.section != null && info.section!.isNotEmpty)
                _buildMetadataChip(
                  icon: Icons.groups_rounded,
                  label: 'Section: ${info.section}',
                  bgColor: const Color(0xFFF1F5F9),
                  fgColor: DefensysTokens.textPrimary,
                ),
              if (info.yearLevel != null && info.yearLevel!.isNotEmpty)
                _buildMetadataChip(
                  icon: Icons.school_rounded,
                  label: info.yearLevel!,
                  bgColor: const Color(0xFFF1F5F9),
                  fgColor: DefensysTokens.textSecondary,
                ),
              if (info.subjectCode != null && info.subjectCode!.isNotEmpty)
                _buildMetadataChip(
                  icon: Icons.menu_book_rounded,
                  label: info.subjectCode!,
                  bgColor: const Color(0xFFF1F5F9),
                  fgColor: DefensysTokens.textSecondary,
                ),
              _buildMetadataChip(
                icon: entityIcon,
                label: entityCountText,
                bgColor: entityBg,
                fgColor: entityFg,
                borderColor: entityBorder,
              ),
              if (info.primaryRole != null && info.formatLabel != 'Official Class List')
                _buildMetadataChip(
                  icon: Icons.person_pin_circle_outlined,
                  label: 'Role: ${info.primaryRole}',
                  bgColor: const Color(0xFFF8FAFC),
                  fgColor: DefensysTokens.textSecondary,
                  borderColor: const Color(0xFFE2E8F0),
                ),
            ],
          ),

          // Warning Notice (if any)
          if (info.warning != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: DefensysTokens.warningBg,
                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                border: Border.all(color: DefensysTokens.warningBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: DefensysTokens.warningText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      info.warning!,
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        color: DefensysTokens.warningText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetadataChip({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color fgColor,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
        border: Border.all(color: borderColor ?? DefensysTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              color: fgColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_open_rounded,
            size: 40,
            color: DefensysTokens.steelGrey,
          ),
          const SizedBox(height: 10),
          const Text(
            'No files currently staged',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              color: DefensysTokens.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _activeImportMode == 'student'
                ? 'Click below to add a class list (.csv / .xlsx) to stage for import.'
                : 'Click below to add a user accounts file (.csv / .xlsx) to stage for import.',
            style: const TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              color: DefensysTokens.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMoreButton() {
    final addLabel = _stagedFiles.isEmpty
        ? 'Select file(s) to import'
        : (_activeImportMode == 'student'
            ? 'Add another class section or file'
            : 'Add another user file');

    return InkWell(
      onTap: _isProcessing ? null : _handleAddMoreFiles,
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
        decoration: BoxDecoration(
          color: DefensysTokens.background,
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          border: Border.all(
            color: const Color(0xFFCBD5E1),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_circle_outline_rounded,
              size: 16,
              color: DefensysTokens.maroon,
            ),
            const SizedBox(width: 8),
            Text(
              addLabel,
              style: const TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                color: DefensysTokens.maroon,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool hasValidFiles, bool isStudent) {
    final previewLabel = _totalValidRows > 0
        ? 'Generate Preview Table ($_totalValidRows rows)'
        : 'Generate Preview Table';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: DefensysTokens.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: DefensysTokens.maroon,
              foregroundColor: Colors.white,
              disabledBackgroundColor: DefensysTokens.maroon.withValues(alpha: 0.4),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              ),
            ),
            onPressed: hasValidFiles && !_isProcessing
                ? () => Navigator.of(context).pop(
                    StagedImportResult(
                      files: _stagedFiles,
                      importMode: _activeImportMode,
                    ),
                  )
                : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(
              previewLabel,
              style: const TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
