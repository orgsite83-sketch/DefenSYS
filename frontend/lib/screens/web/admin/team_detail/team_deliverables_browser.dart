import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../config/api_config.dart';
import '../../../../services/authenticated_client.dart';
import '../../../../services/team_detail_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../utils/universal_file_viewer.dart';
import '../../../../widgets/repository/requirement_summary.dart';
import '../../../../widgets/shadcn/defensys_breadcrumb.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../shared/project_archive/components/archive_browser_cards.dart';
import '../../shared/project_archive/dialogs/archive_file_details_dialog.dart';
import 'team_detail_components.dart';

class _TeamFolder {
  const _TeamFolder(
    this.key,
    this.title,
    this.subtitle,
    this.files, {
    this.missing = 0,
    this.item,
    this.kind = 'requirement',
  });
  final String key, title, subtitle, kind;
  final List<Map<String, dynamic>> files;
  final int missing;
  final Map<String, dynamic>? item;
  int get fileCount => kind == 'weekly'
      ? ((item?['weekly_summary'] as Map?)?['uploaded'] as num? ?? 0).toInt()
      : files.where((file) => file['has_file'] == true).length;
}

/// Browses active team evidence using Project Archive's shared folder/file cards.
/// Every action here is a read, preview, or download, including weekly reports.
class TeamDeliverablesBrowser extends ConsumerStatefulWidget {
  const TeamDeliverablesBrowser({
    super.key,
    required this.teamId,
    required this.state,
    required this.stage,
    required this.stageLabel,
    required this.onRetry,
    required this.onDownloadDocument,
    required this.onViewReport,
  });
  final int teamId;
  final TeamDetailState state;
  final Map<String, dynamic> stage;
  final String stageLabel;
  final VoidCallback onRetry;
  final ValueChanged<int> onDownloadDocument;
  final ValueChanged<Map<String, dynamic>> onViewReport;

  @override
  ConsumerState<TeamDeliverablesBrowser> createState() =>
      _TeamDeliverablesBrowserState();
}

