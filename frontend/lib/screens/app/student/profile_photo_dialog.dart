import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../config/api_config.dart';
import '../../../services/auth_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';

Future<void> showProfilePhotoDialog(
  BuildContext context, {
  required Future<void> Function() upload,
  required Future<void> Function() remove,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ProfilePhotoDialog(upload: upload, remove: remove),
);

class _ProfilePhotoDialog extends ConsumerStatefulWidget {
  const _ProfilePhotoDialog({required this.upload, required this.remove});
  final Future<void> Function() upload;
  final Future<void> Function() remove;

  @override
  ConsumerState<_ProfilePhotoDialog> createState() =>
      _ProfilePhotoDialogState();
}

class _ProfilePhotoDialogState extends ConsumerState<_ProfilePhotoDialog> {
  String? _pending;

  Future<void> _run(String action, Future<void> Function() operation) async {
    if (_pending != null) return;
    setState(() => _pending = action);
    try {
      await operation();
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = ref.watch(authProvider).user?['avatar']?.toString().trim();
    final hasPhoto = avatar != null && avatar.isNotEmpty;
    final busy = _pending != null;
    return PopScope(
      canPop: !busy,
      child: DefensysShadcnScope(
        maroonActions: true,
        child: ShadDialog(
          title: const Text('Profile photo'),
          constraints: const BoxConstraints(maxWidth: 400),
          closeIcon: Tooltip(
            message: 'Close photo',
            child: ShadButton.ghost(
              width: 32,
              height: 32,
              padding: EdgeInsets.zero,
              foregroundColor: DefensysTokens.textSecondaryOf(context),
              hoverForegroundColor: DefensysTokens.textPrimaryOf(context),
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Icon(Icons.close_rounded, size: 18),
            ),
          ),
          child: SingleChildScrollView(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      width: 176,
                      height: 176,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: DefensysTokens.surfaceHigherOf(context),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: DefensysTokens.borderOf(context),
                        ),
                      ),
                      child: hasPhoto
                          ? Image.network(
                              ApiConfig.publicMediaUrl(avatar),
                              key: const ValueKey('profile-photo-preview'),
                              fit: BoxFit.cover,
                              semanticLabel: 'Current profile photo',
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                  ? child
                                  : const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                              errorBuilder: (_, _, _) => const Center(
                                child: Text('Photo unavailable'),
                              ),
                            )
                          : Icon(
                              Icons.person_outline_rounded,
                              size: 56,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                    ),
                  ),
                  if (!hasPhoto) ...[
                    const SizedBox(height: 16),
                    Text(
                      'No profile photo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 14,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ShadButton(
                    width: double.infinity,
                    onPressed: busy
                        ? null
                        : () => _run('upload', widget.upload),
                    leading: _pending == 'upload'
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.file_upload_outlined, size: 18),
                    child: Text(
                      _pending == 'upload'
                          ? 'Updating…'
                          : hasPhoto
                          ? 'Change photo'
                          : 'Upload photo',
                    ),
                  ),
                  if (hasPhoto) ...[
                    const SizedBox(height: 8),
                    ShadButton.outline(
                      width: double.infinity,
                      foregroundColor: DefensysTokens.maroonTextOf(context),
                      onPressed: busy
                          ? null
                          : () => _run('remove', widget.remove),
                      leading: _pending == 'remove'
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline_rounded, size: 18),
                      child: Text(
                        _pending == 'remove' ? 'Removing…' : 'Remove photo',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
