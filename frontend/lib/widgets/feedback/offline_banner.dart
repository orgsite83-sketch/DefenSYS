import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_ext.dart';
import '../../services/connectivity_provider.dart';
import '../../theme/defensys_tokens.dart';

/// Persistent banner shown when [connectivityProvider] reports offline.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider);
    return Column(
      children: [
        if (!online)
          MaterialBanner(
            content: Text(
              context.l10n.offlineBannerMessage,
              style: DefensysTokens.body.copyWith(
                color: DefensysTokens.warningText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            leading: const Icon(Icons.wifi_off_rounded, color: DefensysTokens.warningText, size: 20),
            backgroundColor: DefensysTokens.warningBg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(child: child),
      ],
    );
  }
}
