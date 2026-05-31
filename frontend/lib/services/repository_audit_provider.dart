import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';
import '../utils/progress_upload.dart';

final repositoryAuditProvider =
    NotifierProvider<RepositoryAuditNotifier, RepositoryAuditState>(
      RepositoryAuditNotifier.new,
    );

class RepositoryAuditState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> counts;
  final Map<String, dynamic> options;
  final Map<String, dynamic> scope;
  final Map<String, dynamic> uploadWindow;
  final Map<String, dynamic> capstoneUploadWindow;
  final String search;
  final String type;
  final String yearLevel;
  final String academicYear;
  final String status;
  final String semester;
  final String teamId;
  final String stage;
  final String deliverableId;
  final String submissionKind;
  final String viewMode;
  final List<Map<String, dynamic>> groupedByStage;
  final Map<String, dynamic> deliverableSummary;
  final String? error;
  final String? message;
  final List<Map<String, dynamic>> lastUploadSkipped;
  final double uploadProgress;

  const RepositoryAuditState({
    this.isLoading = false,
    this.isSaving = false,
    this.entries = const [],
    this.counts = const {},
    this.options = const {},
    this.scope = const {},
    this.uploadWindow = const {},
    this.capstoneUploadWindow = const {},
    this.search = '',
    this.type = '',
    this.yearLevel = '',
    this.academicYear = '',
    this.status = '',
    this.semester = '',
    this.teamId = '',
    this.stage = '',
    this.deliverableId = '',
    this.submissionKind = '',
    this.viewMode = '',
    this.groupedByStage = const [],
    this.deliverableSummary = const {},
    this.error,
    this.message,
    this.lastUploadSkipped = const [],
    this.uploadProgress = 0.0,
  });

  RepositoryAuditState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? entries,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? options,
    Map<String, dynamic>? scope,
    Map<String, dynamic>? uploadWindow,
    Map<String, dynamic>? capstoneUploadWindow,
    String? search,
    String? type,
    String? yearLevel,
    String? academicYear,
    String? status,
    String? semester,
    String? teamId,
    String? stage,
    String? deliverableId,
    String? submissionKind,
    String? viewMode,
    List<Map<String, dynamic>>? groupedByStage,
    Map<String, dynamic>? deliverableSummary,
    String? error,
    String? message,
    List<Map<String, dynamic>>? lastUploadSkipped,
    double? uploadProgress,
    bool clearError = false,
    bool clearMessage = false,
    bool clearLastUploadSkipped = false,
  }) {
    return RepositoryAuditState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      entries: entries ?? this.entries,
      counts: counts ?? this.counts,
      options: options ?? this.options,
      scope: scope ?? this.scope,
      uploadWindow: uploadWindow ?? this.uploadWindow,
      capstoneUploadWindow: capstoneUploadWindow ?? this.capstoneUploadWindow,
      search: search ?? this.search,
      type: type ?? this.type,
      yearLevel: yearLevel ?? this.yearLevel,
      academicYear: academicYear ?? this.academicYear,
      status: status ?? this.status,
      semester: semester ?? this.semester,
      teamId: teamId ?? this.teamId,
      stage: stage ?? this.stage,
      deliverableId: deliverableId ?? this.deliverableId,
      submissionKind: submissionKind ?? this.submissionKind,
      viewMode: viewMode ?? this.viewMode,
      groupedByStage: groupedByStage ?? this.groupedByStage,
      deliverableSummary: deliverableSummary ?? this.deliverableSummary,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
      lastUploadSkipped: clearLastUploadSkipped
          ? const []
          : lastUploadSkipped ?? this.lastUploadSkipped,
      uploadProgress: uploadProgress ?? this.uploadProgress,
    );
  }
}

class UploadPitResult {
  final bool savedAny;
  final int createdCount;
  final List<Map<String, dynamic>> skipped;

  const UploadPitResult({
    required this.savedAny,
    required this.createdCount,
    required this.skipped,
  });
}

class RepositoryAuditNotifier extends Notifier<RepositoryAuditState> {
    static String get baseUrl => ApiConfig.repositoryAuditUrl;

  @override
  RepositoryAuditState build() {
    return const RepositoryAuditState();
  }

