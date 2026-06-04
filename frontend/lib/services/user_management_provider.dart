import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';

final userManagementProvider =
    NotifierProvider<UserManagementNotifier, UserManagementState>(
      UserManagementNotifier.new,
    );

class UserManagementState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> guestCodes;
  final List<Map<String, dynamic>> defenseSchedules;
  final Map<String, dynamic> counts;
  final Map<String, dynamic> guestCounts;
  final String search;
  final String role;
  final String? error;
  final String? message;

  const UserManagementState({
    this.isLoading = false,
    this.isSaving = false,
    this.users = const [],
    this.guestCodes = const [],
    this.defenseSchedules = const [],
    this.counts = const {},
    this.guestCounts = const {},
    this.search = '',
    this.role = '',
    this.error,
    this.message,
  });

  UserManagementState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? users,
    List<Map<String, dynamic>>? guestCodes,
    List<Map<String, dynamic>>? defenseSchedules,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? guestCounts,
    String? search,
    String? role,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return UserManagementState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      users: users ?? this.users,
      guestCodes: guestCodes ?? this.guestCodes,
      defenseSchedules: defenseSchedules ?? this.defenseSchedules,
      counts: counts ?? this.counts,
      guestCounts: guestCounts ?? this.guestCounts,
      search: search ?? this.search,
      role: role ?? this.role,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class UserManagementNotifier extends Notifier<UserManagementState> {
  static final String baseUrl = ApiConfig.usersUrl;

  @override
  UserManagementState build() {
    return const UserManagementState();
  }

  void clearNotice() {
    state = state.copyWith(clearMessage: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void showError(String message) {
    state = state.copyWith(isSaving: false, error: message, clearMessage: true);
  }

  Future<void> fetchUsers({
    String? search,
    String? role,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextRole = role ?? state.role;

    state = state.copyWith(
      isLoading: state.users.isEmpty,
      isSaving: false,
      search: nextSearch,
      role: nextRole,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextRole.isNotEmpty) 'role': nextRole,
        },
      );
      final response = await _client.get(uri);

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        _applyPayload(payload, successMessage: successMessage);
        return;
      }

      state = state.copyWith(
        isLoading: false,
        isSaving: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isSaving: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<bool> addUser(Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/'),

        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        await fetchUsers(successMessage: 'User created.');
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> updateUser(int userId, Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$userId/'),

        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchUsers(successMessage: 'User updated.');
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchAdviserAssignmentHistory(
    int userId,
  ) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/$userId/adviser-assignments/'),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return (payload['assignments'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
    } catch (_) {
      // Caller shows empty state on failure.
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> fetchRoleAssignmentHistory(
    int userId,
  ) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/$userId/role-assignments/'),
      );
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return (payload['assignments'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
    } catch (_) {
      // Caller shows empty state on failure.
    }
    return const [];
  }

  Future<bool> deleteUser(int userId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.delete(Uri.parse('$baseUrl/$userId/'));

      if (response.statusCode == 200) {
        await fetchUsers(successMessage: 'User deleted.');
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> bulkImport(
    List<Map<String, dynamic>> rows, {
    Map<String, dynamic>? studentContext,
  }) async {
    if (rows.isEmpty) {
      state = state.copyWith(error: 'CSV has no valid data rows.');
      return false;
    }

    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/bulk-import/'),

        body: jsonEncode({
          'users': rows,
          if (studentContext != null) 'student_context': studentContext,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final created = payload['created_count'] ?? 0;
        final records = payload['records_created_count'] ?? 0;
        final skipped = payload['skipped_count'] ?? 0;
        final errors = payload['error_count'] ?? 0;
        final recordsMessage = records == 0
            ? ''
            : ' $records academic records created.';
        final assignmentMessage = payload['instructor_assignment'] != null
            ? ' PIT Instructor assigned.'
            : '';
        await fetchUsers(
          successMessage:
              '$created users imported.$recordsMessage $skipped skipped. $errors errors.$assignmentMessage',
        );
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> pitLeadStudentImport(
    List<Map<String, dynamic>> rows, {
    Map<String, dynamic>? studentContext,
  }) async {
    if (rows.isEmpty) {
      state = state.copyWith(error: 'CSV has no valid student rows.');
      return false;
    }

    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/pit-lead/student-import/'),
        body: jsonEncode({
          'users': rows,
          if (studentContext != null) 'student_context': studentContext,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final created = payload['created_count'] ?? 0;
        final records = payload['records_created_count'] ?? 0;
        final skipped = payload['skipped_count'] ?? 0;
        final errors = payload['error_count'] ?? 0;
        final recordsMessage = records == 0
            ? ''
            : ' $records academic records created.';
        state = state.copyWith(
          isSaving: false,
          message:
              '$created students imported.$recordsMessage $skipped skipped. $errors errors.',
          clearError: true,
        );
        return errors == 0;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<bool> pitLeadOfficialClassListImport({
    required Map<String, dynamic> metadata,
    required List<Map<String, dynamic>> students,
  }) async {
    if (students.isEmpty) {
      state = state.copyWith(error: 'Class list has no valid student rows.');
      return false;
    }

    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/pit-lead/official-class-list-import/'),
        body: jsonEncode({'metadata': metadata, 'students': students}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final created = payload['created_count'] ?? 0;
        final updated = payload['updated_count'] ?? 0;
        final recordsCreated = payload['records_created_count'] ?? 0;
        final recordsUpdated = payload['records_updated_count'] ?? 0;
        final errors = payload['error_count'] ?? 0;
        final warnings = payload['warning_count'] ?? 0;
        final assignment = payload['instructor_assignment'] != null
            ? ' PIT Instructor assigned.'
            : '';
        state = state.copyWith(
          isSaving: false,
          message:
              '$created students created. $updated updated. '
              '$recordsCreated records created. $recordsUpdated records updated. '
              '$warnings warnings. $errors errors.$assignment',
          clearError: true,
        );
        return errors == 0;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Future<void> fetchGuestCodes({String? successMessage}) async {
    state = state.copyWith(clearError: true);

    try {
      final response = await _client.get(Uri.parse('$baseUrl/guest-codes/'));

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        _applyGuestPayload(payload, successMessage: successMessage);
        return;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
    }
  }

  Future<Map<String, dynamic>?> generateGuestCode(
    Map<String, dynamic> payload,
  ) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/guest-codes/'),

        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        final responsePayload = Map<String, dynamic>.from(
          jsonDecode(response.body),
        );
        _applyGuestPayload(
          responsePayload,
          successMessage: 'Guest panelist code generated.',
        );
        final guestCode = responsePayload['guest_code'];
        if (guestCode is Map) {
          return Map<String, dynamic>.from(guestCode);
        }
        return null;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return null;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return null;
    }
  }

  Future<bool> revokeGuestCode(int codeId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/guest-codes/$codeId/'),

        body: jsonEncode({'is_active': false}),
      );

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        _applyGuestPayload(payload, successMessage: 'Guest code revoked.');
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      users: _readMapList(payload['users']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : state.counts,
      message: successMessage,
      clearError: true,
    );
  }

  void _applyGuestPayload(
    Map<String, dynamic> payload, {
    String? successMessage,
  }) {
    state = state.copyWith(
      isSaving: false,
      guestCodes: _readMapList(payload['guest_codes']),
      defenseSchedules: _readMapList(payload['defense_schedules']),
      guestCounts: payload['guest_counts'] is Map
          ? Map<String, dynamic>.from(payload['guest_counts'])
          : state.guestCounts,
      message: successMessage,
      clearError: true,
    );
  }

  List<Map<String, dynamic>> _readMapList(dynamic value) {
    if (value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _errorFromResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        if (data['detail'] != null) {
          return data['detail'].toString();
        }
        if (data.isNotEmpty) {
          final firstValue = data.values.first;
          if (firstValue is List && firstValue.isNotEmpty) {
            return firstValue.first.toString();
          }
          return firstValue.toString();
        }
      }
    } catch (_) {
      return 'Request failed. Status: ${response.statusCode}';
    }

    return 'Request failed. Status: ${response.statusCode}';
  }
}
