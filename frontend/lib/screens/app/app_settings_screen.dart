import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_distribution_config.dart';
import '../../navigation/workspace_access.dart';
import '../../services/auth_provider.dart';
import '../../services/installation/app_installation.dart';
import '../../services/theme_provider.dart';
import '../../theme/defensys_tokens.dart';

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({
    super.key,
    this.installation,
    this.androidDownloadUrl,
  });
  final AppInstallation? installation;
  final String? androidDownloadUrl;

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  late final AppInstallation _installation;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _installation = widget.installation ?? createAppInstallation();
    _installation.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _installation.removeListener(_changed);
    if (widget.installation == null) _installation.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    final outcome = await _installation.install();
    if (!mounted) return;
    setState(() => _installing = false);
    if (outcome == 'unavailable') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use your browser menu to install DefenSYS or add it to your home screen.',
          ),
        ),
      );
    }
  }

  Future<void> _download(Uri uri) async {
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      )) {
        return;
      }
    } catch (_) {
      /* Keep the browser workspace usable if launching fails. */
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open the download. Please try again or contact your coordinator.',
          ),
        ),
      );
    }
  }

  Widget _section(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: DefensysTokens.panelOf(context),
      border: Border.all(color: DefensysTokens.borderOf(context)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  Widget _step(int number, String title, String detail) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: DefensysTokens.surfaceHigherOf(context),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 13,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user ?? {};
    final status = _installation.state;
    final download = AppDistributionConfig.androidDownload(
      value:
          widget.androidDownloadUrl ?? AppDistributionConfig.androidDownloadUrl,
    );
    final themeMode = ref.watch(themeModeProvider);
    final eligible = WorkspaceAccess.canUsePhone(user);
    final ios = status.platform == InstallPlatform.ios;
    return Scaffold(
      backgroundColor: DefensysTokens.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to workspace',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(WorkspaceAccess.home(user));
            }
          },
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _section('Appearance', [
                  DropdownButtonFormField<ThemeMode>(
                    isExpanded: true,
                    initialValue: themeMode,
                    decoration: const InputDecoration(
                      labelText: 'Theme',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('Use device setting'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Light'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Dark'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(themeModeProvider.notifier)
                            .setThemeMode(value);
                      }
                    },
                  ),
                ]),
                if (eligible && status.isWeb && !status.installed)
                  _section('Get DefenSYS on your phone', [
                    Text(
                      'Open your workspace from your home screen. Your account, teams and evaluations stay the same.',
                      style: TextStyle(
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!ios && download != null) ...[
                      const Text(
                        'Android app',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Download the Android app, open the APK and follow your phone’s installation instructions.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _download(download),
                        icon: const Icon(Icons.android),
                        label: const Text('Download Android app'),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(),
                      ),
                    ],
                    Text(
                      ios
                          ? 'Add to Home Screen on iPhone'
                          : 'Install the web app',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (ios) ...[
                      _step(
                        1,
                        'Open DefenSYS in Safari',
                        'Use the same address you use to sign in.',
                      ),
                      _step(
                        2,
                        'Tap Share, then Add to Home Screen',
                        'If it is hidden, choose Edit Actions to add it to the Share menu.',
                      ),
                      _step(
                        3,
                        'Turn on Open as Web App, then tap Add',
                        'Open the DefenSYS icon and sign in. You may need to sign in once more.',
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Keep the browser version as an app with its own icon and window.',
                      ),
                      const SizedBox(height: 12),
                      if (status.canPrompt)
                        FilledButton.icon(
                          onPressed: _installing ? null : _install,
                          icon: const Icon(Icons.install_mobile),
                          label: Text(
                            _installing
                                ? 'Opening install…'
                                : 'Install DefenSYS',
                          ),
                        )
                      else
                        _step(
                          1,
                          'Open your browser menu',
                          'Choose Install app or Add to Home Screen when available.',
                        ),
                      if (!status.secure)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'You can use this local address in your browser. Full web app installation is available on the school’s secure web address.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      if (status.platform == InstallPlatform.desktop)
                        _step(
                          2,
                          'Using an iPhone?',
                          'Open this address in Safari, tap Share → Add to Home Screen, turn on Open as Web App and tap Add.',
                        ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'An internet or school network connection is required to load and save your work.',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ]),
                if (eligible && (!status.isWeb || status.installed))
                  _section('DefenSYS app', [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('You’re using the app'),
                      subtitle: Text('Your workspace is ready on this device.'),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
