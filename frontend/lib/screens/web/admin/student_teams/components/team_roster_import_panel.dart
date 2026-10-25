import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic/team_formation_service.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/import/class_list_template.dart';
import '../../user_management/bulk_import/official_class_list_parser.dart';

/// Links an official class section list to existing enrollments; it never creates student accounts.
/// Formatted specifically for class-section verification and intake without full-cohort / by-year overhead.
class TeamRosterImportPanel extends ConsumerStatefulWidget {
  const TeamRosterImportPanel({
    super.key,
    required this.level,
    this.section,
    this.semester,
    required this.sections,
    required this.students,
    required this.onImported,
    this.onBusyChanged,
    this.onDirtyChanged,
    this.canResolveConflicts = false,
    this.showGroupingHeader = true,
  });

  final String level;
  final String? section;
  final Map<String, dynamic>? semester;
  final List<Map<String, dynamic>> sections;
  final List<Map<String, dynamic>> students;
  final Future<void> Function() onImported;
  final ValueChanged<bool>? onBusyChanged;
  final ValueChanged<bool>? onDirtyChanged;
  final bool canResolveConflicts;
  final bool showGroupingHeader;

  @override
  ConsumerState<TeamRosterImportPanel> createState() =>
      _TeamRosterImportPanelState();
}

class _TeamRosterImportPanelState extends ConsumerState<TeamRosterImportPanel> {
  static const Color _ink = DefensysUi.textDark;
  static const Color _line = Color(0xFFE2E8F0);
  static const Color _maroon = DefensysUi.primaryMaroon;
  static const Color _muted = DefensysUi.steelGrey;

  late final TextEditingController section;
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? preview;
  String? error, message, stagedFileName;
  bool busy = false, resolveConflicts = false;
  bool isDraggingFile = false;
  bool showCurrentRoster = false;
  StreamSubscription? _dropSubscription;

  bool get isPit => widget.level.contains('PIT');

  String get effectiveSection {
    if (widget.section?.trim().isNotEmpty == true) {
      return widget.section!.trim();
    }
    if (section.text.trim().isNotEmpty) {
      return section.text.trim();
    }
    return '';
  }

  String get yearLevelLabel {
    if (isPit) {
      return widget.level.replaceFirst(' PIT', '').trim();
    }
    return widget.level.split(' ').take(2).join(' ');
  }

