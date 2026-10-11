import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../../services/auth_provider.dart';
import '../../services/network/authenticated_client.dart';
import '../../services/reports_provider.dart';
import '../../toasts/feedback_toast.dart';
import 'defensys_export_dialog.dart';
import 'defensys_export_models.dart';
import 'report_catalog.dart';

Future<bool?> showReportExportConfiguration({
  required BuildContext context,
  required WidgetRef ref,
  required ReportDefinition report,
  Map<String, String> params = const {},
  String initialFormat = 'pdf',
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _ReportConfiguration(
      report: report,
      params: params,
      initialFormat: initialFormat,
    ),
  );
}

class _ReportConfiguration extends ConsumerStatefulWidget {
  const _ReportConfiguration({
    required this.report,
    required this.params,
    required this.initialFormat,
  });
  final ReportDefinition report;
  final Map<String, String> params;
  final String initialFormat;
  @override
  ConsumerState<_ReportConfiguration> createState() =>
      _ReportConfigurationState();
}

class _ReportConfigurationState extends ConsumerState<_ReportConfiguration> {
  Map<String, dynamic> _options = {};
  String? _optionsError;
  bool _loadingOptions = true;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(
            Uri.parse('${ApiConfig.baseUrl}/reports/catalog-options/').replace(
              queryParameters: {...widget.params, 'report': widget.report.id},
            ),
          );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw Exception(data['detail'] ?? 'Unable to load report selections.');
      }
      if (mounted) {
        setState(() {
          _options = Map<String, dynamic>.from(data);
          _loadingOptions = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _optionsError = error.toString().replaceFirst('Exception: ', '');
          _loadingOptions = false;
        });
      }
    }
  }

  Map<String, String> _scoped(Map<String, String> values) {
    final params = Map<String, String>.from(values)
      ..removeWhere(
        (key, value) =>
            value.isEmpty ||
            value == 'ALL' ||
            (value == 'all' && key != 'coverage' && key != 'term_context'),
      );
    if (widget.report.scope.isNotEmpty) params['scope'] = widget.report.scope;
    if (params['coverage'] != 'specific') params.remove('grade_id');
    final user = ref.read(authProvider).user;
    if (user?['is_pit_lead'] == true &&
        user?['role'] != 'admin' &&
        user?['is_superuser'] != true) {
      params['scope'] = 'pit';
      params['year_level'] = user?['pit_lead_year']?.toString() ?? '';
      if (widget.report.id == 'project-records') params['type'] = 'pit';
    }
    return params;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return DefensysExportDialog(
      config: DefensysExportConfig(
        title: report.title,
        subtitle: report.description,
        icon: report.icon,
        defaultFilename:
            'DefenSYS_${report.id}_${DateTime.now().toIso8601String().substring(0, 10)}',
        initialFormat: widget.initialFormat,
        initialParams: _scoped(widget.params),
        leftPaneWidth: 320,
        leftPaneBuilder: (_, params, update, refresh) => _ReportFilters(
          report: report,
          params: params,
          options: _options,
          loading: _loadingOptions,
          error: _optionsError,
          onChanged: update,
          onRetry: _loadOptions,
          pitLead:
              ref.read(authProvider).user?['is_pit_lead'] == true &&
              ref.read(authProvider).user?['role'] != 'admin' &&
              ref.read(authProvider).user?['is_superuser'] != true,
        ),
        onFetchPreview: (values) async {
          final params = _scoped(values);
          if (report.missingSelection(params) != null) return null;
          return ref
              .read(reportsProvider.notifier)
              .fetchReportPreview(
                endpoint: report.endpointFor(params),
                queryParams: params,
              );
        },
        onDownload: (values, format, signatories, includeSignatures) async {
          final params = _scoped(values);
          final missing = report.missingSelection(params);
          if (missing != null) {
            showValidationToast(context, missing);
            return false;
          }
          final success = await ref
              .read(reportsProvider.notifier)
              .downloadReport(
                endpoint: report.endpointFor(params),
                queryParams: {
                  ...params,
                  'include_signatures': includeSignatures.toString(),
                  'signatories': jsonEncode(
                    signatories.map((signer) => signer.toJson()).toList(),
                  ),
                },
                defaultFilename:
                    '${params['custom_filename'] ?? 'DefenSYS_${report.id}'}.${format == 'xlsx' ? 'xlsx' : 'pdf'}',
                exportFormat: format,
              );
          if (context.mounted && !success) {
            showErrorToast(
              context,
              ref.read(reportsProvider).error ?? 'Unable to export report.',
            );
          }
          return success;
        },
      ),
    );
  }
}

class _ReportFilters extends StatefulWidget {
  const _ReportFilters({
    required this.report,
    required this.params,
    required this.options,
    required this.loading,
    required this.error,
    required this.onChanged,
    required this.onRetry,
    required this.pitLead,
  });
  final ReportDefinition report;
  final Map<String, String> params;
  final Map<String, dynamic> options;
  final bool loading, pitLead;
  final String? error;
  final ValueChanged<Map<String, String>> onChanged;
  final VoidCallback onRetry;
  @override
  State<_ReportFilters> createState() => _ReportFiltersState();
}

