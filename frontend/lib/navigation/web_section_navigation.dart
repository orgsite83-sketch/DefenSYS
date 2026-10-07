import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Explicitly discarding a form resets that section without clearing other tabs.
class WebSectionState extends ChangeNotifier {
  final Map<String, int> _generations = {};

  int generation(String path) => _generations[path] ?? 0;

  void reset(String path) {
    _generations[path] = generation(path) + 1;
    notifyListeners();
  }
}

class WebSectionStateScope extends InheritedNotifier<WebSectionState> {
  const WebSectionStateScope({
    required super.notifier,
    required super.child,
    super.key,
  });

  static int generationOf(BuildContext context, String path) =>
      context
          .dependOnInheritedWidgetOfExactType<WebSectionStateScope>()
          ?.notifier
          ?.generation(path) ??
      0;
}

/// No periodic timers: data is reconsidered only when a section is activated.
class WebSectionRefreshGate {
  WebSectionRefreshGate({
    this.cooldown = const Duration(seconds: 45),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration cooldown;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastRefresh = {};

  bool activate(String section) {
    final now = _now();
    final previous = _lastRefresh[section];
    if (previous == null) {
      _lastRefresh[section] = now;
      return false; // The root screen already performs its initial fetch.
    }
    if (now.difference(previous) < cooldown) return false;
    _lastRefresh[section] = now;
    return true;
  }
}

/// Sidebar navigation resumes a section; explicit links still use go/push.
/// Branches are lazy (preload stays false), so unvisited screens do no work.
bool resumeWebSection(
  StatefulNavigationShell? shell,
  String rootPath, {
  bool initialLocation = false,
}) {
  if (shell == null) return false;
  final branches = shell.route.branches;
  final index = branches.indexWhere(
    (branch) => branch.initialLocation == rootPath,
  );
  if (index < 0) return false;
  shell.goBranch(index, initialLocation: initialLocation);
  return true;
}
