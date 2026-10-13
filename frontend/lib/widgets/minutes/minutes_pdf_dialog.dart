import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/api_config.dart';
import '../../services/authenticated_client.dart';
import '../../services/auth_provider.dart';
import '../../services/authz_errors.dart';
import '../../screens/web/faculty/e_signature_upload_dialog.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/universal_file_viewer.dart';
import '../export/defensys_pdf_viewer.dart';
import '../file_viewer_dialog_layout.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Previews protected PDFs without creating a draft; authorized reviewers can sign.
class MinutesPdfDialog extends ConsumerStatefulWidget {
  const MinutesPdfDialog({
    super.key,
    required this.scheduleId,
    required this.finalized,
    this.teamName = 'Defense',
    this.allowAdviserSigning = false,
    this.allowChairmanSigning = false,
  }) : assert(!finalized || !(allowAdviserSigning || allowChairmanSigning)),
       assert(!(allowAdviserSigning && allowChairmanSigning));
  final int scheduleId;
  final bool finalized;
  final String teamName;
  final bool allowAdviserSigning;
  final bool allowChairmanSigning;

  bool get allowsSigning => allowAdviserSigning || allowChairmanSigning;

  static Future<bool?> show(
    BuildContext context, {
    required int scheduleId,
    required bool finalized,
    String teamName = 'Defense',
    bool allowAdviserSigning = false,
    bool allowChairmanSigning = false,
  }) => showDialog<bool>(
    context: context,
    builder: (_) => MinutesPdfDialog(
      scheduleId: scheduleId,
      finalized: finalized,
      teamName: teamName,
      allowAdviserSigning: allowAdviserSigning,
      allowChairmanSigning: allowChairmanSigning,
    ),
  );

  @override
  ConsumerState<MinutesPdfDialog> createState() => _MinutesPdfDialogState();
}

class _MinutesPdfDialogState extends ConsumerState<MinutesPdfDialog> {
  Uint8List? _bytes;
  bool _loading = true, _missing = false;
  String? _error;
  String? _signError;
  bool _isSigning = false, _pdfReady = false;

  bool get _hasSignature =>
      ref
          .read(authProvider)
          .user?['e_signature']
          ?.toString()
          .trim()
          .isNotEmpty ==
      true;

  Future<void> _uploadSignature() => showDialog<void>(
    context: context,
    builder: (_) => const ESignatureUploadDialog(),
  );

