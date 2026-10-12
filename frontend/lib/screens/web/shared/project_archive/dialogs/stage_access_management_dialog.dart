import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';

class StageAccessManagementDialog {
  static Future<void> show({
    required BuildContext context,
    required WidgetRef ref,
    int? teamId,
    String? teamName,
    required String scope,
    String programScope = 'capstone',
    String? yearLevel,
    ProjectArchiveState? state,
    List<String> availableStages = const [],
  }) => showDialog<void>(
    context: context,
    builder: (_) => _StageAccessDialog(
      teamId: teamId,
      teamName: teamName,
      scope: scope,
      programScope: programScope,
      yearLevel: yearLevel,
      availableStages: availableStages,
    ),
  );
}

class _StageAccessDialog extends ConsumerStatefulWidget {
  const _StageAccessDialog({
    this.teamId,
    this.teamName,
    required this.scope,
    required this.programScope,
    this.yearLevel,
    required this.availableStages,
  });
  final int? teamId;
  final String? teamName;
  final String scope;
  final String programScope;
  final String? yearLevel;
  final List<String> availableStages;

  @override
  ConsumerState<_StageAccessDialog> createState() => _StageAccessDialogState();
}

class _StageAccessDialogState extends ConsumerState<_StageAccessDialog> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _access;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  late String _program;
  late String _year;

  @override
  void initState() {
    super.initState();
    _program = widget.programScope;
    _year = widget.yearLevel ?? '';
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final access = await ref
        .read(capstoneDeliverablesProvider.notifier)
        .fetchStageAccess(
          scope: widget.scope,
          teamId: widget.teamId,
          programScope: _program,
          yearLevel: _year,
        );
    if (!mounted) return;
    setState(() {
      _access = access;
      _loading = false;
      _error = access == null
          ? ref.read(capstoneDeliverablesProvider).error ??
                'Could not load file access.'
          : null;
    });
  }

  Future<void> _change(
    Map<String, dynamic> stage,
    String type,
    bool allow, {
    String? deliverableId,
  }) async {
    final reason = _reason.text.trim();
    if (reason.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await ref
        .read(capstoneDeliverablesProvider.notifier)
        .unlockDeliverables(
          scope: widget.scope,
          teamId: widget.teamId,
          programScope:
              _access?['program_scope']?.toString() ?? widget.programScope,
          yearLevel: _access?['year_level']?.toString() ?? widget.yearLevel,
          stageLabel: stage['stage_label'].toString(),
          unlockType: type,
          deliverableId: deliverableId,
          targetState: allow,
          reason: reason,
        );
    if (!mounted) return;
    if (saved) {
      await _load();
      if (!mounted) return;
      ref.read(projectArchiveProvider.notifier).fetchEntries();
      showSuccessToast(
        context,
        'File access updated and recorded in Audit Trail.',
      );
    } else {
      setState(
        () => _error =
            ref.read(capstoneDeliverablesProvider).error ??
            'Could not update file access.',
      );
    }
    if (mounted) setState(() => _saving = false);
  }

  bool get _canChange =>
      !_saving && !_loading && _reason.text.trim().isNotEmpty;

  Widget _accessRow(
    Map<String, dynamic> stage,
    Map<String, dynamic> settings,
    String label,
    String type, {
    String? id,
  }) {
    final count = (settings['team_count'] as num?)?.toInt() ?? 0;
    final allowed = (settings['allowed_count'] as num?)?.toInt() ?? 0;
    final archived = (settings['archived_count'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            type == 'pre' ? Icons.description_outlined : Icons.archive_outlined,
            size: 17,
            color: const Color(0xFF475569),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${settings['mixed'] == true ? 'Mixed · ' : ''}$allowed of $count teams can upload'
                  '${archived > 0 ? ' · $archived archived' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (archived > 0)
                  const Text(
                    'Archived files require an Admin revision request.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            key: ValueKey('stageAccess:${stage['stage_label']}:${id ?? type}'),
            value: settings['unlocked'] == true,
            activeTrackColor: AppColors.maroon.withValues(alpha: 0.5),
            activeThumbColor: AppColors.maroon,
            onChanged: _canChange && count > 0 && archived != count
                ? (value) => _change(stage, type, value, deliverableId: id)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _stageCard(Map<String, dynamic> stage) {
    final pre = Map<String, dynamic>.from(stage['pre'] as Map? ?? {});
    final post = Map<String, dynamic>.from(stage['post'] as Map? ?? {});
    final deliverables = (stage['deliverables'] as List? ?? [])
        .whereType<Map>();
    final count = (pre['team_count'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stage['stage_label'].toString(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 18),
          _accessRow(stage, pre, 'Pre-Defense Files', 'pre'),
          _accessRow(stage, post, 'Post-Defense Files', 'post'),
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: _canChange && count > 0
                    ? () => _change(stage, 'all', true)
                    : null,
                child: const Text('Unlock All Files'),
              ),
              TextButton(
                onPressed: _canChange && count > 0
                    ? () => _change(stage, 'all', false)
                    : null,
                child: const Text('Lock All Files'),
              ),
            ],
          ),
          if (deliverables.isNotEmpty) ...[
            const Divider(height: 20),
            const Text(
              'Individual deliverables',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            ...deliverables.map((raw) {
              final item = Map<String, dynamic>.from(raw);
              return _accessRow(
                stage,
                item,
                item['label'].toString(),
                item['type'].toString(),
                id: item['id'].toString(),
              );
            }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final program =
        _access?['program_scope']?.toString() ?? widget.programScope;
    final year = _access?['year_level']?.toString() ?? widget.yearLevel ?? '';
    final stages = (_access?['stages'] as List? ?? [])
        .whereType<Map>()
        .map((stage) => Map<String, dynamic>.from(stage))
        .where(
          (stage) =>
              widget.availableStages.isEmpty ||
              widget.availableStages.contains(stage['stage_label']),
        );
    final title = widget.scope == 'team'
        ? 'Manage File Access · ${widget.teamName ?? 'Team'}'
        : 'Program Stage Access (${program.toUpperCase()}${year.isEmpty ? '' : ' · $year'})';
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(24),
        decoration: DefensysTokens.dialogDecoration(),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.maroon,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _load,
                    child: const Text('Retry'),
                  ),
                ],
                if (_access != null) ...[
                  if (widget.scope == 'global' &&
                      _access!['can_choose_program'] == true) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final selectorWidth = constraints.maxWidth < 420
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: selectorWidth,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey('accessProgram:$_program'),
                                isExpanded: true,
                                initialValue: _program,
                                decoration: const InputDecoration(
                                  labelText: 'Program',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'capstone',
                                    child: Text('Capstone'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pit',
                                    child: Text('PIT'),
                                  ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        if (value == null) return;
                                        setState(() {
                                          _program = value;
                                          _year = '';
                                          _loading = true;
                                        });
                                        _load();
                                      },
                              ),
                            ),
                            SizedBox(
                              width: selectorWidth,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey('accessYear:$_year'),
                                isExpanded: true,
                                initialValue: _year,
                                decoration: const InputDecoration(
                                  labelText: 'Year level',
                                ),
                                items:
                                    [
                                          '',
                                          '1st Year',
                                          '2nd Year',
                                          '3rd Year',
                                          '4th Year',
                                        ]
                                        .map(
                                          (year) => DropdownMenuItem(
                                            value: year,
                                            child: Text(
                                              year.isEmpty ? 'All years' : year,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        if (value == null) return;
                                        setState(() {
                                          _year = value;
                                          _loading = true;
                                        });
                                        _load();
                                      },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    '${_access!['semester_label']} · ${_access!['team_count']} teams',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Manage uploads by file group or by individual deliverable. Grades and team approval are preserved. '
                    'Individual unlocks allow one replacement of approved pre-defense files, keeping approval.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('stageAccessReason'),
                    controller: _reason,
                    onChanged: (_) => setState(() {}),
                    enabled: !_saving,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reason for access change (required)',
                      helperText:
                          'The actor, reason and affected teams/files are recorded in Audit Trail.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  if (_saving) const LinearProgressIndicator(),
                  ...stages.map(_stageCard),
                  if (stages.isEmpty)
                    const Text('No configured stages or events in this scope.'),
                ],
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
