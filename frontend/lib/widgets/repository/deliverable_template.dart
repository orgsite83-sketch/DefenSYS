import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../services/auth_provider.dart';
import '../../services/defense/template_configuration.dart';
import '../../services/network/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/universal_file_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// A draft attachment belongs to the surrounding setup form until Save succeeds.
class DeliverableTemplateEditor extends StatefulWidget {
  const DeliverableTemplateEditor({
    super.key,
    required this.item,
    required this.onChanged,
    this.enabled = true,
    this.allowedExtensions = templateExtensions,
    this.requiredTemplate = false,
    this.label = 'Template',
  });
  final Map<String, dynamic> item;
  final VoidCallback onChanged;
  final bool enabled;
  final List<String> allowedExtensions;
  final bool requiredTemplate;
  final String label;

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
        allowedExtensions: widget.allowedExtensions,
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (!widget.allowedExtensions.contains(file.extension?.toLowerCase()) ||
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
    return DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${widget.label} ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: widget.requiredTemplate ? '(required)' : '(optional)',
                    style: TextStyle(
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
              style: DefensysTokens.body.copyWith(
                fontSize: 13,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            _TemplateSurface(
              name: attached ? name : null,
              byteSize: size is num ? size.toInt() : null,
              emptyMetadata:
                  widget.allowedExtensions.length == 1 &&
                      widget.allowedExtensions.single == 'docx'
                  ? 'Word document (.docx) · Up to 20 MB'
                  : null,
              actions: [
                if (attached) ...[
                  _TemplateAction(
                    label: 'Preview',
                    icon: LucideIcons.eye,
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
                  ),
                  _TemplateAction(
                    label: 'Replace',
                    icon: LucideIcons.refreshCw,
                    loading: picking,
                    onPressed: busy ? null : pick,
                  ),
                  _TemplateAction(
                    label: 'Remove',
                    icon: LucideIcons.trash2,
                    variant: ShadButtonVariant.ghost,
                    destructive: true,
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
                  ),
                ] else
                  _TemplateAction(
                    label: picking ? 'Selecting...' : 'Upload template',
                    icon: LucideIcons.upload,
                    loading: picking,
                    onPressed: busy ? null : pick,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              replacing && local == null
                  ? 'Select this template again before saving; file selections are not stored in browser drafts.'
                  : replacing
                  ? 'Save changes to make this template available to students.'
                  : removed
                  ? 'This template will be removed when you save changes.'
                  : 'Students can preview and download this file in their Deliverables tab.',
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            if (error != null) _TemplateError(message: error!),
          ],
        ),
      ),
    );
  }
}

/// Student guidance stays available independently of submission upload permission.
/// Faculty review surfaces focus on submitted work; setup uses the editor above.
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
    final student = ref.watch(
      authProvider.select((state) => state.user?['role'] == 'student'),
    );
    if (!student) {
      return const SizedBox.shrink();
    }
    return DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TemplateSurface(
              label: 'Template',
              name: '${template['original_name']}',
              byteSize: (template['byte_size'] as num?)?.toInt(),
              actions: [
                _TemplateAction(
                  label: 'Preview',
                  icon: LucideIcons.eye,
                  onPressed: () => viewFileInDialog(
                    context: context,
                    fileName: '${template['original_name']}',
                    fileUrl: '${template['file_url']}',
                  ),
                ),
                _TemplateAction(
                  label: downloading ? 'Downloading...' : 'Download template',
                  icon: LucideIcons.download,
                  variant: ShadButtonVariant.primary,
                  loading: downloading,
                  onPressed: downloading ? null : () => download(template),
                ),
              ],
            ),
            if (error != null) _TemplateError(message: error!),
          ],
        ),
      ),
    );
  }
}

class _TemplateSurface extends StatelessWidget {
  const _TemplateSurface({
    required this.name,
    required this.actions,
    this.byteSize,
    this.label,
    this.emptyMetadata,
  });

  final String? name;
  final int? byteSize;
  final String? label;
  final String? emptyMetadata;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final secondary = DefensysTokens.textSecondaryOf(context);
    final extension = name != null && name!.contains('.')
        ? name!.split('.').last.toUpperCase()
        : '';
    final metadata = name == null
        ? emptyMetadata ?? 'Documents, media or ZIP · Up to 20 MB'
        : [
            if (extension.isNotEmpty) extension,
            if (byteSize != null) FileViewerMetadata.formatBytes(byteSize!),
          ].join(' · ');
    final summary = Row(
      children: [
        Container(
          width: 40,
          height: 44,
          decoration: BoxDecoration(
            color: name == null
                ? DefensysTokens.surfaceHigherOf(context)
                : DefensysTokens.maroonOf(context).withValues(alpha: .08),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
          ),
          child: Icon(
            name == null ? LucideIcons.upload : LucideIcons.fileText,
            size: 20,
            color: name == null
                ? secondary
                : DefensysTokens.maroonTextOf(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null) ...[
                Text(
                  label!,
                  style: DefensysTokens.caption.copyWith(color: secondary),
                ),
                const SizedBox(height: 2),
              ],
              Tooltip(
                message: name ?? 'No template attached',
                child: Text(
                  name ?? 'No template attached',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DefensysTokens.body.copyWith(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  metadata,
                  style: DefensysTokens.caption.copyWith(color: secondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final controls = Wrap(
      spacing: 6,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DefensysTokens.backgroundOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Reserve room for a useful filename, including larger text settings.
          final inline =
              constraints.maxWidth >=
              (actions.length > 2 ? 640 : 560) *
                  MediaQuery.textScalerOf(context).scale(12) /
                  12;
          if (inline) {
            return Row(
              children: [
                Expanded(child: summary),
                const SizedBox(width: 20),
                controls,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [summary, const SizedBox(height: 12), controls],
          );
        },
      ),
    );
  }
}

class _TemplateAction extends StatelessWidget {
  const _TemplateAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = ShadButtonVariant.outline,
    this.loading = false,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final ShadButtonVariant variant;
  final bool loading;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final primary = variant == ShadButtonVariant.primary;
    final danger = Theme.of(context).colorScheme.error;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return ShadButton.raw(
      variant: variant,
      size: ShadButtonSize.sm,
      height:
          DefensysTokens.buttonHeightSecondary *
          textScale.clamp(1.0, double.infinity),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      gap: 6,
      textStyle: const TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      enabled: onPressed != null,
      onPressed: onPressed,
      backgroundColor: primary ? DefensysTokens.maroonOf(context) : null,
      hoverBackgroundColor: primary
          ? DefensysTokens.maroonOf(context).withValues(alpha: .9)
          : destructive
          ? danger.withValues(alpha: .08)
          : null,
      foregroundColor: primary
          ? Colors.white
          : destructive
          ? danger
          : null,
      hoverForegroundColor: primary
          ? Colors.white
          : destructive
          ? danger
          : null,
      leading: loading
          ? SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: primary
                    ? Colors.white
                    : DefensysTokens.textSecondaryOf(context),
              ),
            )
          : Icon(icon, size: 14),
      child: Flexible(
        child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _TemplateError extends StatelessWidget {
  const _TemplateError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    ),
  );
}
