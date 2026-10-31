import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/defense/template_configuration.dart';
import '../../services/network/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/universal_file_viewer.dart';

/// A draft attachment belongs to the surrounding setup form until Save succeeds.
class DeliverableTemplateEditor extends StatefulWidget {
  const DeliverableTemplateEditor({
    super.key,
    required this.item,
    required this.onChanged,
    this.enabled = true,
  });
  final Map<String, dynamic> item;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  State<DeliverableTemplateEditor> createState() =>
      _DeliverableTemplateEditorState();
}

class _DeliverableTemplateEditorState extends State<DeliverableTemplateEditor> {
  String? error;
  bool picking = false;

  Future<void> pick() async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: templateExtensions,
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (!templateExtensions.contains(file.extension?.toLowerCase()) ||
          file.bytes == null ||
          file.size == 0 ||
          file.size > templateMaxBytes) {
        setState(
          () =>
              error = 'Choose a supported, non-empty template of up to 20 MB.',
        );
        return;
      }
      widget.item['_templateFile'] = file;
      widget.item['template_action'] = 'replace';
      widget.item['template_selection_name'] = file.name;
      widget.item['template_selection_size'] = file.size;
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to select the template. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final saved = item['template'] as Map?;
    final replacing = item['template_action'] == 'replace';
    final removed = item['template_action'] == 'remove';
    final local = item['_templateFile'] as PlatformFile?;
    final name = replacing
        ? '${item['template_selection_name'] ?? ''}'
        : '${saved?['original_name'] ?? ''}';
    final attached = !removed && name.isNotEmpty;
    final size = replacing
        ? item['template_selection_size']
        : saved?['byte_size'];
    final canPreview =
        attached &&
        (replacing ? local?.bytes != null : saved?['file_url'] != null);
    final busy = picking || !widget.enabled;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Template ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: '(optional)',
                  style: TextStyle(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          _TemplateSurface(
            children: [
              Icon(
                attached
                    ? Icons.description_outlined
                    : Icons.file_upload_outlined,
                size: 18,
                color: DefensysTokens.textSecondaryOf(context),
              ),
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attached ? name : 'No template attached',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (attached && size is num)
                      Text(
                        FileViewerMetadata.formatBytes(size.toInt()),
                        style: TextStyle(
                          fontSize: 11,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                  ],
                ),
              ),
              if (attached) ...[
                TextButton.icon(
                  onPressed: canPreview
                      ? () => viewFileInDialog(
                          context: context,
                          fileName: name,
                          fileBytes: replacing ? local!.bytes : null,
                          fileUrl: replacing
                              ? null
                              : saved?['file_url']?.toString(),
                        )
                      : null,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Preview'),
                ),
                TextButton(
                  onPressed: busy ? null : pick,
                  child: const Text('Replace'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          setState(() {
                            error = null;
                            item['template_action'] = 'remove';
                            item.remove('_templateFile');
                            item.remove('template_selection_name');
                            item.remove('template_selection_size');
                          });
                          widget.onChanged();
                        },
                  child: const Text('Remove'),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: busy ? null : pick,
                  icon: const Icon(Icons.upload_file_outlined, size: 16),
                  label: Text(picking ? 'Selecting...' : 'Upload template'),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            replacing && local == null
                ? 'Select this template again before saving; file selections are not stored in browser drafts.'
                : 'Students can preview and download this file in their Deliverables tab.',
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

/// Read-only access stays independent of submission upload permission.
class DeliverableTemplateDownload extends ConsumerStatefulWidget {
  const DeliverableTemplateDownload({super.key, required this.template});
  final dynamic template;
  @override
  ConsumerState<DeliverableTemplateDownload> createState() =>
      _DeliverableTemplateDownloadState();
}

class _DeliverableTemplateDownloadState
    extends ConsumerState<DeliverableTemplateDownload> {
  bool downloading = false;
  String? error;

  Future<void> download(Map template) async {
    setState(() {
      downloading = true;
      error = null;
    });
    try {
      final name = '${template['original_name']}';
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile('${template['file_url']}');
      await downloadBytesFile(
        bytes: bytes,
        fileName: name,
        mimeType: FileViewerMetadata.getMimeType(name),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to download the template. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    if (template is! Map || '${template['file_url'] ?? ''}'.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TemplateSurface(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: DefensysTokens.textSecondaryOf(context),
              ),
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Template',
                      style: TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    Text(
                      '${template['original_name']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => viewFileInDialog(
                  context: context,
                  fileName: '${template['original_name']}',
                  fileUrl: '${template['file_url']}',
                ),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Preview'),
              ),
              TextButton.icon(
                onPressed: downloading ? null : () => download(template),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: Text(
                  downloading ? 'Downloading...' : 'Download template',
                ),
              ),
            ],
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

class _TemplateSurface extends StatelessWidget {
  const _TemplateSurface({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceHigherOf(context),
          border: Border.all(color: DefensysTokens.borderOf(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children
              .map(
                (child) => ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (constraints.maxWidth - 22).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: child,
                ),
              )
              .toList(),
        ),
      );
    },
  );
}
