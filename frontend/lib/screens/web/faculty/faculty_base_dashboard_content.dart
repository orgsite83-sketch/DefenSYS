import 'package:flutter/material.dart';
import '../admin/widgets/defensys_admin_shell.dart';
import '../../../theme/defensys_tokens.dart';

class FacultyBaseDashboardContent extends StatelessWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final VoidCallback onOpenDefenseBoard;
  final VoidCallback onOpenProjectArchive;
  final VoidCallback onOpenRubrics;
  final VoidCallback onOpenSignatureUpload;

  const FacultyBaseDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    required this.onOpenDefenseBoard,
    required this.onOpenProjectArchive,
    required this.onOpenRubrics,
    required this.onOpenSignatureUpload,
  });

  @override
  Widget build(BuildContext context) {
    final activeSemester = data?['active_semester']?.toString() ?? 'Active Semester';
    final hasSignature = data?['has_e_signature'] == true ||
        data?['faculty']?['has_e_signature'] == true;
    final panelAssignments = (data?['panelist_assignments'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final advisedTeams = (data?['advised_teams'] as List?) ?? [];
    final roles = (data?['roles'] as Map?)?.cast<String, dynamic>() ?? {};
    final isPitLead = roles['pit_lead'] == true;
    final isPitInstructor = roles['pit_instructor'] == true;

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 1100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefensysPageHeader(
          icon: Icons.school_outlined,
          title: 'Welcome, $facultyName',
          subtitle: 'Faculty Member Portal · $activeSemester',
        ),
        const SizedBox(height: 24),

        // Row 1: Readiness & Status Deck
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildSignatureCard(hasSignature)),
              const SizedBox(width: 16),
              Expanded(child: _buildDeliberationPoolCard(panelAssignments.length, activeSemester)),
              const SizedBox(width: 16),
              Expanded(child: _buildAcademicLoadCard(advisedTeams.length, isPitLead, isPitInstructor, roles)),
            ],
          )
        else ...[
          _buildSignatureCard(hasSignature),
          const SizedBox(height: 12),
          _buildDeliberationPoolCard(panelAssignments.length, activeSemester),
          const SizedBox(height: 12),
          _buildAcademicLoadCard(advisedTeams.length, isPitLead, isPitInstructor, roles),
        ],

        const SizedBox(height: 28),

        // Row 2: Defense Hearings & Panel Assignments
        _buildDefenseHearingsSection(panelAssignments),

        const SizedBox(height: 28),

        // Row 3: Institutional Tools & Academic Resources
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _buildProjectArchiveCard()),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: _buildRubricsGuidelinesCard()),
            ],
          )
        else ...[
          _buildProjectArchiveCard(),
          const SizedBox(height: 16),
          _buildRubricsGuidelinesCard(),
        ],
      ],
    );
  }

  Widget _buildSignatureCard(bool hasSignature) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasSignature ? const Color(0xFFD1FAE5) : const Color(0xFFFDE68A),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasSignature ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  hasSignature ? Icons.verified_user_rounded : Icons.draw_rounded,
                  color: hasSignature ? const Color(0xFF047857) : const Color(0xFFD97706),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasSignature ? 'Digital Signature Verified' : 'E-Signature Required',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: hasSignature ? const Color(0xFF065F46) : const Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSignature ? 'Ready for deliberations' : 'Action required for grading',
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            hasSignature
                ? 'Your electronic signature is registered and ready to sign defense rubrics, minutes, and clearance sheets.'
                : 'Upload your digital signature to enable scoring rubrics and sign defense minutes during active hearings.',
            style: const TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              fontSize: 12,
              color: Color(0xFF4B5563),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOpenSignatureUpload,
              icon: Icon(
                hasSignature ? Icons.refresh_rounded : Icons.upload_file_rounded,
                size: 16,
                color: hasSignature ? const Color(0xFF047857) : DefensysTokens.maroon,
              ),
              label: Text(
                hasSignature ? 'Update Signature' : 'Upload Digital Signature',
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: hasSignature ? const Color(0xFF047857) : DefensysTokens.maroon,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                backgroundColor: hasSignature ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: hasSignature ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliberationPoolCard(int hearingCount, String activeSemester) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: Color(0xFF7C3AED),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Defense Deliberation Pool',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeSemester,
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hearingCount.toString(),
                style: const TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hearingCount == 1 ? 'Assigned Hearing' : 'Assigned Hearings',
                style: const TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOpenDefenseBoard,
              icon: const Icon(Icons.calendar_month_outlined, size: 16, color: Color(0xFF6D28D9)),
              label: const Text(
                'Open Defense Board',
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6D28D9),
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                backgroundColor: const Color(0xFFF5F3FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFFDDD6FE)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicLoadCard(
    int advisedCount,
    bool isPitLead,
    bool isPitInstructor,
    Map<String, dynamic> roles,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Department Roles & Load',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Active Teaching & Mentorship',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildRoleBadge('Faculty Member', const Color(0xFFFFEDD5), const Color(0xFFEA580C)),
              if (advisedCount > 0)
                _buildRoleBadge('$advisedCount Advised Team(s)', const Color(0xFFECFDF5), const Color(0xFF047857))
              else
                _buildRoleBadge('Advising: 0 Teams', const Color(0xFFF3F4F6), const Color(0xFF6B7280)),
              if (isPitLead)
                _buildRoleBadge('PIT Lead: ${roles['pit_lead_year'] ?? 'Active'}', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
              if (isPitInstructor)
                _buildRoleBadge('PIT Instructor', const Color(0xFFF0FDF4), const Color(0xFF15803D)),
              if (roles['documenter'] == true)
                _buildRoleBadge('Documenter', const Color(0xFFCCFBF1), const Color(0xFF0F766E)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Specialized workspaces unlock automatically in your sidebar when assigned by the Coordinator.',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              fontSize: 11,
              color: Color(0xFF9CA3AF),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: DefensysTokens.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }

  Widget _buildDefenseHearingsSection(List<Map<String, dynamic>> hearings) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_note_rounded, color: DefensysTokens.maroon, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assigned Defense Hearings (PIT & Capstone)',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Sessions where you are scheduled as Panel Chair or Member',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onOpenDefenseBoard,
                icon: const Icon(Icons.view_agenda_outlined, size: 16),
                label: const Text('View All in Board'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DefensysTokens.maroon,
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (hearings.isEmpty)
            _buildEmptyHearingsState()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: hearings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _buildHearingCard(hearings[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyHearingsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: Color(0xFF9CA3AF),
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No Defense Hearings Currently Scheduled',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'You are in the active deliberation pool for this semester. When the Capstone Coordinator or PIT Lead schedules defense sessions, your assigned teams, room assignments, and rubric scorecards will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              fontSize: 12,
              color: Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHearingCard(Map<String, dynamic> hearing) {
    final scope = hearing['scope']?.toString().toUpperCase() ?? 'CAPSTONE';
    final isPit = scope.contains('PIT');
    final isChair = hearing['is_chair'] == true;
    final date = hearing['scheduled_date']?.toString() ?? '';
    final time = hearing['start_time']?.toString() ?? '';
    final room = hearing['room']?.toString() ?? 'TBD';
    final stage = hearing['stage_label']?.toString() ?? 'Defense Stage';
    final teamName = hearing['team_name']?.toString() ?? 'Unassigned Team';
    final projectTitle = hearing['project_title']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isPit ? const Color(0xFFEFF6FF) : const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isPit ? const Color(0xFFBFDBFE) : const Color(0xFFFECDD3),
              ),
            ),
            child: Text(
              scope,
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isPit ? const Color(0xFF1D4ED8) : DefensysTokens.maroon,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      stage,
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isChair)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, size: 12, color: Color(0xFFB45309)),
                            SizedBox(width: 4),
                            Text(
                              'Panel Chair',
                              style: TextStyle(
                                fontFamily: DefensysTokens.fontFamily,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Panelist',
                          style: TextStyle(
                            fontFamily: DefensysTokens.fontFamily,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  teamName,
                  style: const TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.maroon,
                  ),
                ),
                if (projectTitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    projectTitle,
                    style: const TextStyle(
                      fontFamily: DefensysTokens.fontFamily,
                      fontSize: 12,
                      color: Color(0xFF4B5563),
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFF6B7280)),
                        const SizedBox(width: 5),
                        Text(
                          date,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time_rounded, size: 13, color: Color(0xFF6B7280)),
                        const SizedBox(width: 5),
                        Text(
                          time,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.room_outlined, size: 13, color: Color(0xFF6B7280)),
                        const SizedBox(width: 5),
                        Text(
                          'Room: $room',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onOpenDefenseBoard,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              backgroundColor: const Color(0xFFF9FAFB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            child: const Text(
              'Evaluation',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DefensysTokens.maroon,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectArchiveCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.manage_search_rounded,
                  color: Color(0xFF16A34A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Institutional Project Repository',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Search past approved student proposals & manuscripts',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Check project abstracts, keywords, and technology stacks to prevent duplicate project proposals during title defenses.',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              fontSize: 12,
              color: Color(0xFF4B5563),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onOpenProjectArchive,
              icon: const Icon(Icons.search_rounded, size: 16),
              label: const Text('Search Project Archive'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF15803D),
                side: const BorderSide(color: Color(0xFFBBF7D0)),
                backgroundColor: const Color(0xFFF0FDF4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRubricsGuidelinesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.rule_folder_outlined,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scoring Rubrics & Guidelines',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Evaluation criteria & defense thresholds',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Reference official criteria for Proposal, Progress, and Final Oral Defenses, including weight breakdowns and passing scales.',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              fontSize: 12,
              color: Color(0xFF4B5563),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onOpenRubrics,
              icon: const Icon(Icons.rule_rounded, size: 16),
              label: const Text('View Rubrics'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB45309),
                side: const BorderSide(color: Color(0xFFFDE68A)),
                backgroundColor: const Color(0xFFFFFBEB),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
