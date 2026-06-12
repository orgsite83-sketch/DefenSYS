import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import 'authenticated_client.dart';

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationsState>(
      NotificationsNotifier.new,
    );

class NotificationsState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> notifications;
  final int unreadCount;
  final String? error;
  final String? message;

  const NotificationsState({
    this.isLoading = false,
    this.isSaving = false,
    this.notifications = const [],
    this.unreadCount = 0,
    this.error,
    this.message,
  });

  NotificationsState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? notifications,
    int? unreadCount,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return NotificationsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class NotificationsNotifier extends Notifier<NotificationsState> {
  static String get baseUrl => ApiConfig.notificationsUrl;

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);

  @override
  NotificationsState build() {
    return const NotificationsState();
  }

  Future<void> fetchNotifications() async {
    state = state.copyWith(
      isLoading: state.notifications.isEmpty,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.get(Uri.parse(baseUrl));

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));
        final list = List<Map<String, dynamic>>.from(data['notifications'] ?? []);
        final unread = data['unread_count'] as int? ?? 0;

        state = state.copyWith(
          isLoading: false,
          notifications: list,
          unreadCount: unread,
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<bool> markAsRead(int notificationId) async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);

    try {
      final url = '$baseUrl/$notificationId/read/';
      final response = await _client.post(Uri.parse(url), body: {});

      if (response.statusCode == 200) {
        // Update local list state
        final updatedList = state.notifications.map((n) {
          if (n['id'] == notificationId) {
            return {...n, 'is_read': true};
          }
          return n;
        }).toList();

        // Recalculate unread count
        final newUnread = updatedList.where((n) => n['is_read'] != true).length;

        state = state.copyWith(
          isSaving: false,
          notifications: updatedList,
          unreadCount: newUnread,
        );
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: 'Connection error: $e',
      );
      return false;
    }
  }

  Future<bool> markAllAsRead() async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);

    try {
      final url = '$baseUrl/read-all/';
      final response = await _client.post(Uri.parse(url), body: {});

      if (response.statusCode == 200) {
        // Update all locally to read
        final updatedList = state.notifications.map((n) {
          return {...n, 'is_read': true};
        }).toList();

        state = state.copyWith(
          isSaving: false,
          notifications: updatedList,
          unreadCount: 0,
          message: 'All notifications marked as read.',
        );
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: 'Connection error: $e',
      );
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
    return 'Failed with status ${response.statusCode}';
  }
}
