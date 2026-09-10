import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/admin/reports_provider.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_export_models.dart';
import 'defensys_live_data_preview_pane.dart';

/// Top-level helper function to launch the centralized DefenSYS export workflow anywhere.
Future<bool?> showDefensysExportModal({
  required BuildContext context,
  required DefensysExportConfig config,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogCtx) => DefensysExportDialog(config: config),
  );
}

/// Universal, Centralized DefenSYS Export Modal.
/// Features a modern split-pane layout:
/// - Left Sidebar: File Name editing, Export Format selection, and In-Place Signatory Editor
/// - Right Area: Live Document & Data Preview framed inside an institutional desk container
class DefensysExportDialog extends StatefulWidget {
  final DefensysExportConfig config;

  const DefensysExportDialog({
    super.key,
    required this.config,
  });

  @override
  State<DefensysExportDialog> createState() => _DefensysExportDialogState();
}

class _DefensysExportDialogState extends State<DefensysExportDialog> {
  late String _selectedFormat;
  late bool _includeSignatures;
  late List<DefensysSignatory> _signatories;
  late Map<String, String> _currentParams;

  late TextEditingController _filenameController;
  late List<TextEditingController> _signerNameControllers;
  late List<TextEditingController> _signerRoleControllers;
  late List<String> _availableLabels;

  Timer? _debounceTimer;
  bool _isDownloading = false;
  bool _isLoadingPreview = false;
  ReportPreviewData? _previewData;

