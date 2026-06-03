import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/dashboard_provider.dart';
import '../../../services/user_management_provider.dart';
import '../../../utils/csv_file_io.dart';
import '../../../utils/student_bulk_import_csv.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class PitStudentImportScreen extends ConsumerStatefulWidget {
  const PitStudentImportScreen({super.key});

  @override
  ConsumerState<PitStudentImportScreen> createState() =>
      _PitStudentImportScreenState();
}

class _PitStudentImportScreenState
    extends ConsumerState<PitStudentImportScreen> {
  final _sectionController = TextEditingController();
  List<Map<String, dynamic>> _rows = [];

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userManagementProvider);
    final dashboard = ref.watch(dashboardProvider('faculty')).data;
    final year = dashboard?['pit_lead_year']?.toString() ?? 'your PIT year';

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.person_add_alt_outlined,
            title: 'Import PIT Students',
            subtitle: 'Create student accounts for $year only.',
            actions: OutlinedButton.icon(
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('CSV Template'),
              onPressed: () => _downloadTemplate(year),
            ),
          ),
          const SizedBox(height: 20),
          if (userState.error != null) ...[
            _notice(userState.error!, warning: true),
            const SizedBox(height: 12),
          ],
          if (userState.message != null) ...[
            _notice(userState.message!),
            const SizedBox(height: 12),
          ],
          _importPanel(userState, year),
        ],
      ),
    );
  }

  Widget _importPanel(UserManagementState state, String year) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Student Batch Context', style: DefensysUi.sectionTitle),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final yearBox = InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Batch Year Level',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  year,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              );
              final sectionField = TextField(
                controller: _sectionController,
                enabled: !state.isSaving,
                decoration: const InputDecoration(
                  labelText: 'Section',
                  hintText: 'BSIT 3A',
                  border: OutlineInputBorder(),
                ),
              );
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [yearBox, const SizedBox(height: 12), sectionField],
                );
              }
              return Row(
                children: [
                  Expanded(child: yearBox),
                  const SizedBox(width: 12),
                  Expanded(child: sectionField),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: state.isSaving ? null : _pickCsv,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              height: 138,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_upload_outlined,
                    color: Color(0xFF98A2B3),
                    size: 34,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _rows.isEmpty
                        ? 'Click to choose a student CSV'
                        : '${_rows.length} student row${_rows.length == 1 ? '' : 's'} ready',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Student rows only',
                    style: TextStyle(color: Color(0xFF667085), fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Year level and active semester are locked by your PIT Lead assignment.',
                  style: TextStyle(
                    color: DefensysUi.steelGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: state.isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import Students'),
                onPressed: state.isSaving || _rows.isEmpty ? null : _importRows,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _downloadTemplate(String year) async {
    await downloadTextFile(
      filename: sampleStudentCsvFilenameForYear(year),
      content: sampleStudentCsvForYear(year),
    );
  }

  Future<void> _pickCsv() async {
    final csv = await pickCsvTextFile();
    if (!mounted || csv == null) return;
    setState(() => _rows = _parseCsv(csv));
  }

  Future<void> _importRows() async {
    final saved = await ref
        .read(userManagementProvider.notifier)
        .pitLeadStudentImport(
          _rows,
          studentContext: {
            if (_sectionController.text.trim().isNotEmpty)
              'section': _sectionController.text.trim(),
          },
        );
    if (!mounted || !saved) return;
    setState(() => _rows = []);
  }

  List<Map<String, dynamic>> _parseCsv(String csv) {
    final lines = csv
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 2) return [];

    final headers = lines.first
        .split(',')
        .map((header) => header.trim().toLowerCase().replaceFirst('\ufeff', ''))
        .toList();
    final idIndex = headers.indexOf('id_number');
    final firstIndex = headers.indexOf('first_name');
    final lastIndex = headers.indexOf('last_name');
    final emailIndex = headers.indexOf('email');
    final roleIndex = headers.indexOf('role');
    if ([idIndex, firstIndex, lastIndex, emailIndex, roleIndex].contains(-1)) {
      return [];
    }

    return lines
        .skip(1)
        .map((line) {
          final columns = line.split(',').map((cell) => cell.trim()).toList();
          String read(int index) =>
              index < columns.length ? columns[index] : '';
          return {
            'id_number': read(idIndex),
            'first_name': read(firstIndex),
            'last_name': read(lastIndex),
            'email': read(emailIndex),
            'role': read(roleIndex).isEmpty ? 'student' : read(roleIndex),
          };
        })
        .where((row) => row['id_number']!.isNotEmpty)
        .toList();
  }

  Widget _notice(String message, {bool warning = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: warning ? DefensysUi.warningBg : DefensysUi.successBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warning ? DefensysUi.warningBorder : DefensysUi.successBorder,
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: warning ? DefensysUi.warningText : DefensysUi.successText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