class _ReportFiltersState extends State<_ReportFilters> {
  final Map<String, TextEditingController> _controllers = {};
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _change(String key, String value) {
    final next = {...widget.params, key: value};
    if (key == 'semester_id' || key == 'scope') {
      for (final selector in [
        'rubric_id',
        'team_id',
        'student_id',
        'grade_id',
      ]) {
        next.remove(selector);
      }
      if (next['coverage'] == 'specific') next['coverage'] = 'latest';
    }
    if (key == 'coverage' && value != 'specific') next.remove('grade_id');
    widget.onChanged(next);
  }

  List<Map<String, String>>? _choices(String key) {
    final source = const {
      'semester_id': 'semesters',
      'rubric_id': 'rubrics',
      'team_id': 'teams',
      'student_id': 'students',
      'stage_id': 'stages',
    }[key];
    // Choices are filtered locally so changing period or scope cannot offer stale records.
    if (source != null) {
      return (widget.options[source] as List? ?? [])
          .whereType<Map>()
          .where(
            (row) =>
                (row['semester_id'] == null ||
                    (widget.params['semester_id'] ?? '').isEmpty ||
                    row['semester_id'].toString() ==
                        widget.params['semester_id']) &&
                (row['scope'] == null ||
                    (widget.params['scope'] ?? '').isEmpty ||
                    row['scope'] == widget.params['scope']),
          )
          .map(
            (row) => {
              'value': row['id'].toString(),
              'label': (row['label'] ?? row['name']).toString(),
            },
          )
          .toList();
    }
    final fixed = <String, List<String>>{
      'view': ['directory', 'assignments'],
      'scope': ['capstone', 'pit'],
      'type': ['capstone', 'pit'],
      'term_context': ['active', 'history'],
      'coverage': [
        'latest',
        'all',
        if ((widget.params['grade_id'] ?? '').isNotEmpty) 'specific',
      ],
      'evaluation_type': ['panel', 'adviser', 'peer'],
      'semester': ['1st Semester', '2nd Semester', 'Summer'],
      'year_level': ['1st Year', '2nd Year', '3rd Year', '4th Year'],
    }[key];
    return fixed
        ?.map(
          (value) => {
            'value': value,
            'label': value == 'capstone'
                ? 'Capstone'
                : value == 'pit'
                ? 'PIT'
                : value.replaceFirstMapped(
                    RegExp(r'^.'),
                    (m) => m[0]!.toUpperCase(),
                  ),
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final fields = {
      ...widget.report.filters,
      ...widget.params.keys.where(
        (key) => ![
          'include_signatures',
          'signatories',
          'custom_filename',
          'source_context',
          'view',
        ].contains(key),
      ),
    };
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Report filters',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Exports include every matching record across pages.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (widget.loading) const LinearProgressIndicator(),
            if (widget.error != null) ...[
              Text(widget.error!),
              TextButton(
                onPressed: widget.onRetry,
                child: const Text('Retry selections'),
              ),
            ],
            for (final key in fields) ...[
              if (key == 'grade_id')
                const Text(
                  'Selected recorded assessment',
                  style: TextStyle(fontSize: 12),
                )
              else if (widget.pitLead &&
                  ['scope', 'type', 'year_level', 'track'].contains(key))
                Text(
                  '${ReportCatalog.filterLabel(key)}: ${widget.params[key] ?? 'PIT'} (assigned)',
                  style: const TextStyle(fontSize: 12),
                )
              else if (_choices(key) != null)
                Builder(
                  builder: (_) {
                    final choices = _choices(key)!;
                    final current = widget.params[key] ?? '';
                    if (current.isNotEmpty &&
                        !choices.any((choice) => choice['value'] == current)) {
                      choices.add({
                        'value': current,
                        'label': sourceIdField(key)
                            ? (widget.loading
                                  ? 'Loading selected record…'
                                  : 'Selected record unavailable for these filters')
                            : current,
                      });
                    }
                    return DropdownButtonFormField<String>(
                      key: ValueKey('$key:$current:${widget.loading}'),
                      initialValue: current,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: ReportCatalog.filterLabel(key),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('All / default'),
                        ),
                        ...choices.map(
                          (choice) => DropdownMenuItem(
                            value: choice['value'],
                            child: Text(
                              choice['label']!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) => _change(key, value ?? ''),
                    );
                  },
                )
              else
                TextField(
                  controller: _controllers.putIfAbsent(
                    key,
                    () => TextEditingController(text: widget.params[key] ?? ''),
                  ),
                  decoration: InputDecoration(
                    labelText: ReportCatalog.filterLabel(key),
                    hintText: key.endsWith('_date') ? 'YYYY-MM-DD' : 'All',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => _change(key, value.trim()),
                ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  bool sourceIdField(String key) => [
    'semester_id',
    'rubric_id',
    'team_id',
    'student_id',
    'stage_id',
  ].contains(key);
}