  Future<void> _signMinutes() async {
    if (!widget.allowsSigning || _isSigning || !_pdfReady || !_hasSignature) {
      return;
    }
    setState(() {
      _isSigning = true;
      _signError = null;
    });
    try {
      final endpoint = widget.allowChairmanSigning
          ? 'sign-chairman'
          : 'sign-adviser';
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .post(
            Uri.parse(
              '${ApiConfig.defenseMinutesUrl}/${widget.scheduleId}/$endpoint/',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _isSigning = false);
        Navigator.pop(context, true);
      } else {
        setState(() {
          _isSigning = false;
          _signError = friendlyHttpErrorMessage(
            response.statusCode,
            response.body,
          );
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSigning = false;
        _signError = 'Unable to sign the minutes. Please try again.';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _missing = false;
      _bytes = null;
      _pdfReady = false;
    });
    try {
      final endpoint = widget.finalized ? 'pdf' : 'preview';
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(
            Uri.parse(
              '${ApiConfig.defenseMinutesUrl}/${widget.scheduleId}/$endpoint/',
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (response.statusCode == 200) {
          _bytes = response.bodyBytes;
        } else if (response.statusCode == 404) {
          _missing = true;
        } else {
          _error = friendlyHttpErrorMessage(response.statusCode, response.body);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Unable to load the minutes PDF. Please try again.';
        });
      }
    }
  }

  Widget _signaturePrompt() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final upload = ShadButton(
          onPressed: _uploadSignature,
          width: compact ? double.infinity : null,
          height: 36,
          backgroundColor: DefensysTokens.maroonOf(context),
          hoverBackgroundColor: DefensysTokens.isDark(context)
              ? DefensysTokens.maroonLight
              : DefensysTokens.maroonDark,
          foregroundColor: Colors.white,
          hoverForegroundColor: Colors.white,
          leading: const Icon(LucideIcons.signature, size: 16),
          child: const Text('Upload signature'),
        );
        return ShadAlert(
          key: const ValueKey('minutes-signature-prompt'),
          icon: const Icon(LucideIcons.signature, size: 18),
          decoration: ShadDecoration(
            border: ShadBorder.all(
              padding: const EdgeInsets.all(12),
              color: DefensysTokens.borderOf(context),
              radius: BorderRadius.circular(8),
            ),
          ),
          title: const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('E-signature required'),
          ),
          titleStyle: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
          description: const Text('Add your signature to sign these minutes.'),
          descriptionStyle: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 12,
            height: 1.4,
            color: DefensysTokens.textSecondaryOf(context),
          ),
          trailing: compact
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: upload,
                ),
          bottom: compact
              ? Padding(padding: const EdgeInsets.only(top: 12), child: upload)
              : null,
        );
      },
    ),
  );

  Widget _signingFooter(bool hasSignature) => Padding(
    padding: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final sign = ShadButton(
          key: ValueKey(
            widget.allowChairmanSigning
                ? 'minutes-chairman-sign'
                : 'minutes-adviser-sign',
          ),
          enabled:
              !_loading &&
              !_missing &&
              _error == null &&
              _pdfReady &&
              hasSignature &&
              !_isSigning,
          onPressed: _signMinutes,
          width: compact ? double.infinity : null,
          backgroundColor: DefensysTokens.maroonOf(context),
          hoverBackgroundColor: DefensysTokens.isDark(context)
              ? DefensysTokens.maroonLight
              : DefensysTokens.maroonDark,
          foregroundColor: Colors.white,
          hoverForegroundColor: Colors.white,
          leading: _isSigning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.signature, size: 16),
          child: Text(
            _isSigning
                ? 'Signing…'
                : widget.allowChairmanSigning
                ? 'Sign as chairman'
                : 'Sign as project adviser',
          ),
        );
        final close = ShadButton.outline(
          enabled: !_isSigning,
          onPressed: () => Navigator.pop(context),
          width: compact ? double.infinity : null,
          child: const Text('Close'),
        );
        final note = Text(
          widget.allowChairmanSigning
              ? 'Your signature finalizes the minutes and generates the official signed PDF.'
              : 'After you sign, the chairman adds the final signature.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_signError != null) ...[
              ShadAlert.destructive(
                icon: const Icon(LucideIcons.circleAlert, size: 17),
                description: Text(_signError!),
              ),
              const SizedBox(height: 12),
            ],
            if (compact) ...[
              note,
              const SizedBox(height: 12),
              sign,
              const SizedBox(height: 8),
              close,
            ] else
              Row(
                children: [
                  Expanded(child: note),
                  const SizedBox(width: 24),
                  close,
                  const SizedBox(width: 8),
                  sign,
                ],
              ),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final layout = FileViewerDialogLayout.of(context);
    final hasSignature =
        ref
            .watch(authProvider)
            .user?['e_signature']
            ?.toString()
            .trim()
            .isNotEmpty ==
        true;
    return PopScope(
      canPop: !_isSigning,
      child: DefensysShadcnScope(
        child: Padding(
          padding: layout.insetPadding,
          child: ShadDialog(
            key: const ValueKey('minutes-review-dialog'),
            constraints: const BoxConstraints(
              maxWidth: FileViewerDialogLayout.maxWidth,
            ),
            padding: EdgeInsets.zero,
            scrollable: false,
            removeBorderRadiusWhenTiny: false,
            radius: BorderRadius.circular(12),
            closeIcon: const SizedBox.shrink(),
            backgroundColor: DefensysTokens.surfaceOf(context),
            child: Material(
              type: MaterialType.transparency,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: layout.size.width,
                height: layout.size.height,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: DefensysTokens.surfaceHigherOf(context),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(LucideIcons.fileText, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.allowsSigning
                                      ? 'Review minutes'
                                      : widget.teamName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.allowsSigning
                                      ? '${widget.teamName} · ${widget.allowChairmanSigning ? 'Chairman' : 'Adviser'} review'
                                      : widget.finalized
                                      ? 'Official signed minutes'
                                      : 'Draft preview · Saved minutes',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DefensysTokens.textSecondaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_bytes != null &&
                              !_loading &&
                              _error == null &&
                              !_missing &&
                              widget.finalized) ...[
                            ShadButton.outline(
                              onPressed: () => downloadBytesFile(
                                bytes: _bytes!,
                                fileName: 'minutes_${widget.scheduleId}.pdf',
                                mimeType: 'application/pdf',
                              ),
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              leading: const Icon(
                                LucideIcons.download,
                                size: 15,
                              ),
                              child: const Text(
                                'Download PDF',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Tooltip(
                            message: 'Close preview',
                            child: ShadButton.ghost(
                              enabled: !_isSigning,
                              onPressed: () => Navigator.pop(context),
                              width: 32,
                              height: 32,
                              padding: EdgeInsets.zero,
                              child: const Icon(LucideIcons.x, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (widget.allowsSigning && !hasSignature)
                      _signaturePrompt(),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _missing
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  widget.finalized
                                      ? 'The signed PDF is unavailable. Please contact an administrator.'
                                      : 'Minutes have not been prepared yet.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_error!, textAlign: TextAlign.center),
                                    const SizedBox(height: 12),
                                    ShadButton.outline(
                                      onPressed: _load,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : DefensysPdfViewer(
                              pdfBytes: _bytes!,
                              onReadyChanged: widget.allowsSigning
                                  ? (ready) {
                                      if (mounted) {
                                        setState(() => _pdfReady = ready);
                                      }
                                    }
                                  : null,
                            ),
                    ),
                    if (widget.allowsSigning) ...[
                      const Divider(height: 1),
                      _signingFooter(hasSignature),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
