import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/admin/reports_provider.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_export_format_bar.dart';
import 'defensys_export_models.dart';
import 'defensys_live_data_preview_pane.dart';
import 'defensys_report_dialog_shell.dart';
import 'defensys_signatory_customizer_dialog.dart';

Future<bool?> showDefensysExportModal({
  required BuildContext context,
  required DefensysExportConfig config,
}) => showDialog<bool>(
  context: context,
  builder: (_) => DefensysExportDialog(config: config),
);

/// Catalog exports use the same workspace and footer as assessment reports.
class DefensysExportDialog extends StatefulWidget {
  const DefensysExportDialog({super.key, required this.config});
  final DefensysExportConfig config;

  @override
  State<DefensysExportDialog> createState() => _DefensysExportDialogState();
}

class _DefensysExportDialogState extends State<DefensysExportDialog> {
  late String _selectedFormat;
  late bool _includeSignatures;
  late List<DefensysSignatory> _signatories;
  late Map<String, String> _currentParams;
  late final TextEditingController _filenameController;
  bool _isDownloading = false;
  bool _isLoadingPreview = false;
  ReportPreviewData? _previewData;
  int _previewRequestId = 0;

  List<String> get _supportedFormats =>
      widget.config.formatsForParams?.call(_currentParams) ??
      widget.config.supportedFormats;

  List<DefensysSignatory> get _defaultSignatories =>
      widget.config.initialSignatories.isNotEmpty
      ? List.of(widget.config.initialSignatories)
      : const [
          DefensysSignatory(
            label: 'Prepared by:',
            name: '',
            role: 'Academic Documenter / Evaluator',
          ),
          DefensysSignatory(
            label: 'Noted by:',
            name: '',
            role: 'Project Adviser / Panel Chair',
          ),
          DefensysSignatory(
            label: 'Approved by:',
            name: 'IT Program Chairperson',
            role: 'IT Program Chairperson',
          ),
        ];

  @override
  void initState() {
    super.initState();
    _selectedFormat = widget.config.initialFormat;
    _includeSignatures = widget.config.initialIncludeSignatures;
    _signatories = _defaultSignatories;
    _currentParams = Map.of(widget.config.initialParams);
    if (!_supportedFormats.contains(_selectedFormat)) {
      _selectedFormat = _supportedFormats.first;
    }
    _filenameController = TextEditingController(
      text: widget.config.defaultFilename,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPreview();
    });
  }

  @override
  void dispose() {
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    final requestId = ++_previewRequestId;
    setState(() => _isLoadingPreview = true);
    try {
      final preview = await widget.config.onFetchPreview({
        ..._currentParams,
        'include_signatures': _includeSignatures.toString(),
        'signatories': jsonEncode(_signatories.map((s) => s.toJson()).toList()),
      });
      if (mounted && requestId == _previewRequestId) {
        setState(() {
          _isLoadingPreview = false;
          _previewData = preview;
        });
      }
    } catch (_) {
      if (mounted && requestId == _previewRequestId) {
        setState(() {
          _isLoadingPreview = false;
          _previewData = null;
        });
      }
    }
  }

  void _updateParams(Map<String, String> updated) {
    setState(() {
      _currentParams = Map.of(updated);
      if (!_supportedFormats.contains(_selectedFormat)) {
        _selectedFormat = _supportedFormats.first;
      }
    });
    _loadPreview();
  }

  void _editSignatories() {
    DefensysSignatoryCustomizerDialog.show(
      context: context,
      currentSignatories: _signatories,
      currentIncludeSignatures: _includeSignatures,
      defaultSignatories: _defaultSignatories,
      onApply: (signatories, enabled) {
        setState(() {
          _signatories = signatories;
          _includeSignatures = enabled;
        });
        _loadPreview();
      },
    );
  }

  Future<void> _handleDownload() async {
    setState(() => _isDownloading = true);
    try {
      final filename = _filenameController.text.trim();
      final success = await widget.config.onDownload(
        {
          ..._currentParams,
          if (filename.isNotEmpty) 'custom_filename': filename,
        },
        _selectedFormat,
        _signatories,
        _includeSignatures,
      );
      if (mounted) {
        setState(() => _isDownloading = false);
        if (success) Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefensysReportDialogShell(
      title: widget.config.title,
      subtitle: widget.config.subtitle,
      icon: widget.config.icon,
      tag: widget.config.tag,
      filterPaneWidth: widget.config.leftPaneWidth,
      onClose: () => Navigator.of(context).pop(false),
      filters: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.config.leftPaneBuilder != null)
              widget.config.leftPaneBuilder!(
                context,
                _currentParams,
                _updateParams,
                _loadPreview,
              ),
            const SizedBox(height: 20),
            Divider(height: 1, color: DefensysTokens.borderOf(context)),
            const SizedBox(height: 18),
            Text(
              'EXPORT FILE NAME',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DefensysTokens.textSecondaryOf(context),
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('report-filename'),
              controller: _filenameController,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                filled: true,
                fillColor: DefensysTokens.isDark(context)
                    ? DefensysTokens.surfaceHigherOf(context)
                    : const Color(0xFFF8FAFC),
                suffixText: '.${_selectedFormat.toUpperCase()}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                  borderSide: BorderSide(
                    color: DefensysTokens.borderOf(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      preview: DefensysLiveDataPreviewPane(
        isLoading: _isLoadingPreview,
        previewData: _previewData,
        onRefresh: _loadPreview,
        signatories: _signatories,
        includeSignatures: _includeSignatures,
        selectedFormat: _selectedFormat,
      ),
      footer: DefensysExportFormatBar(
        supportedFormats: _supportedFormats,
        selectedFormat: _selectedFormat,
        onFormatChanged: (format) => setState(() => _selectedFormat = format),
        includeSignatures: _includeSignatures,
        signatoriesCount: _signatories.length,
        allowSignatoryCustomization: widget.config.allowSignatoryCustomization,
        onOpenSignatoryCustomizer: _editSignatories,
        isDownloading: _isDownloading,
        onCancel: () => Navigator.of(context).pop(false),
        onDownload: _handleDownload,
      ),
    );
  }
}
