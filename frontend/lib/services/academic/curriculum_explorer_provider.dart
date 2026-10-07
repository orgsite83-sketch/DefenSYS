import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

class CurriculumExplorerQuery {
  const CurriculumExplorerQuery({
    this.scope = 'capstone',
    this.yearLevel = '1',
    this.year = '',
    this.semester = '',
    this.context = '',
    this.role = 'panel',
    this.reference = 75,
  });
  final String scope, yearLevel, year, semester, context, role;
  final double reference;

  CurriculumExplorerQuery copyWith({
    String? scope,
    String? yearLevel,
    String? year,
    String? semester,
    String? context,
    String? role,
    double? reference,
  }) => CurriculumExplorerQuery(
    scope: scope ?? this.scope,
    yearLevel: yearLevel ?? this.yearLevel,
    year: year ?? this.year,
    semester: semester ?? this.semester,
    context: context ?? this.context,
    role: role ?? this.role,
    reference: reference ?? this.reference,
  );

  Map<String, String> toParams() => {
    'scope': scope,
    if (scope == 'pit') 'year_level': yearLevel,
    if (year.isNotEmpty) 'academic_year': year,
    if (semester.isNotEmpty) 'semester': semester,
    if (context.isNotEmpty) 'context': context,
    'evaluation_type': role,
    'reference': reference.toString(),
  };
}

class CurriculumExplorerState {
  const CurriculumExplorerState({
    this.query = const CurriculumExplorerQuery(),
    this.data = const {},
    this.isLoading = false,
    this.error,
  });
  final CurriculumExplorerQuery query;
  final Map<String, dynamic> data;
  final bool isLoading;
  final String? error;
}

final curriculumExplorerProvider =
    NotifierProvider<CurriculumExplorerNotifier, CurriculumExplorerState>(
      CurriculumExplorerNotifier.new,
    );

class CurriculumExplorerNotifier extends Notifier<CurriculumExplorerState> {
  int _request = 0;
  @override
  CurriculumExplorerState build() => const CurriculumExplorerState();

  Future<void> fetch(CurriculumExplorerQuery query) async {
    final request = ++_request;
    state = CurriculumExplorerState(
      query: query,
      data: state.data,
      isLoading: true,
    );
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(
            Uri.parse(
              '${ApiConfig.curriculumAnalyticsUrl}/explorer/',
            ).replace(queryParameters: query.toParams()),
          );
      if (!ref.mounted || request != _request) return;
      if (response.statusCode != 200) {
        throw Exception(_error(response.bodyBytes));
      }
      final data = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
      state = CurriculumExplorerState(
        query: query.copyWith(context: data['context']?.toString() ?? ''),
        data: data,
      );
    } catch (error) {
      if (!ref.mounted || request != _request) return;
      state = CurriculumExplorerState(
        query: query,
        error: error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<Map<String, dynamic>> detail(
    String projectId, {
    bool allAssessments = false,
  }) async {
    final query = allAssessments
        ? state.query.copyWith(context: '')
        : state.query;
    final params = query.toParams();
    if (allAssessments) params['all_assessments'] = 'true';
    final response = await ref
        .read(authenticatedHttpClientProvider)
        .get(
          Uri.parse(
            '${ApiConfig.curriculumAnalyticsUrl}/explorer/projects/${Uri.encodeComponent(projectId)}/',
          ).replace(queryParameters: params),
        );
    if (response.statusCode != 200) throw Exception(_error(response.bodyBytes));
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map,
    );
  }

  String _error(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) {
        return decoded.values
            .map((v) => v is List ? v.join(' ') : '$v')
            .join(' ');
      }
    } catch (_) {}
    return 'Unable to load curriculum analytics. Try again.';
  }
}

List<Map<String, dynamic>> explorerRows(dynamic value) => value is List
    ? value.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : [];

double? explorerNumber(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value');
