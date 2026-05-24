import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';
import 'session_expired.dart';

final digitalVaultProvider =
    NotifierProvider<DigitalVaultNotifier, DigitalVaultState>(
      DigitalVaultNotifier.new,
    );

class DigitalVaultState {
  final bool isLoading;
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> counts;
  final Map<String, dynamic> options;
  final String search;
  final String type;
  final String yearLevel;
  final String stage;
  final String academicYear;
  final String? error;

  const DigitalVaultState({
    this.isLoading = false,
    this.entries = const [],
    this.counts = const {},
    this.options = const {},
    this.search = '',
    this.type = '',
    this.yearLevel = '',
    this.stage = '',
    this.academicYear = '',
    this.error,
  });

  DigitalVaultState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? entries,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? options,
    String? search,
    String? type,
    String? yearLevel,
    String? stage,
    String? academicYear,
    String? error,
    bool clearError = false,
  }) {
    return DigitalVaultState(
      isLoading: isLoading ?? this.isLoading,
      entries: entries ?? this.entries,
      counts: counts ?? this.counts,
      options: options ?? this.options,
      search: search ?? this.search,
      type: type ?? this.type,
      yearLevel: yearLevel ?? this.yearLevel,
      stage: stage ?? this.stage,
      academicYear: academicYear ?? this.academicYear,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class DigitalVaultNotifier extends Notifier<DigitalVaultState> {
    static String get baseUrl => ApiConfig.digitalVaultUrl;

  @override
  DigitalVaultState build() {
    return const DigitalVaultState();
  }

  /// Mobile student Repository tab: vault archives plus team document uploads.
  Future<void> fetchForStudent({String? search}) {
    return fetchEntries(search: search, includeTeamDocuments: true);
  }

  Future<void> fetchEntries({
    String? search,
    String? type,
    String? yearLevel,
    String? stage,
    String? academicYear,
    bool includeTeamDocuments = false,
  }) async {
    final nextSearch = search ?? state.search;
    final nextType = type ?? state.type;
    final nextYearLevel = yearLevel ?? state.yearLevel;
    final nextStage = stage ?? state.stage;
    final nextAcademicYear = academicYear ?? state.academicYear;

    state = state.copyWith(
      isLoading: state.entries.isEmpty,
      search: nextSearch,
      type: nextType,
      yearLevel: nextYearLevel,
      stage: nextStage,
      academicYear: nextAcademicYear,
      clearError: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextType.isNotEmpty) 'type': nextType,
          if (nextYearLevel.isNotEmpty) 'year_level': nextYearLevel,
          if (nextStage.isNotEmpty) 'stage': nextStage,
          if (nextAcademicYear.isNotEmpty) 'academic_year': nextAcademicYear,
        },
      );

      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        var entries = _readMapList(payload['entries']);
        if (includeTeamDocuments) {
          entries = [...entries, ...await _fetchTeamDocumentEntries()];
        }
        state = state.copyWith(
          isLoading: false,
          entries: entries,
          counts: payload['counts'] is Map
              ? Map<String, dynamic>.from(payload['counts'])
              : const {},
          options: payload['options'] is Map
              ? Map<String, dynamic>.from(payload['options'])
              : const {},
          clearError: true,
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        error: _errorFromResponse(response),
      );
    } on SessionExpiredException {
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTeamDocumentEntries() async {
    try {
      final response = await _client
          .get(Uri.parse('${ApiConfig.teamDocumentsUrl}/'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return [];
      }
      final docsData = jsonDecode(response.body);
      if (docsData is! Map) {
        return [];
      }
      final documents = docsData['documents'] as List? ?? [];
      return documents.whereType<Map>().map((doc) {
        final map = Map<String, dynamic>.from(doc);
        final description = map['description']?.toString() ?? '';
        final fileName = map['file_name']?.toString() ?? 'Unknown';
        return {
          'id': 'doc_${map['id']}',
          'file_name': fileName,
          'file_url': map['file_url']?.toString(),
          'team_name': map['team_name'] ?? '—',
          'uploaded_by': map['uploaded_by_name'] ?? '—',
          'academic_year': '—',
          'status': 'Approved',
          'uploaded_at': map['uploaded_at'] ?? '',
          'year_level': '—',
          'stage': map['document_type'] ?? 'other',
          'type': 'uploader',
          'deliverable_label':
              description.isNotEmpty ? description : fileName,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);


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
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
    } catch (_) {
      return 'Request failed. Status: ${response.statusCode}';
    }
    return 'Request failed. Status: ${response.statusCode}';
  }
}
