import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../config/api_config.dart';
import '../../services/auth_provider.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../services/network/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/universal_file_viewer.dart';
import '../../models/team_workflow_status.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'deliverable_file_widgets.dart';
import 'deliverable_requirement_card.dart';
import 'deliverable_template.dart';
import 'requirement_summary.dart';
import 'deliverable_popup_navigation.dart';

String _error(http.Response response) {
  try {
    final body = jsonDecode(response.body);
    return body is Map ? '${body['detail'] ?? body.values.first}' : '$body';
  } catch (_) {
    return 'The request could not be completed (${response.statusCode}).';
  }
}

String _message(Object error) => error is StateError ? error.message : '$error';

String _requestId() {
  final random = Random.secure();
  final parts = List.generate(16, (_) => random.nextInt(256));
  parts[6] = (parts[6] & 15) | 64;
  parts[8] = (parts[8] & 63) | 128;
  final hex = parts.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Counts and dates belong to the selected stage's required reporting range.
class _WeeklyStageOverview extends StatelessWidget {
  const _WeeklyStageOverview({
    required this.stageLabel,
    required this.summary,
    required this.weeks,
    required this.onRefresh,
  });

  final String stageLabel;
  final RequirementSummary summary;
  final List<Map> weeks;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final primary = DefensysTokens.textPrimaryOf(context);
    final caption = DefensysTokens.caption.copyWith(
      fontFamily: DefensysTokens.fontFamilyInter,
      color: DefensysTokens.textSecondaryOf(context),
    );
    final body = DefensysTokens.body.copyWith(
      fontFamily: DefensysTokens.fontFamilyInter,
      color: primary,
    );
    final first = weeks.firstOrNull;
    final last = weeks.lastOrNull;
    final range = first == null
        ? null
        : first == last
        ? 'Week ${first['week_number']}'
        : 'Weeks ${first['week_number']}–${last!['week_number']}';
    String date(dynamic raw) {
      final value = DateTime.tryParse('$raw');
      return value == null ? '' : DateFormat('d MMM yyyy').format(value);
    }

    final remaining = (summary.required - summary.acceptedFiles).clamp(
      0,
      summary.required,
    );
    final complete = summary.required > 0 && remaining == 0;
    final progress = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${summary.acceptedFiles}/${summary.required} accepted',
          style: body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Semantics(
          label:
              '${summary.acceptedFiles} of ${summary.required} required reports accepted',
          child: ShadProgress(
            value: summary.required == 0
                ? 0
                : (summary.acceptedFiles / summary.required).clamp(0.0, 1.0),
            minHeight: 6,
            color: complete
                ? DefensysTokens.success
                : DefensysTokens.maroonOf(context),
            backgroundColor: DefensysTokens.surfaceHigherOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          complete
              ? 'All required reports accepted'
              : '$remaining ${remaining == 1 ? 'report still needs' : 'reports still need'} acceptance',
          style: caption,
        ),
      ],
    );
    return Container(
      key: const ValueKey('weekly-stage-overview'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stage requirement', style: caption),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.required} ${summary.required == 1 ? 'report' : 'reports'} required',
                      style: body.copyWith(
                        fontSize: 22,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [stageLabel, ?range].join(' · '),
                      style: body.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (first != null && last != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Reports cover ${date(first['starts_on'])} – ${date(last['ends_on'])}',
                        style: caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                enabled: onRefresh != null,
                onPressed: onRefresh,
                child: const Tooltip(
                  message: 'Refresh weekly reports',
                  child: Icon(Icons.refresh, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final counts = Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  for (final label in [
                    '${summary.uploaded} uploaded',
                    '${summary.pending} awaiting review',
                    '${summary.missing} not uploaded',
                    if (summary.corrections > 0)
                      '${summary.corrections} need correction',
                    if (summary.overdue > 0) '${summary.overdue} overdue',
                  ])
                    Text(label, style: caption),
                ],
              );
              if (constraints.maxWidth < 640) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [progress, const SizedBox(height: 16), counts],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: counts),
                  const SizedBox(width: 24),
                  SizedBox(width: 260, child: progress),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Student checklist entry: every week stays inside one compact requirement.
class WeeklyReportRequirement extends StatelessWidget {
  const WeeklyReportRequirement({
    super.key,
    required this.teamId,
    required this.stageLabel,
    required this.item,
    this.semesterId,
    this.projectVersion,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic> item;
  final int? semesterId;
  final int? projectVersion;

  @override
  Widget build(BuildContext context) {
    return DeliverableRequirementCard(
      item: item,
      onOpen: () => showDeliverableRequirementDialog(
        context,
        builder: (context) => DeliverableRequirementDialog(
          item: item,
          child: WeeklyReportCollection(
            teamId: teamId,
            stageLabel: stageLabel,
            item: item,
            semesterId: semesterId,
            projectVersion: projectVersion,
          ),
        ),
      ),
    );
  }
}

class WeeklyReportCollection extends ConsumerStatefulWidget {
  const WeeklyReportCollection({
    super.key,
    required this.teamId,
    required this.stageLabel,
    required this.item,
    this.semesterId,
    this.projectVersion,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic> item;
  final int? semesterId;
  final int? projectVersion;

  @override
  ConsumerState<WeeklyReportCollection> createState() =>
      _WeeklyReportCollectionState();
}

class _WeeklyReportCollectionState
    extends ConsumerState<WeeklyReportCollection> {
  Map<String, dynamic>? collection;
  bool loading = true;
  bool busy = false;
  bool pickingFiles = false;
  String? error;
  int generation = 0;

  Map<String, String> get identity => {
    'team_id': '${widget.teamId}',
    'stage_label': widget.stageLabel,
    if (widget.semesterId != null) 'semester_id': '${widget.semesterId}',
    if (widget.projectVersion != null)
      'project_version': '${widget.projectVersion}',
  };

  Uri endpoint({bool review = false, bool write = false}) {
    final state = ref.read(capstoneDeliverablesProvider);
    return Uri.parse(
      '${ApiConfig.weeklyProgressUrl}/collection/${review ? 'review/' : ''}',
    ).replace(
      queryParameters: write
          ? {
              'response_mode': 'team',
              'scope': 'capstone',
              'stage_label': widget.stageLabel,
              'status': state.status,
              'search': state.search,
              if (state.section != null) 'section': state.section!,
              if (state.yearLevel != null) 'year_level': state.yearLevel!,
              if (state.workspace.isNotEmpty) 'workspace': state.workspace,
            }
          : identity,
    );
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant WeeklyReportCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId ||
        oldWidget.stageLabel != widget.stageLabel ||
        oldWidget.semesterId != widget.semesterId ||
        oldWidget.projectVersion != widget.projectVersion) {
      collection = null;
      load();
    }
  }

  Future<void> load() async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(endpoint());
      if (!mounted || ticket != generation) return;
      if (response.statusCode != 200) throw StateError(_error(response));
      setState(
        () => collection = Map<String, dynamic>.from(jsonDecode(response.body)),
      );
    } catch (e) {
      if (mounted && ticket == generation) setState(() => error = _message(e));
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  Future<void> consume(http.Response response, {int? ticket}) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_error(response));
    }
    final payload = Map<String, dynamic>.from(jsonDecode(response.body));
    if (!mounted) return;
    final current = ticket == null || ticket == generation;
    if (current) {
      setState(() {
        collection = Map<String, dynamic>.from(payload['collection']);
        error = null;
      });
    }
    if (!ref
            .read(capstoneDeliverablesProvider.notifier)
            .applyWeeklyReportResponse(payload) &&
        current) {
      await ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
    }
  }

  Future<void> review(Map week, String decision) async {
    final activity = DeliverablePopupActivity.maybeOf(context);
    final ticket = generation;
    final target = Map<String, String>.from(identity);
    final url = endpoint(review: true, write: true);
    final feedback = TextEditingController();
    String? validation;
    final confirmed = await showDeliverablePopupStep<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => DefensysShadcnScope(
          child: ShadDialog(
            title: Text(
              decision == 'accepted'
                  ? 'Accept Week ${week['week_number']}?'
                  : 'Request correction',
            ),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ShadButton(
                backgroundColor: DefensysTokens.maroonOf(context),
                foregroundColor: Colors.white,
                onPressed: () {
                  if (decision == 'rejected' && feedback.text.trim().isEmpty) {
                    update(
                      () => validation = 'Describe the correction needed.',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: Text(
                  decision == 'accepted'
                      ? 'Accept report'
                      : 'Request correction',
                ),
              ),
            ],
            scrollable: true,
            titlePinned: true,
            actionsPinned: true,
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (decision == 'accepted')
                    const Text(
                      'Confirm that you reviewed the uploaded PDF and its physical adviser signature.',
                    ),
                  if (decision == 'rejected')
                    ShadInput(
                      controller: feedback,
                      minLines: 3,
                      maxLines: 6,
                      placeholder: const Text('Correction feedback'),
                    ),
                  if (validation != null)
                    Text(
                      validation!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final text = feedback.text.trim();
    feedback.dispose();
    if (confirmed != true || !mounted || ticket != generation) return;
    activity?.value = true;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .post(
            url,
            body: jsonEncode({
              ...target,
              'version_id': (week['file'] as Map)['id'],
              'status': decision,
              'feedback': text,
            }),
          );
      await consume(response, ticket: ticket);
    } catch (e) {
      if (mounted && ticket == generation) setState(() => error = _message(e));
    } finally {
      activity?.value = false;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> history(Map week) async {
    final ticket = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(
            Uri.parse(
              '${ApiConfig.weeklyProgressUrl}/${week['report_id']}/versions/',
            ),
          );
      if (response.statusCode != 200) throw StateError(_error(response));
      final versions = (jsonDecode(response.body)['versions'] as List)
          .whereType<Map>()
          .toList();
      if (!mounted || ticket != generation) return;
      await showDeliverablePopupStep<void>(
        context: context,
        builder: (dialogContext) => DefensysShadcnScope(
          child: ShadDialog(
            title: Text('Week ${week['week_number']} history'),
            scrollable: true,
            titlePinned: true,
            actionsPinned: true,
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
            child: SizedBox(
              width: 560,
              height: 360,
              child: ListView(
                children: [
                  for (final version in versions)
                    ListTile(
                      title: Text(
                        'Version ${version['revision']} · ${version['file_name']}',
                      ),
                      subtitle: Text(
                        (version['reviews'] as List? ?? []).isEmpty
                            ? '${version['status']}\n${version['feedback'] ?? ''}'
                            : (version['reviews'] as List)
                                  .whereType<Map>()
                                  .map(
                                    (review) =>
                                        '${review['status']} · ${review['reviewer_name']}\n${review['feedback'] ?? ''}',
                                  )
                                  .join('\n'),
                      ),
                      trailing: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () => viewFileInDialog(
                          context: dialogContext,
                          fileUrl: '${version['file_url']}',
                          fileName: '${version['file_name']}',
                        ),
                        child: const Text('View PDF'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted && ticket == generation) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> uploadReport({
    required PlatformFile file,
    required int week,
    required String requestId,
    required Map<String, String> target,
    required Uri url,
    required int ticket,
  }) async {
    if (!mounted || ticket != generation) {
      throw StateError(
        'The selected team or reporting period changed. Reopen the weekly collection.',
      );
    }
    if (file.extension?.toLowerCase() != 'pdf' ||
        file.bytes == null ||
        file.bytes!.isEmpty ||
        file.size == 0 ||
        file.size > 50 * 1024 * 1024 ||
        file.bytes!.length > 50 * 1024 * 1024) {
      throw StateError('Choose a non-empty PDF of up to 50 MB.');
    }
    final request = http.MultipartRequest('POST', url)
      ..fields.addAll({
        ...target,
        'week_number': '$week',
        'request_id': requestId,
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          'report_file',
          file.bytes!,
          filename: file.name,
        ),
      );
    final response = await http.Response.fromStream(
      await ref
          .read(authenticatedHttpClientProvider)
          .sendAuthenticated(request, retryOn401: false),
    );
    await consume(response, ticket: ticket);
  }

  Future<void> pickFiles({int? targetWeek}) async {
    if (busy || loading || pickingFiles) return;
    final activity = DeliverablePopupActivity.maybeOf(context);
    final ticket = generation;
    final target = Map<String, String>.from(identity);
    final url = endpoint(write: true);
    FilePickerResult? picked;
    pickingFiles = true;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        withData: true,
      );
    } catch (e) {
      if (mounted && ticket == generation) setState(() => error = _message(e));
      return;
    } finally {
      pickingFiles = false;
    }
    if (picked == null ||
        picked.files.isEmpty ||
        !mounted ||
        ticket != generation) {
      return;
    }
    final files = picked.files;
    final available = ((collection ?? widget.item)['weeks'] as List? ?? [])
        .whereType<Map>()
        .where((week) => week['required'] == true && week['can_upload'] == true)
        .map((week) => week['week_number'] as int)
        .toList();
    // A row already supplies the destination; only a batch needs week mapping.
    if (files.length == 1 && targetWeek != null) {
      if (!available.contains(targetWeek)) return;
      setState(() {
        busy = true;
        error = null;
      });
      activity?.value = true;
      try {
        await uploadReport(
          file: files.single,
          week: targetWeek,
          requestId: _requestId(),
          target: target,
          url: url,
          ticket: ticket,
        );
      } catch (e) {
        if (mounted && ticket == generation) {
          setState(() => error = 'Week $targetWeek: ${_message(e)}');
        }
      } finally {
        activity?.value = false;
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    final selected = <int?>[];
    final keys = <String>[];
    final done = <bool>[];
    final failures = <String?>[];
    for (final file in files) {
      final match = RegExp(
        r'week[\s_-]*(\d+)',
        caseSensitive: false,
      ).firstMatch(file.name);
      final guessed = match == null ? null : int.tryParse(match[1]!);
      selected.add(
        (selected.isEmpty && available.contains(targetWeek)
                ? targetWeek
                : null) ??
            (available.contains(guessed)
                ? guessed
                : available
                      .where((week) => !selected.contains(week))
                      .firstOrNull),
      );
      keys.add(_requestId());
      done.add(false);
      failures.add(null);
    }
    var sending = false;
    String? mappingError;
    await showDeliverablePopupStep<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !sending,
          child: DefensysShadcnScope(
            child: ShadDialog(
              title: const Text('Upload weekly reports'),
              closeIcon: const SizedBox.shrink(),
              scrollable: true,
              titlePinned: true,
              actionsPinned: true,
              actions: [
                ShadButton.outline(
                  enabled: !sending,
                  onPressed: sending
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(done.any((value) => value) ? 'Close' : 'Cancel'),
                ),
                ShadButton(
                  backgroundColor: DefensysTokens.maroonOf(context),
                  foregroundColor: Colors.white,
                  enabled: !sending && !done.every((value) => value),
                  onPressed: sending || done.every((value) => value)
                      ? null
                      : () async {
                          if (selected.any((week) => week == null) ||
                              selected.toSet().length != selected.length) {
                            update(
                              () => mappingError =
                                  'Choose a different reporting week for each file.',
                            );
                            return;
                          }
                          update(() {
                            sending = true;
                            mappingError = null;
                          });
                          activity?.value = true;
                          for (var i = 0; i < files.length; i++) {
                            if (done[i]) continue;
                            try {
                              await uploadReport(
                                file: files[i],
                                week: selected[i]!,
                                requestId: keys[i],
                                target: target,
                                url: url,
                                ticket: ticket,
                              );
                              update(() {
                                done[i] = true;
                                failures[i] = null;
                              });
                            } catch (e) {
                              update(() => failures[i] = _message(e));
                            }
                          }
                          update(() => sending = false);
                          activity?.value = false;
                        },
                  child: Text(
                    sending
                        ? 'Uploading...'
                        : done.any((value) => value)
                        ? 'Retry remaining'
                        : 'Upload reports',
                  ),
                ),
              ],
              child: SizedBox(
                width: 650,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Assign each signed PDF to its reporting week. Overdue weeks remain open.',
                      ),
                      if (mappingError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            mappingError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      for (var i = 0; i < files.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                files[i].name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              if (done[i])
                                const Text(
                                  'Uploaded',
                                  style: TextStyle(color: Colors.green),
                                )
                              else
                                ShadSelect<int>(
                                  key: ValueKey(
                                    'report-week-$i-${selected[i]}',
                                  ),
                                  enabled: !sending,
                                  initialValue: selected[i],
                                  placeholder: const Text('Reporting week'),
                                  selectedOptionBuilder: (context, value) =>
                                      Text('Week $value'),
                                  options: [
                                    for (final week in available)
                                      ShadOption<int>(
                                        value: week,
                                        child: Text('Week $week'),
                                      ),
                                  ],
                                  onChanged: sending
                                      ? null
                                      : (week) =>
                                            update(() => selected[i] = week),
                                ),
                              if (failures[i] != null)
                                Text(
                                  failures[i]!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (sending)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = collection ?? widget.item;
    final summary = RequirementSummary(data);
    final weeks = (data['weeks'] as List? ?? []).whereType<Map>().toList();
    final user = ref.watch(authProvider).user;
    final student = user?['role'] == 'student';
    final requiredWeeks =
        weeks.where((week) => week['required'] == true).toList()..sort(
          (a, b) =>
              (a['week_number'] as num).compareTo(b['week_number'] as num),
        );
    final caption = DefensysTokens.caption.copyWith(
      fontFamily: DefensysTokens.fontFamilyInter,
      color: DefensysTokens.textSecondaryOf(context),
    );
    String coverage(Map week) {
      final start = DateTime.tryParse('${week['starts_on']}');
      final end = DateTime.tryParse('${week['ends_on']}');
      if (start == null || end == null) {
        return [
          week['starts_on'],
          week['ends_on'],
        ].where((value) => value != null && '$value'.isNotEmpty).join(' – ');
      }
      if (start.year != end.year) {
        return '${DateFormat('MMM d, y').format(start)} – ${DateFormat('MMM d, y').format(end)}';
      }
      final last = DateFormat(
        start.month == end.month ? 'd, y' : 'MMM d, y',
      ).format(end);
      return '${DateFormat('MMM d').format(start)}–$last';
    }

    String date(dynamic raw) {
      final parsed = DateTime.tryParse('$raw');
      return parsed == null
          ? ''
          : DateFormat(
              'MMM d, yyyy · h:mm a',
            ).format(parsed.toUtc().add(const Duration(hours: 8)));
    }

    String submissionSummary(Map week) {
      final file = week['file'] as Map;
      final revision = (file['revision'] as num?)?.toInt() ?? 1;
      final uploaded = date(file['uploaded_at']);
      return [
        if (revision > 1) 'Version $revision',
        if (uploaded.isNotEmpty)
          '${revision > 1 ? 'Updated' : 'Submitted'} $uploaded',
        if (uploaded.isEmpty && revision == 1) 'Submitted',
      ].join(' · ');
    }

    String submissionDetails(Map week) {
      final file = week['file'] as Map;
      final first = date(week['first_submitted_at']);
      final uploaded = date(file['uploaded_at']);
      return [
        if (first.isNotEmpty) 'First submitted $first',
        if (uploaded.isNotEmpty)
          'Version ${file['revision'] ?? 1} uploaded $uploaded',
        'Times in Asia/Manila',
      ].join('\n');
    }

    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!student) ...[
            _WeeklyStageOverview(
              stageLabel: widget.stageLabel,
              summary: summary,
              weeks: requiredWeeks,
              onRefresh: busy || loading ? null : load,
            ),
            const SizedBox(height: 12),
          ],
          DeliverableTemplateDownload(template: widget.item['template']),
          const SizedBox(height: 8),
          Text(
            'Deadlines use Asia/Manila. Late reports can still be submitted and accepted.',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (loading || busy)
            LinearProgressIndicator(color: DefensysTokens.maroonOf(context)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Required reports',
                    style: DefensysTokens.body.copyWith(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                ),
                if (student)
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    width: 40,
                    height: 40,
                    padding: EdgeInsets.zero,
                    enabled: !busy && !loading,
                    onPressed: busy || loading ? null : load,
                    child: const Tooltip(
                      message: 'Refresh weekly reports',
                      child: Icon(Icons.refresh, size: 18),
                    ),
                  ),
              ],
            ),
          ),
          for (final week in requiredWeeks)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceOf(context),
                border: Border.all(color: DefensysTokens.borderOf(context)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Week ${week['week_number']}',
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamilyInter,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            DeliverableStatusBadge(
                              label: switch ('${week['status']}') {
                                'accepted' => 'Accepted',
                                'pending' => 'Awaiting review',
                                'rejected' => 'Needs correction',
                                _ =>
                                  week['timing'] == 'upcoming'
                                      ? 'Upcoming'
                                      : 'Missing',
                              },
                              tone: week['status'] == 'accepted'
                                  ? WorkflowStatusTone.success
                                  : week['status'] == 'rejected'
                                  ? WorkflowStatusTone.attention
                                  : WorkflowStatusTone.neutral,
                            ),
                            if (week['timing'] == 'late' ||
                                week['timing'] == 'overdue')
                              DeliverableStatusBadge(
                                label: week['timing'] == 'late'
                                    ? 'Late'
                                    : 'Overdue',
                                tone: WorkflowStatusTone.attention,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${coverage(week)}\nDue ${date(week['due_at'])}',
                    style: caption,
                  ),
                  if (week['file'] is Map) ...[
                    const SizedBox(height: 10),
                    DeliverableUploadedFileTile(
                      fileName: '${week['file']['file_name']}',
                      onDetails: () => viewFileInDialog(
                        context: context,
                        fileUrl: '${week['file']['file_url']}',
                        fileName: '${week['file']['file_name']}',
                      ),
                      onRevision:
                          week['status'] == 'rejected' &&
                              week['can_upload'] == true
                          ? () => pickFiles(
                              targetWeek: week['week_number'] as int,
                            )
                          : null,
                      revisionEnabled: !busy,
                    ),
                    const SizedBox(height: 6),
                    Tooltip(
                      message: submissionDetails(week),
                      child: Text(submissionSummary(week), style: caption),
                    ),
                    if ('${week['file']['feedback'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${week['file']['feedback']}',
                          style: caption,
                        ),
                      ),
                  ],
                  if (week['file'] == null && week['can_upload'] == true) ...[
                    const SizedBox(height: 10),
                    DeliverableUploadTile(
                      title: 'Upload Week ${week['week_number']} report',
                      format: DeliverableFormatInfo.fromFormat('pdf'),
                      enabled: !busy,
                      onUpload: () =>
                          pickFiles(targetWeek: week['week_number'] as int),
                    ),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (week['file'] is Map)
                        ShadButton.outline(
                          size: ShadButtonSize.sm,
                          enabled: !busy,
                          onPressed: busy
                              ? null
                              : () => viewFileInDialog(
                                  context: context,
                                  fileUrl: '${week['file']['file_url']}',
                                  fileName: '${week['file']['file_name']}',
                                ),
                          child: const Text('View PDF'),
                        ),
                      if (week['can_upload'] == true &&
                          week['file'] is Map &&
                          week['status'] != 'rejected')
                        ShadButton.outline(
                          size: ShadButtonSize.sm,
                          enabled: !busy,
                          onPressed: busy
                              ? null
                              : () => pickFiles(
                                  targetWeek: week['week_number'] as int,
                                ),
                          leading: const Icon(Icons.upload_file, size: 16),
                          child: Text(
                            week['file'] == null
                                ? 'Upload'
                                : 'Submit new version',
                          ),
                        ),
                      if (week['can_review'] == true &&
                          week['status'] == 'pending')
                        ShadButton(
                          size: ShadButtonSize.sm,
                          backgroundColor: DefensysTokens.maroonOf(context),
                          foregroundColor: Colors.white,
                          enabled: !busy,
                          onPressed: busy
                              ? null
                              : () => review(week, 'accepted'),
                          child: const Text('Accept'),
                        ),
                      if (week['can_review'] == true &&
                          week['status'] != 'rejected')
                        ShadButton.outline(
                          size: ShadButtonSize.sm,
                          enabled: !busy,
                          onPressed: busy
                              ? null
                              : () => review(week, 'rejected'),
                          child: const Text('Request correction'),
                        ),
                      if (week['history_url'] != null)
                        ShadButton.ghost(
                          size: ShadButtonSize.sm,
                          enabled: !busy,
                          onPressed: busy ? null : () => history(week),
                          child: const Text('History'),
                        ),
                    ],
                  ),
                  if ('${week['blocker'] ?? ''}'.isNotEmpty)
                    Text('${week['blocker']}', style: caption),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