  @override
  void initState() {
    super.initState();
    section = TextEditingController(text: widget.section ?? '');
    _dropSubscription = setupDropzoneListener(
      _handleFilesDropped,
      onDragStateChanged: (dragging) {
        if (mounted && isDraggingFile != dragging) {
          setState(() => isDraggingFile = dragging);
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant TeamRosterImportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section && widget.section?.isNotEmpty == true) {
      section.text = widget.section!;
    }
  }

  @override
  void dispose() {
    _dropSubscription?.cancel();
    section.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() operation) async {
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      await operation();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> _handleFilesDropped(List<PickedTabularFile> files) async {
    if (!mounted || files.isEmpty) return;
    await _processPickedFiles(files);
  }

  Future<void> pick() async {
    final files = await pickMultipleTabularDataFiles();
    if (files.isEmpty || !mounted) return;
    await _processPickedFiles(files);
  }

  Future<void> _processPickedFiles(List<PickedTabularFile> files) async {
    await run(() async {
      final parsed = <Map<String, dynamic>>[];
      for (final file in files) {
        final result = file.isXlsx
            ? parseOfficialClassListXlsx(file.bytes)
            : parseOfficialClassListCsv(file.text ?? utf8.decode(file.bytes));
        if (result.students.isEmpty) {
          throw FormatException(
            'No students found in ${file.name}. Please ensure you are using the official By Section class-list format.',
          );
        }
        parsed.addAll(result.students);
        if (section.text.isEmpty && result.metadata['section'] != null) {
          section.text = result.metadata['section'].toString();
        }
      }
      if (mounted) {
        setState(() {
          rows = parsed;
          preview = null;
          stagedFileName = files.length == 1
              ? files.first.name
              : '${files.length} class section files';
        });
      }
      widget.onDirtyChanged?.call(true);
    });
    if (rows.isNotEmpty && error == null) {
      await review();
    }
  }

  void clearStaged() {
    setState(() {
      rows = [];
      preview = null;
      stagedFileName = null;
      error = null;
    });
    widget.onDirtyChanged?.call(false);
  }

  Future<void> review() => run(() async {
        final sec = effectiveSection;
        final result = await ref
            .read(teamFormationServiceProvider)
            .importPreview({
          'level': widget.level,
          'section': sec,
          'students': rows,
          'resolve_conflicts': resolveConflicts,
        }, roster: true);
        if (mounted) setState(() => preview = result);
      });

  Future<void> save() => run(() async {
        final result = await ref
            .read(teamFormationServiceProvider)
            .importCommit(preview!['preview_token'] as String, roster: true);
        if (!mounted) return;
        final updatedCount = result['updated_count'] ?? 0;
        final unchangedCount = result['unchanged_count'] ?? 0;
        setState(() {
          rows = [];
          preview = null;
          stagedFileName = null;
          message =
              '$updatedCount section assignments updated; $unchangedCount already matched.';
        });
        widget.onDirtyChanged?.call(false);
        showSuccessToast(
          context,
          '$updatedCount student section assignments confirmed successfully.',
        );
        await widget.onImported();
      });

  ClassListTemplate get _sample => ClassListTemplate(
    level: widget.level, section: effectiveSection,
    term: templateTermLabel(widget.semester ?? ref.read(academicPeriodProvider).activeSemester),
    instructor: templateInstructorName(ref.read(authProvider).user),
  );

  String _getSampleSectionCsv() => _sample.csv;

  Future<void> _downloadSectionTemplate() async {
    final filename = _sample.filename;
    final content = _getSampleSectionCsv();
    await downloadTextFile(
      filename: filename,
      content: content,
    );
    if (mounted) {
      showSuccessToast(context, 'Sample By Section class list template downloaded.');
    }
  }

  void _showSectionBlueprintModal(BuildContext context) {
    final sample = _sample;
    final term = sample.term;
    final sec = sample.classSection;
    final yr = sample.yearLevel;
    final instructorName = sample.instructor;
    final subCode = sample.subjectCode;
    final subTitle = sample.subjectTitle;

    showDialog(
      context: context,
      builder: (ctx) {
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
                            const Text(
                              'Official University Class List Blueprint (Section Intake)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Target Term: $term • Interactive guide for supported intake layouts',
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

                // Section Guidance Bar (Class-specific intake directly into section)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  color: const Color(0xFFF8FAFC),
                  child: Row(
                    children: [
                      const Icon(Icons.class_outlined, size: 16, color: _maroon),
                      const SizedBox(width: 8),
                      const Text(
                        'By Section',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Class-Specific Intake',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                      const Spacer(),
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
                const Divider(height: 1, color: _line),

                // Blueprint Spreadsheet Window
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Guidance Note
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Class-specific intake. Students are enrolled directly into the section specified in Row 10.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Authentic Spreadsheet Preview Table
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
                              // Sheet Window Titlebar
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                                  border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1))),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                          Icon(Icons.insert_drive_file_outlined, size: 12, color: Color(0xFF475569)),
                                          SizedBox(width: 5),
                                          Text(
                                            sample.filename,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1E293B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _buildMiniBadge('Class-Specific Intake', const Color(0xFFF1F5F9), const Color(0xFF475569)),
                                  ],
                                ),
                              ),

                              // Row 1: Header
                              _buildOfficialHeaderRow(
                                rowNumber: '1',
                                keyName: 'OFFICIAL LIST OF ENROLLED STUDENTS',
                                valueText: '',
                                isRequired: false,
                              ),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),

                              // Row 2: Term
                              _buildOfficialHeaderRow(
                                rowNumber: '2',
                                keyName: 'Academic Term',
                                valueText: term,
                                badgeText: 'Auto-Detected Term',
                                badgeBg: const Color(0xFFF1F5F9),
                                badgeFg: const Color(0xFF334155),
                                isRequired: true,
                              ),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),

                              // Row 4: Subject Code & Title
                              _buildOfficialHeaderRow(
                                rowNumber: '4',
                                keyName: 'Subject Code',
                                valueText: subCode,
                                secondaryKey: 'Subject Title',
                                secondaryValue: subTitle,
                                isRequired: false,
                              ),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),

                              // Row 6: Units & Mode
                              _buildOfficialHeaderRow(
                                rowNumber: '6',
                                keyName: 'Academic Units',
                                valueText: '3 (Lab Units: 1)',
                                secondaryKey: 'Mode',
                                secondaryValue: 'Lecture and Laboratory',
                                isRequired: false,
                              ),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),

                              // Row 9: Instructor
                              _buildOfficialHeaderRow(
                                rowNumber: '9',
                                keyName: 'Instructor',
                                valueText: instructorName,
                                badgeText: 'Auto-Detected Instructor',
                                badgeBg: const Color(0xFFF1F5F9),
                                badgeFg: const Color(0xFF334155),
                                isRequired: false,
                              ),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),

