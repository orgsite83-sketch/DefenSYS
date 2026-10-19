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
    this.subject = '',
    this.comparison = '',
    this.reference = 75,
    this.initial = false,
    this.view = 'overview',
    this.yearFrom = '',
    this.yearTo = '',
    this.projectStatus = 'completed',
  });
  final String scope,
      yearLevel,
      year,
      semester,
      context,
      role,
      subject,
      comparison,
      view,
      yearFrom,
      yearTo,
      projectStatus;
  final double reference;
  final bool initial;

  CurriculumExplorerQuery copyWith({
    String? scope,
    String? yearLevel,
    String? year,
    String? semester,
    String? context,
    String? role,
    String? subject,
    String? comparison,
    double? reference,
    bool? initial,
    String? view,
    String? yearFrom,
    String? yearTo,
    String? projectStatus,
  }) => CurriculumExplorerQuery(
    scope: scope ?? this.scope,
    yearLevel: yearLevel ?? this.yearLevel,
    year: year ?? this.year,
    semester: semester ?? this.semester,
    context: context ?? this.context,
    role: role ?? this.role,
    subject: subject ?? this.subject,
    comparison: comparison ?? this.comparison,
    reference: reference ?? this.reference,
    initial: initial ?? this.initial,
    view: view ?? this.view,
    yearFrom: yearFrom ?? this.yearFrom,
    yearTo: yearTo ?? this.yearTo,
    projectStatus: projectStatus ?? this.projectStatus,
  );

  Map<String, String> toParams() => {
    'scope': scope,
    if (scope == 'pit') 'year_level': yearLevel,
    if (year.isNotEmpty) 'academic_year': year,
    if (semester.isNotEmpty) 'semester': semester,
    if (context.isNotEmpty) 'context': context,
    if (subject.isNotEmpty) 'subject': subject,
    if (comparison.isNotEmpty) 'comparison': comparison,
    'evaluation_type': role,
    'reference': reference.toString(),
    if (initial) 'initial': 'true',
    'view': view,
    if (yearFrom.isNotEmpty) 'year_from': yearFrom,
    if (yearTo.isNotEmpty) 'year_to': yearTo,
    'project_status': projectStatus,
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
  String? _pendingKey;
  Future<void>? _pending;
  @override
  CurriculumExplorerState build() {
    ref.onDispose(() {
      _request++;
      _pending = null;
      _pendingKey = null;
    });
    return const CurriculumExplorerState();
  }

  Future<void> fetch(CurriculumExplorerQuery query) {
    final key = jsonEncode(query.toParams());
    if (_pendingKey == key && _pending != null) return _pending!;
    _pendingKey = key;
    final pending = _fetch(query);
    _pending = pending;
    return pending.whenComplete(() {
      if (identical(_pending, pending)) {
        _pending = null;
        _pendingKey = null;
      }
    });
  }

  Future<void> _fetch(CurriculumExplorerQuery query) async {
    final request = ++_request;
    final sameScope =
        state.query.scope == query.scope &&
        state.query.yearLevel == query.yearLevel;
    state = CurriculumExplorerState(
      query: query,
      data: sameScope ? state.data : const {},
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
        query: query.copyWith(
          year: data.containsKey('academic_year')
              ? data['academic_year']?.toString() ?? ''
              : query.year,
          initial: false,
          yearFrom: data['year_from']?.toString() ?? query.yearFrom,
          yearTo: data['year_to']?.toString() ?? query.yearTo,
          comparison: data['comparison']?.toString() ?? query.comparison,
          context: data['context']?.toString() ?? '',
          role: data['evaluation_type']?.toString() ?? query.role,
        ),
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
        ? state.query.copyWith(context: '', subject: '')
        : state.query;
    final project = explorerRows(
      state.data['projects'],
    ).where((p) => p['id'] == projectId).firstOrNull;
    final params = query
        .copyWith(
          view: 'detail',
          initial: false,
          year: allAssessments
              ? (project?['academic_year']?.toString() ?? query.year)
              : query.year,
        )
        .toParams();
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
