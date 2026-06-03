import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/pit_instructor_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class PitInstructorAssignmentScreen extends ConsumerStatefulWidget {
  final String? initialSection;

  const PitInstructorAssignmentScreen({super.key, this.initialSection});

  @override
  ConsumerState<PitInstructorAssignmentScreen> createState() =>
      _PitInstructorAssignmentScreenState();
}

class _PitInstructorAssignmentScreenState
    extends ConsumerState<PitInstructorAssignmentScreen> {
  final _sectionController = TextEditingController();
  int? _selectedFacultyId;

  @override
  void initState() {
    super.initState();
    final initialSection = widget.initialSection?.trim();
    if (initialSection != null && initialSection.isNotEmpty) {
      _sectionController.text = initialSection;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pitInstructorProvider.notifier).fetchAssignments();
    });
  }

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pitInstructorProvider);

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.assignment_ind_outlined,
            title: 'PIT Instructors',
            subtitle:
                'Assign faculty instructors to sections in your PIT year.',
          ),
          const SizedBox(height: 20),
          if (state.error != null) ...[
            _notice(state.error!, warning: true),
            const SizedBox(height: 12),
          ],
          if (state.message != null) ...[
            _notice(state.message!),
            const SizedBox(height: 12),
          ],
          _assignmentPanel(state),
          const SizedBox(height: 20),
          _assignmentTable(state),
        ],
      ),
    );
  }

  Widget _assignmentPanel(PitInstructorState state) {
    final facultyItems = state.faculty
        .map((user) {
          final id = _asInt(user['id']);
          if (id == null) return null;
          final name =
              user['name']?.toString() ??
              user['username']?.toString() ??
              'Faculty';
          final role = user['displayRole'] is Map
              ? (user['displayRole']['label']?.toString() ?? 'Faculty')
              : 'Faculty';
          return DropdownMenuItem<int>(value: id, child: Text('$name - $role'));
        })
        .whereType<DropdownMenuItem<int>>()
        .toList();

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
          Row(
            children: [
              const Icon(
                Icons.person_add_alt_1_outlined,
                color: DefensysTokens.maroon,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Assign Instructor${state.yearLevel == null ? '' : ' - ${state.yearLevel}'}',
                  style: DefensysUi.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;
              final facultyField = DropdownButtonFormField<int>(
                initialValue: _selectedFacultyId,
                decoration: const InputDecoration(
                  labelText: 'Faculty',
                  border: OutlineInputBorder(),
                ),
                items: facultyItems,
                onChanged: state.isSaving
                    ? null
                    : (value) => setState(() => _selectedFacultyId = value),
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
              final assignButton = SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  icon: state.isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Assign'),
                  onPressed: state.isSaving ? null : _assignInstructor,
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    facultyField,
                    const SizedBox(height: 12),
                    sectionField,
                    const SizedBox(height: 12),
                    assignButton,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: facultyField),
                  const SizedBox(width: 12),
                  Expanded(child: sectionField),
                  const SizedBox(width: 12),
                  assignButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _assignmentTable(PitInstructorState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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
          Text(
            'Section Instructor Assignments',
            style: DefensysUi.sectionTitle,
          ),
          const SizedBox(height: 14),
          if (state.assignments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No PIT Instructor assignments yet.'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Faculty')),
                  DataColumn(label: Text('Section')),
                  DataColumn(label: Text('Semester')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Action')),
                ],
                rows: state.assignments.map((assignment) {
                  final id = _asInt(assignment['id']);
                  final active = assignment['is_active'] == true;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          assignment['faculty_name']?.toString() ?? 'Faculty',
                        ),
                      ),
                      DataCell(Text(assignment['section']?.toString() ?? '-')),
                      DataCell(
                        Text(assignment['semester_label']?.toString() ?? '-'),
                      ),
                      DataCell(_statusBadge(active)),
                      DataCell(
                        TextButton.icon(
                          icon: Icon(
                            active
                                ? Icons.visibility_off_outlined
                                : Icons.restore_outlined,
                            size: 17,
                          ),
                          label: Text(active ? 'Deactivate' : 'Restore'),
                          onPressed: id == null || state.isSaving
                              ? null
                              : () => ref
                                    .read(pitInstructorProvider.notifier)
                                    .setAssignmentActive(id, !active),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(bool active) {
    final color = active ? DefensysUi.successText : DefensysUi.steelGrey;
    final bg = active ? DefensysUi.successBg : const Color(0xFFF3F4F6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
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

  Future<void> _assignInstructor() async {
    final facultyId = _selectedFacultyId;
    final section = _sectionController.text.trim();
    if (facultyId == null || section.isEmpty) {
      return;
    }

    final saved = await ref
        .read(pitInstructorProvider.notifier)
        .assignInstructor(facultyId: facultyId, section: section);
    if (!mounted || !saved) return;
    setState(() {
      _selectedFacultyId = null;
      _sectionController.clear();
    });
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
