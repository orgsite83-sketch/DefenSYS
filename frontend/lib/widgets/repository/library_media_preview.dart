import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_config.dart';
import '../../models/repository_library.dart';
import '../../services/authenticated_client.dart';
import '../../services/auth_provider.dart';
import '../../theme/defensys_tokens.dart';

final libraryPreviewBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, (String, String)>((ref, target) async {
      // Watch the authenticated client so identity changes discard these bytes.
      ref.watch(authProvider.select((auth) => (auth.token, auth.user?['id'])));
      final client = ref.watch(authenticatedHttpClientProvider);
      final uri = Uri.parse('${ApiConfig.repositoryUrl}preview/').replace(
        queryParameters: {'target_id': target.$1, 'revision': target.$2},
      );
      final response = await client.get(uri);
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').startsWith('image/')) {
        return null;
      }
      return response.bodyBytes;
    });

class LibraryMediaPreview extends ConsumerWidget {
  const LibraryMediaPreview({super.key, required this.entry});
  final VaultEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final previewable =
        entry.isImage || entry.isPdf || entry.outputKind == 'video';
    final preview = previewable && entry.fileUrl?.isNotEmpty == true
        ? ref.watch(
            libraryPreviewBytesProvider((
              entry.id,
              '${entry.timestamp}:${entry.fileUrl}',
            )),
          )
        : null;
    Widget fallback() => Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            entry.outputKind == 'video'
                ? Icons.smart_display_outlined
                : entry.outputKind == 'poster' || entry.isImage
                ? Icons.image_outlined
                : entry.extension == 'zip'
                ? Icons.folder_zip_outlined
                : const ['ppt', 'pptx'].contains(entry.extension)
                ? Icons.slideshow_outlined
                : Icons.insert_drive_file_outlined,
            size: 36,
            color: DefensysTokens.maroonTextOf(context),
          ),
          const SizedBox(height: 10),
          Text(
            entry.outputLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DefensysTokens.body.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            entry.extension.toUpperCase(),
            style: DefensysTokens.caption.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      image: true,
      label: '${entry.outputLabel} preview for ${entry.displayTitle}',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: DefensysTokens.borderOf(context)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            preview?.when(
                  data: (bytes) => bytes == null
                      ? fallback()
                      : Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => fallback(),
                        ),
                  loading: () => fallback(),
                  error: (_, _) => fallback(),
                ) ??
                fallback(),
            if (entry.outputKind == 'video' && preview?.asData?.value != null)
              const Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xB3000000),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
