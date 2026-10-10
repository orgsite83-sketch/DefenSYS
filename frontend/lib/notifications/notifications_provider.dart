import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../services/auth_provider.dart';
import '../services/authenticated_client.dart';

final notificationsProvider = NotifierProvider.autoDispose
    .family<NotificationsNotifier, NotificationsState, String>(
      NotificationsNotifier.new,
    );

class NotificationsState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool isSaving;
  final bool unreadOnly;
  final List<Map<String, dynamic>> notifications;
  final int unreadCount;
  final int totalCount;
  final int? nextPage;
  final String? error;

  const NotificationsState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isSaving = false,
    this.unreadOnly = false,
    this.notifications = const [],
    this.unreadCount = 0,
    this.totalCount = 0,
    this.nextPage,
    this.error,
  });

  NotificationsState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSaving,
    bool? unreadOnly,
    List<Map<String, dynamic>>? notifications,
    int? unreadCount,
    int? totalCount,
    int? nextPage,
    String? error,
    bool clearError = false,
    bool clearNextPage = false,
  }) => NotificationsState(
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    isSaving: isSaving ?? this.isSaving,
    unreadOnly: unreadOnly ?? this.unreadOnly,
    notifications: notifications ?? this.notifications,
    unreadCount: unreadCount ?? this.unreadCount,
    totalCount: totalCount ?? this.totalCount,
    nextPage: clearNextPage ? null : nextPage ?? this.nextPage,
    error: clearError ? null : error ?? this.error,
  );
}

class NotificationsNotifier extends Notifier<NotificationsState> {
  NotificationsNotifier(this.workspace);
  final String workspace;
  int _epoch = 0;
  int _request = 0;

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  @override
  NotificationsState build() {
    // A new login must never inherit cached inbox contents or an old response.
    final userId = ref.watch(authProvider.select((s) => s.user?['id']));
    final epoch = ++_epoch;
    if (userId != null) {
      Timer? timer;
      void startPolling() {
        timer?.cancel();
        timer = Timer.periodic(const Duration(seconds: 60), (_) {
          if (ref.mounted &&
              epoch == _epoch &&
              !state.isLoading &&
              !state.isLoadingMore &&
              !state.isSaving &&
              state.notifications.length <= 20 &&
              (WidgetsBinding.instance.lifecycleState == null ||
                  WidgetsBinding.instance.lifecycleState ==
                      AppLifecycleState.resumed)) {
            fetchNotifications();
          }
        });
      }

      startPolling();
      ref.onCancel(() => timer?.cancel());
      ref.onResume(startPolling);
      ref.onDispose(() => timer?.cancel());
      Future.microtask(() {
        if (ref.mounted && epoch == _epoch) fetchNotifications();
      });
    }
    return const NotificationsState(isLoading: true);
  }

  Uri _uri([String suffix = '', Map<String, String> params = const {}]) =>
      Uri.parse(
        '${ApiConfig.notificationsUrl}$suffix',
      ).replace(queryParameters: {'workspace': workspace, ...params});

