import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'jwt_utils.dart';
import 'session_keepalive_stub.dart'
    if (dart.library.html) 'session_keepalive_web.dart' as visibility;

/// Keeps JWT access fresh while the user is away from the tab (visible, signed in).
class SessionKeepaliveHost extends ConsumerStatefulWidget {
  const SessionKeepaliveHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionKeepaliveHost> createState() => _SessionKeepaliveHostState();
}

class _SessionKeepaliveHostState extends ConsumerState<SessionKeepaliveHost>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      visibility.onBrowserTabVisible(_maybeRefresh);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTimer());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, __) => _syncTimer());
    return widget.child;
  }

  void _syncTimer() {
    _timer?.cancel();
    final auth = ref.read(authProvider);
    if (auth.token == null || auth.user == null || auth.isRestoring) {
      return;
    }
    if (auth.user?['role'] == 'guest_panelist') {
      return;
    }
    _timer = Timer.periodic(const Duration(minutes: 12), (_) => _maybeRefresh());
  }

  Future<void> _maybeRefresh() async {
    final auth = ref.read(authProvider);
    if (auth.isRestoring || auth.token == null) return;
    if (auth.user?['role'] == 'guest_panelist') return;
    if (!shouldRefreshAccess(auth.token)) return;
    await ref.read(authProvider.notifier).refreshTokens(silent: true);
  }
}
