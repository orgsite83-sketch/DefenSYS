import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/api_config.dart';
import '../../../services/student_teams_provider.dart';
import '../../../services/team_detail_provider.dart';
import '../../../utils/pdf_viewer.dart';
import 'widgets/defensys_admin_shell.dart';

class TeamDetailPage extends ConsumerStatefulWidget {
  const TeamDetailPage({
    super.key,
    required this.teamId,
    required this.onBack,
    required this.canManage,
    required this.isPitLead,
    this.pitLeadYear,
    this.onDeleted,
  });

  final int teamId;
  final VoidCallback onBack;
  final bool canManage;
  final bool isPitLead;
  final String? pitLeadYear;
  final VoidCallback? onDeleted;

  @override
  ConsumerState<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends ConsumerState<TeamDetailPage>
    with SingleTickerProviderStateMixin {
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _gold = DefensysUi.accentGold;
  static const _red = Color(0xFFDC2626);
  static const _line = Color(0xFFE5E7EB);

  late final TabController _tabController;

  final _nameController = TextEditingController();
  final _projectTitleController = TextEditingController();

  String _status = 'Pending';
  int? _adviserId;
  int? _originalAdviserId;
  final _selectedMembers = <int>{};
  int? _leaderId;
  String _selectedDeliverableStage = 'Concept Proposal';
  int? _selectedReportIndex;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(teamDetailProvider(widget.teamId).notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _projectTitleController.dispose();
    super.dispose();
  }

  void _syncFormFromTeam(Map<String, dynamic> team, List<String> statuses) {
    _nameController.text = team['name']?.toString() ?? '';
    _projectTitleController.text = team['project_title']?.toString() ?? '';
    _status = team['status']?.toString() ?? 'Pending';
    if (!statuses.contains(_status) && statuses.isNotEmpty) {
      _status = statuses.first;
    }
    _adviserId = _asInt(team['adviser_id']);
    _originalAdviserId = _adviserId;
    _selectedMembers
      ..clear()
      ..addAll(_readIntList(team['member_ids']));
    _leaderId =
        _asInt(team['leader_id']) ??
        (_selectedMembers.isNotEmpty ? _selectedMembers.first : null);
  }

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(teamDetailProvider(widget.teamId));
    final team = detailState.team;

    if (detailState.isLoading && team == null) {
      return const Center(child: CircularProgressIndicator(color: _maroon));
    }

    if (team == null) {
      return Padding(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(null),
            const SizedBox(height: 24),
            Text(
              detailState.error ?? 'Team not found.',
              style: const TextStyle(color: _red),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: widget.onBack, child: const Text('Back')),
          ],
        ),
      );
    }

    if (_nameController.text.isEmpty && team['name'] != null) {
      _syncFormFromTeam(team, detailState.statuses);
    }

    final stageOptions = detailState.stageOptions.isNotEmpty
        ? detailState.stageOptions
        : const [
            'Concept Proposal',
            'Project Proposal',
            'Final Defense',
          ];
    if (!stageOptions.contains(_selectedDeliverableStage)) {
      _selectedDeliverableStage = stageOptions.first;
    }

    ref.listen(teamDetailProvider(widget.teamId), (prev, next) {
      final msg = next.message;
      if (msg != null && msg.isNotEmpty && msg != prev?.message) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    });

    return Padding(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(team),
          if (detailState.error != null) ...[
            const SizedBox(height: 12),
            Text(detailState.error!, style: const TextStyle(color: _red)),
          ],
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            labelColor: _maroon,
            unselectedLabelColor: _muted,
            indicatorColor: _maroon,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Weekly Reports'),
              Tab(text: 'Deliverables'),
              Tab(text: 'Team Documents'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(detailState, team),
                _buildWeeklyReportsTab(detailState),
                _buildDeliverablesTab(detailState, stageOptions),
                _buildDocumentsTab(detailState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic>? team) {
    final title = team?['name']?.toString() ?? 'Team';
    final project = team?['project_title']?.toString() ?? '';

    return Row(
      children: [
        IconButton(
          tooltip: 'Back to teams',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: _maroon),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DefensysUi.pageTitle),
              if (project.isNotEmpty)
                Text(project, style: DefensysUi.subtitle, maxLines: 2),
              if (!_isEditing)
                const Text(
                  'Team workspace — submissions and roster',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
            ],
          ),
        ),
        if (widget.canManage && !_isEditing)
          OutlinedButton.icon(
            onPressed: () => setState(() => _isEditing = true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit team'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _maroon,
              side: const BorderSide(color: _maroon),
            ),
          ),
        if (widget.canManage && _isEditing) ...[
          TextButton(
            onPressed: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? null
                : _cancelEditing,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? null
                : _saveOverview,
            style: ElevatedButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: _gold,
            ),
            child: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Changes'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? null
                : _confirmDelete,
            icon: const Icon(Icons.delete_outline, size: 18, color: _red),
            label: const Text('Delete', style: TextStyle(color: _red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _line),
            ),
          ),
        ],
      ],
    );
  }

  void _cancelEditing() {
    final detailState = ref.read(teamDetailProvider(widget.teamId));
    final team = detailState.team;
    if (team != null) {
      _syncFormFromTeam(team, detailState.statuses);
    }
    setState(() => _isEditing = false);
  }

  Widget _buildOverviewTab(
    TeamDetailState detailState,
    Map<String, dynamic> team,
  ) {
    if (widget.canManage && _isEditing) {
      return _buildOverviewEdit(detailState, team);
    }
    return _buildOverviewView(detailState, team);
  }

  Widget _buildOverviewView(
    TeamDetailState detailState,
    Map<String, dynamic> team,
  ) {
    final level = team['level']?.toString() ?? '';
    final yearLevel = team['year_level']?.toString() ?? '3rd Year';
    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    final programLabel = widget.isPitLead
        ? '${widget.pitLeadYear ?? yearLevel} PIT'
        : 'Capstone · $yearLevel';
    final adviserName = team['adviser_name']?.toString() ??
        _adviserLabel(_asInt(team['adviser_id']), detailState.advisers);

    final memberIds = _readIntList(team['member_ids']);
    final leaderId = _asInt(team['leader_id']);
    final members = detailState.students
        .where((s) => memberIds.contains(_asInt(s['id'])))
        .toList();

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _readOnlyField('Team Name', team['name']?.toString() ?? '—'),
            const SizedBox(height: 12),
            _readOnlyField(
              'Project Title',
              team['project_title']?.toString() ?? '—',
            ),
            const SizedBox(height: 12),
            _readOnlyField('Program', programLabel),
            const SizedBox(height: 12),
            _readOnlyField('Team Result', team['status']?.toString() ?? '—'),
            if (!widget.isPitLead && isCapstone) ...[
              const SizedBox(height: 12),
              _readOnlyField('Adviser', adviserName),
              const SizedBox(height: 16),
              _adviserHistorySection(detailState.adviserHistory),
            ],
            const SizedBox(height: 16),
            Text(
              'Members (${members.length}/4)',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (members.isEmpty)
              const Text(
                'No members assigned.',
                style: TextStyle(color: _muted, fontSize: 12.5),
              )
            else
              ...members.map((student) {
                final studentId = _asInt(student['id']);
                final isLeader = studentId == leaderId;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        isLeader
                            ? Icons.workspace_premium_rounded
                            : Icons.person_outline,
                        color: isLeader ? _gold : _muted,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${student['name']} (${student['username']})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                            if (isLeader)
                              const Text(
                                'Team Leader',
                                style: TextStyle(
                                  color: _maroon,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: _muted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewEdit(
    TeamDetailState detailState,
    Map<String, dynamic> team,
  ) {
    final level = team['level']?.toString() ?? '';
    final yearLevel = team['year_level']?.toString() ?? '3rd Year';
    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    final statusOptions = detailState.statuses.isEmpty
        ? const ['Pending', 'Approved', 'Failed', 'Delayed/Extended']
        : detailState.statuses;

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Team Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _projectTitleController,
              decoration: const InputDecoration(labelText: 'Project Title'),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Program'),
              child: Text(
                widget.isPitLead
                    ? '${widget.pitLeadYear ?? yearLevel} PIT'
                    : 'Capstone · $yearLevel',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: statusOptions.contains(_status) ? _status : statusOptions.first,
              decoration: const InputDecoration(labelText: 'Team Result'),
              items: statusOptions
                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) => setState(() => _status = value ?? _status),
            ),
            if (!widget.isPitLead && isCapstone) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _adviserId,
                decoration: const InputDecoration(labelText: 'Adviser'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  ...detailState.advisers.map(
                    (adviser) => DropdownMenuItem<int?>(
                      value: _asInt(adviser['id']),
                      child: Text(
                        '${adviser['name']} (${adviser['username']})',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _adviserId = value),
              ),
              const SizedBox(height: 16),
              _adviserHistorySection(detailState.adviserHistory),
            ],
            const SizedBox(height: 16),
            Text(
              'Members (${_selectedMembers.length}/4)',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _line),
              ),
              child: ListView(
                shrinkWrap: true,
                children: detailState.students.map((student) {
                  final studentId = _asInt(student['id'])!;
                  final selected = _selectedMembers.contains(studentId);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          if (_selectedMembers.length >= 4 && !selected) {
                            return;
                          }
                          _selectedMembers.add(studentId);
                          _leaderId ??= studentId;
                        } else {
                          _selectedMembers.remove(studentId);
                          if (_leaderId == studentId) {
                            _leaderId = _selectedMembers.isEmpty
                                ? null
                                : _selectedMembers.first;
                          }
                        }
                      });
                    },
                    title: Text(
                      '${student['name']} (${student['username']})',
                    ),
                    subtitle: _leaderId == studentId
                        ? const Text('Team Leader')
                        : null,
                    secondary: selected
                        ? IconButton(
                            tooltip: 'Set as leader',
                            icon: Icon(
                              _leaderId == studentId
                                  ? Icons.workspace_premium_rounded
                                  : Icons.circle_outlined,
                              color: _leaderId == studentId ? _gold : _muted,
                            ),
                            onPressed: () => setState(() => _leaderId = studentId),
                          )
                        : null,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select up to 4 members. Use the medal button to choose the leader.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyReportsTab(TeamDetailState detailState) {
    final reports = detailState.weeklyReports;

    if (reports.isEmpty) {
      return _emptyTab('No weekly progress reports submitted yet.');
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              final selected = _selectedReportIndex == index;
              return ListTile(
                selected: selected,
                selectedTileColor: const Color(0xFFF3F4F6),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE5E7EB),
                  child: Text(
                    '${report['week_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text('Week ${report['week_number'] ?? ''}'),
                subtitle: Text(report['report_date']?.toString() ?? ''),
                onTap: () => setState(() => _selectedReportIndex = index),
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _selectedReportIndex == null
              ? _emptyTab('Select a report to preview.')
              : _weeklyReportPreview(reports[_selectedReportIndex!]),
        ),
      ],
    );
  }

  Widget _weeklyReportPreview(Map<String, dynamic> report) {
    final reportFile = report['report_file'] as String?;
    final hasFile = reportFile != null && reportFile.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Week ${report['week_number'] ?? ''}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('Date: ${report['report_date'] ?? '—'}'),
          Text('Submitted by: ${report['student_name'] ?? '—'}'),
          const SizedBox(height: 16),
          if (hasFile)
            ElevatedButton.icon(
              onPressed: () => _viewWeeklyReportFile(report),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('View report file'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _maroon,
                foregroundColor: _gold,
              ),
            )
          else
            const Text(
              'Legacy structured report (no file attachment).',
              style: TextStyle(color: _muted),
            ),
        ],
      ),
    );
  }

  Widget _buildDeliverablesTab(
    TeamDetailState detailState,
    List<String> stageOptions,
  ) {
    final deliverableTeam = detailState.deliverableTeam;
    if (deliverableTeam == null) {
      return _emptyTab(
        'No capstone deliverable record for this team (non-capstone or not loaded).',
      );
    }

    final stages = (deliverableTeam['stages'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final stage = stages.firstWhere(
      (item) => item['stage_label']?.toString() == _selectedDeliverableStage,
      orElse: () => stages.isNotEmpty ? stages.first : <String, dynamic>{},
    );
    final deliverables = (stage['deliverables'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final pre = deliverables.where((d) => d['type'] == 'pre').toList();
    final vault = deliverables.where((d) => d['type'] == 'vault').toList();

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: stageOptions.map((label) {
                final active = label == _selectedDeliverableStage;
                return ChoiceChip(
                  label: Text(label),
                  selected: active,
                  onSelected: (_) =>
                      setState(() => _selectedDeliverableStage = label),
                  selectedColor: _maroon.withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                    color: active ? _maroon : _ink,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'Pre-Defense Requirements',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ...pre.map((item) => _deliverableRow(item)),
            const SizedBox(height: 20),
            const Text(
              'Post-Defense Vault Submissions',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (stage['vault_unlocked'] != true)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Vault items unlock after the defense for this stage is completed.',
                  style: TextStyle(color: _muted, fontSize: 12.5),
                ),
              )
            else
              ...vault.map((item) => _deliverableRow(item)),
          ],
        ),
      ),
    );
  }

  Widget _deliverableRow(Map<String, dynamic> item) {
    final uploaded = item['uploaded'] == true;
    final submission = Map<String, dynamic>.from(
      item['submission'] as Map? ?? const {},
    );
    final fileUrl = submission['file_url']?.toString();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Icon(
            uploaded ? Icons.check_circle : Icons.radio_button_unchecked,
            color: uploaded ? const Color(0xFF10B981) : _muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['label']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (uploaded)
                  Text(
                    '${submission['file_name'] ?? ''} · ${submission['uploaded_by_name'] ?? ''}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (item['required'] == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Required',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          if (uploaded && fileUrl != null && fileUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Open file',
              onPressed: () => _openMediaUrl(fileUrl),
              icon: const Icon(Icons.open_in_new, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentsTab(TeamDetailState detailState) {
    final docs = detailState.documents;
    if (docs.isEmpty) {
      return _emptyTab('No team documents uploaded yet.');
    }

    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text('FILE', style: DefensysUi.tableHeader),
                  ),
                  Expanded(child: Text('TYPE', style: DefensysUi.tableHeader)),
                  Expanded(child: Text('DATE', style: DefensysUi.tableHeader)),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 1, color: _line),
            ...docs.map((doc) {
              final id = _asInt(doc['id']);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        doc['file_name']?.toString() ?? '—',
                        style: DefensysUi.tableCell,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        doc['document_type']?.toString() ?? 'other',
                        style: DefensysUi.tableCell,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _formatDate(doc['uploaded_at']),
                        style: DefensysUi.tableCell,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Download',
                      onPressed: id == null ? null : () => _downloadTeamDocument(id),
                      icon: const Icon(Icons.download_outlined, color: _maroon),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _emptyTab(String message) {
    return Center(
      child: Text(message, style: const TextStyle(color: _muted, fontSize: 14)),
    );
  }

  Widget _adviserHistorySection(List<Map<String, dynamic>> rows) {
    const headStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: Color(0xFF9CA3AF),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Adviser History',
          style: TextStyle(
            color: _ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Past and current advisers for this team.',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const Text(
            'No adviser changes recorded yet.',
            style: TextStyle(color: _muted, fontSize: 12.5),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text('ADVISER', style: headStyle),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('ASSIGNED', style: headStyle),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('ENDED', style: headStyle),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('CHANGED BY', style: headStyle),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _line),
                ...rows.map((row) {
                  final isCurrent = row['is_current'] == true;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: _line)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row['adviser_name']?.toString() ?? 'Unassigned',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (isCurrent)
                                const Text(
                                  'Current',
                                  style: TextStyle(
                                    color: _maroon,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(_formatDate(row['assigned_at'])),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            row['ended_at'] != null
                                ? _formatDate(row['ended_at'])
                                : '—',
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            row['assigned_by_name']?.toString() ?? '—',
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _saveOverview() async {
    if (_selectedMembers.isEmpty || _leaderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one member and a leader.')),
      );
      return;
    }

    final detailState = ref.read(teamDetailProvider(widget.teamId));
    final team = detailState.team;
    if (team == null) return;

    final level = team['level']?.toString() ?? '';
    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    var adviserId = isCapstone && !widget.isPitLead ? _adviserId : null;

    String? adviserChangeReason;
    if (widget.canManage &&
        isCapstone &&
        !widget.isPitLead &&
        _originalAdviserId != adviserId) {
      final reason = await _confirmAdviserChange(
        teamName: _nameController.text.trim(),
        fromAdviserId: _originalAdviserId,
        toAdviserId: adviserId,
        advisers: detailState.advisers,
      );
      if (!mounted) return;
      if (reason == null) return;
      adviserChangeReason = reason;
    }

    final payload = {
      'name': _nameController.text.trim(),
      'project_title': _projectTitleController.text.trim().isEmpty
          ? _nameController.text.trim()
          : _projectTitleController.text.trim(),
      'leader_id': _leaderId,
      'member_ids': _selectedMembers.toList(),
      'adviser_id': adviserId,
      'status': _status,
      if (adviserChangeReason != null && adviserChangeReason.isNotEmpty)
        'adviser_change_reason': adviserChangeReason,
    };

    final ok = await ref
        .read(teamDetailProvider(widget.teamId).notifier)
        .save(payload);
    if (ok && mounted) {
      setState(() {
        _originalAdviserId = adviserId;
        _isEditing = false;
      });
      await ref.read(studentTeamsProvider.notifier).fetchTeams();
    }
  }

  Future<void> _confirmDelete() async {
    final team = ref.read(teamDetailProvider(widget.teamId)).team;
    final name = team?['name']?.toString() ?? 'this team';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Delete Team'),
        content: Text('Delete $name? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final deleted = await ref
        .read(studentTeamsProvider.notifier)
        .deleteTeam(widget.teamId);
    if (deleted && mounted) {
      widget.onDeleted?.call();
      widget.onBack();
    }
  }

  Future<String?> _confirmAdviserChange({
    required String teamName,
    required int? fromAdviserId,
    required int? toAdviserId,
    required List<Map<String, dynamic>> advisers,
  }) async {
    final reasonCtrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Change project adviser?'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Team: $teamName', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('From: ${_adviserLabel(fromAdviserId, advisers)}'),
              Text('To: ${_adviserLabel(toAdviserId, advisers)}'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, reasonCtrl.text.trim()),
            child: const Text('Confirm change'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    return result;
  }

  String _adviserLabel(int? id, List<Map<String, dynamic>> advisers) {
    if (id == null) return 'Unassigned';
    for (final adviser in advisers) {
      if (_asInt(adviser['id']) == id) {
        return '${adviser['name']} (${adviser['username']})';
      }
    }
    return 'Unknown adviser';
  }

  Future<void> _viewWeeklyReportFile(Map<String, dynamic> report) async {
    final reportFile = report['report_file'] as String?;
    if (reportFile == null || reportFile.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: _maroon),
      ),
    );

    try {
      var cleanPath = reportFile;
      if (cleanPath.startsWith('media/')) {
        cleanPath = cleanPath.substring(6);
      }
      if (cleanPath.startsWith('/media/')) {
        cleanPath = cleanPath.substring(7);
      }
      final url =
          'http://${ApiConfig.baseIp}:${ApiConfig.basePort}/media/$cleanPath';
      final response = await http.get(Uri.parse(url));
      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200 && mounted) {
        await viewPdfInDialog(
          context: context,
          pdfBytes: response.bodyBytes,
          fileName: reportFile.split('/').last,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load file (${response.statusCode})')),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file: $e')),
        );
      }
    }
  }

  Future<void> _openMediaUrl(String fileUrl) async {
    var path = fileUrl;
    if (path.startsWith('/media/')) {
      path = path.substring(7);
    } else if (path.startsWith('media/')) {
      path = path.substring(6);
    }
    final url = path.startsWith('http')
        ? path
        : 'http://${ApiConfig.baseIp}:${ApiConfig.basePort}/media/$path';
    final response = await http.get(Uri.parse(url));
    if (!mounted) return;
    if (response.statusCode == 200 && url.toLowerCase().contains('.pdf')) {
      await viewPdfInDialog(
        context: context,
        pdfBytes: response.bodyBytes,
        fileName: url.split('/').last,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File preview is only available for PDFs.')),
      );
    }
  }

  Future<void> _downloadTeamDocument(int docId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${ApiConfig.teamDocumentsUrl}/$docId/download/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document downloaded.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed (${response.statusCode})')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download error: $e')),
        );
      }
    }
  }

  String _formatDate(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length > 10 ? raw.substring(0, 10) : raw;
    final local = dt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  List<int> _readIntList(dynamic value) {
    if (value is! List) return [];
    return value.map(_asInt).whereType<int>().toList();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
