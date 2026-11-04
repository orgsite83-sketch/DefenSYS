import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_provider.dart';
import '../../services/app/app_navigator.dart';
import '../../services/app/unsaved_changes_provider.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../services/updates/update_service.dart';
import '../../services/updates/update_activity.dart';
import '../../services/updates/update_platform.dart';
import '../../theme/defensys_tokens.dart';
import '../repository/deliverable_requirement_card.dart';
import '../shadcn/defensys_shadcn_scope.dart';

final refreshReleaseProvider = Provider<void Function(String)>(
  (ref) => refreshWebRelease,
);

/// Conservative fallback for editors with a local guard rather than the shared
/// dirty provider. Never treat a quiet network as proof that a form is saved.
bool hasOpenUpdateWork(Element root) {
  bool found = false;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Form ||
        widget is EditableText && !widget.readOnly ||
        widget is PopScope && !widget.canPop ||
        widget is DeliverablePopupActivity && widget.busy.value) {
      found = true;
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found;
}

bool hasBusyUpdateWork(Element root) {
  var busy = false;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is DeliverablePopupActivity && widget.busy.value) busy = true;
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return busy;
}

class AppUpdateHost extends ConsumerStatefulWidget {
  const AppUpdateHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AppUpdateHost> createState() => _AppUpdateHostState();
}

class _AppUpdateHostState extends ConsumerState<AppUpdateHost>
    with WidgetsBindingObserver {
  Timer? timer;
  Object? userId;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (foreground) {
      timer = Timer.periodic(const Duration(minutes: 5), (_) => check());
    }
  }

  void check() {
    if (mounted && foreground && ref.read(authProvider).user != null) {
      ref.read(appUpdateProvider.notifier).check();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    schedule();
    if (foreground) check();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get busy =>
      apiWriteActivity.value > 0 ||
      ref.read(capstoneDeliverablesProvider).isSaving ||
      hasBusyUpdateWork(context as Element);
  Future<void> act(UpdateState state) async {
    if (state.latest == null || busy) return;
    if (state.current?.isWeb != true) {
      final url = state.latest!.download;
      try {
        if (url != null &&
            await launchUrl(url, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {
        // Keep the current workspace intact if Android cannot open the URL.
      }
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          rootNavigatorKey.currentContext ?? context,
        )?.showSnackBar(
          const SnackBar(
            content: Text('Could not open the download. Try again.'),
          ),
        );
      }
      return;
    }
    final dirty =
        ref.read(unsavedChangesProvider) ||
        hasOpenUpdateWork(context as Element);
    if (dirty) {
      final dialogContext = rootNavigatorKey.currentContext;
      if (dialogContext == null) return;
      final discard = await showDialog<bool>(
        context: dialogContext,
        builder: (context) => DefensysShadcnScope(
          child: ShadDialog(
            actionsAxis: Axis.vertical,
            title: const Text('Refresh with an open editor?'),
            description: const Text(
              'Save and close your work first. Refreshing can discard unsaved changes.',
            ),
            actions: [
              ShadButton.outline(
                width: double.infinity,
                expands: true,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              ShadButton.destructive(
                width: double.infinity,
                expands: true,
                height: 56,
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Discard changes and refresh',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
      if (discard != true || !mounted || busy) return;
    }
    ref.read(refreshReleaseProvider)(state.latest!.id);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(capstoneDeliverablesProvider.select((state) => state.isSaving));
    final user = ref.watch(authProvider).user;
    final identity = user?['id'] ?? user?['username'];
    if (identity != userId) {
      userId = identity;
      WidgetsBinding.instance.addPostFrameCallback((_) => check());
    }
    final state = ref.watch(appUpdateProvider);
    return Column(
      children: [
        if (user != null && state.showPrompt)
          SafeArea(
            bottom: false,
            child: Material(
              color: DefensysTokens.surfaceOf(context),
              child: DefensysShadcnScope(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ValueListenableBuilder<int>(
                    valueListenable: apiWriteActivity,
                    builder: (context, writes, _) => Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          state.current!.isWeb
                              ? 'A new version of DefenSYS is available.'
                              : 'A new Android version is available.',
                        ),
                        ShadButton(
                          size: ShadButtonSize.sm,
                          enabled: !busy,
                          onPressed: () => act(state),
                          child: Text(
                            state.current!.isWeb
                                ? 'Refresh'
                                : 'Download update',
                          ),
                        ),
                        ShadButton.ghost(
                          size: ShadButtonSize.sm,
                          onPressed: () =>
                              ref.read(appUpdateProvider.notifier).dismiss(),
                          child: const Text('Later'),
                        ),
                        if (busy)
                          const Text(
                            'Finish saving or uploading before updating.',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class AppVersionSettings extends ConsumerWidget {
  const AppVersionSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(runningReleaseProvider);
    final state = ref.watch(appUpdateProvider);
    final running = current.asData?.value;
    return DefensysShadcnScope(
      child: ShadCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'App version',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              running == null
                  ? current.hasError
                        ? 'Version unavailable'
                        : 'Reading version…'
                  : '${running.version} · Build ${running.build} · ${running.isWeb ? 'Web app' : 'Android app'}',
            ),
            if (state.checkedAt != null)
              Text(
                'Last checked: ${TimeOfDay.fromDateTime(state.checkedAt!.toLocal()).format(context)}',
                style: TextStyle(
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            if (state.error != null) Text(state.error!),
            if (state.available)
              Text(
                'Version ${state.latest!.version} · Build ${state.latest!.build} is available.',
              ),
            if (state.upToDate) const Text('Already up to date'),
            if (!state.checking &&
                state.checkedAt != null &&
                state.latest == null &&
                state.error == null)
              const Text(
                'No published release is available for this platform.',
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.outline(
                width: double.infinity,
                expands: true,
                size: ShadButtonSize.sm,
                enabled: !state.checking,
                onPressed: () =>
                    ref.read(appUpdateProvider.notifier).check(manual: true),
                child: Text(
                  state.checking ? 'Checking…' : 'Check for updates',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 13,
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
