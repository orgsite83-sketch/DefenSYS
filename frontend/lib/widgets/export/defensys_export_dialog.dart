import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../services/admin/reports_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'defensys_export_format_bar.dart';
import 'defensys_export_models.dart';
import 'defensys_live_data_preview_pane.dart';
import 'defensys_report_dialog_shell.dart';
import 'defensys_signatory_customizer_dialog.dart';
import 'report_settings_section.dart';

Future<bool?> showDefensysExportModal({
  required BuildContext context,
  required DefensysExportConfig config,
}) => showDialog<bool>(
  context: context,
  builder: (_) => DefensysExportDialog(config: config),
);

/// Catalog exports use the same workspace and footer as assessment reports.
class DefensysExportDialog extends StatefulWidget {
  const DefensysExportDialog({
    super.key,
    required this.config,
    this.embedded = false,
    this.simplified = false,
    this.onParamsChanged,
  });
  final DefensysExportConfig config;
  final bool embedded;
  final bool simplified;
  final ValueChanged<Map<String, String>>? onParamsChanged;

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
  Timer? _previewTimer;
  bool _showWorkspaceOptions = false;

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
    _previewTimer?.cancel();
    _filenameController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    _previewTimer?.cancel();
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
    widget.onParamsChanged?.call(updated);
    if (widget.embedded || widget.simplified) {
      _previewTimer?.cancel();
      _previewRequestId++;
      setState(() => _isLoadingPreview = true);
      _previewTimer = Timer(const Duration(milliseconds: 300), _loadPreview);
    } else {
      _loadPreview();
    }
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
        if (success) {
          if (widget.embedded) {
            ToastService.success(
              context,
              '${_selectedFormat == 'xlsx' ? 'Excel' : 'PDF'} downloaded.',
            );
          } else {
            Navigator.of(context).pop(true);
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildWorkspace(context);
    if (widget.simplified) return _buildWorkspace(context, popup: true);
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

  Widget _buildWorkspace(BuildContext context, {bool popup = false}) {
    final missing = widget.config.selectionHint?.call(_currentParams);
    final canDownload =
        !_isDownloading &&
        !_isLoadingPreview &&
        _previewData != null &&
        missing == null;
    final filters = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.config.leftPaneBuilder != null)
          widget.config.leftPaneBuilder!(
            context,
            _currentParams,
            _updateParams,
            _loadPreview,
          ),
        const SizedBox(height: 16),
        ReportSettingsSection(
          triggerKey: const ValueKey('report-more-options'),
          title: 'Export options',
          icon: Icons.settings_outlined,
          expanded: _showWorkspaceOptions,
          onToggle: () =>
              setState(() => _showWorkspaceOptions = !_showWorkspaceOptions),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'File name',
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              ShadInput(
                key: const ValueKey('report-filename'),
                controller: _filenameController,
              ),
              if (widget.config.allowSignatoryCustomization) ...[
                const SizedBox(height: 16),
                ShadButton.outline(
                  onPressed: _editSignatories,
                  leading: const Icon(Icons.draw_outlined, size: 16),
                  child: const Text('Signatures'),
                ),
                const SizedBox(height: 6),
                Text(
                  _includeSignatures
                      ? 'Signature blocks included'
                      : 'Signature blocks off',
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final previewHeader = Wrap(
      spacing: 12,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preview',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            if (_previewData != null && !_isLoadingPreview)
              Text(
                '${_previewData!.totalRows} matching ${_previewData!.totalRows == 1 ? 'record' : 'records'}',
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
          ],
        ),
        if (_supportedFormats.length > 1)
          SizedBox(
            width: 125,
            child: ShadSelect<String>(
              key: ValueKey('report-preview-format-$_selectedFormat'),
              initialValue: _selectedFormat,
              options: [
                for (final format in _supportedFormats)
                  ShadOption(
                    value: format,
                    child: Text(format == 'xlsx' ? 'Excel' : 'PDF'),
                  ),
              ],
              selectedOptionBuilder: (_, value) =>
                  Text(value == 'xlsx' ? 'Excel' : 'PDF'),
              onChanged: (value) {
                if (value != null) setState(() => _selectedFormat = value);
              },
            ),
          ),
      ],
    );
    final previewBody = Container(
      height: popup
          ? null
          : MediaQuery.sizeOf(context).height.clamp(600, 900) * .65,
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: DefensysLiveDataPreviewPane(
        isLoading: _isLoadingPreview,
        previewData: _previewData,
        onRefresh: _loadPreview,
        signatories: _signatories,
        includeSignatures: _includeSignatures,
        selectedFormat: _selectedFormat,
        emptyStateOverride: _previewData != null
            ? null
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.description_outlined, size: 28),
                      const SizedBox(height: 12),
                      Text(
                        missing ??
                            widget.config.previewError?.call() ??
                            'No preview is available for these selections.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: DefensysTokens.fontFamilyInter,
                          fontSize: 13,
                        ),
                      ),
                      if (missing == null) ...[
                        const SizedBox(height: 12),
                        ShadButton.outline(
                          onPressed: _loadPreview,
                          child: const Text('Retry preview'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
    final downloads = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final format in _supportedFormats)
          if (format == 'pdf' || _supportedFormats.length == 1)
            ShadButton(
              key: ValueKey('report-download-$format'),
              onPressed: canDownload
                  ? () {
                      setState(() => _selectedFormat = format);
                      _handleDownload();
                    }
                  : null,
              leading: Icon(
                format == 'pdf'
                    ? Icons.picture_as_pdf_outlined
                    : Icons.table_view_outlined,
                size: 16,
              ),
              child: Text(
                _isDownloading && _selectedFormat == format
                    ? 'Downloading…'
                    : 'Download ${format == 'xlsx' ? 'Excel' : 'PDF'}',
              ),
            )
          else
            ShadButton.outline(
              key: ValueKey('report-download-$format'),
              onPressed: canDownload
                  ? () {
                      setState(() => _selectedFormat = format);
                      _handleDownload();
                    }
                  : null,
              leading: const Icon(Icons.table_view_outlined, size: 16),
              child: Text(
                _isDownloading && _selectedFormat == format
                    ? 'Downloading…'
                    : 'Download Excel',
              ),
            ),
      ],
    );
    final preview = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        previewHeader,
        const SizedBox(height: 12),
        if (popup) Expanded(child: previewBody) else previewBody,
        if (!popup) ...[const SizedBox(height: 14), downloads],
      ],
    );
    if (popup) {
      return DefensysShadcnScope(
        maroonActions: true,
        child: DefensysReportDialogShell(
          title: widget.config.title,
          subtitle: widget.config.subtitle,
          icon: widget.config.icon,
          tag: widget.config.tag,
          filterPaneWidth: widget.config.leftPaneWidth,
          onClose: () => Navigator.of(context).pop(false),
          filters: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: filters,
          ),
          preview: Padding(padding: const EdgeInsets.all(18), child: preview),
          footer: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                ShadButton.ghost(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                downloads,
              ],
            ),
          ),
        ),
      );
    }
    return DefensysShadcnScope(
      maroonActions: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 820) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [filters, const SizedBox(height: 24), preview],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 300, child: filters),
              const SizedBox(width: 28),
              Expanded(child: preview),
            ],
          );
        },
      ),
    );
  }
}
