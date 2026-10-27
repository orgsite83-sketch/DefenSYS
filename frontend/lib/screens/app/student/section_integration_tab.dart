import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../widgets/repository/title_review_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../theme/defensys_tokens.dart';
import '../../../services/student_teams_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../services/app/data_refresh_provider.dart';
import '../../../services/academic/section_concept_service.dart';
import '../../../services/network/authenticated_client.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../widgets/export/defensys_pdf_viewer.dart';
import '../../../widgets/repository/team_concept_title_editor.dart';
import '../../../widgets/repository/shared_deliverables_panel.dart';
import '../../../widgets/repository/shared_concept_review.dart'
    show systemLetter;

class SectionIntegrationTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> studentData;

  const SectionIntegrationTab({super.key, required this.studentData});

  @override
  ConsumerState<SectionIntegrationTab> createState() =>
      _SectionIntegrationTabState();
}

class _SectionIntegrationTabState extends ConsumerState<SectionIntegrationTab> {
  Map<String, dynamic>? sectionProject;
  bool loadingProject = false;
  String? projectError;
  bool _isUploading = false;
  String _selectedSystemKey = 'c1';
  final Set<String> _expandedTeamIds = {};
  List<Map<String, dynamic>> _sharedGroups = [];
  String? _sharedStage;
  int _loadRevision = 0;