                              // Row 10: Class Section
                              _buildOfficialHeaderRow(
                                rowNumber: '10',
                                keyName: 'Class Section',
                                valueText: sec,
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
                                valueText: yr,
                                badgeText: 'Auto-Detected Year Level',
                                badgeBg: const Color(0xFFF1F5F9),
                                badgeFg: const Color(0xFF334155),
                                isRequired: true,
                              ),
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),

                              // Row 12: Schedule
                              _buildOfficialHeaderRow(
                                rowNumber: '12',
                                keyName: 'Schedule(s)',
                                valueText: 'M 1:00 PM - 3:00 PM',
                                isRequired: false,
                              ),
                              const Divider(height: 1, color: Color(0xFFCBD5E1)),

                              // Row 14: Column Headers
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

                              // Rows 15 & 16: Sample Records
                              _buildOfficialStudentRow(
                                rowNumber: '15',
                                index: '1',
                                id: '2024-00001',
                                name: 'DELA CRUZ, Juan',
                                prog: 'BSIT',
                                gen: 'M',
                                level: sample.studentLevel,
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
                                level: sample.studentLevel,
                                email: '202400002@university.edu.ph',
                                contact: '09170000002',
                                isAlt: true,
                              ),
                            ],
                          ),
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
                              await _downloadSectionTemplate();
                            },
                            icon: const Icon(Icons.download_rounded, size: 15),
                            label: const Text('Download By Section Template (.csv)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _ink,
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _getSampleSectionCsv()));
                              showSuccessToast(context, 'Sample By Section CSV copied to clipboard.');
                            },
                            icon: const Icon(Icons.copy_rounded, size: 14),
                            label: const Text('Copy Sample CSV'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _ink,
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
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

  Widget _buildMiniBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildTemplateSpecTag(String label, {bool isRequired = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isRequired ? const Color(0xFFFEE2E2).withValues(alpha: 0.4) : Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isRequired ? const Color(0xFFFECACA) : const Color(0xFFCBD5E1),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRequired) ...[
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 5),
              decoration: const BoxDecoration(
                color: _maroon,
                shape: BoxShape.circle,
              ),
            ),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isRequired ? FontWeight.w700 : FontWeight.w600,
                color: isRequired ? _maroon : const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeSem = widget.semester ?? ref.watch(academicPeriodProvider).activeSemester;
    final term = activeSem?['display_name']?.toString() ??
        activeSem?['label']?.toString() ??
        'Active Semester';
    final reviewRows = (preview?['rows'] as List? ?? []).cast<Map>();
    final displaySection = effectiveSection.isNotEmpty ? effectiveSection : 'Assigned Section';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Prepare the roster header
        Text(
          '1. Prepare the roster',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          '${widget.students.length} students in the available roster. Use the current roster or import an updated class list.',
          style: const TextStyle(fontSize: 13, color: DefensysUi.steelGrey),
        ),
        const SizedBox(height: 14),

        // Current Roster Banner if students are already enrolled
        if (widget.students.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final summary = Row(children: [
                    const Icon(Icons.people_outline_rounded, color: Color(0xFF15803D), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.students.length} students enrolled in $displaySection',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF166534),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Review this class list before team grouping.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF15803D)),
                          ),
                        ],
                      ),
                    ),
                  ]);
                  final viewRoster = TextButton.icon(
                    onPressed: () => setState(() => showCurrentRoster = !showCurrentRoster),
                    icon: Icon(
                      showCurrentRoster ? Icons.expand_less_rounded : Icons.people_outline_rounded,
                      size: 16,
                      color: const Color(0xFF166534),
                    ),
                    label: Text(
                      showCurrentRoster ? 'Hide Roster' : 'View Roster (${widget.students.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF166534),
                      ),
                    ),
                  );
                  return constraints.maxWidth < 360
                      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          summary,
                          Align(alignment: Alignment.centerLeft, child: viewRoster),
                        ])
                      : Row(children: [Expanded(child: summary), viewRoster]);
                }),
                if (showCurrentRoster) ...[
                  const Divider(height: 16, color: Color(0xFFBBF7D0)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.students.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFDCFCE7)),
                      itemBuilder: (context, i) {
                        final s = widget.students[i];
                        final inTeam = s['assigned'] == true;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Row(
                            children: [
                              Text(
                                '${i + 1}.',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF166534),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${s['name']} (${s['username']})',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _ink),
                                ),
                              ),
                              if (inTeam)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Already in Team',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Drag active feedback
        if (isDraggingFile)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _maroon, width: 1.5),
            ),
            child: const Row(
              children: [
                Icon(Icons.file_upload_outlined, color: _maroon, size: 20),
                SizedBox(width: 10),
                Text(
                  'Drop official class list here to stage and verify students for this section',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _maroon),
                ),
              ],
            ),
          ),

        // Dual-Card Workspace: Specification Card (Left) & Upload Files Card (Right)
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;

            final specCard = Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _line),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: _maroon.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.description_outlined, color: _maroon, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Official Class List Specification',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Target Term: $term • Section-Specific Intake',
                              style: const TextStyle(fontSize: 11, color: _muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Container 1: Registrar Preamble Metadata
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
                        Row(
                          children: [
                            const Icon(Icons.assignment_outlined, size: 14, color: Color(0xFF475569)),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'REGISTRAR PREAMBLE METADATA',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: const Text(
                                'Auto-Detected',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: [
                            _buildTemplateSpecTag('Academic Term'),
                            _buildTemplateSpecTag(
                              effectiveSection.isNotEmpty
                                  ? 'Class Section ($effectiveSection)'
                                  : 'Class Section (Required)',
                              isRequired: effectiveSection.isEmpty,
                            ),
                            _buildTemplateSpecTag('Year Level'),
                            _buildTemplateSpecTag('Instructor (${isPit ? 'PIT' : 'Capstone'} - Optional)'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 10),

                        // Container 2: Enrolled Student Table Columns
                        Row(
                          children: [
                            const Icon(Icons.table_rows_outlined, size: 14, color: _maroon),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'ENROLLED STUDENT ROSTER (ROW 14+)',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2).withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: const Text(
                                'Core Required',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: _maroon,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: [
                            _buildTemplateSpecTag('Student Number', isRequired: true),
                            _buildTemplateSpecTag('Full Name', isRequired: true),
                            _buildTemplateSpecTag('Institutional Email', isRequired: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Info Note
                  const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 13, color: _muted),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Extra university preamble rows, subjects, and remarks are safely ignored.',
                          style: TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Action Buttons: View Blueprint & Download Template
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showSectionBlueprintModal(context),
                        icon: const Icon(Icons.visibility_outlined, size: 14),
                        label: const Text('View Sheet Layout Blueprint'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(fontFamily: DefensysTokens.fontFamilyInter, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _downloadSectionTemplate,
                        icon: const Icon(Icons.download_rounded, size: 14),
                        label: const Text('Download Sample Template'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(fontFamily: DefensysTokens.fontFamilyInter, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

            final uploadCard = Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _line),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.cloud_upload_outlined, color: DefensysUi.techBlue, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Upload Class List Files',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Supports official university CSV and XLSX formats · $displaySection',
                              style: const TextStyle(fontSize: 11, color: _muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Default section override input if section is not predetermined
                  if (widget.section?.isNotEmpty != true || rows.isNotEmpty) ...[
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: section,
                        enabled: !busy,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Target section',
                          hintText: 'e.g. BSIT-3A',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onChanged: (_) {
                          if (preview != null) {
                            setState(() => preview = null);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Interactive Dropzone Box
                  InkWell(
                    onTap: busy ? null : pick,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFCBD5E1),
                          style: BorderStyle.solid,
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0A000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Icon(Icons.cloud_upload_outlined, color: _maroon, size: 24),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Drag & drop or click to choose official class list (.csv / .xlsx)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Section roster intake & verification for $displaySection',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildMiniBadge('CSV', const Color(0xFFF1F5F9), const Color(0xFF475569)),
                              const SizedBox(width: 6),
                              _buildMiniBadge('XLSX', const Color(0xFFF1F5F9), const Color(0xFF475569)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: busy ? null : pick,
                            icon: const Icon(Icons.upload_file_outlined, size: 15),
                            label: const Text('Import Class List'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _ink,
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              textStyle: const TextStyle(fontFamily: DefensysTokens.fontFamilyInter, fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Staged File Pill
                  if (stagedFileName != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.attach_file_rounded, size: 14, color: DefensysUi.techBlue),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Staged: $stagedFileName (${rows.length} students)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E40AF),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: busy ? null : clearStaged,
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close_rounded, size: 14, color: Color(0xFF1E40AF)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: specCard),
                  const SizedBox(width: 14),
                  Expanded(child: uploadCard),
                ],
              );
            } else {
              return Column(
                children: [
                  specCard,
                  const SizedBox(height: 14),
                  uploadCard,
                ],
              );
            }
          },
        ),

        // Busy indicator
        if (busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(color: _maroon),
        ],

        // Error message
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: _maroon, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(fontSize: 12, color: _maroon, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: rows.isNotEmpty ? review : null,
                  child: const Text('Retry', style: TextStyle(color: _maroon, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],

        // Success message
        if (message != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF15803D), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message!,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Preflight Student Intake Review (The Confirming Section Flow)
        if (preview != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x06000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preflight Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: _maroon.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.fact_check_outlined, color: _maroon, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Preflight Student Intake Review · ${reviewRows.length} Students',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Target Section: $displaySection · Verify parsed student cohort before confirming',
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    if (preview!['ready'] == true)
                      _buildMiniBadge('Ready to Confirm', const Color(0xFFDCFCE7), const Color(0xFF15803D))
                    else
                      _buildMiniBadge('Action Required', const Color(0xFFFEF3C7), const Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: busy ? null : clearStaged,
                      child: const Text('Clear', style: TextStyle(fontSize: 12, color: _muted)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Conflict Resolution Checkbox
                if (widget.canResolveConflicts && rows.isNotEmpty)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Review existing section reassignments (overwrite conflicting records)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    value: resolveConflicts,
                    onChanged: busy
                        ? null
                        : (v) {
                            setState(() {
                              resolveConflicts = v!;
                              preview = null;
                            });
                            review();
                          },
                  ),

                // Review Table Container
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: reviewRows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, idx) {
                      final row = reviewRows[idx];
                      final issues = (row['issues'] as List? ?? []).cast<String>();
                      final hasIssue = issues.isNotEmpty;
                      final prevSection = row['previous_section']?.toString();
                      final targetSection = row['section']?.toString() ?? displaySection;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              hasIssue ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                              size: 16,
                              color: hasIssue ? _maroon : const Color(0xFF16A34A),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row['name']?.toString() ?? 'Student',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink),
                                  ),
                                  Text(
                                    row['username']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 11, color: _muted),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                prevSection != null && prevSection.isNotEmpty
                                    ? '$prevSection → $targetSection'
                                    : 'New → $targetSection',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                row['action']?.toString() ?? 'Enroll',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: hasIssue ? _maroon : const Color(0xFF15803D),
                                ),
                              ),
                            ),
                            if (hasIssue)
                              Expanded(
                                flex: 3,
                                child: Text(
                                  issues.join(' · '),
                                  style: const TextStyle(fontSize: 10.5, color: _maroon, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),

                // Confirmation Button / Action
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (preview!['ready'] != true)
                      const Expanded(
                        child: Text(
                          'Resolve the listed issues before confirming. No records have been changed.',
                          style: TextStyle(fontSize: 11.5, color: _muted),
                        ),
                      ),
                    if (preview!['ready'] == true)
                      FilledButton.icon(
                        key: const ValueKey('confirm-section-assignments-btn'),
                        onPressed: busy ? null : save,
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                        label: const Text('Confirm section assignments'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],

        if (widget.showGroupingHeader) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            '2. Configure grouping',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }
}
