import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'official_class_list_parser.dart';

/// Bulk CSV Import page component.
class BulkImportView extends StatefulWidget {
  const BulkImportView({
    super.key,
    required this.state,
    required this.academicState,
    required this.onBack,
    required this.onPickFile,
    required this.onDownloadSample,
    required this.onConfirmUpload,
  });

  final UserManagementState state;
  final AcademicPeriodState academicState;
  final VoidCallback onBack;
  final VoidCallback onPickFile;
  final VoidCallback onDownloadSample;
  final ValueChanged<List<Map<String, dynamic>>> onConfirmUpload;

  @override
  State<BulkImportView> createState() => _BulkImportViewState();
}

class _BulkImportViewState extends State<BulkImportView> {
  String _selectedRole = 'student';
  final TextEditingController _csvInputController = TextEditingController();
  AdminOfficialClassListParseResult? _parsedResult;

  @override
  void dispose() {
    _csvInputController.dispose();
    super.dispose();
  }

  void _onParseCsv(String text) {
    if (text.trim().isEmpty) {
      setState(() => _parsedResult = null);
      return;
    }
    final result = parseOfficialClassListCsv(text);
    setState(() => _parsedResult = result);
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsedResult;

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.output_rounded,
            title: 'Bulk Import Users',
            subtitle:
                'Upload a CSV file to create multiple users at once. Default password is set to their ID number.',
            actions: OutlinedButton.icon(
              onPressed: widget.state.isSaving ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Users'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DefensysUi.primaryMaroon,
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          DefensysCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Import Target Base Role',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'student', child: Text('Students')),
                          DropdownMenuItem(value: 'faculty', child: Text('Faculty Members')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedRole = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: widget.onDownloadSample,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Download Sample CSV'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _csvInputController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Paste CSV Content or Drop Class List Data',
                    hintText: 'Student ID, Full Name, Email, Year Level, Section...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _onParseCsv,
                ),
                const SizedBox(height: 16),
                if (parsed != null && parsed.students.isNotEmpty) ...[
                  Text(
                    'Detected ${parsed.students.length} students from parsed class list',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      itemCount: parsed.students.length,
                      itemBuilder: (context, index) {
                        final s = parsed.students[index];
                        return ListTile(
                          dense: true,
                          title: Text('${s['id_number']} — ${s['first_name']} ${s['last_name']}'),
                          subtitle: Text('Year: ${s['year_level'] ?? 'N/A'} | Section: ${s['section'] ?? 'N/A'}'),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: (parsed == null || parsed.students.isEmpty || widget.state.isSaving)
                        ? null
                        : () => widget.onConfirmUpload(parsed.students),
                    icon: const Icon(Icons.file_upload_rounded, size: 18),
                    label: Text('Confirm & Import ${parsed?.students.length ?? 0} Users'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DefensysUi.primaryMaroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
    );
  }
}
