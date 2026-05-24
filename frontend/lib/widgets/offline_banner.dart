import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n_ext.dart';
import '../services/connectivity_provider.dart';
import '../theme/defensys_tokens.dart';

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
              style: const TextStyle(fontSize: 13),
            ),
            leading: Icon(Icons.wifi_off, color: DefensysTokens.warning),
            backgroundColor: DefensysTokens.warningBg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(child: child),
      ],
    );
  }
}
