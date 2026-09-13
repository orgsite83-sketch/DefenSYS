import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/defensys_tokens.dart';

/// Semantic helper to determine whether a deliverable label represents
/// a core manuscript/thesis paper versus a supporting artifact (matrices, logs, specs, etc.).
bool isPrimaryManuscriptLabel(String label) {
  final lower = label.trim().toLowerCase();
  if (lower.isEmpty) return false;
  const primaryKeywords = [
    'manuscript',
    'concept paper',
    'concept pitch',
    'final paper',
    'camera-ready',
    'camera ready',
    'thesis',
    'dissertation',
    'capstone report',
    'final report',
    'project report',
    'research paper',
  ];
  return primaryKeywords.any((k) => lower.contains(k));
}

/// A clean slugifier for preview resolution.
String _slugify(String val) {
  return val.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
}

/// Convert label into PascalCase slug for clean filenames.
String _deliverableSlug(String val) {
  if (val.trim().isEmpty) return 'Deliverable';
  final words = val.trim().split(RegExp(r'\s+'));
  final capitalized = words.map((w) {
    if (w.isEmpty) return '';
    return w[0].toUpperCase() + w.substring(1).toLowerCase();
  }).join('');
  return _slugify(capitalized);
}

/// Map file format to default extension.
String _extensionForFormat(String format) {
  switch (format.toLowerCase()) {
    case 'pdf':
      return '.pdf';
    case 'video':
      return '.mp4';
    case 'image':
      return '.png';
    case 'presentation':
      return '.pptx';
    case 'document':
      return '.docx';
    case 'spreadsheet':
      return '.xlsx';
    case 'archive':
      return '.zip';
    case 'audio':
      return '.mp3';
    default:
      return '.pdf';
  }
}

/// Pure resolver for simulated vault filename.
String resolveArchiveFilePreview({
  required String template,
  required String deliverableLabel,
  required bool isPit,
  String? pitYear,
  required String stageOrEventLabel,
  String format = 'any',
}) {
  final cleanTemplate = template.trim();
  final isManuscript = isPrimaryManuscriptLabel(deliverableLabel);
  final effectiveTemplate = cleanTemplate.isNotEmpty
      ? cleanTemplate
      : (isManuscript ? '{project}' : '{project}_{deliverable}');

  final cleanedYear = (pitYear ?? '3rd Year').replaceAll(' ', '');
  String courseCode;
  if (isPit) {
    if (pitYear == '1st Year') {
      courseCode = 'PIT101';
    } else if (pitYear == '2nd Year') {
      courseCode = 'PIT201';
    } else if (pitYear == '3rd Year') {
      courseCode = 'PIT301';
    } else {
      courseCode = 'PIT401';
    }
  } else {
    courseCode = 'CAP301';
  }

  final project = isPit ? 'IoTMonitor' : 'ProjectTitle';
  final stageSlug = _slugify(
    stageOrEventLabel.trim().isEmpty
        ? (isPit ? '${cleanedYear}PITExpo' : 'StageLabel')
        : stageOrEventLabel.trim(),
  );
  final deliverable = _deliverableSlug(deliverableLabel);
  const semester = '1stSemester';

  var resolved = effectiveTemplate
      .replaceAll('{year}', cleanedYear.isNotEmpty ? cleanedYear : '3rdYear')
      .replaceAll('{course}', courseCode)
      .replaceAll('{project}', project)
      .replaceAll('{stage}', stageSlug)
      .replaceAll('{event}', stageSlug)
      .replaceAll('{deliverable}', deliverable)
      .replaceAll('{semester}', semester);

  if (!resolved.contains('.')) {
    resolved += _extensionForFormat(format);
  }

  return resolved;
}