  bool _current(int epoch, int request) =>
      ref.mounted && epoch == _epoch && request == _request;

  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {
    if (state.isSaving ||
        (loadMore &&
            (state.nextPage == null ||
                state.isLoadingMore ||
                state.isLoading))) {
      return;
    }
    final filter = unreadOnly ?? state.unreadOnly;
    final changed = filter != state.unreadOnly;
    final page = loadMore ? state.nextPage! : 1;
    final epoch = _epoch;
    final request = ++_request;
    state = state.copyWith(
      isLoading: !loadMore && (changed || state.notifications.isEmpty),
      isLoadingMore: loadMore,
      unreadOnly: filter,
      notifications: changed ? [] : null,
      clearNextPage: changed,
      clearError: true,
    );
    try {
      final response = await _client.get(
        _uri('', {'page': '$page', if (filter) 'unread': 'true'}),
      );
      if (!_current(epoch, request)) return;
      if (response.statusCode != 200) {
        throw Exception(_errorFromResponse(response));
      }
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      final incoming = List<Map<String, dynamic>>.from(
        data['notifications'] ?? [],
      );
      final items = <int, Map<String, dynamic>>{
        if (loadMore)
          for (final n in state.notifications) n['id'] as int: n,
        for (final n in incoming) n['id'] as int: n,
      }.values.toList();
      final next = data['next'] == null
          ? null
          : int.tryParse(
              Uri.parse(data['next'].toString()).queryParameters['page'] ?? '',
            );
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        notifications: items,
        unreadCount: data['unread_count'] as int? ?? 0,
        totalCount:
            data['total_count'] as int? ??
            data['count'] as int? ??
            items.length,
        nextPage: next,
        clearNextPage: next == null,
      );
    } catch (_) {
      if (_current(epoch, request)) {
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: 'Could not load notifications. Please try again.',
        );
      }
    }
  }

  Future<bool> markAsRead(int notificationId) async {
    if (state.isSaving) return false;
    final item = state.notifications
        .where((n) => n['id'] == notificationId)
        .firstOrNull;
    if (item == null) return false;
    if (item['is_read'] == true) return true;
    final epoch = _epoch;
    final request = ++_request;
    state = state.copyWith(
      isSaving: true,
      isLoading: false,
      isLoadingMore: false,
      clearError: true,
    );
    try {
      final response = await _client.post(
        _uri('/$notificationId/read/'),
        body: jsonEncode({}),
      );
      if (!_current(epoch, request)) return false;
      if (response.statusCode != 200) {
        throw Exception(_errorFromResponse(response));
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      state = state.copyWith(
        isSaving: false,
        notifications: [
          for (final n in state.notifications)
            if (n['id'] != notificationId || !state.unreadOnly)
              n['id'] == notificationId
                  ? {
                      ...n,
                      if (data['notification'] is Map)
                        ...Map<String, dynamic>.from(data['notification']),
                      'is_read': true,
                    }
                  : n,
        ],
        // This is the server's whole-inbox count, not the unread rows on page one.
        unreadCount:
            data['unread_count'] as int? ??
            (state.unreadCount - 1).clamp(0, state.unreadCount),
      );
      return true;
    } catch (_) {
      if (_current(epoch, request)) {
        state = state.copyWith(
          isSaving: false,
          error: 'Could not mark the notification as read. Please try again.',
        );
      }
      return false;
    }
  }

  /// Recheck a workflow immediately before opening it, including read alerts.
  Future<Map<String, dynamic>?> refreshNotification(int id) async {
    if (state.isSaving) return null;
    final epoch = _epoch;
    final request = ++_request;
    state = state.copyWith(
      isSaving: true,
      isLoading: false,
      isLoadingMore: false,
      clearError: true,
    );
    try {
      final response = await _client.get(_uri('/$id/'));
      if (!_current(epoch, request)) return null;
      if (response.statusCode != 200) {
        throw Exception(_errorFromResponse(response));
      }
      final item = Map<String, dynamic>.from(
        (jsonDecode(response.body) as Map)['notification'],
      );
      state = state.copyWith(
        isSaving: false,
        notifications: [
          for (final n in state.notifications) n['id'] == id ? item : n,
        ],
      );
      return item;
    } catch (_) {
      if (_current(epoch, request)) {
        state = state.copyWith(
          isSaving: false,
          error: 'Could not check this action. Please try again.',
        );
      }
      return null;
    }
  }

  Future<bool> markAllAsRead() async {
    if (state.isSaving) return false;
    final epoch = _epoch;
    final request = ++_request;
    state = state.copyWith(
      isSaving: true,
      isLoading: false,
      isLoadingMore: false,
      clearError: true,
    );
    try {
      final response = await _client.post(
        _uri('/read-all/'),
        body: jsonEncode({}),
      );
      if (!_current(epoch, request)) return false;
      if (response.statusCode != 200) {
        throw Exception(_errorFromResponse(response));
      }
      state = state.copyWith(
        isSaving: false,
        unreadCount: 0,
        notifications: state.unreadOnly
            ? []
            : [
                for (final n in state.notifications) {...n, 'is_read': true},
              ],
        clearNextPage: state.unreadOnly,
      );
      await fetchNotifications();
      return true;
    } catch (_) {
      if (_current(epoch, request)) {
        state = state.copyWith(
          isSaving: false,
          error: 'Could not mark this inbox as read. Please try again.',
        );
      }
      return false;
    }
  }

  String _errorFromResponse(dynamic response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded.containsKey('detail')) {
        return decoded['detail'].toString();
      }
    } catch (_) {}
    return 'Request failed (${response.statusCode}).';
  }
}
