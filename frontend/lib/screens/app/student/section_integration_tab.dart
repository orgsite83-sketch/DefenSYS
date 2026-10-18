import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../theme/defensys_tokens.dart';
import '../../../services/student_teams_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/academic/section_concept_service.dart';
import '../../../services/network/authenticated_client.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../widgets/export/defensys_pdf_viewer.dart';
import '../../../widgets/table/defensys_segmented_control.dart';

class SectionIntegrationTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> studentData;

  const SectionIntegrationTab({
    super.key,
    required this.studentData,
  });

  @override
  ConsumerState<SectionIntegrationTab> createState() =>
      _SectionIntegrationTabState();
}

class _SectionIntegrationTabState extends ConsumerState<SectionIntegrationTab> {
  Map<String, dynamic>? sectionProject;
  bool loadingProject = false;
  bool _isUploading = false;
  String _selectedSystemKey = 'c1';
  final Set<String> _expandedTeamIds = {};

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
            const SnackBar(content: Text('Please select a readable PDF under 25 MB.')),
          );
        }
        return;
      }
      setState(() => _isUploading = true);
      final updatedProject = await ref.read(sectionConceptServiceProvider).upload(
        sectionProject!,
        '${system['key']}',
        file.name,
        file.bytes!,
      );
      if (mounted) {
        setState(() => sectionProject = updatedProject);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded ${file.name} successfully.'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
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
    final teamId = widget.studentData['team']?['id'] as int?;
    final sectionProjectId = widget.studentData['team']?['section_project_id'] as int?;

    setState(() => loadingProject = true);
    try {
      Map<String, dynamic>? p;
      if (sectionProjectId != null) {
        p = await ref.read(sectionConceptServiceProvider).get(sectionProjectId);
      } else {
        final listResult = await ref.read(sectionConceptServiceProvider).list(teamId: teamId);
        final userSection = widget.studentData['student']?['managed_section'] ??
            widget.studentData['team']?['section'] ?? '';
        final projects = (listResult['projects'] as List? ?? [])
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        final match = projects.where((p) => p['section'] == userSection).firstOrNull;
        if (match != null) {
          p = match;
        }
      }
      if (mounted && p != null) {
        final projectData = p;
        setState(() {
          sectionProject = projectData;
          final selected = projectData['selected_key']?.toString();
          if (selected != null && selected.isNotEmpty) {
            _selectedSystemKey = selected;
          }
        });
      }
    } catch (_) {
      // Ignored: fallback to teams view
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
            content: Text('Failed to load document: ${e.toString().replaceFirst('Exception: ', '')}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamsState = ref.watch(studentTeamsProvider);
    final userSection = widget.studentData['student']?['managed_section'] ??
        widget.studentData['team']?['section'] ??
        '';

    final isPM = widget.studentData['student']?['is_project_manager'] == true;
    final myTeamId = widget.studentData['team']?['id']?.toString() ??
        widget.studentData['student']?['team_id']?.toString() ?? '';

    // Filter teams to only show teams in the same section
    final sectionTeams = teamsState.teams.where((t) {
      final tSec = t['section']?.toString() ?? '';
      return tSec.isNotEmpty && tSec.toLowerCase() == userSection.toLowerCase();
    }).toList();

    final systems = (sectionProject?['systems'] as List? ?? [])
        .whereType<Map>()
        .map((s) => Map<String, dynamic>.from(s))
        .toList();

    final segmentItems = <DefensysSegmentItem<String>>[
      for (var i = 0; i < (systems.isNotEmpty ? systems.length : 3); i++) ...[
        () {
          final key = systems.isNotEmpty ? '${systems[i]['key']}' : 'c${i + 1}';
          final letter = String.fromCharCode(65 + i);
          final isFinalSelected = sectionProject?['selected_key'] == key;
          return DefensysSegmentItem<String>(
            value: key,
            label: 'System $letter',
            badgeLabel: isFinalSelected ? '★ Selected' : null,
          );
        }(),
      ],
    ];

    // Identify active system
    final activeSystem = systems.where((s) => '${s['key']}' == _selectedSystemKey).firstOrNull;
    final activeIndex = systems.indexWhere((s) => '${s['key']}' == _selectedSystemKey);
    final activeLetter = activeIndex >= 0 ? String.fromCharCode(65 + activeIndex) : (_selectedSystemKey == 'c2' ? 'B' : (_selectedSystemKey == 'c3' ? 'C' : 'A'));

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
            ref.read(dashboardProvider('student').notifier).fetchDashboardData(),
            _loadProject(),
          ]);
        },
        child: teamsState.isLoading && sectionTeams.isEmpty && sectionProject == null
            ? const Center(child: CircularProgressIndicator(color: DefensysTokens.maroon))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Architecture Hero Banner Card
                    _buildHeroBanner(
                      userSection: userSection.toString(),
                      isPM: isPM,
                      project: sectionProject,
                    ),
                    const SizedBox(height: 16),

                    // 2. Shared System Segmented Switcher (Systems A, B, C)
                    DefensysSegmentedControl<String>(
                      value: _selectedSystemKey,
                      items: segmentItems,
                      onChanged: (newKey) => setState(() => _selectedSystemKey = newKey),
                    ),
                    const SizedBox(height: 12),

                    // 3. Active System Overview Card (Paper status & blueprint info)
                    _buildActiveSystemCard(
                      system: activeSystem,
                      letter: activeLetter,
                      project: sectionProject,
                      isPM: isPM,
                    ),
                    const SizedBox(height: 18),

                    // 4. Proposed Modules for Active System Header
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: DefensysTokens.panelOf(context),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: DefensysTokens.borderOf(context)),
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
                    const SizedBox(height: 4),
                    Text(
                      'All team module proposals for System $activeLetter in Section $userSection. Tap a card to view members and deliverables.',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 5. Team Modules List
                    if (projectTeams.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'No modules found in this section.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: projectTeams.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final team = projectTeams[index];
                          final teamId = team['id']?.toString() ?? '';
                          final isOwnTeam = myTeamId.isNotEmpty && teamId == myTeamId;
                          final isExpanded = _expandedTeamIds.contains(teamId);

                          // Extract proposed concept for the selected system
                          final concepts = (team['concepts'] as List? ?? [])
                              .whereType<Map>()
                              .map((c) => Map<String, dynamic>.from(c))
                              .toList();
                          final activeConcept = concepts.where((c) => '${c['key']}' == _selectedSystemKey).firstOrNull;
                          final moduleTitle = (activeConcept?['title']?.toString() ?? team['project_title']?.toString() ?? '').trim();
                          final isConfirmed = activeConcept?['faculty_confirmed'] == true;
                          final docStatus = activeConcept?['documents_status']?.toString() ?? '';
                          final decision = activeConcept?['decision']?.toString() ?? '';

                          // Metadata from studentTeamsProvider
                          final teamMeta = teamsState.teams.where((t) => t['id']?.toString() == teamId).firstOrNull;
                          final leadName = team['leader_name'] ?? teamMeta?['leader_name'] ?? (team['leader_id'] != null ? 'Lead #${team['leader_id']}' : 'No Leader');
                          final defContext = teamMeta?['defense_context'] as Map<String, dynamic>?;
                          final eventLabel = defContext?['event_label'] ?? '';
                          final scheduledDate = defContext?['scheduled_date'] ?? '';

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
                                color: isOwnTeam
                                    ? DefensysTokens.maroonOf(context).withValues(alpha: 0.035)
                                    : DefensysTokens.surfaceOf(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isConfirmed
                                      ? (Theme.of(context).brightness == Brightness.dark
                                          ? const Color(0xFF4ADE80)
                                          : const Color(0xFF16A34A))
                                      : isOwnTeam
                                          ? DefensysTokens.maroonOf(context).withValues(alpha: 0.45)
                                          : DefensysTokens.borderOf(context),
                                  width: isConfirmed ? 1.4 : (isOwnTeam ? 1.2 : 1.0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isOwnTeam ? 0.03 : 0.015),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                team['name'] ?? 'Team',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: isConfirmed
                                                      ? const Color(0xFF15803D)
                                                      : isOwnTeam
                                                          ? DefensysTokens.maroonOf(context)
                                                          : DefensysTokens.textPrimaryOf(context),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '· Lead: $leadName',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: DefensysTokens.steelGrey,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (isOwnTeam) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: DefensysTokens.maroonOf(context).withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Text(
                                            'Your Team',
                                            style: TextStyle(
                                              color: DefensysTokens.maroonOf(context),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      if (isConfirmed)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF86EFAC)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_rounded, size: 10.5, color: Color(0xFF15803D)),
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
                                      else if (decision == 'approved' || decision == 'approved_with_revisions')
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF86EFAC)),
                                          ),
                                          child: Text(
                                            decision == 'approved' ? 'Approved' : 'Approved w/ Rev',
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                          ),
                                        )
                                      else if (docStatus == 'accepted')
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF86EFAC)),
                                          ),
                                          child: const Text('Paper Cleared', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                                        )
                                      else if (docStatus == 'uploaded' || docStatus == 'ready' || docStatus == 'pending_review')
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: DefensysTokens.panelOf(context),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: DefensysTokens.borderOf(context)),
                                          ),
                                          child: Text('Paper Ready', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: DefensysTokens.textSecondaryOf(context))),
                                        )
                                      else if (moduleTitle.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: DefensysTokens.borderOf(context)),
                                          ),
                                          child: Text('Draft', style: TextStyle(fontSize: 10, color: DefensysTokens.textSecondaryOf(context))),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: DefensysTokens.borderOf(context)),
                                          ),
                                          child: Text('Pending', style: TextStyle(fontSize: 10, color: DefensysTokens.textSecondaryOf(context))),
                                        ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: isConfirmed ? const Color(0xFF15803D) : DefensysTokens.steelGrey,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    moduleTitle.isNotEmpty
                                        ? moduleTitle
                                        : 'Module proposal not yet submitted',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: moduleTitle.isNotEmpty
                                          ? DefensysTokens.textPrimaryOf(context)
                                          : DefensysTokens.steelGrey,
                                      fontStyle: moduleTitle.isEmpty ? FontStyle.italic : FontStyle.normal,
                                      height: 1.3,
                                    ),
                                  ),
                                  if (scheduledDate.isNotEmpty || docStatus.isNotEmpty) ...[
                                    const SizedBox(height: 7),
                                    Row(
                                      children: [
                                        if (scheduledDate.isNotEmpty) ...[
                                          Icon(Icons.event_outlined, size: 13, color: DefensysTokens.steelGrey),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$eventLabel ($scheduledDate)',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: DefensysTokens.textSecondaryOf(context),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        Icon(Icons.description_outlined, size: 13, color: DefensysTokens.steelGrey),
                                        const SizedBox(width: 4),
                                        Text(
                                          docStatus == 'accepted'
                                              ? 'Paper approved'
                                              : docStatus == 'missing' || docStatus.isEmpty
                                                  ? 'Paper missing'
                                                  : 'Paper uploaded',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: docStatus == 'accepted'
                                                ? const Color(0xFF16A34A)
                                                : docStatus == 'missing' || docStatus.isEmpty
                                                    ? DefensysTokens.steelGrey
                                                    : DefensysTokens.darkGold,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  // ─── EXPANDED DETAILS (ROSTER, DELIVERABLES, EVALUATION) ───
                                  if (isExpanded) ...[
                                    const SizedBox(height: 12),
                                    Divider(height: 1, color: isConfirmed ? const Color(0xFF86EFAC).withValues(alpha: 0.5) : DefensysTokens.borderOf(context)),
                                    const SizedBox(height: 10),

                                    // 1. Deliverables Section
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isConfirmed
                                            ? Colors.white.withValues(alpha: 0.7)
                                            : DefensysTokens.panelOf(context),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: isConfirmed ? const Color(0xFF86EFAC).withValues(alpha: 0.6) : DefensysTokens.borderOf(context)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.description_outlined, size: 15, color: DefensysTokens.maroonOf(context)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Module Concept Paper',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: DefensysTokens.textPrimaryOf(context),
                                                  ),
                                                ),
                                                Text(
                                                  docStatus == 'accepted'
                                                      ? 'Paper accepted and endorsed by faculty'
                                                      : (docStatus == 'uploaded' || docStatus == 'ready'
                                                          ? 'Paper submitted · Pending review'
                                                          : 'No paper submitted yet for this module'),
                                                  style: TextStyle(fontSize: 10.5, color: DefensysTokens.textSecondaryOf(context)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: docStatus == 'accepted'
                                                  ? const Color(0xFFDCFCE7)
                                                  : (docStatus == 'uploaded' || docStatus == 'ready'
                                                      ? const Color(0xFFFEF3C7)
                                                      : DefensysTokens.panelOf(context)),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              docStatus == 'accepted'
                                                  ? 'Accepted'
                                                  : (docStatus == 'uploaded' || docStatus == 'ready'
                                                      ? 'Submitted'
                                                      : 'Missing'),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: docStatus == 'accepted'
                                                    ? const Color(0xFF15803D)
                                                    : (docStatus == 'uploaded' || docStatus == 'ready'
                                                        ? const Color(0xFFB45309)
                                                        : DefensysTokens.steelGrey),
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
                                        final rawMembers = (team['members'] as List? ?? [])
                                            .whereType<Map>()
                                            .map((m) => Map<String, dynamic>.from(m))
                                            .toList();
                                        final effectiveMembers = rawMembers.isNotEmpty
                                            ? rawMembers
                                            : teamsState.students
                                                .where((s) => s['team_id']?.toString() == teamId)
                                                .map((s) => {
                                                      'id': s['id'],
                                                      'name': s['full_name'] ?? s['name'] ?? s['username'] ?? 'Student',
                                                      'is_leader': s['id']?.toString() == team['leader_id']?.toString(),
                                                    })
                                                .toList();

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.groups_outlined, size: 14, color: DefensysTokens.maroonOf(context)),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Team Roster (${effectiveMembers.length})',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: DefensysTokens.textPrimaryOf(context),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            if (effectiveMembers.isEmpty)
                                              Text(
                                                'No members assigned to this team yet.',
                                                style: TextStyle(fontSize: 11, color: DefensysTokens.steelGrey, fontStyle: FontStyle.italic),
                                              )
                                            else
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: effectiveMembers.map((m) {
                                                  final mName = m['name']?.toString() ?? 'Member';
                                                  final isLeader = m['is_leader'] == true || m['id']?.toString() == team['leader_id']?.toString();
                                                  final initial = mName.isNotEmpty ? mName[0].toUpperCase() : 'S';

                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: isLeader
                                                          ? DefensysTokens.maroonOf(context).withValues(alpha: 0.08)
                                                          : (isConfirmed ? Colors.white.withValues(alpha: 0.7) : DefensysTokens.panelOf(context)),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: isLeader
                                                            ? DefensysTokens.maroonOf(context).withValues(alpha: 0.25)
                                                            : (isConfirmed ? const Color(0xFF86EFAC).withValues(alpha: 0.6) : DefensysTokens.borderOf(context)),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        CircleAvatar(
                                                          radius: 9,
                                                          backgroundColor: isLeader
                                                              ? DefensysTokens.maroonOf(context)
                                                              : DefensysTokens.steelGrey.withValues(alpha: 0.3),
                                                          child: Text(
                                                            initial,
                                                            style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 5),
                                                        Text(
                                                          mName,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: isLeader ? FontWeight.bold : FontWeight.w500,
                                                            color: isLeader
                                                                ? DefensysTokens.maroonOf(context)
                                                                : DefensysTokens.textPrimaryOf(context),
                                                          ),
                                                        ),
                                                        if (isLeader) ...[
                                                          const SizedBox(width: 4),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                            decoration: BoxDecoration(
                                                              color: DefensysTokens.maroonOf(context),
                                                              borderRadius: BorderRadius.circular(4),
                                                            ),
                                                            child: const Text(
                                                              'Lead',
                                                              style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
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
                                    if (decision.isNotEmpty || scheduledDate.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: isConfirmed ? Colors.white.withValues(alpha: 0.7) : DefensysTokens.panelOf(context),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: isConfirmed ? const Color(0xFF86EFAC).withValues(alpha: 0.6) : DefensysTokens.borderOf(context)),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.event_note_outlined, size: 14, color: DefensysTokens.steelGrey),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                scheduledDate.isNotEmpty
                                                    ? '$eventLabel · $scheduledDate'
                                                    : 'Evaluation Status: ${decision.replaceAll('_', ' ')}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: DefensysTokens.textSecondaryOf(context),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            if (decision.isNotEmpty)
                                              Text(
                                                decision.toUpperCase().replaceAll('_', ' '),
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: decision == 'approved' ? const Color(0xFF16A34A) : DefensysTokens.maroonOf(context),
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
    required bool isPM,
    Map<String, dynamic>? project,
  }) {
    final pmName = project?['project_manager_name'] ?? 'Section PM';
    final reviewerName = project?['reviewer_name'] ?? 'Faculty Reviewer';
    final round = project?['round'] ?? 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroonOf(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.hub_rounded, color: DefensysTokens.maroonOf(context), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Section $userSection Architecture',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Shared System Integration Hub',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              ShadBadge.secondary(
                child: Text('Attempt $round'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: DefensysTokens.panelOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.badge_outlined, size: 13, color: DefensysTokens.steelGrey),
                    const SizedBox(width: 6),
                    Text(
                      'PM: $pmName',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: DefensysTokens.textPrimaryOf(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: DefensysTokens.panelOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.school_outlined, size: 13, color: DefensysTokens.steelGrey),
                    const SizedBox(width: 6),
                    Text(
                      'Reviewer: $reviewerName',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: DefensysTokens.textPrimaryOf(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSystemCard({
    required Map<String, dynamic>? system,
    required String letter,
    required Map<String, dynamic>? project,
    required bool isPM,
  }) {
    final isSelected = project?['selected_key'] == system?['key'];
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroonOf(context).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: DefensysTokens.maroonOf(context).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  'System $letter Blueprint',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.maroonOf(context),
                  ),
                ),
              ),
              const Spacer(),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('★ Selected System', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                )
              else if (isConfirmed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 10.5, color: Color(0xFF15803D)),
                      SizedBox(width: 3),
                      Text('Faculty Confirmed', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                  ),
                  child: Text('Pending Review', style: TextStyle(fontSize: 10, color: DefensysTokens.textSecondaryOf(context))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title.isNotEmpty ? title : 'Shared System Architecture Title (Pending PM)',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              height: 1.3,
              color: title.isNotEmpty ? DefensysTokens.textPrimaryOf(context) : DefensysTokens.steelGrey,
              fontStyle: title.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          if (current == null) ...[
            if (canUpload && system != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DefensysTokens.panelOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 15, color: DefensysTokens.maroonOf(context)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No concept paper uploaded for System $letter yet.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'As Section PM, upload the overarching architecture paper (PDF up to 25 MB).',
                      style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 34,
                      child: OutlinedButton.icon(
                        onPressed: _isUploading ? null : () => _uploadPaper(system),
                        icon: _isUploading
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: DefensysTokens.maroon))
                            : const Icon(Icons.upload_file_rounded, size: 15),
                        label: Text(
                          _isUploading ? 'Uploading PDF...' : 'Upload Concept Paper (PDF)',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DefensysTokens.maroonOf(context),
                          side: BorderSide(color: DefensysTokens.maroonOf(context).withValues(alpha: 0.35)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Icon(Icons.description_outlined, size: 14, color: DefensysTokens.steelGrey),
                  const SizedBox(width: 6),
                  Text(
                    'System concept paper missing (PM upload pending)',
                    style: TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
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
                  Icon(Icons.picture_as_pdf_outlined, size: 16, color: DefensysTokens.maroonOf(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${current['file_name']}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Revision ${current['revision']}',
                          style: TextStyle(fontSize: 10.5, color: DefensysTokens.steelGrey),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => _viewPaper(current),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                          Icon(Icons.arrow_forward_rounded, size: 13, color: DefensysTokens.maroonOf(context)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sync_rounded, size: 13, color: DefensysTokens.maroonOf(context)),
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
