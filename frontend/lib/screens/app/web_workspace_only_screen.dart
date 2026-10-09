import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_provider.dart';
import '../../utils/guest_invitation.dart';

class WebWorkspaceOnlyScreen extends ConsumerWidget {
  const WebWorkspaceOnlyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portal = Uri.tryParse(guestPortalUrl());
    final address = portal?.replace(fragment: '/login', query: '');
    final canOpen = address != null && address.host.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Web workspace')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.desktop_windows_outlined, size: 48),
                  const SizedBox(height: 20),
                  const Text(
                    'Open your staff workspace in a browser',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Management tools are available in the web app. The phone app supports student work, panelist evaluations and assigned documenter minutes.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (canOpen)
                    FilledButton(
                      onPressed: () async {
                        try {
                          await launchUrl(
                            address,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please open the school’s DefenSYS address in your browser.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('Open web workspace'),
                    ),
                  TextButton(
                    onPressed: () => ref.read(authProvider.notifier).logout(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