  @override
  void initState() {
    super.initState();
    _selectedFormat = widget.config.initialFormat;
    _includeSignatures = widget.config.initialIncludeSignatures;
    _signatories = List.from(widget.config.initialSignatories);
    _currentParams = Map.from(widget.config.initialParams);

    if (_signatories.isEmpty) {
      _signatories = [
        const DefensysSignatory(
          label: 'Prepared by:',
          name: '',
          role: 'Academic Documenter / Evaluator',
        ),
        const DefensysSignatory(
          label: 'Noted by:',
          name: '',
          role: 'Project Adviser / Panel Chair',
        ),
        const DefensysSignatory(
          label: 'Approved by:',
          name: 'IT Program Chairperson',
          role: 'IT Program Chairperson',
        ),
      ];
    }

    _filenameController = TextEditingController(text: widget.config.defaultFilename);
    _signerNameControllers = _signatories.map((s) => TextEditingController(text: s.name)).toList();
    _signerRoleControllers = _signatories.map((s) => TextEditingController(text: s.role)).toList();

    _availableLabels = [
      'Prepared by:',
      'Noted by:',
      'Approved by:',
      'Verified by:',
      'Attested by:',
      'Certified Correct by:',
    ];

    for (final s in _signatories) {
      if (s.label.isNotEmpty && !_availableLabels.contains(s.label)) {
        _availableLabels.add(s.label);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPreview();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _filenameController.dispose();
    for (final c in _signerNameControllers) {
      c.dispose();
    }
    for (final c in _signerRoleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncSignatoriesFromControllers() {
    final updated = <DefensysSignatory>[];
    for (int i = 0; i < _signatories.length; i++) {
      final lbl = _signatories[i].label;
      final nm = i < _signerNameControllers.length ? _signerNameControllers[i].text.trim() : '';
      final rl = i < _signerRoleControllers.length ? _signerRoleControllers[i].text.trim() : '';
      updated.add(DefensysSignatory(label: lbl, name: nm, role: rl));
    }
    _signatories = updated;
  }

  void _onSignerFieldChanged() {
    _syncSignatoriesFromControllers();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        _loadPreview();
      }
    });
  }

  Future<void> _loadPreview() async {
    setState(() => _isLoadingPreview = true);

    try {
      final queryParams = Map<String, String>.from(_currentParams);
      queryParams['include_signatures'] = _includeSignatures.toString();
      if (_signatories.isNotEmpty) {
        queryParams['signatories'] = jsonEncode(_signatories.map((s) => s.toJson()).toList());
      }

      final preview = await widget.config.onFetchPreview(queryParams);
      if (mounted) {
        setState(() {
          _isLoadingPreview = false;
          _previewData = preview;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingPreview = false;
          _previewData = null;
        });
      }
    }
  }

  void _updateParams(Map<String, String> updated) {
    setState(() {
      _currentParams = Map.from(updated);
    });
    _loadPreview();
  }

  void _addSignatory() {
    setState(() {
      const newSig = DefensysSignatory(
        label: 'Approved by:',
        name: '',
        role: 'Academic Reviewer',
      );
      _signatories.add(newSig);
      _signerNameControllers.add(TextEditingController(text: ''));
      _signerRoleControllers.add(TextEditingController(text: 'Academic Reviewer'));
    });
    _loadPreview();
  }

  void _removeSignatory(int idx) {
    if (_signatories.length <= 1) return;
    setState(() {
      _signatories.removeAt(idx);
      _signerNameControllers.removeAt(idx).dispose();
      _signerRoleControllers.removeAt(idx).dispose();
    });
    _loadPreview();
  }

  void _resetSignatories() {
    setState(() {
      for (final c in _signerNameControllers) {
        c.dispose();
      }
      for (final c in _signerRoleControllers) {
        c.dispose();
      }
      _signatories = List.from(widget.config.initialSignatories);
      if (_signatories.isEmpty) {
        _signatories = [
          const DefensysSignatory(
            label: 'Prepared by:',
            name: '',
            role: 'Academic Documenter / Evaluator',
          ),
          const DefensysSignatory(
            label: 'Noted by:',
            name: '',
            role: 'Project Adviser / Panel Chair',
          ),
          const DefensysSignatory(
            label: 'Approved by:',
            name: 'IT Program Chairperson',
            role: 'IT Program Chairperson',
          ),
        ];
      }
      _signerNameControllers = _signatories.map((s) => TextEditingController(text: s.name)).toList();
      _signerRoleControllers = _signatories.map((s) => TextEditingController(text: s.role)).toList();
    });
    _loadPreview();
  }

  void _promptCustomLabel(int signerIndex) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (promptCtx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.label_outline_rounded, color: DefensysTokens.maroon, size: 20),
              SizedBox(width: 8),
              Text('Add Custom Signatory Label', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter header label for this signatory (e.g. Verified by:, Attested by:, Dean:)',
                style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. Endorsed by:',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                    borderSide: const BorderSide(color: DefensysTokens.border),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(promptCtx).pop(),
              child: const Text('Cancel', style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusSm)),
              ),
              onPressed: () {
                final entered = textController.text.trim();
                if (entered.isNotEmpty) {
                  final formatted = entered.endsWith(':') ? entered : '$entered:';
                  setState(() {
                    if (!_availableLabels.contains(formatted)) {
                      _availableLabels.add(formatted);
                    }
                    _signatories[signerIndex] = _signatories[signerIndex].copyWith(label: formatted);
                  });
                  _loadPreview();
                }
                Navigator.of(promptCtx).pop();
              },
              child: const Text('Add & Apply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleDownload() async {
    setState(() => _isDownloading = true);
    _syncSignatoriesFromControllers();

    try {
      final paramsWithFilename = Map<String, String>.from(_currentParams);
      final filenameText = _filenameController.text.trim();
      if (filenameText.isNotEmpty) {
        paramsWithFilename['custom_filename'] = filenameText;
      }

      final success = await widget.config.onDownload(
        paramsWithFilename,
        _selectedFormat,
        _signatories,
        _includeSignatures,
      );
      if (mounted) {
        setState(() => _isDownloading = false);
        if (success) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.95).clamp(940.0, 1400.0);
    final dialogHeight = (screenSize.height * 0.92).clamp(620.0, 880.0);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 32,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // 1. Modal Top Banner Header
            _buildModalHeader(),

            // 2. Main Split Area: Left Editing Sidebar + Right Desktop Preview Container
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LEFT PANEL: Controls, File Name, Format & Signatories
                  SizedBox(
                    width: 400,
                    child: _buildLeftEditingSidebar(),
                  ),

                  // VERTICAL SEPARATOR
                  const VerticalDivider(width: 1, thickness: 1, color: DefensysTokens.border),

                  // RIGHT PANEL: Framed Document Desktop Workspace
                  Expanded(
                    child: Container(
                      color: const Color(0xFFF1F5F9), // Desktop canvas feel
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0E000000),
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: DefensysLiveDataPreviewPane(
                          isLoading: _isLoadingPreview,
                          previewData: _previewData,
                          onRefresh: _loadPreview,
                          signatories: _signatories,
                          includeSignatures: _includeSignatures,
                          selectedFormat: _selectedFormat,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1. Modal Top Header
  Widget _buildModalHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: DefensysTokens.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: DefensysTokens.maroon.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            child: Icon(widget.config.icon, color: DefensysTokens.maroon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.config.title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.textDark,
                          letterSpacing: 0.4,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: DefensysTokens.maroon.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                      ),
                      child: Text(
                        widget.config.tag,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.maroon,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.config.subtitle,
                  style: const TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20, color: DefensysTokens.steelGrey),
            tooltip: 'Close Modal',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  /// 2. Left Editing Sidebar (Filename, Formats, Signatories, Actions)
  Widget _buildLeftEditingSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Scrollable Settings List
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A. Custom Left Filter Builder (If Provided by screen)
                if (widget.config.leftPaneBuilder != null) ...[
                  widget.config.leftPaneBuilder!(
                    context,
                    _currentParams,
                    _updateParams,
                    _loadPreview,
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1, color: DefensysTokens.border),
                  const SizedBox(height: 18),
                ],

                // B. Export File Name Section
                _buildFilenameSection(),
                const SizedBox(height: 18),

                // C. Format Selector Section
                _buildFormatSection(),
                const SizedBox(height: 18),

                // D. In-Place Signatory Editor Section
                _buildSignatoriesSection(),
              ],
            ),
          ),
        ),

