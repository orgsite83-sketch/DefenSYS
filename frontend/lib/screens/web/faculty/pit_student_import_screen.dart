import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:excel/excel.dart' as xl;

import '../../../navigation/admin_route_paths.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/user_management_provider.dart';
import '../../../utils/csv_file_io.dart';
import '../../../utils/student_bulk_import_csv.dart';
import '../admin/widgets/defensys_admin_shell.dart';
import '../../../toasts/feedback_toast.dart';

class PitStudentImportScreen extends ConsumerStatefulWidget {
  const PitStudentImportScreen({super.key});

  @override
  ConsumerState<PitStudentImportScreen> createState() =>
      _PitStudentImportScreenState();
}

class _PitStudentImportScreenState
    extends ConsumerState<PitStudentImportScreen> {
  final _sectionController = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _parsedMetadata = {};
  bool _isOfficialClassList = false;
  int _loadedFilesCount = 0;
  dynamic _dropSubscription;

  @override
  void initState() {
    super.initState();
    _sectionController.addListener(_onSectionChanged);
    _dropSubscription = setupDropzoneListener(_handleFiles);
  }

  void _onSectionChanged() {
    if (_rows.isNotEmpty && !_isOfficialClassList) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _dropSubscription?.cancel();
    _sectionController.removeListener(_onSectionChanged);
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userManagementProvider);
    final dashboard = ref.watch(dashboardProvider('faculty')).data;
    final year = dashboard?['pit_lead_year']?.toString() ?? 'your PIT year';

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.person_add_alt_outlined,
            title: 'Import PIT Students',
            subtitle: 'Create student accounts for $year only.',
            actions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('CSV Template'),
                  onPressed: () => _downloadTemplate(year),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to Cohort'),
                  onPressed: () => context.go(FacultyRoutes.cohort),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (userState.error != null) ...[
            _notice(userState.error!, warning: true),
            const SizedBox(height: 12),
          ],
          if (userState.message != null) ...[
            _notice(userState.message!),
            const SizedBox(height: 12),
          ],
          _importPanel(userState, year),
        ],
      ),
    );
  }

  Map<String, int> _getSectionCounts() {
    final counts = <String, int>{};
    for (final r in _rows) {
      final s = (r['section']?.toString() ?? '').trim();
      final key = s.isEmpty ? 'Unassigned' : s;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  Widget _importPanel(UserManagementState state, String year) {
    final sectionCounts = _getSectionCounts();
    final hasMultipleSections = sectionCounts.length > 1 || (sectionCounts.isNotEmpty && !sectionCounts.containsKey('Unassigned'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Student Batch Context', style: DefensysUi.sectionTitle),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final yearBox = InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Batch Year Level',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  year,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              );
              final sectionField = TextField(
                controller: _sectionController,
                enabled: !state.isSaving,
                decoration: InputDecoration(
                  labelText: hasMultipleSections ? 'Default / Override Section' : 'Section',
                  hintText: 'e.g. BSIT 1A',
                  helperText: hasMultipleSections
                      ? 'Editing student section directly in the table below overrides this default.'
                      : null,
                  border: const OutlineInputBorder(),
                ),
              );
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [yearBox, const SizedBox(height: 12), sectionField],
                );
              }
              return Row(
                children: [
                  Expanded(child: yearBox),
                  const SizedBox(width: 12),
                  Expanded(child: sectionField),
                ],
              );
            },
          ),
          if (sectionCounts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Sections in Batch:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF4B5563)),
                ),
                ...sectionCounts.entries.map((e) {
                  final isUnassigned = e.key == 'Unassigned';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isUnassigned ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isUnassigned ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUnassigned ? Icons.warning_amber_rounded : Icons.class_outlined,
                          size: 14,
                          color: isUnassigned ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${e.key} (${e.value} student${e.value == 1 ? '' : 's'})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isUnassigned ? const Color(0xFFDC2626) : const Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ],
          if (_isOfficialClassList) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: DefensysUi.infoBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DefensysUi.infoBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: DefensysUi.infoText, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Official USTP Class List template(s) loaded. Sections and instructors detected automatically per file.',
                      style: TextStyle(
                        color: DefensysUi.infoText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          InkWell(
            onTap: state.isSaving ? null : _pickCsv,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              height: 138,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_upload_outlined,
                    color: Color(0xFF98A2B3),
                    size: 34,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _rows.isEmpty
                        ? 'Click to choose student CSV / Excel file(s)'
                        : '${_rows.length} student row${_rows.length == 1 ? '' : 's'} ready (${_loadedFilesCount > 1 ? "$_loadedFilesCount files" : "1 file"})',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _rows.isEmpty
                        ? 'Supports selecting multiple section class list files at once'
                        : _isOfficialClassList
                            ? 'Official USTP Class List template(s) loaded'
                            : 'Student rows only',
                    style: const TextStyle(color: Color(0xFF667085), fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
          _previewTable(state),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Year level and active semester are locked by your PIT Lead assignment.',
                  style: TextStyle(
                    color: DefensysUi.steelGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: state.isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import Students'),
                onPressed: state.isSaving || _rows.isEmpty ? null : _importRows,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _downloadTemplate(String year) async {
    await downloadTextFile(
      filename: sampleStudentCsvFilenameForYear(year),
      content: sampleStudentCsvForYear(year),
    );
  }

  Future<void> _pickCsv() async {
    final files = await pickMultipleTabularDataFiles();
    await _handleFiles(files);
  }

  Future<void> _handleFiles(List<PickedTabularFile> files) async {
    if (!mounted || files.isEmpty) return;

    try {
      final allRows = <Map<String, dynamic>>[];
      final sectionsSet = <String>{};
      var officialCount = 0;
      Map<String, dynamic> firstOfficialMetadata = {};

      for (final file in files) {
        if (file.isXlsx) {
          final official = _parseOfficialClassListXlsx(file.bytes);
          if (official.students.isNotEmpty) {
            officialCount++;
            if (firstOfficialMetadata.isEmpty) {
              firstOfficialMetadata = official.metadata;
            }
            final section = official.metadata['section']?.toString().trim() ?? '';
            final yearLevel = official.metadata['year_level']?.toString().trim() ?? '';
            if (section.isNotEmpty) sectionsSet.add(section);
            for (final s in official.students) {
              allRows.add({
                ...s,
                'section': (s['section']?.toString().trim().isNotEmpty == true)
                    ? s['section'].toString().trim()
                    : section,
                if (s['year_level'] == null || s['year_level'].toString().trim().isEmpty)
                  if (yearLevel.isNotEmpty) 'year_level': yearLevel,
                '_fileMetadata': Map<String, dynamic>.from(official.metadata),
              });
            }
          }
          continue;
        }

        final csvText = file.text ?? '';
        final official = _parseOfficialClassListCsv(csvText);
        if (official.students.isNotEmpty) {
          officialCount++;
          if (firstOfficialMetadata.isEmpty) {
            firstOfficialMetadata = official.metadata;
          }
          final section = official.metadata['section']?.toString().trim() ?? '';
          final yearLevel = official.metadata['year_level']?.toString().trim() ?? '';
          if (section.isNotEmpty) sectionsSet.add(section);
          for (final s in official.students) {
            allRows.add({
              ...s,
              'section': (s['section']?.toString().trim().isNotEmpty == true)
                  ? s['section'].toString().trim()
                  : section,
              if (s['year_level'] == null || s['year_level'].toString().trim().isEmpty)
                if (yearLevel.isNotEmpty) 'year_level': yearLevel,
              '_fileMetadata': Map<String, dynamic>.from(official.metadata),
            });
          }
          continue;
        }

        final standardRows = _parseStandardCsv(csvText);
        if (standardRows.isNotEmpty) {
          allRows.addAll(standardRows);
        }
      }

      if (allRows.isEmpty) {
        throw 'The selected file(s) do not match the official class list format or standard CSV template.';
      }

      setState(() {
        _isOfficialClassList = officialCount > 0;
        _parsedMetadata = firstOfficialMetadata;
        _rows = allRows;
        _loadedFilesCount = files.length;

        if (sectionsSet.length == 1) {
          _sectionController.text = sectionsSet.first;
        } else if (sectionsSet.length > 1) {
          _sectionController.text = '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, 'Error reading file(s): $e');
    }
  }

  Future<void> _importRows() async {
    final notifier = ref.read(userManagementProvider.notifier);
    final defaultSection = _sectionController.text.trim();

    if (_isOfficialClassList) {
      final groupRows = <String, List<Map<String, dynamic>>>{};
      final groupMetaMap = <String, Map<String, dynamic>>{};

      for (final row in _rows) {
        final rowSection = (row['section']?.toString().trim().isNotEmpty == true)
            ? row['section'].toString().trim()
            : '';
        final fileMeta = row['_fileMetadata'] as Map<String, dynamic>? ?? {};
        final fileSection = (fileMeta['section']?.toString().trim().isNotEmpty == true)
            ? fileMeta['section'].toString().trim()
            : '';
        final sec = rowSection.isNotEmpty
            ? rowSection
            : (fileSection.isNotEmpty ? fileSection : defaultSection);

        final facultyName = (fileMeta['instructor'] ?? fileMeta['faculty'] ?? fileMeta['instructor_name'] ?? '').toString().trim();
        final groupKey = '${facultyName}_$sec';

        groupRows.putIfAbsent(groupKey, () {
          final meta = Map<String, dynamic>.from(fileMeta.isNotEmpty ? fileMeta : _parsedMetadata);
          if (sec.isNotEmpty) {
            meta['section'] = sec;
          }
          groupMetaMap[groupKey] = meta;
          return [];
        }).add(row);
      }

      final combinedWarnings = <dynamic>[];
      final combinedErrors = <dynamic>[];
      var successCount = 0;

      for (final entry in groupRows.entries) {
        final groupKey = entry.key;
        final secRows = entry.value;
        final meta = groupMetaMap[groupKey] ?? Map<String, dynamic>.from(_parsedMetadata);

        final responsePayload = await notifier.pitLeadOfficialClassListImport(
          metadata: meta,
          students: secRows,
        );
        if (!mounted) return;
        if (responsePayload == null) continue;

        successCount++;
        final warnings = responsePayload['warnings'] as List? ?? const [];
        final errors = responsePayload['errors'] as List? ?? const [];
        combinedWarnings.addAll(warnings);
        combinedErrors.addAll(errors);
      }

      if (combinedWarnings.isNotEmpty || combinedErrors.isNotEmpty) {
        _showImportSummaryDialog(combinedWarnings, combinedErrors);
      } else if (successCount > 0) {
        setState(() {
          _rows = [];
          _isOfficialClassList = false;
          _parsedMetadata = {};
          _loadedFilesCount = 0;
        });
      }
    } else {
      // Group standard CSV rows by section if individual rows specify section
      final sectionGroups = <String, List<Map<String, dynamic>>>{};
      for (final row in _rows) {
        final sec = (row['section']?.toString().trim().isNotEmpty == true)
            ? row['section'].toString().trim()
            : defaultSection;
        sectionGroups.putIfAbsent(sec, () => []).add(row);
      }

      var importedAny = false;
      for (final entry in sectionGroups.entries) {
        final secName = entry.key;
        final secRows = entry.value;

        final saved = await notifier.pitLeadStudentImport(
          secRows,
          studentContext: {
            if (secName.isNotEmpty) 'section': secName,
          },
        );
        if (!mounted) return;
        if (saved) importedAny = true;
      }

      if (importedAny) {
        setState(() {
          _rows = [];
          _loadedFilesCount = 0;
        });
      }
    }
  }

  List<Map<String, dynamic>> _parseStandardCsv(String csv) {
    final rawLines = csv
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (rawLines.length < 2) return [];

    int headerLineIndex = -1;
    List<String> headers = [];

    for (var i = 0; i < rawLines.length && i < 15; i++) {
      final lineHeaders = _splitCsvLine(rawLines[i])
          .map((h) => _normalizeHeader(h))
          .toList();
      final hasId = lineHeaders.any((h) =>
          h.contains('student') ||
          h.contains('id') ||
          h == 'number' ||
          h == 'no');
      final hasName = lineHeaders.any((h) =>
          h.contains('name') || h.contains('first') || h.contains('last'));
      if (hasId && hasName) {
        headerLineIndex = i;
        headers = lineHeaders;
        break;
      }
    }

    if (headerLineIndex == -1) {
      headerLineIndex = 0;
      headers = _splitCsvLine(rawLines[0]).map((h) => _normalizeHeader(h)).toList();
    }

    int findCol(List<String> keywords) {
      return headers.indexWhere((h) => keywords.any((k) => h == k || h.contains(k)));
    }

    final idIndex = findCol(['student number', 'student no', 'student id', 'id number', 'id_number', 'id']);
    final fullNameIndex = findCol(['full name', 'full_name', 'student name', 'name']);
    final firstIndex = findCol(['first name', 'first_name', 'given name', 'firstname']);
    final lastIndex = findCol(['last name', 'last_name', 'surname', 'family name', 'lastname']);
    final emailIndex = findCol(['email', 'email address', 'mail']);
    final sectionIndex = findCol(['section', 'class section', 'class_section']);

    if (idIndex == -1 && fullNameIndex == -1 && firstIndex == -1) {
      return [];
    }

    final result = <Map<String, dynamic>>[];
    for (final line in rawLines.skip(headerLineIndex + 1)) {
      final cols = _splitCsvLine(line);
      String read(int idx) => (idx >= 0 && idx < cols.length) ? cols[idx].trim() : '';

      final id = read(idIndex);
      final fullName = read(fullNameIndex);
      final firstName = read(firstIndex);
      final lastName = read(lastIndex);
      final email = read(emailIndex);
      final section = read(sectionIndex);

      if (id.isEmpty && fullName.isEmpty && firstName.isEmpty) continue;

      String finalFirstName = firstName;
      String finalLastName = lastName;
      if (fullName.isNotEmpty && (firstName.isEmpty && lastName.isEmpty)) {
        if (fullName.contains(',')) {
          final parts = fullName.split(',');
          finalLastName = parts[0].trim();
          finalFirstName = parts.skip(1).join(',').trim();
        } else {
          final parts = fullName.split(RegExp(r'\s+'));
          if (parts.length > 1) {
            finalLastName = parts.last;
            finalFirstName = parts.take(parts.length - 1).join(' ');
          } else {
            finalFirstName = fullName;
          }
        }
      }

      final studentId = id.isNotEmpty ? id : 'STU-${result.length + 1}';
      final studentEmail = email.isNotEmpty ? email : '$studentId@ustp.edu.ph';

      result.add({
        'id_number': studentId,
        'first_name': finalFirstName,
        'last_name': finalLastName,
        'full_name': fullName.isNotEmpty ? fullName : '$finalFirstName $finalLastName'.trim(),
        'email': studentEmail,
        'role': 'student',
        if (section.isNotEmpty) 'section': section,
      });
    }

    return result;
  }

  _OfficialClassListParseResult _parseOfficialClassListCsv(String csv) {
    final rows = csv
        .split(RegExp(r'\r?\n'))
        .map(_splitCsvLine)
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    return _parseOfficialClassListRows(rows);
  }

  _OfficialClassListParseResult _parseOfficialClassListXlsx(List<int> bytes) {
    final workbook = xl.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      return const _OfficialClassListParseResult(metadata: {}, students: []);
    }
    final sheet = workbook.tables.values.first;
    final rows = sheet.rows
        .map((row) => row.map((cell) => _excelCellText(cell?.value)).toList())
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    return _parseOfficialClassListRows(rows);
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
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        values.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString().trim());
    return values;
  }

  String _nextCell(List<String> row, int index) {
    for (var i = index + 1; i < row.length; i++) {
      final value = row[i].trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _normalizeHeader(String value) => value
      .trim()
      .replaceFirst('\ufeff', '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  String _normalizeYearLevel(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('1')) return '1st Year';
    if (lower.contains('2')) return '2nd Year';
    if (lower.contains('3')) return '3rd Year';
    if (lower.contains('4')) return '4th Year';
    return value.trim();
  }

  _OfficialClassListParseResult _parseOfficialClassListRows(
    List<List<String>> rows,
  ) {
    if (rows.isEmpty) {
      return const _OfficialClassListParseResult(
        metadata: {},
        students: [],
      );
    }

    final blocks = <List<List<String>>>[];
    var currentBlock = <List<String>>[];

    for (final row in rows) {
      final lineText = row.join(' ').toLowerCase();
      final isNewHeader = lineText.contains('official list of enrolled students') ||
          (lineText.contains('subject code') && currentBlock.isNotEmpty);

      if (isNewHeader && currentBlock.isNotEmpty) {
        blocks.add(currentBlock);
        currentBlock = <List<String>>[];
      }
      currentBlock.add(row);
    }
    if (currentBlock.isNotEmpty) {
      blocks.add(currentBlock);
    }

    final allStudents = <Map<String, dynamic>>[];
    Map<String, dynamic> firstMetadata = {};

    for (final blockRows in blocks) {
      final parsed = _parseSingleOfficialClassListBlock(blockRows);
      if (firstMetadata.isEmpty && parsed.metadata.isNotEmpty) {
        firstMetadata = parsed.metadata;
      }
      allStudents.addAll(parsed.students);
    }

    return _OfficialClassListParseResult(
      metadata: firstMetadata,
      students: allStudents,
    );
  }

  _OfficialClassListParseResult _parseSingleOfficialClassListBlock(
    List<List<String>> rows,
  ) {
    final metadata = <String, dynamic>{};
    var headerIndex = -1;

    for (var i = 0; i < rows.length; i++) {
      final normalized = rows[i].map(_normalizeHeader).toList();

      void readMeta(String key, List<String> labels) {
        if (metadata[key]?.toString().trim().isNotEmpty == true) return;
        for (final label in labels) {
          final index = normalized.indexWhere((cell) => cell == label);
          if (index == -1) continue;
          final value = _nextCell(rows[i], index);
          if (value.isNotEmpty) metadata[key] = value;
          return;
        }
      }

      readMeta('faculty', ['faculty', 'instructor']);
      readMeta('section', ['class section', 'section']);
      readMeta('year_level', ['year level', 'level']);

      final hasStudentNumber = normalized.any(
        (cell) =>
            cell.contains('student') &&
            (cell.contains('number') ||
                cell.contains('no') ||
                cell == 'student n'),
      );
      final hasFullName = normalized.contains('full name') || normalized.contains('name');
      if (hasStudentNumber && hasFullName) {
        headerIndex = i;
        break;
      }
    }

    if (metadata['year_level'] != null) {
      metadata['year_level'] = _normalizeYearLevel(
        metadata['year_level'].toString(),
      );
    }
    if (headerIndex == -1) {
      return _OfficialClassListParseResult(
        metadata: metadata,
        students: const [],
      );
    }

    final headers = rows[headerIndex].map(_normalizeHeader).toList();
    int findHeader(bool Function(String value) matches) =>
        headers.indexWhere(matches);
    final idIndex = findHeader(
      (value) =>
          value.contains('student') &&
          (value.contains('number') ||
              value.contains('no') ||
              value == 'student n'),
    );
    final nameIndex = findHeader((value) => value == 'full name' || value == 'name');
    final programIndex = findHeader((value) => value == 'program');
    final levelIndex = findHeader((value) => value == 'level');
    final emailIndex = findHeader((value) => value == 'email');
    final sectionColumnIndex = findHeader((value) => value == 'section' || value == 'class section');
    final blockSection = metadata['section']?.toString() ?? '';
    final blockYearLevel = metadata['year_level']?.toString() ?? '';
    final students = <Map<String, dynamic>>[];

    for (final row in rows.skip(headerIndex + 1)) {
      String read(int index) =>
          index >= 0 && index < row.length ? row[index].trim() : '';
      final id = read(idIndex);
      final name = read(nameIndex);
      if (id.isEmpty || name.isEmpty) continue;
      final rowSection = sectionColumnIndex != -1 ? read(sectionColumnIndex) : '';
      final sec = rowSection.isNotEmpty ? rowSection : blockSection;
      final rowLevel = levelIndex != -1 ? _normalizeYearLevel(read(levelIndex)) : blockYearLevel;

      students.add({
        'id_number': id,
        'full_name': name,
        if (programIndex != -1) 'program': read(programIndex),
        if (rowLevel.isNotEmpty) 'year_level': rowLevel,
        if (emailIndex != -1) 'email': read(emailIndex),
        if (sec.isNotEmpty) 'section': sec,
        '_fileMetadata': metadata,
      });
    }

    return _OfficialClassListParseResult(
      metadata: metadata,
      students: students,
    );
  }

  List<String> _formatBulkImportErrorLines(dynamic messages) {
    if (messages is List) {
      return messages.map((item) => item.toString()).toList();
    }
    if (messages is Map) {
      final lines = <String>[];
      for (final entry in messages.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          for (final item in value) {
            lines.add('$key: $item');
          }
        } else {
          lines.add('$key: $value');
        }
      }
      return lines;
    }
    return [messages?.toString() ?? 'Unknown error'];
  }

  Future<void> _showImportSummaryDialog(List<dynamic> warnings, List<dynamic> errors) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Class List Import Details'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errors.isNotEmpty) ...[
                  const Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Errors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...errors.map((error) {
                    final row = error['row'];
                    final id = error['id_number'] ?? '';
                    final issueLines = _formatBulkImportErrorLines(error['errors']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Row $row ${id.isNotEmpty ? "· Student ID: $id" : ""}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ...issueLines.map((line) => Text('• $line', style: const TextStyle(fontSize: 12.5))),
                        ],
                      ),
                    );
                  }),
                  if (warnings.isNotEmpty) const Divider(),
                ],
                if (warnings.isNotEmpty) ...[
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Text('Warnings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amber)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...warnings.map((warning) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $warning', style: const TextStyle(fontSize: 13)),
                  )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _updateNamesFromFullName(Map<String, dynamic> row, String val) {
    row['full_name'] = val;
    final cleanVal = val.trim();
    if (cleanVal.contains(',')) {
      final parts = cleanVal.split(',');
      row['last_name'] = parts[0].trim();
      row['first_name'] = parts.skip(1).join(',').trim();
    } else {
      final parts = cleanVal.split(RegExp(r'\s+'));
      if (parts.length > 1) {
        row['last_name'] = parts.last;
        row['first_name'] = parts.take(parts.length - 1).join(' ');
      } else {
        row['first_name'] = cleanVal;
        row['last_name'] = '';
      }
    }
  }

  Widget _previewTable(UserManagementState state) {
    if (_rows.isEmpty) return const SizedBox.shrink();

    final columns = const [
      'Student ID',
      'Full Name',
      'Email',
      'Year Level',
      'Section',
      'Status',
    ];

    // Find duplicates inside the list to display in the Status column
    final idCounts = <String, int>{};
    for (final row in _rows) {
      final id = row['id_number']?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        idCounts[id] = (idCounts[id] ?? 0) + 1;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            const Text(
              'Roster Preview',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: DefensysUi.textDark,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_rows.length} rows',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4B5563),
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _rows = [];
                  _isOfficialClassList = false;
                  _parsedMetadata = {};
                });
              },
              icon: const Icon(Icons.clear_all_rounded, size: 16, color: Color(0xFFDC2626)),
              label: const Text('Clear File', style: TextStyle(color: Color(0xFFDC2626))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              constraints: const BoxConstraints(minWidth: 1104), // 6 columns * 184 = 1104
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Container(
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0F1F4),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                    ),
                    child: Row(
                      children: columns
                          .map((col) => _reviewCell(col, header: true))
                          .toList(),
                    ),
                  ),
                  // Body Rows
                  ...List.generate(_rows.length, (index) {
                    final row = _rows[index];
                    final String idNumber = row['id_number']?.toString() ?? '';
                    final String email = row['email']?.toString() ?? '';
                    final String yearLevel = row['year_level']?.toString() ?? _parsedMetadata['year_level']?.toString() ?? '';
                    final String sectionName = row['section']?.toString() ?? _sectionController.text.trim();

                    // Full Name determination
                    String name = '';
                    if (_isOfficialClassList) {
                      name = row['full_name']?.toString() ?? '';
                    } else {
                      if (row['full_name'] != null) {
                        name = row['full_name'].toString();
                      } else {
                        final first = row['first_name']?.toString() ?? '';
                        final last = row['last_name']?.toString() ?? '';
                        name = '$first $last'.trim();
                      }
                    }

                    // Status determination
                    final isDuplicate = idCounts[idNumber.trim()] != null && idCounts[idNumber.trim()]! > 1;
                    final status = isDuplicate ? 'Duplicate ID' : 'Ready';

                    return Container(
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                      ),
                      child: Row(
                        children: [
                          _reviewCellWidget(
                            EditableCell(
                              value: idNumber,
                              onChanged: (val) => row['id_number'] = val.trim(),
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: DefensysUi.textDark),
                            ),
                          ),
                          _reviewCellWidget(
                            EditableCell(
                              value: name,
                              onChanged: (val) => _updateNamesFromFullName(row, val),
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DefensysUi.textDark),
                            ),
                          ),
                          _reviewCellWidget(
                            EditableCell(
                              value: email,
                              onChanged: (val) => row['email'] = val.trim(),
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF536079)),
                            ),
                          ),
                          _reviewCellWidget(
                            EditableCell(
                              value: yearLevel,
                              enabled: false, // Locked to assigned year level
                              onChanged: (_) {},
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF536079)),
                            ),
                          ),
                          _reviewCellWidget(
                            EditableCell(
                              value: sectionName,
                              enabled: !state.isSaving,
                              onChanged: (val) {
                                setState(() {
                                  row['section'] = val.trim();
                                });
                              },
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F766E)),
                            ),
                          ),
                          _reviewCellWidget(
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: isDuplicate ? Colors.red : const Color(0xFF10B981),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reviewCell(String value, {bool header = false}) {
    return SizedBox(
      width: 184,
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
            color: header ? DefensysUi.textDark : const Color(0xFF536079),
            fontSize: 12.5,
            fontWeight: header ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _reviewCellWidget(Widget child) {
    return SizedBox(
      width: 184,
      child: Container(
        height: double.infinity,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: child,
      ),
    );
  }

  Widget _notice(String message, {bool warning = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: warning ? DefensysUi.warningBg : DefensysUi.successBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warning ? DefensysUi.warningBorder : DefensysUi.successBorder,
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: warning ? DefensysUi.warningText : DefensysUi.successText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OfficialClassListParseResult {
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> students;

  const _OfficialClassListParseResult({
    required this.metadata,
    required this.students,
  });
}

class EditableCell extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final TextStyle? style;

  const EditableCell({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.style,
  });

  @override
  State<EditableCell> createState() => _EditableCellState();
}

class _EditableCellState extends State<EditableCell> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant EditableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      style: widget.style ?? const TextStyle(fontSize: 13),
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        border: widget.enabled
            ? const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE5E7EB)))
            : InputBorder.none,
        enabledBorder: widget.enabled
            ? const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFCBD5E1)))
            : InputBorder.none,
        focusedBorder: widget.enabled
            ? const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF0F766E), width: 1.5))
            : InputBorder.none,
        disabledBorder: InputBorder.none,
      ),
    );
  }
}