/// Enterprise-grade Repository Archiving & File Naming panel.
///
/// Features:
/// - Semantic content classification (Primary Manuscript vs Supporting Artifact).
/// - Stage-wide conflict detection with automated collision prevention.
/// - Broad preset suite (Project + Deliverable, Project Only, Academic, Milestone, Semester).
/// - Visual Custom Token Builder without raw curly braces.
/// - Monospace live preview with extension badge and reassurance notices.
class RepositoryArchiveNamingPanel extends StatefulWidget {
  final TextEditingController templateController;
  final String deliverableLabel;
  final String fileFormat;
  final bool isLocked;
  final bool isPit;
  final String? pitYear;
  final String stageOrEventLabel;
  final List<Map<String, dynamic>> siblingDeliverables;
  final int currentIndex;
  final VoidCallback onChanged;

  const RepositoryArchiveNamingPanel({
    super.key,
    required this.templateController,
    required this.deliverableLabel,
    required this.fileFormat,
    required this.isLocked,
    required this.isPit,
    this.pitYear,
    required this.stageOrEventLabel,
    required this.siblingDeliverables,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  State<RepositoryArchiveNamingPanel> createState() => _RepositoryArchiveNamingPanelState();
}

class _RepositoryArchiveNamingPanelState extends State<RepositoryArchiveNamingPanel> {
  bool _isExpanded = false;
  bool _isCustomBuilderActive = false;
  String _activeDelimiter = '_';
  final TextEditingController _customPrefixController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkCustomBuilderStatus();
  }

  @override
  void didUpdateWidget(covariant RepositoryArchiveNamingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.templateController.text != widget.templateController.text) {
      _checkCustomBuilderStatus();
    }
  }

  @override
  void dispose() {
    _customPrefixController.dispose();
    super.dispose();
  }

  void _checkCustomBuilderStatus() {
    final tpl = widget.templateController.text.trim();
    if (tpl.isEmpty) {
      _isCustomBuilderActive = false;
      return;
    }
    final standardPresets = [
      '{project}_{deliverable}',
      '{project}',
      '{year}_{course}_{project}_{deliverable}',
      widget.isPit ? '{event}_{project}_{deliverable}' : '{stage}_{project}_{deliverable}',
      '{semester}_{project}_{deliverable}',
    ];
    if (!standardPresets.contains(tpl)) {
      _isCustomBuilderActive = true;
    }
  }

  void _applyPreset(String template) {
    widget.templateController.text = template;
    setState(() {
      _isCustomBuilderActive = false;
    });
    widget.onChanged();
  }

  void _insertToken(String tokenKey) {
    if (widget.isLocked) return;
    var current = widget.templateController.text.trim();
    if (current.isEmpty) {
      current = tokenKey;
    } else {
      current = '$current$_activeDelimiter$tokenKey';
    }
    widget.templateController.text = current;
    setState(() {
      _isCustomBuilderActive = true;
    });
    widget.onChanged();
  }

  void _applyPrefix(String prefix) {
    if (widget.isLocked) return;
    final cleanPrefix = prefix.trim();
    var current = widget.templateController.text.trim();
    if (cleanPrefix.isEmpty) return;

    // Prepend prefix if not already present
    if (!current.startsWith(cleanPrefix)) {
      current = '$cleanPrefix$current';
      widget.templateController.text = current;
      setState(() {
        _isCustomBuilderActive = true;
      });
      widget.onChanged();
    }
  }

  void _removeLastToken() {
    if (widget.isLocked) return;
    var current = widget.templateController.text.trim();
    if (current.isEmpty) return;

    final delimiters = ['_', '-', '.'];
    int lastDelimIndex = -1;
    for (final d in delimiters) {
      final idx = current.lastIndexOf(d);
      if (idx > lastDelimIndex) {
        lastDelimIndex = idx;
      }
    }

    if (lastDelimIndex > 0) {
      current = current.substring(0, lastDelimIndex);
    } else {
      current = '';
    }

    widget.templateController.text = current;
    setState(() {});
    widget.onChanged();
  }

