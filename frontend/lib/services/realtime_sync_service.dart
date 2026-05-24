import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import 'auth_provider.dart';
import 'dashboard_provider.dart';
import 'jwt_utils.dart';

enum RealtimeConnectionState { disconnected, connecting, connected }

final realtimeSyncServiceProvider =
    NotifierProvider<RealtimeSyncNotifier, RealtimeConnectionState>(
  RealtimeSyncNotifier.new,
);

class RealtimeSyncNotifier extends Notifier<RealtimeConnectionState> {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _fallbackPollTimer;
  DateTime? _disconnectedSince;
  int _reconnectAttempt = 0;
  String? _activeRole;

  @override
  RealtimeConnectionState build() {
    ref.onDispose(_disconnect);
    return RealtimeConnectionState.disconnected;
  }

  void connect({required String? role}) {
    _activeRole = role;
    if (role != 'student') {
      _disconnect();
      return;
    }
    _connectInternal();
  }

  void disconnect() {
    _activeRole = null;
    _disconnect();
  }

  Future<void> _connectInternal() async {
    if (_activeRole != 'student') return;

    final auth = ref.read(authProvider);
    final token = auth.token;
    if (token == null || token.isEmpty) {
      _disconnect();
      return;
    }

    _reconnectTimer?.cancel();
    state = RealtimeConnectionState.connecting;

    try {
      await _openSocket(token);
      _reconnectAttempt = 0;
      _disconnectedSince = null;
      _stopFallbackPoll();
      state = RealtimeConnectionState.connected;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('RealtimeSync: connect failed: $e');
      }
      state = RealtimeConnectionState.disconnected;
      _disconnectedSince ??= DateTime.now();
      _scheduleReconnect();
      _maybeStartFallbackPoll();
    }
  }

  Future<void> _openSocket(String token) async {
    await _subscription?.cancel();
    await _channel?.sink.close();

    final uri = ApiConfig.webSocketGradingUri(token);
    _channel = WebSocketChannel.connect(uri);
    _subscription = _channel!.stream.listen(
      _onMessage,
      onError: (_) => _handleDisconnect(),
      onDone: _handleDisconnect,
      cancelOnError: true,
    );
  }

  void _onMessage(dynamic raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final data = jsonDecode(text);
      if (data is! Map) return;
      if (data['event'] != 'grading.flags_changed') return;

      ref.read(dashboardProvider('student').notifier).fetchDashboardData(
            silent: true,
          );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('RealtimeSync: bad message: $e');
      }
    }
  }

  void _handleDisconnect() {
    if (state == RealtimeConnectionState.disconnected &&
        _disconnectedSince != null) {
      return;
    }
    state = RealtimeConnectionState.disconnected;
    _disconnectedSince ??= DateTime.now();
    _scheduleReconnect();
    _maybeStartFallbackPoll();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_activeRole != 'student') return;

    final delaySeconds = (1 << _reconnectAttempt.clamp(0, 5)).clamp(1, 32);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      final auth = ref.read(authProvider);
      var token = auth.token;
      if (token != null && shouldRefreshAccess(token)) {
        await ref.read(authProvider.notifier).refreshTokens(silent: true);
        token = ref.read(authProvider).token;
      }
      if (token == null || token.isEmpty) return;
      await _connectInternal();
    });
  }

  void _maybeStartFallbackPoll() {
    if (_fallbackPollTimer != null) return;
    if (_activeRole != 'student') return;

    _fallbackPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final since = _disconnectedSince;
      if (since == null) return;
      if (DateTime.now().difference(since) < const Duration(seconds: 10)) {
        return;
      }
      if (state == RealtimeConnectionState.connected) {
        _stopFallbackPoll();
        return;
      }
      ref.read(dashboardProvider('student').notifier).fetchDashboardData(
            silent: true,
          );
    });
  }

  void _stopFallbackPoll() {
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = null;
  }

  void _disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopFallbackPoll();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _disconnectedSince = null;
    _reconnectAttempt = 0;
    state = RealtimeConnectionState.disconnected;
  }
}

/// Starts/stops WebSocket sync based on auth state.
class RealtimeSyncHost extends ConsumerStatefulWidget {
  const RealtimeSyncHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RealtimeSyncHost> createState() => _RealtimeSyncHostState();
}

class _RealtimeSyncHostState extends ConsumerState<RealtimeSyncHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, __) => _sync());
    return widget.child;
  }

  void _sync() {
    final auth = ref.read(authProvider);
    final notifier = ref.read(realtimeSyncServiceProvider.notifier);
    if (auth.isRestoring) return;
    if (auth.token != null && auth.user != null) {
      notifier.connect(role: auth.user!['role']?.toString());
    } else {
      notifier.disconnect();
    }
  }
}