  Future<void> _uploadPaper(Map<String, dynamic> system) async {
    if (sectionProject == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.bytes == null || file.size > 25 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a readable PDF under 25 MB.'),
            ),
          );
        }
        return;
      }
      setState(() => _isUploading = true);
      final updatedProject = await ref
          .read(sectionConceptServiceProvider)
          .upload(sectionProject!, '${system['key']}', file.name, file.bytes!);
      if (mounted) {
        setState(() => sectionProject = updatedProject);
        ref.read(dataRefreshProvider.notifier).markChanged(const [
          DataArea.dashboard,
          DataArea.teams,
          DataArea.deliverables,
        ]);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded ${file.name} successfully.'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) await _loadProject();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Upload failed: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _editSystemTitles() async {
    if (sectionProject == null) return;
    final updated = await editSharedSystemTitles(context, sectionProject!);
    if (!mounted || updated == null) return;
    setState(() {
      sectionProject = updated;
      if (updated['shared_deliverables'] is Map) {
        final group = Map<String, dynamic>.from(
          updated['shared_deliverables'] as Map,
        );
        final index = _sharedGroups.indexWhere(
          (row) => row['stage_label'] == group['stage_label'],
        );
        if (index >= 0) _sharedGroups[index] = group;
      }
    });
    ref.read(dataRefreshProvider.notifier).markChanged(const [
      DataArea.dashboard,
      DataArea.teams,
      DataArea.deliverables,
    ]);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shared system titles saved.')),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(studentTeamsProvider.notifier).fetchTeams();
      _loadProject();
    });
  }

  Future<void> _loadProject() async {
    final revision = ++_loadRevision;
    final teamId = widget.studentData['team']?['id'] as int?;
    final sectionProjectId =
        widget.studentData['team']?['section_project_id'] as int?;

    setState(() {
      loadingProject = true;
      projectError = null;
    });
    try {
      var groups = <Map<String, dynamic>>[];
      Map<String, dynamic>? p;
      if (sectionProjectId != null) {
        p = await ref.read(sectionConceptServiceProvider).get(sectionProjectId);
        groups = (p['shared_contexts'] as List? ?? [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      } else {
        final listResult = await ref
            .read(sectionConceptServiceProvider)
            .list(teamId: teamId);
        groups = (listResult['shared_contexts'] as List? ?? [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final userSection =
            widget.studentData['student']?['managed_section'] ??
            widget.studentData['team']?['section'] ??
            '';
        final projects = (listResult['projects'] as List? ?? [])
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        final match = projects
            .where((p) => p['section'] == userSection)
            .firstOrNull;
        if (match != null) {
          p = match;
        } else if (teamId != null &&
            (groups.isEmpty ||
                groups.any((group) => group['imported'] == true))) {
          final pending = groups
              .where((group) => group['imported'] == true)
              .firstOrNull;
          p = await ref
              .read(sectionConceptServiceProvider)
              .imported(
                teamId,
                stageLabel: pending?['stage_label']?.toString(),
              );
        }
      }
      if (mounted && revision == _loadRevision) {
        setState(() {
          _sharedGroups = groups;
          if (!groups.any((group) => group['stage_label'] == _sharedStage)) {
            final current =
                widget.studentData['team']?['current_defense_stage'] ??
                p?['stage_label'];
            _sharedStage =
                groups
                    .where((group) => group['stage_label'] == current)
                    .firstOrNull?['stage_label']
                    ?.toString() ??
                groups.firstOrNull?['stage_label']?.toString();
          }
        });
      }
      if (mounted && p != null && revision == _loadRevision) {
        final projectData = p;
        setState(() {
          sectionProject = projectData;
          final selected = projectData['selected_key']?.toString();
          if (selected != null && selected.isNotEmpty) {
            _selectedSystemKey = selected;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => projectError = e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => loadingProject = false);
    }
  }

  Future<void> _viewPaper(Map<String, dynamic> paper) async {
    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile('${paper['file_url']}');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(
                '${paper['file_name']} · Revision ${paper['revision']}',
              ),
            ),
            body: DefensysPdfViewer(
              pdfBytes: bytes,
              title: '${paper['file_name']}',
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load document: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamsState = ref.watch(studentTeamsProvider);
    final userSection =
        widget.studentData['student']?['managed_section'] ??
        widget.studentData['team']?['section'] ??
        '';

    final userId =
        ref.watch(authProvider).user?['id'] ??
        widget.studentData['student']?['id'];
    final isPM = sectionProject != null
        ? '${sectionProject!['project_manager_id']}' == '$userId'
        : widget.studentData['student']?['is_project_manager'] == true;
    final myTeamId =
        widget.studentData['team']?['id']?.toString() ??
        widget.studentData['student']?['team_id']?.toString() ??
        '';

    // Filter teams to only show teams in the same section
    final sectionTeams = teamsState.teams.where((t) {
      final tSec = t['section']?.toString() ?? '';
      return tSec.isNotEmpty && tSec.toLowerCase() == userSection.toLowerCase();
    }).toList();

    final systems = (sectionProject?['systems'] as List? ?? [])
        .whereType<Map>()
        .map((s) => Map<String, dynamic>.from(s))
        .toList();

    // Identify active system
    final activeSystem = systems
        .where((s) => '${s['key']}' == _selectedSystemKey)
        .firstOrNull;
    final activeLetter = systemLetter(_selectedSystemKey);
    final sharedGroup = _sharedGroups
        .where((group) => group['stage_label'] == _sharedStage)
        .firstOrNull;
    final showConcept =
        sharedGroup == null ||
        sharedGroup['stage_label'] == sectionProject?['stage_label'];

    // Extract all teams from sectionProject or fallback to sectionTeams
    final rawTeams = (sectionProject?['teams'] as List? ?? [])
        .whereType<Map>()
        .map((t) => Map<String, dynamic>.from(t))
        .toList();

    final List<Map<String, dynamic>> projectTeams = rawTeams.isNotEmpty
        ? List<Map<String, dynamic>>.from(rawTeams)
        : sectionTeams;

    // Sort teams so the student's own team is pinned at the very top
    projectTeams.sort((a, b) {
      final aId = a['id']?.toString() ?? '';
      final bId = b['id']?.toString() ?? '';
      final aIsMine = myTeamId.isNotEmpty && aId == myTeamId;
      final bIsMine = myTeamId.isNotEmpty && bId == myTeamId;
      if (aIsMine && !bIsMine) return -1;
      if (!aIsMine && bIsMine) return 1;
      final aName = a['name']?.toString() ?? '';
      final bName = b['name']?.toString() ?? '';
      return aName.compareTo(bName);
    });

    return DefensysShadcnScope(
      child: RefreshIndicator(
        color: DefensysTokens.maroon,
        onRefresh: () async {
          await Future.wait([
            ref.read(studentTeamsProvider.notifier).fetchTeams(),
            ref
                .read(dashboardProvider('student').notifier)
                .fetchDashboardData(),
            _loadProject(),
          ]);
        },
        child:
            teamsState.isLoading &&
                sectionTeams.isEmpty &&
                sectionProject == null
            ? const Center(
                child: CircularProgressIndicator(color: DefensysTokens.maroon),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Architecture Hero Banner Card
                    _buildHeroBanner(
                      userSection: userSection.toString(),
                      project: showConcept
                          ? sectionProject ?? sharedGroup
                          : sharedGroup,
                    ),
                    if (loadingProject) const LinearProgressIndicator(),
                    if (projectError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        projectError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: _loadProject,
                        child: const Text('Retry shared proposals'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (_sharedGroups.length > 1) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _sharedStage,
                        decoration: const InputDecoration(
                          labelText: 'Stage / event',
                          isDense: true,
                        ),
                        items: _sharedGroups
                            .map(
                              (group) => DropdownMenuItem<String>(
                                value: '${group['stage_label']}',
                                child: Text('${group['stage_label']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _sharedStage = value),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (showConcept) _buildSystemToolbar(systems),
                    const SizedBox(height: 16),
                    if (sharedGroup != null)
                      SharedDeliverablesPanel(
                        key: ValueKey(
                          '${sharedGroup['scope']}-${sharedGroup['context_id']}',
                        ),
                        group: sharedGroup,
                        selectedSystemKey: _selectedSystemKey,
                        systemHeaderBuilder:
                            sectionProject?['title_workflow_version'] == 2
                            ? (row) {
                                final item =
                                    systems
                                        .where((s) => s['key'] == row['key'])
                                        .firstOrNull ??
                                    row;
                                final snapshot = Map<String, dynamic>.from(
                                  sectionProject!,
                                );
                                return TitleReviewCard(
                                  concept: item,
                                  system: true,
                                  onAction: (action, title, reason) async {
                                    await ref
                                        .read(sectionConceptServiceProvider)
                                        .titleAction(snapshot, action, {
                                          'concept_key': item['key'],
                                          if (title != null) 'title': title,
                                          if (reason != null) 'remarks': reason,
                                        });
                                    await _loadProject();
                                    ref
                                        .read(dataRefreshProvider.notifier)
                                        .markChanged(const [
                                          DataArea.dashboard,
                                          DataArea.teams,
                                          DataArea.deliverables,
                                        ]);
                                    return mounted;
                                  },
                                );
                              }
                            : null,
                        onSystemChanged: (value) =>
                            setState(() => _selectedSystemKey = value),
                        onChanged: (value) {
                          setState(() {
                            final index = _sharedGroups.indexOf(sharedGroup);
                            if (index >= 0) _sharedGroups[index] = value;
                          });
                          if (sectionProject?['imported'] == true &&
                              value['source_project_id'] != null) {
                            _loadProject();
                          }
                        },
                      ),

                    // 2. Shared System Segmented Switcher (Systems A, B, C)
                    if (showConcept && sharedGroup == null)
                      _buildSystemTabs(systems),
                    const SizedBox(height: 16),

                    // 3. Active System Overview Card (Paper status & blueprint info)
                    if (showConcept && sharedGroup == null)
                      _buildActiveSystemCard(
                        system: activeSystem,
                        letter: activeLetter,
                        project: sectionProject,
                        isPM: isPM,
                      ),
                    const SizedBox(height: 24),

                    // 4. Proposed Modules for Active System Header
                    if (showConcept)
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 18,
                            decoration: BoxDecoration(
                              color: DefensysTokens.maroonOf(context),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Proposed Modules for System $activeLetter',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: DefensysTokens.panelOf(context),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: DefensysTokens.borderOf(context),
                              ),
                            ),
                            child: Text(
                              '${projectTeams.length} Teams',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),

                    // 5. Team Modules List
                    if (showConcept && projectTeams.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'No modules found in this section.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else if (showConcept)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: projectTeams.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final team = projectTeams[index];
                          final teamId = team['id']?.toString() ?? '';
                          final isOwnTeam =
                              myTeamId.isNotEmpty && teamId == myTeamId;
                          final isExpanded = _expandedTeamIds.contains(teamId);

                          // Extract proposed concept for the selected system
                          final concepts = (team['concepts'] as List? ?? [])
                              .whereType<Map>()
                              .map((c) => Map<String, dynamic>.from(c))
                              .toList();
                          final activeConcept = concepts
                              .where((c) => '${c['key']}' == _selectedSystemKey)
                              .firstOrNull;
                          final moduleTitle =
                              (activeConcept?['title']?.toString() ??
                                      (_selectedSystemKey == 'c1'
                                          ? team['project_title']?.toString()
                                          : '') ??
                                      '')
                                  .trim();
                          final isConfirmed =
                              activeConcept?['faculty_confirmed'] == true;
                          final docStatus =
                              activeConcept?['documents_status']?.toString() ??
                              '';
                          final decision =
                              activeConcept?['decision']?.toString() ?? '';

                          // Metadata from studentTeamsProvider
                          final teamMeta = teamsState.teams
                              .where((t) => t['id']?.toString() == teamId)
                              .firstOrNull;
                          final leadName =
                              team['leader_name'] ??
                              teamMeta?['leader_name'] ??
                              (team['leader_id'] != null
                                  ? 'Lead #${team['leader_id']}'
                                  : 'No Leader');
                          final defContext =
                              teamMeta?['defense_context']
                                  as Map<String, dynamic>?;
                          final eventLabel = defContext?['event_label'] ?? '';
                          final scheduledDate =
                              defContext?['scheduled_date'] ?? '';

                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedTeamIds.remove(teamId);
                                } else {
                                  _expandedTeamIds.add(teamId);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: DefensysTokens.surfaceOf(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isConfirmed
                                      ? (Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? const Color(
                                                0xFF4ADE80,
                                              ).withValues(alpha: 0.6)
                                            : const Color(0xFF86EFAC))
                                      : isOwnTeam
                                      ? DefensysTokens.maroonOf(
                                          context,
                                        ).withValues(alpha: 0.35)
                                      : DefensysTokens.borderOf(context),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.015,
                                    ),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Tier 1: Team Name + "Your Team" on Left, Status Pill + Arrow on Right ──
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                team['name'] ?? 'Team',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      DefensysTokens.textPrimaryOf(
                                                        context,
                                                      ),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isOwnTeam) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      DefensysTokens.maroonOf(
                                                        context,
                                                      ).withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'Your Team',
                                                  style: TextStyle(
                                                    color:
                                                        DefensysTokens.maroonOf(
                                                          context,
                                                        ),
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isConfirmed)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFF86EFAC),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.check_rounded,
                                                size: 10.5,
                                                color: Color(0xFF15803D),
                                              ),
                                              SizedBox(width: 3),
                                              Text(
                                                'Confirmed',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF15803D),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else if (decision == 'approved' ||
                                          decision == 'approved_with_revisions')
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFF86EFAC),
                                            ),
                                          ),
                                          child: Text(
                                            decision == 'approved'
                                                ? 'Approved'
                                                : 'Approved w/ Rev',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF15803D),
                                            ),
                                          ),
                                        )
                                      else if (docStatus == 'accepted')
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFF86EFAC),
                                            ),
                                          ),
                                          child: const Text(
                                            'Paper Cleared',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF15803D),
                                            ),
                                          ),
                                        )
                                      else if (docStatus == 'uploaded' ||
                                          docStatus == 'ready' ||
                                          docStatus == 'pending_review')
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: DefensysTokens.panelOf(
                                              context,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: DefensysTokens.borderOf(
                                                context,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            'Paper Ready',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  DefensysTokens.textSecondaryOf(
                                                    context,
                                                  ),
                                            ),
                                          ),
                                        )
                                      else if (moduleTitle.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: DefensysTokens.borderOf(
                                                context,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            'Draft',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  DefensysTokens.textSecondaryOf(
                                                    context,
                                                  ),
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: DefensysTokens.borderOf(
                                                context,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            'Pending',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color:
                                                  DefensysTokens.textSecondaryOf(
                                                    context,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_up_rounded
                                            : Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: DefensysTokens.steelGrey,
                                      ),
                                    ],
                                  ),
                                  // ── Tier 2: Sub-Metadata (Lead Name) ──
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 2,
                                      bottom: 4,
                                    ),
                                    child: Text(
                                      'Lead: $leadName',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: DefensysTokens.steelGrey,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    moduleTitle.isNotEmpty
                                        ? moduleTitle
                                        : 'Module proposal not yet submitted',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: moduleTitle.isNotEmpty
                                          ? DefensysTokens.textPrimaryOf(
                                              context,
                                            )
                                          : DefensysTokens.steelGrey,
                                      fontStyle: moduleTitle.isEmpty
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                      height: 1.3,
                                    ),
                                  ),
                                  if (scheduledDate.isNotEmpty) ...[
                                    const SizedBox(height: 7),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.event_outlined,
                                          size: 13,
                                          color: DefensysTokens.steelGrey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$eventLabel ($scheduledDate)',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color:
                                                DefensysTokens.textSecondaryOf(
                                                  context,
                                                ),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  // ─── EXPANDED DETAILS (ROSTER, DELIVERABLES, EVALUATION) ───
                                  if (isExpanded) ...[
                                    const SizedBox(height: 12),
                                    Divider(
                                      height: 1,
                                      color: isConfirmed
                                          ? const Color(
                                              0xFF86EFAC,
                                            ).withValues(alpha: 0.5)
                                          : DefensysTokens.borderOf(context),
                                    ),
                                    const SizedBox(height: 10),

                                    // 1. Deliverables Section
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isConfirmed
                                            ? Colors.white.withValues(
                                                alpha: 0.7,
                                              )
                                            : DefensysTokens.panelOf(context),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isConfirmed
                                              ? const Color(
                                                  0xFF86EFAC,
                                                ).withValues(alpha: 0.6)
                                              : DefensysTokens.borderOf(
                                                  context,
                                                ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.description_outlined,
                                            size: 15,
                                            color: DefensysTokens.maroonOf(
                                              context,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Module Concept Paper',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        DefensysTokens.textPrimaryOf(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                                Text(
                                                  docStatus == 'accepted'
                                                      ? 'Paper accepted for hearing'
                                                      : docStatus ==
                                                            'corrections_requested'
                                                      ? 'Corrections requested'
                                                      : (docStatus ==
                                                                    'uploaded' ||
                                                                docStatus ==
                                                                    'ready' ||
                                                                docStatus ==
                                                                    'pending_review'
                                                            ? 'Paper submitted · Awaiting review'
                                                            : 'No paper submitted yet for this module'),
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    color:
                                                        DefensysTokens.textSecondaryOf(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: docStatus == 'accepted'
                                                  ? const Color(0xFFDCFCE7)
                                                  : (docStatus == 'uploaded' ||
                                                            docStatus ==
                                                                'ready' ||
                                                            docStatus ==
                                                                'pending_review' ||
                                                            docStatus ==
                                                                'corrections_requested'
                                                        ? const Color(
                                                            0xFFFEF3C7,
                                                          )
                                                        : DefensysTokens.panelOf(
                                                            context,
                                                          )),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              docStatus == 'accepted'
                                                  ? 'Accepted'
                                                  : docStatus ==
                                                        'corrections_requested'
                                                  ? 'Corrections requested'
                                                  : (docStatus == 'uploaded' ||
                                                            docStatus ==
                                                                'ready' ||
                                                            docStatus ==
                                                                'pending_review'
                                                        ? 'Awaiting review'
                                                        : 'Missing'),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: docStatus == 'accepted'
                                                    ? const Color(0xFF15803D)
                                                    : (docStatus ==
                                                                  'uploaded' ||
                                                              docStatus ==
                                                                  'ready' ||
                                                              docStatus ==
                                                                  'pending_review' ||
                                                              docStatus ==
                                                                  'corrections_requested'
                                                          ? const Color(
                                                              0xFFB45309,
                                                            )
                                                          : DefensysTokens
                                                                .steelGrey),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    // 2. Team Members Roster
                                    Builder(
                                      builder: (_) {
                                        final rawMembers =
                                            (team['members'] as List? ?? [])
                                                .whereType<Map>()
                                                .map(
                                                  (m) =>
                                                      Map<String, dynamic>.from(
                                                        m,
                                                      ),
                                                )
                                                .toList();
                                        final effectiveMembers =
                                            rawMembers.isNotEmpty
                                            ? rawMembers
                                            : teamsState.students
                                                  .where(
                                                    (s) =>
                                                        s['team_id']
                                                            ?.toString() ==
                                                        teamId,
                                                  )
                                                  .map(
                                                    (s) => {
                                                      'id': s['id'],
                                                      'name':
                                                          s['full_name'] ??
                                                          s['name'] ??
                                                          s['username'] ??
                                                          'Student',
                                                      'is_leader':
                                                          s['id']?.toString() ==
                                                          team['leader_id']
                                                              ?.toString(),
                                                    },
                                                  )
                                                  .toList();

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.groups_outlined,
                                                  size: 14,
                                                  color:
                                                      DefensysTokens.maroonOf(
                                                        context,
                                                      ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Team Roster (${effectiveMembers.length})',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        DefensysTokens.textPrimaryOf(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            if (effectiveMembers.isEmpty)
                                              Text(
                                                'No members assigned to this team yet.',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      DefensysTokens.steelGrey,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              )
                                            else
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: effectiveMembers.map((
                                                  m,
                                                ) {
                                                  final mName =
                                                      m['name']?.toString() ??
                                                      'Member';
                                                  final isLeader =
                                                      m['is_leader'] == true ||
                                                      m['id']?.toString() ==
                                                          team['leader_id']
                                                              ?.toString();
                                                  final initial =
                                                      mName.isNotEmpty
                                                      ? mName[0].toUpperCase()
                                                      : 'S';

                                                  return Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isLeader
                                                          ? DefensysTokens.maroonOf(
                                                              context,
                                                            ).withValues(
                                                              alpha: 0.08,
                                                            )
                                                          : (isConfirmed
                                                                ? Colors.white
                                                                      .withValues(
                                                                        alpha:
                                                                            0.7,
                                                                      )
                                                                : DefensysTokens.panelOf(
                                                                    context,
                                                                  )),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                      border: Border.all(
                                                        color: isLeader
                                                            ? DefensysTokens.maroonOf(
                                                                context,
                                                              ).withValues(
                                                                alpha: 0.25,
                                                              )
                                                            : (isConfirmed
                                                                  ? const Color(
                                                                      0xFF86EFAC,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.6,
                                                                    )
                                                                  : DefensysTokens.borderOf(
                                                                      context,
                                                                    )),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        CircleAvatar(
                                                          radius: 9,
                                                          backgroundColor:
                                                              isLeader
                                                              ? DefensysTokens.maroonOf(
                                                                  context,
                                                                )
                                                              : DefensysTokens
                                                                    .steelGrey
                                                                    .withValues(
                                                                      alpha:
                                                                          0.3,
                                                                    ),
                                                          child: Text(
                                                            initial,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 9,
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 5,
                                                        ),
                                                        Text(
                                                          mName,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: isLeader
                                                                ? FontWeight
                                                                      .bold
                                                                : FontWeight
                                                                      .w500,
                                                            color: isLeader
                                                                ? DefensysTokens.maroonOf(
                                                                    context,
                                                                  )
                                                                : DefensysTokens.textPrimaryOf(
                                                                    context,
                                                                  ),
                                                          ),
                                                        ),
                                                        if (isLeader) ...[
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 4,
                                                                  vertical: 1,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  DefensysTokens.maroonOf(
                                                                    context,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: const Text(
                                                              'Lead',
                                                              style: TextStyle(
                                                                fontSize: 8,
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                          ],
                                        );
                                      },
                                    ),

                                    // 3. Evaluation and Remarks (if available)
                                    if (decision.isNotEmpty ||
                                        scheduledDate.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isConfirmed
                                              ? Colors.white.withValues(
                                                  alpha: 0.7,
                                                )
                                              : DefensysTokens.panelOf(context),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: isConfirmed
                                                ? const Color(
                                                    0xFF86EFAC,
                                                  ).withValues(alpha: 0.6)
                                                : DefensysTokens.borderOf(
                                                    context,
                                                  ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.event_note_outlined,
                                              size: 14,
                                              color: DefensysTokens.steelGrey,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                scheduledDate.isNotEmpty
                                                    ? '$eventLabel · $scheduledDate'
                                                    : 'Evaluation Status: ${decision.replaceAll('_', ' ')}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      DefensysTokens.textSecondaryOf(
                                                        context,
                                                      ),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            if (decision.isNotEmpty)
                                              Text(
                                                decision
                                                    .toUpperCase()
                                                    .replaceAll('_', ' '),
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: decision == 'approved'
                                                      ? const Color(0xFF16A34A)
                                                      : DefensysTokens.maroonOf(
                                                          context,
                                                        ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeroBanner({
    required String userSection,
    Map<String, dynamic>? project,
  }) {
    final pmName =
        project?['project_manager_name'] ??
        (loadingProject ? 'Loading…' : 'Not assigned');
    final reviewerName =
        project?['reviewer_name'] ??
        (loadingProject ? 'Loading…' : 'Not assigned');
    final round = project?['round'] ?? 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Section $userSection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (project?['concept_selection_enabled'] != false)
                ShadBadge.secondary(child: Text('Attempt $round')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'PM: $pmName',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Reviewers: $reviewerName',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemToolbar(List<Map<String, dynamic>> systems) {
    final provided = systems
        .where((s) => '${s['title'] ?? ''}'.trim().isNotEmpty)
        .length;
    final unavailableReason =
        '${sectionProject?['setup_unavailable_reason'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'System proposals',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  if (sectionProject != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '$provided of ${systems.length} titles provided',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (sectionProject?['can_edit_names'] == true &&
                sectionProject?['title_workflow_version'] != 2) ...[
              const SizedBox(width: 12),
              ShadButton.outline(
                key: const ValueKey('edit-shared-system-titles'),
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.edit_outlined, size: 16),
                onPressed: _editSystemTitles,
                child: const Text(
                  'Edit titles',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        if (unavailableReason.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            unavailableReason,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSystemTabs(List<Map<String, dynamic>> systems) {
    final tabs = systems.isNotEmpty
        ? systems
        : [
            for (var i = 1; i <= 3; i++) <String, dynamic>{'key': 'c$i'},
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrollable =
            tabs.length > 3 && constraints.maxWidth < tabs.length * 104;
        return ShadTabs<String>(
          value: _selectedSystemKey,
          gap: 0,
          tabsGap: 4,
          padding: const EdgeInsets.all(4),
          scrollable: scrollable,
          decoration: ShadDecoration(
            color: DefensysTokens.panelOf(context),
            border: ShadBorder.all(
              color: DefensysTokens.borderOf(context),
              radius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (key) => setState(() => _selectedSystemKey = key),
          tabs: [
            for (final system in tabs)
              ShadTab<String>(
                value: '${system['key']}',
                height: 40,
                width: scrollable ? 104 : null,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                selectedBackgroundColor: DefensysTokens.maroonOf(context),
                selectedForegroundColor: Colors.white,
                foregroundColor: DefensysTokens.textPrimaryOf(context),
                leading: sectionProject?['selected_key'] == system['key']
                    ? const Tooltip(
                        message: 'Selected system',
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 12,
                        ),
                      )
                    : null,
                child: Text(
                  'System ${systemLetter(system['key'])}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActiveSystemCard({
    required Map<String, dynamic>? system,
    required String letter,
    required Map<String, dynamic>? project,
    required bool isPM,
  }) {
    final selectedKey = '${project?['selected_key'] ?? ''}';
    final isSelected =
        selectedKey.isNotEmpty &&
        system != null &&
        selectedKey == system['key'];
    final isConfirmed = system?['confirmed'] == true;
    final papers = (system?['papers'] as List? ?? [])
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    final current = papers.where((p) => p['is_current'] == true).firstOrNull;
    final title = system?['title']?.toString().trim() ?? '';
    final canUpload = system?['can_upload'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConfirmed
              ? (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFF16A34A))
              : DefensysTokens.borderOf(context),
          width: isConfirmed ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'System $letter',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const Spacer(),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '★ Selected System',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else if (isConfirmed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_rounded,
                        size: 10.5,
                        color: Color(0xFF15803D),
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Faculty Confirmed',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                  ),
                  child: Text(
                    'Pending Review',
                    style: TextStyle(
                      fontSize: 10,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title.isNotEmpty ? title : 'System name not yet provided',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              height: 1.5,
              color: title.isNotEmpty
                  ? DefensysTokens.textPrimaryOf(context)
                  : DefensysTokens.steelGrey,
              fontStyle: title.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Concept paper',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          if (current == null) ...[
            if (canUpload && system != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No concept paper uploaded for System $letter yet.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: _isUploading
                          ? null
                          : () => _uploadPaper(system),
                      icon: _isUploading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: DefensysTokens.maroon,
                              ),
                            )
                          : const Icon(Icons.upload_file_rounded, size: 15),
                      label: Text(
                        _isUploading
                            ? 'Uploading PDF...'
                            : 'Upload Concept Paper (PDF)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DefensysTokens.maroonOf(context),
                        side: BorderSide(
                          color: DefensysTokens.maroonOf(
                            context,
                          ).withValues(alpha: 0.35),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 14,
                    color: DefensysTokens.steelGrey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Concept paper missing · Awaiting PM upload',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: DefensysTokens.steelGrey,
                      ),
                    ),
                  ),
                ],
              ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: DefensysTokens.panelOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DefensysTokens.borderOf(context)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 16,
                    color: DefensysTokens.maroonOf(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${current['file_name']}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Revision ${current['revision']}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: DefensysTokens.steelGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => _viewPaper(current),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Read Paper',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.maroonOf(context),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: DefensysTokens.maroonOf(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (canUpload && system != null) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _isUploading ? null : () => _uploadPaper(system),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sync_rounded,
                              size: 13,
                              color: DefensysTokens.maroonOf(context),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Replace',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.maroonOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