  void _resetToDefault() {
    if (widget.isLocked) return;
    final isManuscript = isPrimaryManuscriptLabel(widget.deliverableLabel);
    final smartDefault = isManuscript ? '{project}' : '{project}_{deliverable}';
    widget.templateController.text = smartDefault;
    setState(() {
      _isCustomBuilderActive = false;
      _customPrefixController.clear();
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isManuscript = isPrimaryManuscriptLabel(widget.deliverableLabel);
    final currentTemplate = widget.templateController.text.trim();

    // 1. Resolve raw preview for current deliverable
    final rawPreview = resolveArchiveFilePreview(
      template: currentTemplate,
      deliverableLabel: widget.deliverableLabel,
      isPit: widget.isPit,
      pitYear: widget.pitYear,
      stageOrEventLabel: widget.stageOrEventLabel,
      format: widget.fileFormat,
    );

    // 2. Stage-wide collision detection against prior deliverables in the same stage
    bool collisionDetected = false;
    String collidingSiblingLabel = '';
    String originalDuplicateName = '';

    for (int i = 0; i < widget.currentIndex; i++) {
      if (i >= widget.siblingDeliverables.length) break;
      final sibling = widget.siblingDeliverables[i];
      final sibLabel = (sibling['_labelController'] as TextEditingController?)?.text ??
          sibling['label']?.toString() ??
          '';
      final sibTpl = (sibling['_templateController'] as TextEditingController?)?.text ??
          sibling['archive_file_template']?.toString() ??
          '';
      final sibFormat = sibling['file_format']?.toString() ?? 'any';

      final siblingRawPreview = resolveArchiveFilePreview(
        template: sibTpl,
        deliverableLabel: sibLabel,
        isPit: widget.isPit,
        pitYear: widget.pitYear,
        stageOrEventLabel: widget.stageOrEventLabel,
        format: sibFormat,
      );

      if (siblingRawPreview.toLowerCase() == rawPreview.toLowerCase()) {
        collisionDetected = true;
        collidingSiblingLabel = sibLabel.isNotEmpty
            ? 'Deliverable #${i + 1} ("$sibLabel")'
            : 'Deliverable #${i + 1}';
        originalDuplicateName = rawPreview;
        break;
      }
    }

    // 3. If collision detected, DefenSYS auto-disambiguates by appending deliverable slug
    final effectivePreview = collisionDetected
        ? resolveArchiveFilePreview(
            template: currentTemplate.contains('{deliverable}')
                ? currentTemplate
                : '${currentTemplate}_{deliverable}',
            deliverableLabel: widget.deliverableLabel,
            isPit: widget.isPit,
            pitYear: widget.pitYear,
            stageOrEventLabel: widget.stageOrEventLabel,
            format: widget.fileFormat,
          )
        : rawPreview;

    // Presets definitions
    const presetProjectDeliverable = '{project}_{deliverable}';
    const presetProjectOnly = '{project}';
    const presetAcademic = '{year}_{course}_{project}_{deliverable}';
    final presetMilestone = widget.isPit
        ? '{event}_{project}_{deliverable}'
        : '{stage}_{project}_{deliverable}';
    const presetSemester = '{semester}_{project}_{deliverable}';

    final isDefaultSelection = currentTemplate.isEmpty;
    final isPreset1 = currentTemplate == presetProjectDeliverable || (isDefaultSelection && !isManuscript);
    final isPreset2 = currentTemplate == presetProjectOnly || (isDefaultSelection && isManuscript);
    final isPreset3 = currentTemplate == presetAcademic;
    final isPreset4 = currentTemplate == presetMilestone;
    final isPreset5 = currentTemplate == presetSemester;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row: Title + Status Badge + Collapse/Expand Toggle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.archive_outlined, size: 15, color: AppColors.maroon),
              ),
              const SizedBox(width: 8),
              const Text(
                'Repository Archiving & Naming',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                  fontFamily: DefensysTokens.fontFamily,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: const Text(
                  '⚡ Auto-Renamed by System',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
              ),
              const Spacer(),
              // Classification Badge (Manuscript vs Supporting)
              Tooltip(
                message: isManuscript
                    ? 'Primary Manuscript: DefenSYS defaults this to Project Title for clean archiving.'
                    : 'Supporting Artifact: DefenSYS includes Deliverable Name to keep all files distinct.',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isManuscript ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isManuscript ? const Color(0xFFBFDBFE) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isManuscript ? Icons.menu_book_rounded : Icons.attach_file_rounded,
                        size: 13,
                        color: isManuscript ? const Color(0xFF2563EB) : const Color(0xFF475569),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isManuscript ? 'Primary Manuscript' : 'Supporting Artifact',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isManuscript ? const Color(0xFF1D4ED8) : const Color(0xFF334155),
                          fontFamily: DefensysTokens.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isExpanded ? 'Hide Options' : 'Configure Format',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _isExpanded ? AppColors.maroon : const Color(0xFF64748B),
                          fontFamily: DefensysTokens.fontFamily,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 15,
                        color: _isExpanded ? AppColors.maroon : const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Live Archive Output Preview Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: collisionDetected ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                width: collisionDetected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 15, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                const Text(
                  'Preview Output: ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SelectableText(
                    effectivePreview,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: collisionDetected ? const Color(0xFFB45309) : AppColors.maroon,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Collision Prevention Reassurance Banner
          if (collisionDetected) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF92400E),
                          height: 1.35,
                          fontFamily: DefensysTokens.fontFamily,
                        ),
                        children: [
                          const TextSpan(
                            text: 'Duplicate Avoided: ',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text:
                                'Another item ($collidingSiblingLabel) already produces "$originalDuplicateName". '
                                'DefenSYS automatically appends the deliverable label to ensure both documents are preserved safely without overwriting.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 5),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'DefenSYS formats repository files automatically upon upload. Students can upload their work under any filename without naming restrictions.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF64748B),
                    fontFamily: DefensysTokens.fontFamily,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),

          // Expanded Format Options
          if (_isExpanded) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 10),

            // Presets Selector Header
            Row(
              children: [
                const Text(
                  'Naming Pattern Presets',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
                const Spacer(),
                if (_isCustomBuilderActive)
                  TextButton.icon(
                    onPressed: widget.isLocked ? null : _resetToDefault,
                    icon: const Icon(Icons.restart_alt_rounded, size: 13),
                    label: const Text('Reset to Recommended'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.maroon,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: DefensysTokens.fontFamily,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Presets Wrap Chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildPresetChip(
                  label: 'Project + Deliverable',
                  subtitle: 'e.g. IoTMonitor_Specs.pdf',
                  isSelected: isPreset1 && !_isCustomBuilderActive,
                  onSelected: () => _applyPreset(presetProjectDeliverable),
                ),
                _buildPresetChip(
                  label: 'Project Only',
                  subtitle: 'e.g. IoTMonitor.pdf (Manuscript)',
                  isSelected: isPreset2 && !_isCustomBuilderActive,
                  onSelected: () => _applyPreset(presetProjectOnly),
                ),
                _buildPresetChip(
                  label: 'Academic Standard',
                  subtitle: 'Year + Course + Project + Deliverable',
                  isSelected: isPreset3 && !_isCustomBuilderActive,
                  onSelected: () => _applyPreset(presetAcademic),
                ),
                _buildPresetChip(
                  label: widget.isPit ? 'Milestone Specific' : 'Stage Specific',
                  subtitle: widget.isPit ? 'Event + Project + Deliverable' : 'Stage + Project + Deliverable',
                  isSelected: isPreset4 && !_isCustomBuilderActive,
                  onSelected: () => _applyPreset(presetMilestone),
                ),
                _buildPresetChip(
                  label: 'Semester Standard',
                  subtitle: 'Semester + Project + Deliverable',
                  isSelected: isPreset5 && !_isCustomBuilderActive,
                  onSelected: () => _applyPreset(presetSemester),
                ),
                _buildPresetChip(
                  label: '⚙️ Custom Token Builder',
                  subtitle: 'Assemble pattern visually',
                  isSelected: _isCustomBuilderActive,
                  onSelected: () {
                    setState(() {
                      _isCustomBuilderActive = true;
                    });
                  },
                ),
              ],
            ),

            // Interactive Custom Token Builder Section
            if (_isCustomBuilderActive) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded, size: 14, color: AppColors.maroon),
                        const SizedBox(width: 6),
                        const Text(
                          'Visual Token Builder',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            fontFamily: DefensysTokens.fontFamily,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Delimiter: ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                            fontFamily: DefensysTokens.fontFamily,
                          ),
                        ),
                        _buildDelimiterChoice('_', 'Underscore (_)'),
                        const SizedBox(width: 4),
                        _buildDelimiterChoice('-', 'Hyphen (-)'),
                        const SizedBox(width: 4),
                        _buildDelimiterChoice('.', 'Dot (.)'),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Active Pattern Visualization
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Active Pattern: ',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              fontFamily: DefensysTokens.fontFamily,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              currentTemplate.isNotEmpty ? currentTemplate : '(Empty - using smart default)',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                color: currentTemplate.isNotEmpty ? AppColors.maroon : const Color(0xFF94A3B8),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (currentTemplate.isNotEmpty)
                            InkWell(
                              onTap: widget.isLocked ? null : _removeLastToken,
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.backspace_outlined, size: 11, color: Color(0xFF64748B)),
                                    SizedBox(width: 3),
                                    Text(
                                      'Remove Last',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
                    const Text(
                      'Click to append token (no curly braces required):',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF64748B),
                        fontFamily: DefensysTokens.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Clickable Token Pills
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildTokenPill('+ Project Title', '{project}', Icons.title_rounded),
                        _buildTokenPill('+ Deliverable Name', '{deliverable}', Icons.insert_drive_file_outlined),
                        _buildTokenPill('+ Year Level', '{year}', Icons.school_outlined),
                        _buildTokenPill('+ Course Code', '{course}', Icons.tag_rounded),
                        _buildTokenPill(
                          widget.isPit ? '+ Event Name' : '+ Defense Stage',
                          widget.isPit ? '{event}' : '{stage}',
                          Icons.flag_outlined,
                        ),
                        _buildTokenPill('+ Semester', '{semester}', Icons.calendar_today_outlined),
                      ],
                    ),

                    const SizedBox(height: 8),
                    // Optional static prefix row
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: TextField(
                              controller: _customPrefixController,
                              enabled: !widget.isLocked,
                              decoration: InputDecoration(
                                hintText: 'Optional Prefix (e.g. FINAL_, CS-DEPT_)',
                                hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFamily: DefensysTokens.fontFamily,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          onPressed: widget.isLocked
                              ? null
                              : () {
                                  _applyPrefix(_customPrefixController.text);
                                  _customPrefixController.clear();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.maroon,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text(
                            'Add Prefix',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return InkWell(
      onTap: widget.isLocked ? null : onSelected,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.maroon.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.maroon : const Color(0xFFCBD5E1),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.maroon),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? AppColors.maroon : const Color(0xFF334155),
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9.5,
                color: isSelected ? AppColors.maroon.withValues(alpha: 0.85) : const Color(0xFF64748B),
                fontFamily: DefensysTokens.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDelimiterChoice(String delim, String tooltip) {
    final isCurrent = _activeDelimiter == delim;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => setState(() => _activeDelimiter = delim),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isCurrent ? AppColors.maroon : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            delim == ' ' ? 'Space' : delim,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isCurrent ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTokenPill(String label, String tokenKey, IconData icon) {
    return ActionChip(
      onPressed: widget.isLocked ? null : () => _insertToken(tokenKey),
      avatar: Icon(icon, size: 13, color: AppColors.maroon),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.maroon,
          fontFamily: DefensysTokens.fontFamily,
        ),
      ),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFCBD5E1)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      visualDensity: VisualDensity.compact,
    );
  }
}
