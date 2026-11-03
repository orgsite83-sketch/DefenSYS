import 'dart:collection';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import '../app/data_refresh_provider.dart';

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
    this.isRefreshing = false,
    this.error,
  });
  final CurriculumExplorerQuery query;
  final Map<String, dynamic> data;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
}

final curriculumExplorerProvider =
    NotifierProvider<CurriculumExplorerNotifier, CurriculumExplorerState>(
      CurriculumExplorerNotifier.new,
    );

class CurriculumExplorerNotifier extends Notifier<CurriculumExplorerState> {
  CurriculumExplorerNotifier({Duration freshness = const Duration(minutes: 2)})
    : _freshness = freshness;
  int _request = 0;
  int _generation = 0;
  final Duration _freshness;
  static const _maxBytes = 5 * 1024 * 1024;
  final _cache = <String, _ExplorerResponse>{};
  final _pending = <String, Future<_ExplorerResponse>>{};
  int _bytes = 0;
  @override
  CurriculumExplorerState build() {
    ref.watch(authenticatedHttpClientProvider);
    _generation++;
    _cache.clear();
    _pending.clear();
    _bytes = 0;
    ref.listen(dataRefreshProvider, (previous, next) {
      const affected = {
        DataArea.analytics,
        DataArea.grades,
        DataArea.rubrics,
        DataArea.defenseStages,
        DataArea.academicPeriods,
        DataArea.teams,
        DataArea.repository,
        DataArea.deliverables,
      };
      if (affected.any((area) => (previous?[area] ?? 0) != (next[area] ?? 0))) {
        _generation++;
        _request++;
        _cache.clear();
        _pending.clear();
        _bytes = 0;
        if (state.data.isNotEmpty || state.isLoading || state.isRefreshing) {
          fetch(
            state.query,
            force: true,
            loadEvidence:
                state.query.view == 'assessment' &&
                state.data['criteria_complete'] == true,
          );
        }
      }
    });
    ref.onDispose(() {
      _request++;
      _generation++;
      _cache.clear();
      _pending.clear();
      _bytes = 0;
    });
    return const CurriculumExplorerState();
  }

  String _key(Map<String, String> params) =>
      jsonEncode(SplayTreeMap<String, String>.from(params));

  CurriculumExplorerQuery _resolved(
    CurriculumExplorerQuery query,
    Map<String, dynamic> data,
  ) => query.copyWith(
    year: data.containsKey('academic_year')
        ? data['academic_year']?.toString() ?? ''
        : query.year,
    initial: false,
    yearFrom: data['year_from']?.toString() ?? query.yearFrom,
    yearTo: data['year_to']?.toString() ?? query.yearTo,
    comparison: data['comparison']?.toString() ?? query.comparison,
    context: data['context']?.toString() ?? query.context,
    role: data['evaluation_type']?.toString() ?? query.role,
  );

  void _remember(String key, _ExplorerResponse entry) {
    final previous = _cache.remove(key);
    _bytes -= previous?.bytes ?? 0;
    if (entry.bytes > _maxBytes) return;
    _cache[key] = entry;
    _bytes += entry.bytes;
    while (_cache.length > 44 || _bytes > _maxBytes) {
      _bytes -= _cache.remove(_cache.keys.first)!.bytes;
    }
  }

  _ExplorerResponse? _cached(String key) {
    final entry = _cache.remove(key);
    if (entry != null) _cache[key] = entry;
    return entry;
  }

  bool _sameWorkspace(CurriculumExplorerQuery a, CurriculumExplorerQuery b) =>
      a.scope == b.scope && (a.scope != 'pit' || a.yearLevel == b.yearLevel);

  bool _sameRange(CurriculumExplorerQuery a, CurriculumExplorerQuery b) =>
      _sameWorkspace(a, b) &&
      (a.yearFrom.isEmpty || a.yearFrom == b.yearFrom) &&
      (a.yearTo.isEmpty || a.yearTo == b.yearTo);

