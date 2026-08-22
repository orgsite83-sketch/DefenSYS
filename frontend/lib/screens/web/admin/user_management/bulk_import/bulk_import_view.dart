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
import 'package:defensys/utils/import/student_bulk_import_csv.dart';
import 'package:defensys/utils/import/user_bulk_import_draft.dart';

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
        });
      }
    }
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      if (_parsedFacultyRows.isEmpty) {
        await clearUserBulkImportDraft();
        return;
      }

      final csvBuffer = StringBuffer();
      csvBuffer.writeln('id_number,first_name,last_name,email,role');
      for (final r in _parsedFacultyRows) {
        csvBuffer.writeln(
          '${r['id_number'] ?? ''},${r['first_name'] ?? ''},${r['last_name'] ?? ''},${r['email'] ?? ''},${r['role'] ?? 'faculty'}',
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

    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Discard faculty import draft?'),
        content: const Text(
          'You have staged faculty files or unimported rows. Leaving now will discard your current draft.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Stay'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
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

  Future<void> _openStagingModal(List<PickedTabularFile> files) async {
    final result = await showDialog<List<PickedTabularFile>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => FileImportStagingModal(
        initialFiles: files,
        importMode: 'general',
      ),
    );

    if (result != null && result.isNotEmpty) {
      _processPickedFiles(result);
    }
  }

  Future<void> _pickFiles() async {
    try {
      final files = await pickMultipleTabularDataFiles();
      if (!mounted || files.isEmpty) return;
      await _openStagingModal(files);
    } catch (e) {
      if (mounted) {
        ToastService.error(context, 'Failed to select files: $e');
      }
    }
  }

  void _processPickedFiles(List<PickedTabularFile> files) {
    final allRows = <Map<String, dynamic>>[];
    final validFiles = <PickedTabularFile>[];

    for (final file in files) {
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
      ToastService.error(
        context,
        'No valid faculty records recognized in staged files.',
      );
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
      ToastService.warning(
        context,
        '${validFiles.length} file(s) loaded • ${allRows.length} faculty records. ($skipped incompatible file(s) skipped)',
      );
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

  List<Map<String, dynamic>> _parseXlsxBytes(List<int> bytes, String fileName) {
    final rows = <Map<String, dynamic>>[];
    try {
      final excel = xl.Excel.decodeBytes(bytes);
      for (final table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null || sheet.rows.isEmpty) continue;

        int headerIdx = -1;
        int idCol = -1;
        int firstCol = -1;
        int lastCol = -1;
        int emailCol = -1;
        int roleCol = -1;

        for (var i = 0; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          final texts = row.map((cell) => _excelCellText(cell?.value)).map((s) => s.toLowerCase()).toList();

          final hasId = texts.any((t) => t.contains('id') || t.contains('username') || t.contains('number'));
          final hasName = texts.any((t) => t.contains('name'));
          final hasEmail = texts.any((t) => t.contains('email'));

          if ((hasId || hasEmail) && (hasName || texts.contains('first_name') || texts.contains('first name'))) {
            headerIdx = i;
            for (var c = 0; c < texts.length; c++) {
              final t = texts[c];
              if (t.contains('id') || t.contains('username') || t.contains('number')) idCol = c;
              if (t.contains('first') || t == 'fname') firstCol = c;
              if (t.contains('last') || t == 'lname' || t.contains('surname')) lastCol = c;
              if (t.contains('email') || t.contains('mail')) emailCol = c;
              if (t.contains('role') || t.contains('position') || t.contains('type')) roleCol = c;
            }
            break;
          }
        }

        if (headerIdx == -1) continue;

        for (var i = headerIdx + 1; i < sheet.rows.length; i++) {
          final r = sheet.rows[i];
          final idVal = idCol >= 0 && idCol < r.length ? _excelCellText(r[idCol]?.value) : '';
          final firstVal = firstCol >= 0 && firstCol < r.length ? _excelCellText(r[firstCol]?.value) : '';
          final lastVal = lastCol >= 0 && lastCol < r.length ? _excelCellText(r[lastCol]?.value) : '';
          final emailVal = emailCol >= 0 && emailCol < r.length ? _excelCellText(r[emailCol]?.value) : '';
          final roleVal = roleCol >= 0 && roleCol < r.length ? _excelCellText(r[roleCol]?.value) : '';

          if (idVal.isEmpty && emailVal.isEmpty) continue;

          rows.add({
            'id_number': idVal.isNotEmpty ? idVal : emailVal.split('@').first,
            'username': idVal.isNotEmpty ? idVal : emailVal.split('@').first,
            'first_name': firstVal,
            'last_name': lastVal,
            'email': emailVal,
            'role': roleVal.toLowerCase().contains('admin') ? 'admin' : 'faculty',
            'source_file': fileName,
          });
        }
      }
    } catch (_) {}
    return rows;
  }

  String _excelCellText(xl.CellValue? value) {
    if (value == null) return '';
    if (value is xl.TextCellValue) return value.value.toString().trim();
    if (value is xl.IntCellValue) return value.value.toString();
    if (value is xl.DoubleCellValue) {
      final n = value.value;
      return n == n.roundToDouble() ? n.round().toString() : n.toString();
    }
    return value.toString().trim();
  }

  List<Map<String, dynamic>> _parseRawCsvContent(String content, {String fileName = 'Staged CSV'}) {
    final rows = <Map<String, dynamic>>[];
    final lines = const LineSplitter().convert(content).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return rows;

    int headerIdx = -1;
    Map<String, int> headerMap = {};

    for (var i = 0; i < lines.length; i++) {
      final cells = _splitCsvLine(lines[i]).map((c) => c.toLowerCase().replaceAll('"', '').trim()).toList();
      final hasId = cells.any((c) => c.contains('id') || c.contains('username') || c.contains('number'));
      final hasEmail = cells.any((c) => c.contains('email'));
      final hasName = cells.any((c) => c.contains('name'));

      if ((hasId || hasEmail) && (hasName || cells.contains('first_name'))) {
        headerIdx = i;
        for (var c = 0; c < cells.length; c++) {
          final col = cells[c];
          if (col.contains('id') || col.contains('username') || col.contains('number')) headerMap['id'] = c;
          if (col.contains('first') || col == 'fname') headerMap['first'] = c;
          if (col.contains('last') || col == 'lname' || col.contains('surname')) headerMap['last'] = c;
          if (col.contains('email') || col.contains('mail')) headerMap['email'] = c;
          if (col.contains('role') || col.contains('position') || col.contains('type')) headerMap['role'] = c;
        }
        break;
      }
    }

    if (headerIdx == -1) return rows;

    for (var i = headerIdx + 1; i < lines.length; i++) {
      final cells = _splitCsvLine(lines[i]);
      final idVal = headerMap.containsKey('id') && headerMap['id']! < cells.length ? cells[headerMap['id']!].trim() : '';
      final firstVal = headerMap.containsKey('first') && headerMap['first']! < cells.length ? cells[headerMap['first']!].trim() : '';
      final lastVal = headerMap.containsKey('last') && headerMap['last']! < cells.length ? cells[headerMap['last']!] : '';
      final emailVal = headerMap.containsKey('email') && headerMap['email']! < cells.length ? cells[headerMap['email']!] : '';
      final roleVal = headerMap.containsKey('role') && headerMap['role']! < cells.length ? cells[headerMap['role']!] : '';

      if (idVal.isEmpty && emailVal.isEmpty) continue;

      rows.add({
        'id_number': idVal.isNotEmpty ? idVal : emailVal.split('@').first,
        'username': idVal.isNotEmpty ? idVal : emailVal.split('@').first,
        'first_name': firstVal,
        'last_name': lastVal,
        'email': emailVal,
        'role': roleVal.toLowerCase().contains('admin') ? 'admin' : 'faculty',
        'source_file': fileName,
      });
    }

    return rows;
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
      return {
        'username': r['id_number'] ?? r['username'],
        'first_name': r['first_name'] ?? '',
        'last_name': r['last_name'] ?? '',
        'email': r['email'] ?? '',
        'role': r['role'] ?? 'faculty',
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
            actions: OutlinedButton.icon(
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
          ),
          const SizedBox(height: 24),
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
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.table_chart_outlined, size: 14, color: _maroon),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Sample Faculty Spreadsheet',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                        ),
                        _buildMiniBadge('Faculty', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
                        const SizedBox(width: 4),
                        _buildMiniBadge('Panelist', const Color(0xFFFAF5FF), const Color(0xFF7E22CE)),
                        const SizedBox(width: 4),
                        _buildMiniBadge('Adviser', const Color(0xFFDCFCE7), const Color(0xFF15803D)),
                      ],
                    ),
                  ),

                  // Table Header
                  Container(
                    color: const Color(0xFFF1F5F9),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: const Row(
                      children: [
                        Expanded(flex: 3, child: Text('id_number', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)))),
                        Expanded(flex: 3, child: Text('first_name', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)))),
                        Expanded(flex: 3, child: Text('last_name', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)))),
                        Expanded(flex: 4, child: Text('email', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)))),
                        Expanded(flex: 2, child: Text('role', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)))),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),

                  // Sample Rows
                  _buildSampleRow('FAC-0001', 'Ada', 'Lovelace', 'ada@ustp.edu.ph', 'faculty', false),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  _buildSampleRow('FAC-0002', 'Alan', 'Turing', 'a.turing@ustp.edu.ph', 'faculty', true),
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
                    'Best for onboarding faculty, advisers, and panelist accounts. Roles and institutional emails are auto-detected with zero manual setup.',
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

  Widget _buildSampleRow(String id, String first, String last, String email, String role, bool isAlt) {
    return Container(
      color: isAlt ? const Color(0xFFF9FAFB) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(id, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _ink))),
          Expanded(flex: 3, child: Text(first, style: const TextStyle(fontSize: 11, color: _ink))),
          Expanded(flex: 3, child: Text(last, style: const TextStyle(fontSize: 11, color: _ink))),
          Expanded(flex: 4, child: Text(email, style: const TextStyle(fontSize: 11, color: _muted))),
          Expanded(flex: 2, child: Text(role, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _maroon))),
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
      return id.contains(query) || first.contains(query) || last.contains(query) || email.contains(query) || role.contains(query);
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
                final role = row['role']?.toString().toLowerCase() ?? 'faculty';
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

                      // Role
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: role == 'admin' ? const Color(0xFFFEF3C7) : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                role.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: role == 'admin' ? const Color(0xFF92400E) : const Color(0xFF1D4ED8),
                                ),
                              ),
                            ),
                          ],
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
