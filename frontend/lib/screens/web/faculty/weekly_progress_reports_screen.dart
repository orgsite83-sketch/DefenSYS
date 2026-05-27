import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/weekly_progress_provider.dart';
import '../../../widgets/empty_state.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/defensys_tokens.dart';
import 'package:intl/intl.dart';
import '../../../services/authenticated_client.dart';
import '../../../utils/pdf_viewer.dart';
import '../../../widgets/feedback_toast.dart';

class WeeklyProgressReportsScreen extends ConsumerStatefulWidget {
  const WeeklyProgressReportsScreen({super.key});

  @override
  ConsumerState<WeeklyProgressReportsScreen> createState() =>
      _WeeklyProgressReportsScreenState();
}

class _WeeklyProgressReportsScreenState
    extends ConsumerState<WeeklyProgressReportsScreen> {
  String? selectedTeamId;
  int? selectedReportIndex;

  @override
  void initState() {
    super.initState();
    // Fetch weekly progress reports only (dashboard data is already fetched by parent)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(weeklyProgressProvider.notifier).fetchReports();
    });
  }

  Future<void> _refreshData() async {
    await Future.wait([
      ref.read(dashboardProvider('faculty').notifier).fetchDashboardData(),
      ref.read(weeklyProgressProvider.notifier).fetchReports(),
    ]);
  }

  Widget _buildLoadError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text(
              'Failed to load weekly progress reports',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.maroon,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(dashboardProvider('faculty'));
    final progressState = ref.watch(weeklyProgressProvider);
    
    // Get only the teams advised by this faculty member
    final advisedTeams = (dashState.data?['advised_teams'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    
    final isLoading = dashState.isLoading || progressState.isLoading;
    final loadError = dashState.error ?? progressState.error;

    // Filter reports by selected team
    final filteredReports = selectedTeamId != null
        ? progressState.reports.where((r) => r['team'].toString() == selectedTeamId).toList()
        : progressState.reports;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: null, // Remove AppBar since it's embedded in faculty dashboard
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
              ? _buildLoadError(loadError)
              : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with title
                Container(
                  padding: const EdgeInsets.all(24),
                  color: Colors.white,
                  child: const Text(
                    'Weekly Progress Reports',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                // Main content with sidebar and document view
                Expanded(
                  child: Row(
                    children: [
                      // Left sidebar - Team and report selection
                      Container(
                        width: 320,
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: DefensysTokens.maroon.withValues(alpha: 0.05),
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: const Text(
                          'Select a Team',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      
                      // Team Selection List
                      if (advisedTeams.isEmpty)
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refreshData,
                            color: DefensysTokens.maroon,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.orange.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.info_outline,
                                                color: Colors.orange.shade700),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'No teams assigned yet.',
                                                style: TextStyle(
                                                    color: Colors.orange.shade700),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refreshData,
                            color: DefensysTokens.maroon,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              itemCount: advisedTeams.length,
                              itemBuilder: (context, index) {
                              final team = advisedTeams[index];
                              final teamId = team['id']?.toString() ?? team['name'];
                              final isSelected = selectedTeamId == teamId;
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? DefensysTokens.maroon.withValues(alpha: 0.1) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? DefensysTokens.maroon : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: ListTile(
                                  selected: isSelected,
                                  title: Text(
                                    team['name'] ?? 'Unknown Team',
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Text(
                                    team['projectTitle'] ?? 'No project title',
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: filteredReports.where((r) => r['team'].toString() == teamId).isNotEmpty
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '${filteredReports.where((r) => r['team'].toString() == teamId).length}',
                                            style: TextStyle(
                                              color: Colors.green.shade700,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      selectedTeamId = teamId;
                                      selectedReportIndex = null;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                        ),
                      
                      // Reports list for selected team
                      if (selectedTeamId != null && filteredReports.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: DefensysTokens.maroon.withValues(alpha: 0.05),
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade200),
                              bottom: BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Progress Reports (${filteredReports.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: progressState.isLoading
                                    ? null
                                    : () => _compileAllReports(
                                          filteredReports,
                                          advisedTeams.firstWhere(
                                            (t) => (t['id']?.toString() ?? t['name']) == selectedTeamId,
                                            orElse: () => {},
                                          ),
                                        ),
                                icon: const Icon(Icons.folder_zip_outlined, size: 20),
                                tooltip: 'Compile All',
                                color: DefensysTokens.maroon,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refreshData,
                            color: DefensysTokens.maroon,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              itemCount: filteredReports.length,
                              itemBuilder: (context, index) {
                              final report = filteredReports[index];
                              final isSelected = selectedReportIndex == index;
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? Colors.blue : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: ListTile(
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${report['week_number'] ?? 0}',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    'Week ${report['week_number'] ?? 0}',
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    report['report_date'] ?? '',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      selectedReportIndex = index;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Right side - Document view
                Expanded(
                  child: selectedTeamId == null
                      ? const EmptyState(
                          icon: Icons.groups_outlined,
                          message: 'Select a team to view their progress reports',
                        )
                      : filteredReports.isEmpty
                          ? const EmptyState(
                              icon: Icons.assignment_outlined,
                              message: 'No weekly progress reports submitted yet',
                            )
                          : selectedReportIndex == null
                              ? const EmptyState(
                                  icon: Icons.description_outlined,
                                  message: 'Select a report to view details',
                                )
                              : _buildDocumentView(
                                  filteredReports[selectedReportIndex!],
                                  advisedTeams.firstWhere(
                                    (t) => (t['id']?.toString() ?? t['name']) == selectedTeamId,
                                    orElse: () => {},
                                  ),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentView(Map<String, dynamic> report, Map<String, dynamic> team) {
    final reportDate = report['report_date'] ?? '';
    final studentName = report['student_name'] ?? 'Unknown';
    final submittedAt = report['submitted_at'] ?? '';
    
    // Check if this is a file-based report
    final reportFile = report['report_file'] as String?;
    final fileSize = report['file_size'] as String?;
    final isFileBased = reportFile != null && reportFile.isNotEmpty;
    
    // Parse data (for legacy JSON reports)
    final accomplishments = (report['accomplishments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final contributions = (report['contributions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final issues = (report['issues'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final plans = (report['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Container(
      color: Colors.grey.shade200,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'serif',
                color: Colors.black,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // Header with university info
                _buildDocumentHeader(),
                
                // Title
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: const Text(
                    'CAPSTONE PROJECT WEEKLY ACCOMPLISHMENT REPORT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                
                // Team info section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildInfoRow('Team Name/Site:', team['name'] ?? 'Unknown'),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _buildInfoRow('Section:', team['yearLevel'] ?? 'N/A'),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _buildInfoRow('Date:', _formatDate(reportDate)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Project Title:', team['projectTitle'] ?? 'No project title'),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                
                // File-based report or Legacy JSON report
                if (isFileBased)
                  // File-based report display
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // File information banner
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: DefensysTokens.maroon.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: DefensysTokens.maroon.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: DefensysTokens.maroon.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      reportFile.toLowerCase().endsWith('.pdf')
                                          ? Icons.picture_as_pdf
                                          : Icons.description,
                                      color: DefensysTokens.maroon,
                                      size: 32,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Submitted Report File',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: DefensysTokens.maroon,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'The student submitted their weekly report as a file',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 16),
                              // File details
                              _buildFileInfoRow('File Name:', reportFile),
                              const SizedBox(height: 12),
                              _buildFileInfoRow('File Size:', fileSize ?? 'Unknown'),
                              const SizedBox(height: 12),
                              _buildFileInfoRow('File Type:', _getFileType(reportFile)),
                              const SizedBox(height: 12),
                              _buildFileInfoRow('Submitted By:', studentName),
                              const SizedBox(height: 12),
                              _buildFileInfoRow('Submitted At:', _formatDateTime(submittedAt)),
                              const SizedBox(height: 20),
                              // View PDF Button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _viewReportFile(report),
                                  icon: const Icon(Icons.visibility),
                                  label: const Text('View PDF Report'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: DefensysTokens.maroon,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Note
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'This is a PDF-based submission. Click the button above to view the report in an embedded PDF viewer.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  )
                else
                  // Legacy JSON report display
                  Column(
                    children: [
                      // Accomplishment for the Week
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Accomplishment for the Week',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildTable(
                              headers: ['Task / Activity', 'Description of Work Done', 'Output / Evidence'],
                              rows: accomplishments.map((item) => [
                                item['task']?.toString() ?? '',
                                item['description']?.toString() ?? '',
                                'Attached',
                              ]).toList(),
                              columnFlex: [2, 3, 2],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      
                      // Individual Contribution
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Individual Contribution',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildTable(
                              headers: ['Team Member', 'Contribution'],
                              rows: contributions.map((item) => [
                                item['member']?.toString() ?? '',
                                item['contribution']?.toString() ?? '',
                              ]).toList(),
                              columnFlex: [2, 3],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      
                      // Issues Encountered and Actions Taken
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Issues Encountered and Actions Taken',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildTable(
                              headers: ['Issue/Concern', 'Action Taken / Resolution'],
                              rows: issues.map((item) => [
                                item['issue']?.toString() ?? '',
                                item['action']?.toString() ?? '',
                              ]).toList(),
                              columnFlex: [2, 3],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      
                      // Plan for the Next Week
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Plan for the Next Week',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildTable(
                              headers: ['Planned Task', 'Expected Output'],
                              rows: plans.map((item) => [
                                item['task']?.toString() ?? '',
                                item['output']?.toString() ?? '',
                              ]).toList(),
                              columnFlex: [2, 2],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                
                // Adviser's Remarks
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Adviser's Remarks",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 120,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const Text(
                          '',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                
                // Signature section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  child: Column(
                    children: [
                      const Text(
                        'Reviewed by:',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 50),
                      Container(
                        width: 250,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.black, width: 1),
                          ),
                        ),
                        padding: const EdgeInsets.only(top: 4),
                        child: const Text(
                          'Capstone Project Adviser',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Date Signed: _______________',
                        style: TextStyle(fontSize: 11),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
                
                // Note section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Note:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildNoteBullet('This report shall be submitted weekly to the Capstone Adviser.'),
                      _buildNoteBullet('All members must actively contribute and be reflected in the report.'),
                      _buildNoteBullet('Supporting evidence (screenshots, documents, commitments, etc.) may be attached.'),
                      _buildNoteBullet('Submission of this report forms part of the progress monitoring and individual assessment of the Capstone Project.'),
                      const SizedBox(height: 24),
                      
                      // Submission info
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Submitted by: $studentName on ${_formatDateTime(submittedAt)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ), // Column
          ), // DefaultTextStyle
        ), // Container
      ), // Center
    ), // SingleChildScrollView
  ); // Container
}

  Widget _buildNoteBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(fontSize: 12),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // USTP Logo (left)
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'USTP',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'LOGO',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          
          // Center text
          Expanded(
            child: Column(
              children: [
                const Text(
                  'REPUBLIC OF THE PHILIPPINES',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'UNIVERSITY OF SCIENCE AND TECHNOLOGY OF SOUTHERN PHILIPPINES',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Department of Information Technology',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown.shade700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pob. Misamis, Oroquieta City, Misamis Occidental 7207',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 9,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Email Address: ustporoquieta.bsit@ustp.edu.ph',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 9,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Department seal/logo (right) - using same logo
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.brown.shade300,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.brown.shade100,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.school,
                          size: 28,
                          color: Colors.brown.shade700,
                        ),
                        Text(
                          'DEPT',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.brown.shade700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTable({
    required List<String> headers,
    required List<List<String>> rows,
    required List<int> columnFlex,
  }) {
    return Table(
      border: TableBorder.all(color: Colors.black, width: 1),
      columnWidths: {
        for (int i = 0; i < columnFlex.length; i++)
          i: FlexColumnWidth(columnFlex[i].toDouble()),
      },
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: headers.map((header) {
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                header,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            );
          }).toList(),
        ),
        // Data rows
        ...rows.map((row) {
          return TableRow(
            children: row.map((cell) {
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  cell,
                  style: const TextStyle(fontSize: 11),
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMMM d, yyyy').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDateTime(String dateTime) {
    try {
      final dt = DateTime.parse(dateTime);
      return DateFormat('MMMM d, yyyy h:mm a').format(dt);
    } catch (e) {
      return dateTime;
    }
  }

  Widget _buildFileInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: DefensysTokens.maroon,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  String _getFileType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return 'PDF Document';
      case 'doc':
        return 'Word Document (97-2003)';
      case 'docx':
        return 'Word Document';
      default:
        return extension.toUpperCase();
    }
  }

  void _viewReportFile(Map<String, dynamic> report) async {
    final fileUrl = report['file_url'] as String?;
    final reportFile = report['report_file'] as String?;
    final fileRef = (fileUrl != null && fileUrl.isNotEmpty)
        ? fileUrl
        : reportFile;
    final fileName = reportFile?.split('/').last ?? 'Report';

    if (fileRef == null || fileRef.isEmpty) {
      showValidationToast(context, 'No file attached to this report');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      ),
    );

    try {
      final pdfBytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileRef);

      if (mounted) Navigator.pop(context);

      if (mounted) {
        await viewPdfInDialog(
          context: context,
          pdfBytes: pdfBytes,
          fileName: fileName,
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        showErrorToast(context, 'Error opening file: $e');
      }
    }
  }

  Future<void> _compileAllReports(
    List<Map<String, dynamic>> reports,
    Map<String, dynamic> team,
  ) async {
    if (reports.isEmpty) {
      showValidationToast(context, 'No weekly progress reports to compile.');
      return;
    }

    // Show compilation dialog
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.folder_zip, color: DefensysTokens.maroon),
            const SizedBox(width: 10),
            Text('Compile Weekly Reports - ${team['name']}'),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team: ${team['name']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                      color: Color(0xFF0369A1),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This will generate a compilation report of all ${reports.length} weekly progress reports for this team.',
                        style: const TextStyle(
                          color: Color(0xFF0369A1),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Weekly reports to compile:',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                            color: AppColors.success,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Week ${report['week_number'] ?? 0}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Date: ${report['report_date'] ?? 'N/A'}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Week ${report['week_number']}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
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
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _downloadCompilation(team, reports);
            },
            icon: const Icon(Icons.download),
            label: const Text('Download Report'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DefensysTokens.maroon,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _downloadCompilation(
    Map<String, dynamic> team,
    List<Map<String, dynamic>> reports,
  ) {
    // Generate a simple text report
    final buffer = StringBuffer();
    buffer.writeln('='*60);
    buffer.writeln('WEEKLY PROGRESS REPORTS COMPILATION');
    buffer.writeln('='*60);
    buffer.writeln();
    buffer.writeln('Team: ${team['name']}');
    buffer.writeln('Project: ${team['projectTitle'] ?? 'N/A'}');
    buffer.writeln('Section: ${team['yearLevel'] ?? 'N/A'}');
    buffer.writeln('Generated: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln();
    buffer.writeln('='*60);
    buffer.writeln('WEEKLY REPORTS (${reports.length})');
    buffer.writeln('='*60);
    buffer.writeln();

    for (var i = 0; i < reports.length; i++) {
      final report = reports[i];
      final weekNumber = report['week_number'] ?? 0;
      final reportDate = report['report_date'] ?? 'N/A';
      final studentName = report['student_name'] ?? 'Unknown';
      final submittedAt = report['submitted_at'] ?? 'N/A';

      buffer.writeln('${i + 1}. WEEK $weekNumber');
      buffer.writeln('   Date: $reportDate');
      buffer.writeln('   Submitted by: $studentName');
      buffer.writeln('   Submitted at: $submittedAt');
      buffer.writeln();

      // Accomplishments
      final accomplishments = (report['accomplishments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (accomplishments.isNotEmpty) {
        buffer.writeln('   Accomplishments:');
        for (var acc in accomplishments) {
          buffer.writeln('   - Task: ${acc['task'] ?? 'N/A'}');
          buffer.writeln('     Description: ${acc['description'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Contributions
      final contributions = (report['contributions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (contributions.isNotEmpty) {
        buffer.writeln('   Individual Contributions:');
        for (var contrib in contributions) {
          buffer.writeln('   - ${contrib['member'] ?? 'N/A'}: ${contrib['contribution'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Issues
      final issues = (report['issues'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (issues.isNotEmpty) {
        buffer.writeln('   Issues & Actions:');
        for (var issue in issues) {
          buffer.writeln('   - Issue: ${issue['issue'] ?? 'N/A'}');
          buffer.writeln('     Action: ${issue['action'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Plans
      final plans = (report['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (plans.isNotEmpty) {
        buffer.writeln('   Plans for Next Week:');
        for (var plan in plans) {
          buffer.writeln('   - Task: ${plan['task'] ?? 'N/A'}');
          buffer.writeln('     Expected Output: ${plan['output'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      buffer.writeln('-' * 60);
      buffer.writeln();
    }

    buffer.writeln('='*60);
    buffer.writeln('END OF COMPILATION');
    buffer.writeln('='*60);

    // Show success message with view action
    showSuccessToast(
      context,
      'Compilation report generated for ${team['name']}\n'
      '${reports.length} weekly reports compiled.',
      duration: const Duration(seconds: 4),
      action: FeedbackToastAction(
        label: 'View',
        textColor: Colors.white,
        onPressed: () {
          // Show the report in a dialog
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Compilation Report'),
              content: SizedBox(
                width: 600,
                height: 400,
                child: SingleChildScrollView(
                  child: SelectableText(
                    buffer.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
