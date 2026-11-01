import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../config/api_config.dart';
import '../../services/auth_provider.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../services/network/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../utils/universal_file_viewer.dart';
import 'deliverable_template.dart';
import 'requirement_summary.dart';

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
    final summary = RequirementSummary(item);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: const Icon(Icons.assignment_outlined, size: 20),
      title: Text('${item['label']}'),
      subtitle: Text(
        '${summary.progress} uploaded · ${summary.acceptedFiles} accepted'
        '${summary.detail.isEmpty ? '' : '\n${summary.detail}'}',
      ),
      trailing: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 1040,
              height: MediaQuery.sizeOf(context).height * .85,
              child: Column(
                children: [
                  ListTile(
                    title: Text('${item['label']}'),
                    trailing: IconButton(
                      tooltip: 'Close weekly reports',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: WeeklyReportCollection(
                        teamId: teamId,
                        stageLabel: stageLabel,
                        item: item,
                        semesterId: semesterId,
                        projectVersion: projectVersion,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        child: const Text('Manage reports'),
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
  bool allWeeks = false;
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
      allWeeks = false;
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
    final ticket = generation;
    final target = Map<String, String>.from(identity);
    final url = endpoint(review: true, write: true);
    final feedback = TextEditingController();
    String? validation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            decision == 'accepted'
                ? 'Accept Week ${week['week_number']}?'
                : 'Request correction',
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (decision == 'accepted')
                  const Text(
                    'Confirm that you reviewed the uploaded PDF and its physical adviser signature.',
                  ),
                if (decision == 'rejected')
                  TextField(
                    controller: feedback,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: 'Correction feedback',
                      errorText: validation,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (decision == 'rejected' && feedback.text.trim().isEmpty) {
                  update(() => validation = 'Describe the correction needed.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                decision == 'accepted' ? 'Accept report' : 'Request correction',
              ),
            ),
          ],
        ),
      ),
    );
    final text = feedback.text.trim();
    feedback.dispose();
    if (confirmed != true || !mounted || ticket != generation) return;
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
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Week ${week['week_number']} history'),
          content: SizedBox(
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
                    trailing: TextButton(
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted && ticket == generation) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickFiles({int? targetWeek}) async {
    final ticket = generation;
    final target = Map<String, String>.from(identity);
    final url = endpoint(write: true);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: targetWeek == null,
      withData: true,
    );
    if (picked == null || !mounted || ticket != generation) return;
    final available = (collection?['weeks'] as List? ?? [])
        .whereType<Map>()
        .where((week) => week['can_upload'] == true)
        .map((week) => week['week_number'] as int)
        .toList();
    final selected = <int?>[];
    final keys = <String>[];
    final done = <bool>[];
    final failures = <String?>[];
    for (final file in picked.files) {
      final match = RegExp(
        r'week[\s_-]*(\d+)',
        caseSensitive: false,
      ).firstMatch(file.name);
      final guessed = match == null ? null : int.tryParse(match[1]!);
      selected.add(
        targetWeek ??
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
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !sending,
          child: AlertDialog(
            title: const Text('Upload weekly reports'),
            content: SizedBox(
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
                    for (var i = 0; i < picked.files.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              picked.files[i].name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            if (done[i])
                              const Text(
                                'Uploaded',
                                style: TextStyle(color: Colors.green),
                              )
                            else
                              DropdownButtonFormField<int>(
                                initialValue: selected[i],
                                decoration: const InputDecoration(
                                  labelText: 'Reporting week',
                                ),
                                items: [
                                  for (final week in available)
                                    DropdownMenuItem(
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
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(dialogContext),
                child: Text(done.any((value) => value) ? 'Close' : 'Cancel'),
              ),
              FilledButton(
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
                        for (var i = 0; i < picked.files.length; i++) {
                          if (done[i]) continue;
                          try {
                            if (!mounted || ticket != generation) {
                              throw StateError(
                                'The selected team or reporting period changed. Reopen the weekly collection.',
                              );
                            }
                            final file = picked.files[i];
                            if (file.bytes == null ||
                                file.size == 0 ||
                                file.size > 50 * 1024 * 1024) {
                              throw StateError(
                                'Choose a non-empty PDF of up to 50 MB.',
                              );
                            }
                            final request = http.MultipartRequest('POST', url)
                              ..fields.addAll({
                                ...target,
                                'week_number': '${selected[i]}',
                                'request_id': keys[i],
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
                                  .sendAuthenticated(
                                    request,
                                    retryOn401: false,
                                  ),
                            );
                            await consume(response, ticket: ticket);
                            update(() {
                              done[i] = true;
                              failures[i] = null;
                            });
                          } catch (e) {
                            update(() => failures[i] = _message(e));
                          }
                        }
                        update(() => sending = false);
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
    final visible = weeks.where((week) => allWeeks || week['required'] == true);
    final user = ref.watch(authProvider).user;
    final caption = DefensysTokens.caption.copyWith(
      color: DefensysTokens.textSecondaryOf(context),
    );
    String date(dynamic raw) {
      final parsed = DateTime.tryParse('$raw');
      return parsed == null
          ? ''
          : DateFormat(
              'MMM d, yyyy · h:mm a',
            ).format(parsed.toUtc().add(const Duration(hours: 8)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${summary.acceptedFiles}/${summary.required} accepted',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text('${summary.uploaded} uploaded'),
            if (data['current_week'] != null)
              Text(
                data['current_week'] == 0
                    ? 'Reporting not started'
                    : 'Week ${data['current_week']}',
              ),
            DeliverableTemplateDownload(template: widget.item['template']),
            if (user?['role'] == 'student' &&
                weeks.any((week) => week['can_upload'] == true))
              FilledButton.icon(
                onPressed: busy || loading ? null : pickFiles,
                icon: const Icon(Icons.upload_file, size: 17),
                label: const Text('Upload PDFs'),
              ),
            IconButton(
              onPressed: busy || loading ? null : load,
              tooltip: 'Refresh weekly reports',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
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
        if (loading || busy) const LinearProgressIndicator(),
        if (!loading)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show all reporting weeks'),
            value: allWeeks,
            onChanged: (value) => setState(() => allWeeks = value),
          ),
        for (final week in visible)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Week ${week['week_number']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(switch ('${week['status']}') {
                      'accepted' => 'Accepted',
                      'pending' => 'Awaiting review',
                      'rejected' => 'Needs correction',
                      _ =>
                        week['timing'] == 'upcoming' ? 'Upcoming' : 'Missing',
                    }),
                    if (week['timing'] == 'late' || week['timing'] == 'overdue')
                      Text(
                        week['timing'] == 'late' ? 'Late' : 'Overdue',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (week['required'] != true)
                      const Text('Outside this stage\'s required range'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${week['starts_on']} to ${week['ends_on']} · Due ${date(week['due_at'])} Asia/Manila',
                  style: caption,
                ),
                if (week['file'] is Map) ...[
                  Text(
                    '${week['file']['file_name']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'First submitted ${date(week['first_submitted_at'])} · Version ${week['file']['revision']} uploaded ${date(week['file']['uploaded_at'])}',
                    style: caption,
                  ),
                  if ('${week['file']['feedback'] ?? ''}'.isNotEmpty)
                    Text('${week['file']['feedback']}'),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (week['file'] is Map)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => viewFileInDialog(
                                context: context,
                                fileUrl: '${week['file']['file_url']}',
                                fileName: '${week['file']['file_name']}',
                              ),
                        child: const Text('View PDF'),
                      ),
                    if (week['can_upload'] == true)
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => pickFiles(
                                targetWeek: week['week_number'] as int,
                              ),
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: Text(
                          week['file'] == null
                              ? 'Upload'
                              : 'Submit new version',
                        ),
                      ),
                    if (week['can_review'] == true &&
                        week['status'] == 'pending')
                      FilledButton(
                        onPressed: busy ? null : () => review(week, 'accepted'),
                        child: const Text('Accept'),
                      ),
                    if (week['can_review'] == true &&
                        week['status'] != 'rejected')
                      TextButton(
                        onPressed: busy ? null : () => review(week, 'rejected'),
                        child: const Text('Request correction'),
                      ),
                    if (week['history_url'] != null)
                      TextButton(
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
    );
  }
}