class _TeamDeliverablesBrowserState
    extends ConsumerState<TeamDeliverablesBrowser> {
  final search = TextEditingController();
  String? selected;
  bool list = false, history = false, busy = false;
  String sort = 'name';
  String? error;
  Map<String, dynamic>? collection, historyWeek;
  List<Map<String, dynamic>> versions = [];
  int generation = 0;

  bool get capstone =>
      '${widget.state.team?['level']}'.toUpperCase().contains('CAPSTONE');

  @override
  void dispose() {
    generation++;
    search.dispose();
    super.dispose();
  }

  String identity(Map row) =>
      '${row['id'] ?? row['deliverable_id'] ?? row['label']}';
  String countLabel(int count, String name) =>
      '$count $name${count == 1 ? '' : 's'}';
  String date(dynamic raw) {
    final parsed = DateTime.tryParse('$raw');
    return parsed == null ? '' : DateFormat('d MMM yyyy').format(parsed);
  }

  String status(dynamic raw) => switch ('$raw'.toLowerCase()) {
    'accepted' || 'approved' => 'Accepted',
    'pending' || 'pending_review' || 'submitted' => 'Under review',
    'rejected' ||
    'needs_revision' ||
    'needs revision' => 'Corrections requested',
    'missing' => 'Not uploaded',
    '' => 'Uploaded',
    _ => '$raw',
  };

  Map<String, dynamic> file(
    Map raw, {
    String? title,
    String? label,
    bool placeholder = false,
  }) {
    final url = '${raw['file_url'] ?? raw['pdf_url'] ?? ''}';
    return <String, dynamic>{
      ...raw,
      'file_url': url,
      'has_file': url.isNotEmpty,
      'file_name': placeholder
          ? ''
          : '${raw['file_name'] ?? title ?? label ?? 'Document'}',
      'deliverable_label':
          title ?? '${raw['file_name'] ?? label ?? 'Document'}',
      'status': placeholder
          ? '${raw['status_label'] ?? 'Not uploaded'}'
          : status(raw['status']),
      'uploaded_by':
          raw['uploaded_by_name'] ??
          raw['student_name'] ??
          (raw['uploaded_by'] is String ? raw['uploaded_by'] : ''),
      'stage': widget.stageLabel,
      'team_name': widget.state.team?['name'],
      'project_title': widget.state.team?['project_title'],
      'year_level': widget.state.team?['year_level'],
      'can_override': false,
      '_placeholder': placeholder,
    };
  }

  List<Map<String, dynamic>> requirementFiles(
    Map<String, dynamic> item, {
    bool past = false,
  }) {
    final submission = item['submission'] as Map? ?? {};
    final raw = detailRows(submission[past ? 'file_history' : 'files'])
        .where(
          (row) =>
              past ? row['is_current'] != true : row['is_current'] != false,
        )
        .toList();
    if (!past && raw.isEmpty && '${submission['file_url'] ?? ''}'.isNotEmpty) {
      raw.add(Map<String, dynamic>.from(submission));
    }
    final result = [
      for (final row in raw)
        file({
          ...row,
          'uploaded_by_name':
              row['uploaded_by_name'] ?? submission['uploaded_by_name'],
          'status': row['status'] ?? submission['status'],
        }, label: '${item['label']}'),
    ];
    if (!past) {
      final slots = detailRows(
        item['document_slots'],
      ).where((slot) => slot['required'] != false);
      for (final slot in slots) {
        if (!raw.any((row) => row['slot_key'] == slot['key'])) {
          result.add(
            file(
              {'id': 'missing-${slot['key']}', 'slot_key': slot['key']},
              title: '${slot['label'] ?? slot['key']}',
              placeholder: true,
            ),
          );
        }
      }
      if (result.isEmpty) {
        result.add(
          file(
            {'id': 'missing-${identity(item)}'},
            title: '${item['label'] ?? 'Document'}',
            placeholder: true,
          ),
        );
      }
    }
    return result;
  }

  List<_TeamFolder> get folders {
    final system = detailRows(widget.stage['system']);
    final systemIds = system.map(identity).toSet();
    final items = detailRows(widget.stage['deliverables']).where(
      (item) =>
          (capstone || item['source'] != 'weekly_reports') &&
          item['source'] != 'defense_minutes' &&
          !systemIds.contains(identity(item)),
    );
    final result = <_TeamFolder>[];
    for (final item in items) {
      final summary = RequirementSummary(item);
      final weekly = item['source'] == 'weekly_reports';
      result.add(
        _TeamFolder(
          'requirement-${identity(item)}',
          '${item['label'] ?? 'Deliverable'}',
          weekly
              ? '${summary.required} reporting ${summary.required == 1 ? 'week' : 'weeks'}'
              : item['type'] == 'post' || item['type'] == 'vault'
              ? 'After defense'
              : 'Before defense',
          requirementFiles(item),
          item: item,
          missing: summary.missing,
          kind: weekly ? 'weekly' : 'requirement',
        ),
      );
    }
    if (system.isNotEmpty) {
      final files = <Map<String, dynamic>>[];
      for (final record in system) {
        final records = detailRows(record['records']);
        for (final version in records.isEmpty ? [record] : records) {
          files.add(
            file(
              {
                ...version,
                'id':
                    '${identity(record)}-${version['schedule_id'] ?? 'pending'}',
                'file_name': '${record['label'] ?? 'Signed minutes'}.pdf',
                'status_label':
                    version['status_label'] ?? record['status_label'],
                'status': version['completed'] == true
                    ? 'Signed'
                    : version['status_label'] ?? record['status_label'],
                'archive_note': version['schedule_id'] == null
                    ? ''
                    : 'Session ${version['schedule_id']}',
              },
              title: '${record['label'] ?? 'System record'}',
              placeholder: version['pdf_url'] == null,
            ),
          );
        }
        // Preserve earlier uploads when the generated record shares a stable ID.
        for (final item in detailRows(
          widget.stage['deliverables'],
        ).where((item) => identity(item) == identity(record))) {
          files.addAll(
            requirementFiles(item).where((entry) => entry['has_file'] == true),
          );
        }
      }
      result.add(
        _TeamFolder(
          'system',
          'System records',
          'Signed minutes and generated records',
          files,
          kind: 'system',
        ),
      );
    }
    if (widget.state.documents.isNotEmpty) {
      result.add(
        _TeamFolder(
          'legacy-documents',
          'Legacy documents',
          'Earlier team uploads',
          [
            for (final doc in widget.state.documents)
              file({
                ...doc,
                'file_url':
                    '${ApiConfig.teamDocumentsUrl}/${doc['id']}/download/',
                '_legacy_document_id': doc['id'],
                'status': 'Recorded',
              }),
          ],
          kind: 'legacy',
        ),
      );
    }
    if (capstone && widget.state.weeklyReports.isNotEmpty) {
      result.add(
        _TeamFolder(
          'legacy-reports',
          'Legacy reports',
          'Earlier Capstone reports',
          [
            for (final report in widget.state.weeklyReports)
              file({
                ...report,
                'file_url': report['file_url'] ?? report['report_file'],
                '_legacy_report': report,
                'uploaded_at': report['submitted_at'],
                'status': 'Recorded',
                'archive_note': 'Week ${report['week_number']}',
              }, title: 'Week ${report['week_number']} report'),
          ],
          kind: 'legacy',
        ),
      );
    }
    return result;
  }

  Future<void> open(_TeamFolder folder) async {
    generation++;
    setState(() {
      selected = folder.key;
      history = false;
      historyWeek = null;
      collection = null;
      versions = [];
      error = null;
      busy = false;
      search.clear();
    });
    if (folder.kind == 'weekly') await loadWeekly();
  }

  Future<void> loadWeekly() async {
    final team = widget.state.deliverableTeam ?? {};
    await read(
      Uri.parse('${ApiConfig.weeklyProgressUrl}/collection/').replace(
        queryParameters: {
          'team_id': '${widget.teamId}',
          'stage_label': widget.stageLabel,
          if (team['semester_id'] != null)
            'semester_id': '${team['semester_id']}',
          if (team['project_version'] != null)
            'project_version': '${team['project_version']}',
        },
      ),
      (payload) => collection = payload,
    );
  }

  Future<void> read(Uri uri, void Function(Map<String, dynamic>) apply) async {
    final ticket = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final resolved = uri.hasScheme
          ? uri
          : Uri.parse(ApiConfig.baseUrl).resolveUri(uri);
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(resolved);
      if (!mounted || ticket != generation) return;
      if (response.statusCode != 200) {
        throw StateError('Files could not be loaded. Please try again.');
      }
      final payload = Map<String, dynamic>.from(jsonDecode(response.body));
      setState(() => apply(payload));
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => error = 'Files could not be loaded. Please try again.');
      }
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  void back() {
    generation++;
    setState(() {
      if (history) {
        history = false;
        historyWeek = null;
      } else {
        selected = null;
        collection = null;
      }
      versions = [];
      busy = false;
      error = null;
      search.clear();
    });
  }

  Future<void> weekHistory(Map<String, dynamic> entry) async {
    final url = entry['_history_url'];
    if (url == null) return;
    setState(() {
      history = true;
      historyWeek = entry;
      search.clear();
    });
    await read(
      Uri.parse('$url'),
      (payload) => versions = [
        for (final version in detailRows(payload['versions'])) file(version),
      ],
    );
  }

  List<Map<String, dynamic>> weeklyFiles(_TeamFolder folder) {
    if (collection == null) return [];
    return [
      for (final week in detailRows(
        collection!['weeks'],
      ).where((week) => week['required'] == true))
        file(
          {
            ...Map<String, dynamic>.from(week['file'] as Map? ?? {}),
            'id': 'week-${week['week_number']}',
            '_history_url': week['history_url'],
            '_week_number': week['week_number'],
            'status': (week['file'] as Map?)?['status'] ?? week['status'],
            'status_label': week['timing'] == 'upcoming'
                ? 'Upcoming'
                : 'Not uploaded',
            'archive_note': [
              'Week ${week['week_number']}',
              '${date(week['starts_on'])} – ${date(week['ends_on'])}',
              if (week['timing'] == 'late') 'Late',
              if (week['timing'] == 'overdue') 'Overdue',
            ].join(' · '),
          },
          title:
              (week['file'] as Map?)?['file_name']?.toString() ??
              'Week ${week['week_number']}',
          placeholder:
              week['file'] == null &&
              (week['status'] == 'missing' || week['status'] == null),
        ),
    ];
  }

  void details(Map<String, dynamic> entry) {
    final report = entry['_legacy_report'] as Map?;
    if (report != null && entry['has_file'] != true) {
      showShadDialog<void>(
        context: context,
        builder: (context) => DefensysShadcnScope(
          child: ShadDialog(
            title: Text('${entry['deliverable_label']}'),
            scrollable: true,
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
            child: SizedBox(
              width: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${report['student_name'] ?? ''} · ${date(report['report_date'])}',
                  ),
                  for (final field in {
                    'accomplishments': 'Accomplishments',
                    'contributions': 'Contributions',
                    'issues': 'Issues',
                    'plans': 'Plans',
                  }.entries)
                    if ((report[field.key] as List? ?? []).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '${field.value}: ${(report[field.key] as List).map((value) => value is Map ? value.values.join(' · ') : '$value').join('\n')}',
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }
    ArchiveFileDetailsDialog.show(
      context: context,
      entry: entry,
      archiveContext: false,
      onViewPdf: (_, _) => preview(entry),
      onDownloadFile: (_, _) => download(entry),
    );
  }

  void preview(Map<String, dynamic> entry) {
    if (entry['_legacy_report'] is Map) {
      widget.onViewReport(
        Map<String, dynamic>.from(entry['_legacy_report'] as Map),
      );
    } else {
      viewFileInDialog(
        context: context,
        fileUrl: '${entry['file_url']}',
        fileName: '${entry['file_name']}',
      );
    }
  }

  Future<void> download(Map<String, dynamic> entry) async {
    final legacyId = int.tryParse('${entry['_legacy_document_id']}');
    if (legacyId != null) {
      widget.onDownloadDocument(legacyId);
      return;
    }
    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile('${entry['file_url']}');
      await downloadBytesFile(
        bytes: bytes,
        fileName: '${entry['file_name']}'.split(RegExp(r'[/\\]')).last,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'The file could not be downloaded. Please try again.',
        );
      }
    }
  }

  Widget badge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceHigherOf(context),
      border: Border.all(color: DefensysTokens.borderOf(context)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: DefensysTokens.caption.copyWith(
        fontSize: 10,
        color: DefensysTokens.textSecondaryOf(context),
      ),
    ),
  );

  Widget fileCard(Map<String, dynamic> entry) => ArchiveFileCard(
    tapKey: ValueKey('team-file-${entry['id'] ?? entry['file_name']}'),
    title: '${entry['deliverable_label']}',
    fileName: '${entry['file_name']}',
    list: list,
    missing: entry['_placeholder'] == true,
    metadata: [
      if ('${entry['archive_note'] ?? ''}'.isNotEmpty)
        '${entry['archive_note']}',
      if (entry['revision'] != null) 'Version ${entry['revision']}',
      if (date(entry['uploaded_at']).isNotEmpty) date(entry['uploaded_at']),
      if (entry['_placeholder'] == true) 'Not uploaded',
    ].join(' · '),
    status: badge('${entry['status']}'),
    onOpen: () => details(entry),
    actions: _FileActions(
      onDetails: () => details(entry),
      onPreview: entry['has_file'] == true ? () => preview(entry) : null,
      onDownload: entry['has_file'] == true ? () => download(entry) : null,
      onHistory: entry['_history_url'] == null
          ? null
          : () => weekHistory(entry),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final allFolders = folders;
    final current = allFolders
        .where((folder) => folder.key == selected)
        .firstOrNull;
    final fileCount = allFolders.fold<int>(
      0,
      (total, folder) => total + folder.fileCount,
    );
    final query = search.text.trim().toLowerCase();
    bool matches(String value) => value.toLowerCase().contains(query);
    final visibleFolders =
        allFolders
            .where((folder) => matches('${folder.title} ${folder.subtitle}'))
            .toList()
          ..sort((a, b) {
            String latest(_TeamFolder folder) =>
                folder.files.fold<String>('', (value, file) {
                  final date = '${file['uploaded_at'] ?? ''}';
                  return date.compareTo(value) > 0 ? date : value;
                });
            if (sort == 'newest') return latest(b).compareTo(latest(a));
            return sort == 'name_desc'
                ? b.title.toLowerCase().compareTo(a.title.toLowerCase())
                : a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
    final entries = current == null
        ? <Map<String, dynamic>>[]
        : history
        ? historyWeek == null
              ? requirementFiles(current.item!, past: true)
              : versions
        : current.kind == 'weekly'
        ? weeklyFiles(current)
        : current.files;
    final visibleFiles =
        entries
            .where(
              (entry) => matches(
                '${entry['file_name']} ${entry['deliverable_label']} ${entry['archive_note'] ?? ''}',
              ),
            )
            .toList()
          ..sort(
            (a, b) => sort == 'newest'
                ? '${b['uploaded_at'] ?? ''}'.compareTo(
                    '${a['uploaded_at'] ?? ''}',
                  )
                : sort == 'name_desc'
                ? '${b['deliverable_label']}'.compareTo(
                    '${a['deliverable_label']}',
                  )
                : '${a['deliverable_label']}'.compareTo(
                    '${b['deliverable_label']}',
                  ),
          );
    final children = current == null
        ? <Widget>[
            for (final folder in visibleFolders)
              ArchiveFolderCard(
                tapKey: ValueKey('team-folder-${folder.key}'),
                title: folder.title,
                subtitle: folder.subtitle,
                countLabel:
                    '${folder.fileCount} ${folder.fileCount == 1 ? 'file' : 'files'}${folder.missing > 0 ? ' · ${folder.missing} missing' : ''}',
                list: list,
                onOpen: () => open(folder),
              ),
          ]
        : visibleFiles.map(fileCard).toList();
    return DefensysShadcnScope(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          border: Border.all(color: DefensysTokens.borderOf(context)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 3.5,
                  height: 16,
                  color: DefensysTokens.maroonOf(context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Team files',
                  style: DefensysTokens.sectionTitle.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                const Spacer(),
                ShadTooltip(
                  builder: (_) => const Text('Refresh files'),
                  child: ShadButton.ghost(
                    width: 32,
                    height: 32,
                    padding: EdgeInsets.zero,
                    enabled: !busy,
                    onPressed: () {
                      if (historyWeek != null) {
                        weekHistory(historyWeek!);
                      } else if (current?.kind == 'weekly') {
                        loadWeekly();
                      } else {
                        widget.onRetry();
                      }
                    },
                    child: const Icon(LucideIcons.refreshCw, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DefensysBreadcrumb(
              onBack: selected == null ? null : back,
              items: [
                DefensysBreadcrumbItem(
                  label: widget.stageLabel.isEmpty
                      ? 'Deliverables'
                      : widget.stageLabel,
                  icon: const Icon(LucideIcons.folderArchive, size: 14),
                  isCurrent: current == null,
                  onTap: current == null
                      ? null
                      : () {
                          history = false;
                          back();
                        },
                ),
                if (current != null)
                  DefensysBreadcrumbItem(
                    label: current.title,
                    isCurrent: !history,
                    onTap: history ? back : null,
                  ),
                if (history)
                  DefensysBreadcrumbItem(
                    label: historyWeek == null
                        ? 'Previous versions'
                        : 'Week ${historyWeek!['_week_number']} history',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 600
                        ? constraints.maxWidth
                        : constraints.maxWidth - 320,
                    child: ShadInput(
                      controller: search,
                      placeholder: Text(
                        current == null ? 'Search folders' : 'Search files',
                      ),
                      leading: const Icon(LucideIcons.search, size: 16),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  ShadSelect<String>(
                    key: ValueKey('team-file-sort-$sort'),
                    initialValue: sort,
                    minWidth: 150,
                    options: const [
                      ShadOption(value: 'name', child: Text('Name A–Z')),
                      ShadOption(value: 'name_desc', child: Text('Name Z–A')),
                      ShadOption(value: 'newest', child: Text('Newest first')),
                    ],
                    selectedOptionBuilder: (_, value) => Text(
                      value == 'newest'
                          ? 'Newest first'
                          : value == 'name_desc'
                          ? 'Name Z–A'
                          : 'Name A–Z',
                    ),
                    onChanged: (value) {
                      if (value != null) setState(() => sort = value);
                    },
                  ),
                  ShadButton.outline(
                    width: 36,
                    height: 36,
                    padding: EdgeInsets.zero,
                    foregroundColor: list
                        ? DefensysTokens.maroonTextOf(context)
                        : DefensysTokens.textSecondaryOf(context),
                    onPressed: () => setState(() => list = true),
                    child: Semantics(
                      label: 'List view',
                      child: Icon(Icons.view_list_rounded, size: 18),
                    ),
                  ),
                  ShadButton.outline(
                    width: 36,
                    height: 36,
                    padding: EdgeInsets.zero,
                    foregroundColor: !list
                        ? DefensysTokens.maroonTextOf(context)
                        : DefensysTokens.textSecondaryOf(context),
                    onPressed: () => setState(() => list = false),
                    child: Semantics(
                      label: 'Grid view',
                      child: Icon(Icons.grid_view_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  current == null
                      ? '${countLabel(allFolders.length, 'folder')} · ${countLabel(fileCount, 'file')}'
                      : countLabel(
                          entries
                              .where((entry) => entry['has_file'] == true)
                              .length,
                          'file',
                        ),
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                if (current?.kind == 'weekly' && !history && collection != null)
                  Text(
                    countLabel(
                      detailRows(
                        collection!['weeks'],
                      ).where((week) => week['required'] == true).length,
                      'required week',
                    ),
                    style: DefensysTokens.caption.copyWith(
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                if (current?.item != null &&
                    current?.kind != 'weekly' &&
                    requirementFiles(current!.item!, past: true).isNotEmpty &&
                    !history)
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: () => setState(() {
                      history = true;
                      search.clear();
                    }),
                    child: const Text('Previous versions'),
                  ),
              ],
            ),
            if (widget.state.legacyError != null)
              TeamDetailNotice(
                message: widget.state.legacyError!,
                onRetry: widget.onRetry,
              ),
            if (error != null)
              TeamDetailNotice(
                message: error!,
                onRetry: current?.kind == 'weekly'
                    ? () => historyWeek == null
                          ? loadWeekly()
                          : weekHistory(historyWeek!)
                    : null,
              ),
            const SizedBox(height: 12),
            if (busy)
              const ShadProgress()
            else if (children.isEmpty && error == null)
              TeamDetailNotice(
                message: query.isNotEmpty
                    ? 'No matches found.'
                    : history
                    ? 'No earlier files recorded.'
                    : current == null
                    ? 'No files or requirements configured.'
                    : 'No files uploaded yet.',
              )
            else if (list)
              Column(
                children: [
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: child,
                    ),
                ],
              )
            else
              ArchiveCardGrid(folders: current == null, children: children),
          ],
        ),
      ),
    );
  }
}

class _FileActions extends StatefulWidget {
  const _FileActions({
    required this.onDetails,
    this.onPreview,
    this.onDownload,
    this.onHistory,
  });
  final VoidCallback onDetails;
  final VoidCallback? onPreview, onDownload, onHistory;
  @override
  State<_FileActions> createState() => _FileActionsState();
}

class _FileActionsState extends State<_FileActions> {
  final controller = ShadPopoverController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget action(String label, IconData icon, VoidCallback callback) =>
      ShadButton.ghost(
        size: ShadButtonSize.sm,
        height: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        mainAxisAlignment: MainAxisAlignment.start,
        leading: Icon(icon, size: 15),
        onPressed: () {
          controller.hide();
          callback();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 118),
          child: Text(
            label,
            softWrap: true,
            style: const TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontSize: 13,
            ),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => ShadPopover(
    controller: controller,
    padding: const EdgeInsets.all(4),
    popover: (_) => DefensysShadcnScope(
      child: SizedBox(
        width: 175,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onPreview != null)
              action('Preview', LucideIcons.eye, widget.onPreview!),
            if (widget.onDownload != null)
              action('Download', LucideIcons.download, widget.onDownload!),
            action('File details', LucideIcons.info, widget.onDetails),
            if (widget.onHistory != null)
              action('Version history', LucideIcons.history, widget.onHistory!),
          ],
        ),
      ),
    ),
    child: ShadButton.outline(
      width: 32,
      height: 32,
      padding: EdgeInsets.zero,
      onPressed: controller.toggle,
      child: Semantics(
        label: 'File actions',
        child: Icon(Icons.more_horiz, size: 18),
      ),
    ),
  );
}
