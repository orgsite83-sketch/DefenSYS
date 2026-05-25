import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/dashboard_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/feedback_snackbar.dart';

class WeeklyReportTab extends ConsumerStatefulWidget {
  const WeeklyReportTab({super.key});

  @override
  ConsumerState<WeeklyReportTab> createState() => _WeeklyReportTabState();
}

class _WeeklyReportTabState extends ConsumerState<WeeklyReportTab> {
  final _weekNumberCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  
  String? _selectedFileName;
  String? _selectedFileSize;
  Uint8List? _selectedFileBytes;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateCtrl.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _weekNumberCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'], // Only PDF now
        withData: true, // Changed to true to get file bytes
      );

      if (result != null && result.files.single.name.isNotEmpty) {
        setState(() {
          _selectedFileName = result.files.single.name;
          final bytes = result.files.single.size;
          _selectedFileSize = '${(bytes / 1024).toStringAsFixed(2)} KB';
          _selectedFileBytes = result.files.single.bytes; // Store file bytes
        });
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Error picking file: $e');
      }
    }
  }

  Future<void> _submitReport() async {
    if (_weekNumberCtrl.text.trim().isEmpty) {
      showValidationSnackBar(context, 'Please enter week number');
      return;
    }

    if (_selectedFileName == null || _selectedFileBytes == null) {
      showValidationSnackBar(context, 'Please select a PDF file');
      return;
    }

    final week = _weekNumberCtrl.text.trim();
    final fileName = _selectedFileName!;

    final confirmed = await confirmDestructive(
      context,
      title: 'Submit Weekly Report?',
      message:
          'Week $week — $fileName. This submission will be sent to your adviser.',
      confirmLabel: 'Submit',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      final dashState = ref.read(dashboardProvider('student'));
      final teamData = dashState.data?['team'] as Map<String, dynamic>?;
      final teamId = teamData?['id'];

      if (teamId == null) {
        throw Exception('Missing team data');
      }

      final client = ref.read(authenticatedHttpClientProvider);
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.weeklyProgressUrl}/'),
      );

      request.fields['team'] = teamId.toString();
      request.fields['week_number'] = week;
      request.fields['report_date'] = _dateCtrl.text.trim();
      request.fields['file_size'] = _selectedFileSize ?? '';
      request.fields['accomplishments'] = '[]';
      request.fields['contributions'] = '[]';
      request.fields['issues'] = '[]';
      request.fields['plans'] = '[]';

      request.files.add(http.MultipartFile.fromBytes(
        'report_file',
        _selectedFileBytes!,
        filename: fileName,
      ));

      final streamedResponse = await client.sendAuthenticated(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          showSuccessSnackBar(
            context,
            'Weekly report submitted successfully!',
          );

          setState(() {
            _weekNumberCtrl.clear();
            _selectedFileName = null;
            _selectedFileSize = null;
            _selectedFileBytes = null;
          });
        }
      } else {
        throw Exception('Failed to submit: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _refreshDashboard() async {
    await ref.read(dashboardProvider('student').notifier).fetchDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    final dashState = ref.watch(dashboardProvider('student'));
    final teamData = dashState.data?['team'] as Map<String, dynamic>?;
    final isCapstone = teamData?['isCapstone'] == true;

    if (!isCapstone) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                'Weekly progress reports are for capstone teams only.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'PIT students can view grades under the My Grades tab.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Check if student is team leader
    final studentData = dashState.data?['student'] as Map<String, dynamic>?;
    final leaderName = teamData?['leaderName'] as String?;
    final studentName = studentData?['name'] as String?;
    final isLeader = leaderName == studentName;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        color: DefensysTokens.maroon,
        onRefresh: _refreshDashboard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Leadership status banner
            if (!isLeader)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Only the team leader can submit weekly progress reports.',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: DefensysTokens.maroon,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.assignment, color: Colors.white, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weekly Progress Report',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Upload your weekly progress report (PDF only)',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Form Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Week Number
                  TextField(
                    controller: _weekNumberCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Week Number *',
                      hintText: 'e.g., 1, 2, 3...',
                      prefixIcon: const Icon(Icons.calendar_today),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Report Date
                  TextField(
                    controller: _dateCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Report Date',
                      prefixIcon: const Icon(Icons.event),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (date != null) {
                        _dateCtrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  // File Upload Section
                  const Text(
                    'Upload Report (PDF only) *',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // File Picker Button
                  OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : _pickFile,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose PDF File'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      side: BorderSide(color: DefensysTokens.maroon),
                      foregroundColor: DefensysTokens.maroon,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Selected File Display
                  if (_selectedFileName != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedFileName!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedFileSize ?? '',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove file',
                            onPressed: () {
                              setState(() {
                                _selectedFileName = null;
                                _selectedFileSize = null;
                                _selectedFileBytes = null;
                              });
                            },
                            icon: const Icon(Icons.close, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey.shade600, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No file selected. Click "Choose PDF File" to upload your weekly report.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: (_isSubmitting || _selectedFileName == null || !isLeader)
                          ? null
                          : _submitReport,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                        _isSubmitting 
                            ? 'Submitting...' 
                            : !isLeader 
                                ? 'Only Leader Can Submit' 
                                : 'Submit Report'
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isLeader ? DefensysTokens.maroon : Colors.grey,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