  Map<String, dynamic>? _localData(
    CurriculumExplorerQuery query,
    _ExplorerResponse entry,
  ) {
    final source = entry.query;
    final data = entry.data;
    if (!_sameRange(query, source)) return null;
    if (query.view == 'projects' &&
        data['project_collection'] is List &&
        query.projectStatus == source.projectStatus) {
      final projects = explorerRows(data['project_collection']);
      final selectedYear = query.year.isEmpty
          ? (data['range_years'] as List? ?? []).lastOrNull?.toString() ?? ''
          : query.year;
      if (!(data['range_years'] as List? ?? []).contains(selectedYear) &&
          selectedYear.isNotEmpty) {
        return null;
      }
      final selected = projects
          .where((p) => p['academic_year'] == selectedYear)
          .toList();
      return {
        ...data,
        'view': 'projects',
        'academic_year': selectedYear,
        'projects': selected,
        'projects_count': selected.length,
      };
    }
    if (!['year', 'assessment'].contains(query.view) ||
        query.year != source.year ||
        query.semester != source.semester ||
        query.subject != source.subject ||
        query.reference != source.reference ||
        data['assessment_bundles'] is! Map) {
      return null;
    }
    final bundles = data['assessment_bundles'] as Map;
    final context = query.context.isEmpty
        ? data['context']?.toString() ?? ''
        : query.context;
    final roles = bundles[context] as Map?;
    if (roles == null || roles.isEmpty) return null;
    final role = roles.containsKey(query.role)
        ? query.role
        : roles.keys.first.toString();
    final bundle = Map<String, dynamic>.from(roles[role] as Map);
    return {
      ...data,
      ...bundle,
      'view': query.view,
      'context': context,
      'evaluation_type': role,
      'criteria_complete': bundle['criteria_complete'] == true,
    };
  }

