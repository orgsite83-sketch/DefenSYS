import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../../services/auth_provider.dart';
import '../../services/network/authenticated_client.dart';
import '../../services/reports_provider.dart';
import '../../toasts/feedback_toast.dart';
import '../../theme/defensys_tokens.dart';
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
        tag: report.category,
        icon: report.icon,
        defaultFilename:
            'DefenSYS_${report.id}_${DateTime.now().toIso8601String().substring(0, 10)}',
        initialFormat: widget.initialFormat,
        formatsForParams: report.id == 'concept-projects'
            ? (params) => params['layout'] == 'roster'
                  ? const ['xlsx']
                  : const ['pdf', 'xlsx']
            : null,
        initialParams: _scoped(widget.params),
        leftPaneWidth: 380,
        leftPaneBuilder: (_, params, update, refresh) => _ReportFilters(
          report: report,
          params: params,
          options: _options,
          loading: _loadingOptions,
          error: _optionsError,
          onChanged: update,
          onReset: () => update(_scoped({})),
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
          if (report.id == 'concept-projects' &&
              params['layout'] == 'roster' &&
              format != 'xlsx') {
            showValidationToast(
              context,
              'Choose Excel for the importable roster template.',
            );
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
    required this.onReset,
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
  final VoidCallback onReset;
  @override
  State<_ReportFilters> createState() => _ReportFiltersState();
}

class _ReportFiltersState extends State<_ReportFilters> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void didUpdateWidget(covariant _ReportFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final entry in _controllers.entries) {
      final text = widget.params[entry.key] ?? '';
      if (entry.value.text.trim() != text) {
        entry.value.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

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
        'stage',
        'pit_event',
        'stage_id',
        'pit_event_config_id',
      ]) {
        next.remove(selector);
      }
      if (next['coverage'] == 'specific') next['coverage'] = 'latest';
    }
    if (key == 'coverage' && value != 'specific') next.remove('grade_id');
    if (key == 'year_level') next.remove('pit_event_config_id');
    if (key == 'pit_event_config_id' && value.isNotEmpty) {
      next.remove('stage_id');
    }
    if (key == 'stage_id' && value.isNotEmpty) {
      next.remove('pit_event_config_id');
    }
    if (key == 'layout' && value == 'roster') {
      next.remove('concept_status');
      next['include_history'] = '0';
    }
    widget.onChanged(next);
  }

  List<Map<String, String>>? _choices(String key) {
    if (key == 'stage' || key == 'pit_event') {
      final scope = widget.report.id == 'defense-stage-setup'
          ? 'capstone'
          : widget.report.id == 'pit-event-setup' || key == 'pit_event'
          ? 'pit'
          : widget.params['scope'] ??
                widget.params['type'] ??
                widget.report.scope;
      final semester =
          widget.params['semester_id'] ??
          widget.options['default_semester_id']?.toString() ??
          '';
      final contexts =
          widget.options['stage_choices'] as List? ??
          [
            for (final stage in widget.options['stages'] as List? ?? [])
              {
                'value': stage['label'],
                'label': stage['label'],
                'scope': 'capstone',
              },
          ];
      final seen = <String>{};
      return contexts
          .whereType<Map>()
          .where(
            (row) =>
                (scope.isEmpty || row['scope'] == scope) &&
                (row['semester_id'] == null ||
                    semester.isEmpty ||
                    row['semester_id'].toString() == semester),
          )
          .where((row) => seen.add(row['value'].toString()))
          .map(
            (row) => {
              'value': row['value'].toString(),
              'label': row['label'].toString(),
            },
          )
          .toList();
    }
    final source = const {
      'semester_id': 'semesters',
      'rubric_id': 'rubrics',
      'team_id': 'teams',
      'student_id': 'students',
      'stage_id': 'stages',
      'pit_event_config_id': 'pit_events',
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
                (row['year_level'] == null ||
                    (widget.params['year_level'] ?? '').isEmpty ||
                    row['year_level'] == widget.params['year_level']) &&
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
    final conceptChoices = <String, Map<String, String>>{
      'layout': {
        'register': 'Concept register (PDF / Excel)',
        'roster': 'Capstone intake roster (Excel)',
      },
      'include_history': {
        '0': 'Current rounds',
        '1': 'Include historical rounds',
      },
      'concept_status': {
        'approved': 'Approved',
        'approved_with_revisions': 'Approved with revisions',
        'awaiting_decision': 'Awaiting decision',
        'rejected': 'Rejected',
        'not_selected': 'Not selected',
        'revise': 'Revision required',
        'for_redefense': 'Re-defense required',
        'replacement_required': 'Replacement required',
        'not_submitted': 'No concept submitted',
        'not_configured': 'Concepts not configured',
      },
    }[key];
    if (conceptChoices != null) {
      return conceptChoices.entries
          .map((e) => {'value': e.key, 'label': e.value})
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'EXPORT FILTERS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: DefensysTokens.textSecondaryOf(context),
                letterSpacing: .5,
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Exports include every matching record across pages.',
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.report.id == 'concept-projects') ...[
          const Text(
            'Roster template: select a 3rd Year, 1st Semester PIT period and concept event. Admin keeps or clears titles and assigns advisers in the existing team import review. All Capstone files, reviews and approvals start fresh.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 14),
        ],
        if (widget.loading) const LinearProgressIndicator(),
        if (widget.error != null) ...[
          Text(widget.error!, style: const TextStyle(fontSize: 12)),
          TextButton(
            onPressed: widget.onRetry,
            child: const Text('Retry selections'),
          ),
        ],
        for (final key in fields) ...[
          Text(
            ReportCatalog.filterLabel(key).toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textSecondaryOf(context),
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 6),
          _field(key),
          const SizedBox(height: 16),
        ],
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh_rounded, size: 15),
          label: const Text('Reset All Filters'),
          style: OutlinedButton.styleFrom(
            foregroundColor: DefensysTokens.maroonOf(context),
            side: BorderSide(
              color: DefensysTokens.maroonOf(context).withValues(alpha: .3),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
          ),
          onPressed: widget.onReset,
        ),
      ],
    );
  }

  Widget _field(String key) {
    if (key == 'grade_id') {
      return const Text(
        'Selected recorded assessment',
        style: TextStyle(fontSize: 12),
      );
    }
    if (widget.pitLead &&
        ['scope', 'type', 'year_level', 'track'].contains(key)) {
      return Text(
        '${widget.params[key] ?? 'PIT'} (assigned)',
        style: const TextStyle(fontSize: 12.5),
      );
    }
    final choices = _choices(key);
    if (choices != null) {
      final current = widget.params[key] ?? '';
      if (current.isNotEmpty &&
          !choices.any((choice) => choice['value'] == current)) {
        choices.add({
          'value': current,
          'label': sourceIdField(key)
              ? (widget.loading
                    ? 'Loading selected record...'
                    : 'Selected record unavailable for these filters')
              : current,
        });
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('$key:$current:${widget.loading}'),
        initialValue: current,
        isExpanded: true,
        style: TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontSize: 12.5,
          color: DefensysTokens.textPrimaryOf(context),
        ),
        decoration: _decoration(),
        items: [
          const DropdownMenuItem(value: '', child: Text('All / default')),
          ...choices.map(
            (choice) => DropdownMenuItem(
              value: choice['value'],
              child: Text(choice['label']!, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) => _change(key, value ?? ''),
      );
    }
    return TextField(
      key: ValueKey('report-filter-$key'),
      controller: _controllers.putIfAbsent(
        key,
        () => TextEditingController(text: widget.params[key] ?? ''),
      ),
      style: TextStyle(
        fontSize: 12.5,
        color: DefensysTokens.textPrimaryOf(context),
      ),
      decoration: _decoration().copyWith(
        hintText: key.endsWith('_date') ? 'YYYY-MM-DD' : 'All',
      ),
      onChanged: (value) => _change(key, value.trim()),
    );
  }

  InputDecoration _decoration() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: DefensysTokens.isDark(context)
          ? DefensysTokens.surfaceHigherOf(context)
          : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: DefensysTokens.maroonOf(context),
          width: 1.5,
        ),
      ),
    );
  }

  bool sourceIdField(String key) => [
    'pit_event_config_id',
    'semester_id',
    'rubric_id',
    'team_id',
    'student_id',
    'stage_id',
  ].contains(key);
}