  Future<void> fetchEntries({
    String? search,
    String? type,
    String? yearLevel,
    String? academicYear,
    String? status,
    String? semester,
    String? teamId,
    String? stage,
    String? deliverableId,
    String? submissionKind,
    String? viewMode,
    String? successMessage,
    bool clearDeliverable = false,
    bool clearTeam = false,
  }) async {
    final nextSearch = search ?? state.search;
    final nextType = type ?? state.type;
    final nextYearLevel = yearLevel ?? state.yearLevel;
    final nextAcademicYear = academicYear ?? state.academicYear;
    final nextStatus = status ?? state.status;
    final nextSemester = semester ?? state.semester;
    final nextTeamId = clearTeam ? '' : (teamId ?? state.teamId);
    final nextStage = stage ?? state.stage;
    final nextDeliverableId =
        clearDeliverable ? '' : (deliverableId ?? state.deliverableId);
    final nextSubmissionKind = submissionKind ?? state.submissionKind;
    var nextViewMode = viewMode ?? state.viewMode;
    if (nextDeliverableId.isNotEmpty) {
      nextViewMode = 'deliverable';
    } else if (nextTeamId.isNotEmpty) {
      nextViewMode = 'team';
    } else {
      nextViewMode = '';
    }

    state = state.copyWith(
      isLoading: state.entries.isEmpty,
      isSaving: false,
      search: nextSearch,
      type: nextType,
      yearLevel: nextYearLevel,
      academicYear: nextAcademicYear,
      status: nextStatus,
      semester: nextSemester,
      teamId: nextTeamId,
      stage: nextStage,
      deliverableId: nextDeliverableId,
      submissionKind: nextSubmissionKind,
      viewMode: nextViewMode,
      clearError: true,
      clearMessage: true,
      clearLastUploadSkipped: true,
    );

    try {
      final response = await _client.get(
        _uri(
          '',
          search: nextSearch,
          type: nextType,
          yearLevel: nextYearLevel,
          academicYear: nextAcademicYear,
          status: nextStatus,
          semester: nextSemester,
          teamId: nextTeamId,
          stage: nextStage,
          deliverableId: nextDeliverableId,
          submissionKind: nextSubmissionKind,
          viewMode: nextViewMode,
        ),
        
      );

      if (response.statusCode == 200) {
        _applyPayload(
          Map<String, dynamic>.from(jsonDecode(response.body)),
          successMessage: successMessage,
        );
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

  Future<UploadPitResult> uploadPit({
    List<String>? fileNames,
    List<http.MultipartFile>? multipartFiles,
    String? yearLevel,
    String? academicYear,
  }) async {
    if (multipartFiles != null && multipartFiles.isNotEmpty) {
      return uploadPitMultipart(
        multipartFiles: multipartFiles,
        yearLevel: yearLevel,
        academicYear: academicYear,
      );
    }
    return _postUploadAction({
      'file_names': fileNames ?? [],
      if ((yearLevel ?? '').isNotEmpty) 'year_level': yearLevel,
      if ((academicYear ?? '').isNotEmpty) 'academic_year': academicYear,
    });
  }

  Future<UploadPitResult> uploadPitMultipart({
    required List<http.MultipartFile> multipartFiles,
    String? yearLevel,
    String? academicYear,
  }) async {
    state = state.copyWith(
      isSaving: true,
      uploadProgress: 0.0,
      clearError: true,
      clearMessage: true,
    );
    try {
      final request = MultipartRequestWithProgress(
        'POST',
        Uri.parse('$baseUrl/upload-pit/'),
        onProgress: (bytesSent, totalBytes) {
          if (totalBytes > 0) {
            state = state.copyWith(uploadProgress: bytesSent / totalBytes);
          }
        },
      );
      if ((yearLevel ?? '').isNotEmpty) {
        request.fields['year_level'] = yearLevel!;
      }
      if ((academicYear ?? '').isNotEmpty) {
        request.fields['academic_year'] = academicYear!;
      }
      request.files.addAll(multipartFiles);
      final streamed = await _client.sendAuthenticated(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return _applyUploadPayload(
          Map<String, dynamic>.from(jsonDecode(response.body)),
        );
      }
      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return const UploadPitResult(
        savedAny: false,
        createdCount: 0,
        skipped: [],
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return const UploadPitResult(
        savedAny: false,
        createdCount: 0,
        skipped: [],
      );
    }
  }

  Future<UploadPitResult> _postUploadAction(Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
      clearLastUploadSkipped: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/upload-pit/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        return _applyUploadPayload(
          Map<String, dynamic>.from(jsonDecode(response.body)),
        );
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return const UploadPitResult(
        savedAny: false,
        createdCount: 0,
        skipped: [],
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return const UploadPitResult(
        savedAny: false,
        createdCount: 0,
        skipped: [],
      );
    }
  }

  Future<bool> overrideStatus(String entryId, String status) {
    return _postAction('override-status', {
      'entry_id': entryId,
      'status': status,
    }, successMessage: 'PIT status overridden.');
  }

  Future<String?> exportCsv() async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final response = await _client.get(
        _uri(
          'export',
          search: state.search,
          type: state.type,
          yearLevel: state.yearLevel,
          academicYear: state.academicYear,
          status: state.status,
          semester: state.semester,
          teamId: state.teamId,
          stage: state.stage,
          deliverableId: state.deliverableId,
          submissionKind: state.submissionKind,
          viewMode: state.viewMode,
        ),
        
      );
      if (response.statusCode == 200) {
        state = state.copyWith(
          isSaving: false,
          message: 'CSV export generated.',
          clearError: true,
        );
        return response.body;
      }
      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
    }
    return null;
  }

  Future<bool> _postAction(
    String action,
    Map<String, dynamic> payload, {
    required String successMessage,
  }) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
      clearLastUploadSkipped: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/$action/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        _applyPayload(
          Map<String, dynamic>.from(jsonDecode(response.body)),
          successMessage: successMessage,
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

  Uri _uri(
    String path, {
    required String search,
    required String type,
    required String yearLevel,
    required String academicYear,
    required String status,
    required String semester,
    required String teamId,
    required String stage,
    String deliverableId = '',
    String submissionKind = '',
    String viewMode = '',
  }) {
    return Uri.parse(path.isEmpty ? baseUrl : '$baseUrl/$path/').replace(
      queryParameters: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (type.isNotEmpty) 'type': type,
        if (yearLevel.isNotEmpty) 'year_level': yearLevel,
        if (academicYear.isNotEmpty) 'academic_year': academicYear,
        if (status.isNotEmpty) 'status': status,
        if (semester.isNotEmpty) 'semester': semester,
        if (teamId.isNotEmpty) 'team_id': teamId,
        if (stage.isNotEmpty) 'stage': stage,
        if (deliverableId.isNotEmpty) 'deliverable_id': deliverableId,
        if (submissionKind.isNotEmpty) 'submission_kind': submissionKind,
        if (viewMode.isNotEmpty) 'view': viewMode,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchAuditTrail({
    required String entryType,
    int? sourceId,
    String fileName = '',
  }) async {
    final query = <String, String>{
      'entry_type': entryType,
      if (sourceId != null) 'source_id': '$sourceId',
      if (fileName.trim().isNotEmpty) 'file_name': fileName.trim(),
    };
    final uri = Uri.parse('$baseUrl/trail/').replace(queryParameters: query);
    try {
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        return _readMapList(payload['audit_trail']);
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);

  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    final payloadScope = payload['scope'] is Map
        ? Map<String, dynamic>.from(payload['scope'])
        : const <String, dynamic>{};
    final scopeKey = payloadScope['scope']?.toString() ?? '';
    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      entries: _readMapList(payload['entries']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : const {},
      options: payload['options'] is Map
          ? Map<String, dynamic>.from(payload['options'])
          : const {},
      scope: payloadScope,
      uploadWindow: payload['upload_window'] is Map
          ? Map<String, dynamic>.from(payload['upload_window'])
          : const {},
      capstoneUploadWindow: payload['capstone_upload_window'] is Map
          ? Map<String, dynamic>.from(payload['capstone_upload_window'])
          : const {},
      groupedByStage: _readMapList(payload['grouped_by_stage']),
      deliverableSummary: payload['deliverable_summary'] is Map
          ? Map<String, dynamic>.from(payload['deliverable_summary'])
          : const {},
      type: scopeKey == 'admin' ? state.type : 'pit',
      message: successMessage,
      clearError: true,
      clearLastUploadSkipped: true,
    );
  }

  UploadPitResult _applyUploadPayload(
    Map<String, dynamic> payload, {
    String uploadLabel = 'PIT',
  }) {
    final payloadScope = payload['scope'] is Map
        ? Map<String, dynamic>.from(payload['scope'])
        : const <String, dynamic>{};
    final scopeKey = payloadScope['scope']?.toString() ?? '';
    final skipped = _readMapList(payload['skipped']);
    final createdCount = payload['created_count'] is int
        ? payload['created_count'] as int
        : int.tryParse('${payload['created_count']}') ?? 0;

    final feedback = _uploadFeedback(createdCount, skipped, uploadLabel: uploadLabel);

    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      entries: _readMapList(payload['entries']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : const {},
      options: payload['options'] is Map
          ? Map<String, dynamic>.from(payload['options'])
          : const {},
      scope: payloadScope,
      uploadWindow: payload['upload_window'] is Map
          ? Map<String, dynamic>.from(payload['upload_window'])
          : const {},
      capstoneUploadWindow: payload['capstone_upload_window'] is Map
          ? Map<String, dynamic>.from(payload['capstone_upload_window'])
          : const {},
      groupedByStage: _readMapList(payload['grouped_by_stage']),
      deliverableSummary: payload['deliverable_summary'] is Map
          ? Map<String, dynamic>.from(payload['deliverable_summary'])
          : const {},
      type: scopeKey == 'admin' ? state.type : 'pit',
      message: feedback.message,
      error: feedback.error,
      lastUploadSkipped: skipped,
      clearError: feedback.error == null,
      clearMessage: feedback.message == null,
    );

    return UploadPitResult(
      savedAny: createdCount > 0,
      createdCount: createdCount,
      skipped: skipped,
    );
  }

  Future<UploadPitResult> uploadCapstoneMultipart({
    required List<http.MultipartFile> multipartFiles,
    String? academicYear,
  }) async {
    state = state.copyWith(
      isSaving: true,
      uploadProgress: 0.0,
      clearError: true,
      clearMessage: true,
    );
    try {
      final request = MultipartRequestWithProgress(
        'POST',
        Uri.parse('$baseUrl/upload-capstone/'),
        onProgress: (bytesSent, totalBytes) {
          if (totalBytes > 0) {
            state = state.copyWith(uploadProgress: bytesSent / totalBytes);
          }
        },
      );
      if ((academicYear ?? '').isNotEmpty) {
        request.fields['academic_year'] = academicYear!;
      }
      request.files.addAll(multipartFiles);
      final streamed = await _client.sendAuthenticated(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        return _applyUploadPayload(
          Map<String, dynamic>.from(jsonDecode(response.body)),
          uploadLabel: 'Capstone',
        );
      }
      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return const UploadPitResult(
        savedAny: false,
        createdCount: 0,
        skipped: [],
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return const UploadPitResult(
        savedAny: false,
        createdCount: 0,
        skipped: [],
      );
    }
  }

  ({String? message, String? error}) _uploadFeedback(
    int createdCount,
    List<Map<String, dynamic>> skipped, {
    String uploadLabel = 'PIT',
  }) {
    if (createdCount == 0) {
      return (
        message: null,
        error: skipped.isEmpty
            ? 'No files were saved to the vault.'
            : _formatSkippedSummary(skipped, header: 'No files were saved.'),
      );
    }

    if (skipped.isEmpty) {
      return (
        message: createdCount == 1
            ? '1 $uploadLabel file saved to the vault.'
            : '$createdCount $uploadLabel files saved to the vault.',
        error: null,
      );
    }

    return (
      message:
          '$createdCount saved, ${skipped.length} skipped. ${_formatSkippedSummary(skipped)}',
      error: null,
    );
  }

  String _formatSkippedSummary(
    List<Map<String, dynamic>> skipped, {
    String header = '',
  }) {
    final lines = skipped.map((item) {
      final name = item['file_name']?.toString() ?? 'File';
      final reason = item['reason']?.toString() ?? 'Unknown reason';
      return '$name: $reason';
    });
    final body = lines.join('\n');
    if (header.isEmpty) {
      return body;
    }
    return '$header\n$body';
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
        final message = _messageFromErrorBody(data);
        if (message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      return 'Request failed. Status: ${response.statusCode}';
    }
    return 'Request failed. Status: ${response.statusCode}';
  }

  String _messageFromErrorBody(Map<dynamic, dynamic> data) {
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }
    if (detail is List) {
      return detail
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join(' ');
    }
    if (detail is Map) {
      return detail.values
          .expand((value) => value is List ? value : [value])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join(' ');
    }
    for (final value in data.values) {
      if (value is List && value.isNotEmpty) {
        return value.first.toString();
      }
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }
}