  Future<void> fetch(
    CurriculumExplorerQuery query, {
    bool force = false,
    bool loadEvidence = false,
    bool selection = false,
  }) async {
    if (force) {
      _generation++;
      _cache.clear();
      _pending.clear();
      _bytes = 0;
    }
    final request = ++_request;
    final generation = _generation;
    final params = query.toParams();
    if (['year', 'assessment'].contains(query.view) && !loadEvidence) {
      params['workspace'] = 'true';
    }
    final key = _key(params);
    _ExplorerResponse? cached = _cached(key);
    Map<String, dynamic>? local;
    if (!force && !loadEvidence) {
      final candidates = _cache.values.toList()
        ..sort((a, b) => b.at.compareTo(a.at));
      for (final entry in candidates) {
        local = _localData(query, entry);
        if (local != null) {
          cached = entry;
          break;
        }
      }
    }
    final visibleData = local ?? cached?.data;
    if (!force &&
        cached != null &&
        (DateTime.now().difference(cached.at) < _freshness ||
            selection && local != null)) {
      state = CurriculumExplorerState(
        query: _resolved(query, visibleData!),
        data: visibleData,
      );
      return;
    }
    final previousData = state.data;
    final sameQuery =
        _key(state.query.toParams()) == _key(query.toParams()) ||
        (loadEvidence &&
            _sameWorkspace(query, state.query) &&
            query.year == state.query.year &&
            query.context == state.query.context &&
            query.role == state.query.role &&
            query.subject == state.query.subject &&
            query.semester == state.query.semester &&
            query.reference == state.query.reference);
    final retained =
        visibleData ?? (sameQuery ? state.data : <String, dynamic>{});
    state = CurriculumExplorerState(
      query: visibleData == null ? query : _resolved(query, visibleData),
      data: retained,
      isLoading: retained.isEmpty,
      isRefreshing: retained.isNotEmpty,
    );
    try {
      var response = await _read(key, params, query);
      if (!ref.mounted || generation != _generation || request != _request) {
        return;
      }
      if (loadEvidence &&
          sameQuery &&
          previousData['assessment_bundles'] is Map) {
        final bundles = Map<String, dynamic>.from(
          previousData['assessment_bundles'] as Map,
        );
        final roles = Map<String, dynamic>.from(
          bundles[response.query.context] as Map? ?? {},
        );
        roles[response.query.role] = {
          'criteria': response.data['criteria'],
          'assessment_summary': response.data['assessment_summary'],
          'criteria_complete': true,
        };
        bundles[response.query.context] = roles;
        final previousPerformance = Map<String, dynamic>.from(
          previousData['performance'] as Map? ?? {},
        );
        final freshContexts = explorerRows(
          (response.data['performance'] as Map? ?? {})['contexts'],
        );
        previousPerformance['contexts'] =
            explorerRows(previousPerformance['contexts'])
                .map(
                  (context) =>
                      freshContexts
                          .where((fresh) => fresh['id'] == context['id'])
                          .firstOrNull ??
                      context,
                )
                .toList();
        response = _ExplorerResponse(response.query, {
          ...previousData,
          ...response.data,
          'performance': previousPerformance,
          'assessment_bundles': bundles,
        });
        _remember(key, response);
      }
      state = CurriculumExplorerState(
        query: response.query,
        data: response.data,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation || request != _request) {
        return;
      }
      state = CurriculumExplorerState(
        query: state.query,
        data: state.data,
        error: error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<_ExplorerResponse> _read(
    String key,
    Map<String, String> params,
    CurriculumExplorerQuery query, {
    String? projectId,
  }) {
    if (_pending[key] case final pending?) return pending;
    final generation = _generation;
    late final Future<_ExplorerResponse> pending;
    pending =
        (() async {
          final response = await ref
              .read(authenticatedHttpClientProvider)
              .get(
                Uri.parse(
                  projectId == null
                      ? '${ApiConfig.curriculumAnalyticsUrl}/explorer/'
                      : '${ApiConfig.curriculumAnalyticsUrl}/explorer/projects/${Uri.encodeComponent(projectId)}/',
                ).replace(queryParameters: params),
              );
          if (response.statusCode != 200) {
            if ([401, 403].contains(response.statusCode) &&
                ref.mounted &&
                generation == _generation) {
              _generation++;
              _request++;
              _pending.clear();
              _cache.clear();
              _bytes = 0;
              state = CurriculumExplorerState(
                query: query,
                error: _error(response.bodyBytes),
              );
            }
            throw Exception(_error(response.bodyBytes));
          }
          final data = Map<String, dynamic>.from(
            jsonDecode(utf8.decode(response.bodyBytes)) as Map,
          );
          if (projectId == null &&
              query.view == 'projects' &&
              data['project_collection'] is List) {
            final selectedYear = query.year.isNotEmpty
                ? query.year
                : (data['range_years'] as List? ?? []).lastOrNull?.toString() ??
                      '';
            data['academic_year'] = selectedYear;
            data['projects'] = explorerRows(
              data['project_collection'],
            ).where((p) => p['academic_year'] == selectedYear).toList();
            data['projects_count'] = (data['projects'] as List).length;
          }
          final result = _ExplorerResponse(_resolved(query, data), data);
          if (ref.mounted && generation == _generation) {
            _remember(key, result);
            if (projectId == null) {
              final normalized = {...result.query.toParams()};
              if (params['workspace'] == 'true') {
                normalized['workspace'] = 'true';
              }
              _remember(_key(normalized), result);
            }
          }
          return result;
        })().whenComplete(() {
          if (identical(_pending[key], pending)) _pending.remove(key);
        });
    _pending[key] = pending;
    return pending;
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
    final key = '$projectId:${_key(params)}';
    final cached = _cached(key);
    if (cached != null && DateTime.now().difference(cached.at) < _freshness) {
      return cached.data;
    }
    return (await _read(key, params, query, projectId: projectId)).data;
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

class _ExplorerResponse {
  _ExplorerResponse(this.query, this.data)
    : at = DateTime.now(),
      bytes = utf8.encode(jsonEncode(data)).length;
  final CurriculumExplorerQuery query;
  final Map<String, dynamic> data;
  final DateTime at;
  final int bytes;
}

List<Map<String, dynamic>> explorerRows(dynamic value) => value is List
    ? value.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : [];

double? explorerNumber(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value');
