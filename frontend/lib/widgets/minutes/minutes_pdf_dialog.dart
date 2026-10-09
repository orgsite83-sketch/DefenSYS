import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../../services/authenticated_client.dart';
import '../../services/authz_errors.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/universal_file_viewer.dart';
import '../export/defensys_pdf_viewer.dart';

/// Reads only the protected PDF endpoints. Opening this never creates a draft.
class MinutesPdfDialog extends ConsumerStatefulWidget {
  const MinutesPdfDialog({
    super.key,
    required this.scheduleId,
    required this.finalized,
    this.teamName = 'Defense',
    this.onReviewAndSign,
  });
  final int scheduleId;
  final bool finalized;
  final String teamName;
  final VoidCallback? onReviewAndSign;

  static Future<void> show(
    BuildContext context, {
    required int scheduleId,
    required bool finalized,
    String teamName = 'Defense',
    VoidCallback? onReviewAndSign,
  }) => showDialog<void>(
    context: context,
    builder: (_) => MinutesPdfDialog(
      scheduleId: scheduleId,
      finalized: finalized,
      teamName: teamName,
      onReviewAndSign: onReviewAndSign,
    ),
  );

  @override
  ConsumerState<MinutesPdfDialog> createState() => _MinutesPdfDialogState();
}

class _MinutesPdfDialogState extends ConsumerState<MinutesPdfDialog> {
  Uint8List? _bytes;
  bool _loading = true, _missing = false;
  String? _error;

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

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: EdgeInsets.all(
      MediaQuery.sizeOf(context).width < 600 ? 8 : 24,
    ),
    backgroundColor: DefensysTokens.surfaceOf(context),
    child: SizedBox(
      width: 1100,
      height: MediaQuery.sizeOf(context).height * .9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.teamName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        widget.finalized
                            ? 'Official signed minutes'
                            : 'Draft preview · Saved minutes',
                        style: TextStyle(
                          fontSize: 12,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close preview',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
                          OutlinedButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : DefensysPdfViewer(pdfBytes: _bytes!),
          ),
          if (_bytes != null && !_loading && _error == null && !_missing) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (widget.onReviewAndSign != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onReviewAndSign!();
                      },
                      icon: const Icon(Icons.draw_outlined),
                      label: const Text('Review and sign'),
                    ),
                  if (widget.finalized)
                    FilledButton.icon(
                      onPressed: () => downloadBytesFile(
                        bytes: _bytes!,
                        fileName: 'minutes_${widget.scheduleId}.pdf',
                        mimeType: 'application/pdf',
                      ),
                      icon: const Icon(Icons.download),
                      label: const Text('Download PDF'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