        // Bottom Action Bar pinned at the bottom of the left sidebar
        _buildSidebarBottomBar(),
      ],
    );
  }

  /// Section: File Name Editing
  Widget _buildFilenameSection() {
    final extBadge = '.${_selectedFormat.toUpperCase()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.edit_note_rounded, size: 16, color: DefensysTokens.maroon),
            SizedBox(width: 6),
            Text(
              'EXPORT FILE NAME',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: DefensysTokens.steelGrey,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _filenameController,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: DefensysTokens.textDark),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            hintText: 'Enter custom file name',
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            prefixIcon: const Icon(Icons.description_outlined, size: 18, color: DefensysTokens.steelGrey),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            suffixIcon: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Text(
                extBadge,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: DefensysTokens.textDark,
                ),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(minHeight: 24),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
              borderSide: const BorderSide(color: DefensysTokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
              borderSide: const BorderSide(color: DefensysTokens.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
              borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
            ),
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
          ),
        ),
      ],
    );
  }

  /// Section: Format Selector Tiles
  Widget _buildFormatSection() {
    final formats = DefensysExportFormat.all
        .where((f) => widget.config.supportedFormats.contains(f.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.layers_outlined, size: 16, color: DefensysTokens.maroon),
            SizedBox(width: 6),
            Text(
              'SELECT EXPORT FORMAT',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: DefensysTokens.steelGrey,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 2x2 Grid of Format Cards
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: formats.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 64,
          ),
          itemBuilder: (context, index) {
            final fmt = formats[index];
            final isSelected = _selectedFormat.toLowerCase() == fmt.id;

            return InkWell(
              onTap: () {
                setState(() => _selectedFormat = fmt.id);
              },
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? fmt.color.withValues(alpha: 0.06) : Colors.white,
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                  border: Border.all(
                    color: isSelected ? fmt.color : const Color(0xFFE2E8F0),
                    width: isSelected ? 1.75 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: fmt.color.withValues(alpha: 0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? fmt.color.withValues(alpha: 0.14) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                      ),
                      child: Icon(fmt.icon, size: 16, color: isSelected ? fmt.color : DefensysTokens.steelGrey),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            fmt.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? fmt.color : DefensysTokens.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            fmt.ext.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? fmt.color.withValues(alpha: 0.8) : DefensysTokens.steelGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, size: 16, color: fmt.color),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Section: In-Place Signatory Editor
  Widget _buildSignatoriesSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: DefensysTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Toggle Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _includeSignatures ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(DefensysTokens.radiusMd)),
              border: Border(bottom: BorderSide(color: _includeSignatures ? const Color(0xFFFDE68A) : DefensysTokens.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _includeSignatures ? const Color(0xFFFEF3C7) : const Color(0xFFE2E8F0),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.history_edu_rounded,
                    size: 16,
                    color: _includeSignatures ? const Color(0xFFB45309) : DefensysTokens.steelGrey,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Official Signatories',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _includeSignatures ? const Color(0xFF92400E) : DefensysTokens.textDark,
                        ),
                      ),
                      Text(
                        _includeSignatures ? '${_signatories.length} Active Signers' : 'Signatures Disabled',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _includeSignatures ? const Color(0xFFB45309) : DefensysTokens.steelGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _includeSignatures,
                  activeThumbColor: DefensysTokens.maroon,
                  onChanged: (val) {
                    setState(() => _includeSignatures = val);
                    _loadPreview();
                  },
                ),
              ],
            ),
          ),

          // Signatories List & In-Place TextFields (When Enabled)
          if (_includeSignatures) ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ...List.generate(_signatories.length, (idx) => _buildSignatoryRowItem(idx)),

                  const SizedBox(height: 6),
                  Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: DefensysTokens.maroon,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('Add Signer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        onPressed: _addSignatory,
                      ),
                      const Spacer(),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: DefensysTokens.steelGrey,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        onPressed: _resetSignatories,
                        child: const Text('Reset Defaults', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// In-Place Signatory Mini-Card
  Widget _buildSignatoryRowItem(int idx) {
    final s = _signatories[idx];
    final currentLabel = s.label.isNotEmpty ? s.label : 'Prepared by:';
    if (!_availableLabels.contains(currentLabel)) {
      _availableLabels.add(currentLabel);
    }

    final menuItems = <DropdownMenuItem<String>>[
      ..._availableLabels.map((lbl) => DropdownMenuItem(
            value: lbl,
            child: Text(lbl, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          )),
      const DropdownMenuItem(
        value: '__ADD_CUSTOM__',
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 13, color: DefensysTokens.maroon),
            SizedBox(width: 4),
            Text('Custom Label...', style: TextStyle(fontSize: 11, color: DefensysTokens.maroon, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
        border: Border.all(color: DefensysTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${idx + 1}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: DefensysTokens.maroon),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: DropdownButtonFormField<String>(
                    initialValue: currentLabel,
                    isDense: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: menuItems,
                    onChanged: (val) {
                      if (val == '__ADD_CUSTOM__') {
                        _promptCustomLabel(idx);
                      } else if (val != null) {
                        setState(() {
                          _signatories[idx] = _signatories[idx].copyWith(label: val);
                        });
                        _loadPreview();
                      }
                    },
                  ),
                ),
              ),
              if (_signatories.length > 1) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                  tooltip: 'Remove',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _removeSignatory(idx),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Name TextField
          TextField(
            controller: _signerNameControllers[idx],
            onChanged: (_) => _onSignerFieldChanged(),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: DefensysTokens.textDark),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Signatory Name',
              labelStyle: const TextStyle(fontSize: 10.5, color: DefensysTokens.steelGrey),
              hintText: 'e.g. Dr. John Doe, MSIT',
              hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                borderSide: const BorderSide(color: DefensysTokens.border),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 6),

          // Role / Title TextField
          TextField(
            controller: _signerRoleControllers[idx],
            onChanged: (_) => _onSignerFieldChanged(),
            style: const TextStyle(fontSize: 11, color: DefensysTokens.textDark),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Designation / Institutional Role',
              labelStyle: const TextStyle(fontSize: 10.5, color: DefensysTokens.steelGrey),
              hintText: 'e.g. Capstone Project Adviser',
              hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                borderSide: const BorderSide(color: DefensysTokens.border),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom Actions Pinned at Left Sidebar Base
  Widget _buildSidebarBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: DefensysTokens.border)),
      ),
      child: Row(
        children: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: DefensysTokens.textDark,
              side: const BorderSide(color: DefensysTokens.border),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
              ),
              icon: _isDownloading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 16),
              label: Text(
                _isDownloading ? 'Exporting...' : 'Download ${_selectedFormat.toUpperCase()}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: _isDownloading ? null : _handleDownload,
            ),
          ),
        ],
      ),
    );
  }
}
