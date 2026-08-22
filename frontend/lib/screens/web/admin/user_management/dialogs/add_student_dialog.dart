import 'package:flutter/material.dart';
import '../../widgets/defensys_admin_shell.dart';

/// Dialog for enrolling an existing student or creating a new student account
/// and enrolling them into a specific semester, year level, and section in 1 step.
class AddStudentDialog extends StatefulWidget {
  const AddStudentDialog({
    super.key,
    this.record,
    this.overrideStudentId,
    required this.students,
    required this.schoolYears,
    required this.activeSemester,
  });

  final Map<String, dynamic>? record;
  final int? overrideStudentId;
  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> schoolYears;
  final Map<String, dynamic>? activeSemester;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    Map<String, dynamic>? record,
    int? overrideStudentId,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> schoolYears,
    required Map<String, dynamic>? activeSemester,
  }) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) => AddStudentDialog(
        record: record,
        overrideStudentId: overrideStudentId,
        students: students,
        schoolYears: schoolYears,
        activeSemester: activeSemester,
      ),
    );
  }

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog> {
  static const _maroon = DefensysUi.primaryMaroon;
  static const _muted = DefensysUi.steelGrey;
  static const _line = Color(0xFFE5E7EB);
  static const _ink = DefensysUi.textDark;

  static const List<String> _yearLevels = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
  ];

  late bool _editing;
  bool _isNewStudent = false;

  int? _selectedStudentId;
  String? _selectedSchoolYear;
  int? _selectedSemesterId;
  String _selectedYearLevel = '1st Year';

  final _studentIdCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _sectionCtrl = TextEditingController();

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final rec = widget.record;
    _editing = rec != null;

    if (_editing && rec != null) {
      _selectedStudentId = _asInt(rec['student_id']);
      _selectedSchoolYear = rec['school_year']?.toString();
      _selectedSemesterId = _asInt(rec['semester_id']);
      _selectedYearLevel = rec['year_level']?.toString() ?? _yearLevels.first;
      _sectionCtrl.text = rec['section']?.toString() ?? '';
    } else {
      _selectedStudentId = widget.overrideStudentId ??
          (widget.students.isNotEmpty ? _asInt(widget.students.first['id']) : null);
      _selectedSchoolYear = widget.activeSemester?['school_year']?.toString() ??
          (widget.schoolYears.isNotEmpty
              ? widget.schoolYears.first['label']?.toString()
              : null);
      _selectedSemesterId = _asInt(widget.activeSemester?['id']);
      _selectedYearLevel = _yearLevels.first;

      final semesters = _semestersForYear(_selectedSchoolYear);
      _selectedSemesterId ??= _firstSemesterId(semesters);
    }
  }

  @override
  void dispose() {
    _studentIdCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _sectionCtrl.dispose();
    super.dispose();
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v != null) return int.tryParse(v.toString());
    return null;
  }

  List<Map<String, dynamic>> _semestersForYear(String? schoolYearLabel) {
    if (schoolYearLabel == null || schoolYearLabel.isEmpty) return [];
    for (final sy in widget.schoolYears) {
      if (sy['label'] == schoolYearLabel) {
        final list = sy['semesters'];
        if (list is List) {
          return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        }
      }
    }
    return [];
  }

  int? _firstSemesterId(List<Map<String, dynamic>> semesters) {
    if (semesters.isEmpty) return null;
    return _asInt(semesters.first['id']);
  }

  void _onSave() {
    setState(() => _errorMessage = null);

    if (_selectedSemesterId == null) {
      setState(() => _errorMessage = 'Please select a valid semester.');
      return;
    }

    final section = _sectionCtrl.text.trim();

    if (_isNewStudent && !_editing) {
      final username = _studentIdCtrl.text.trim();
      final firstName = _firstNameCtrl.text.trim();
      final lastName = _lastNameCtrl.text.trim();
      final email = _emailCtrl.text.trim();

      if (username.isEmpty) {
        setState(() => _errorMessage = 'Student ID Number is required.');
        return;
      }
      if (firstName.isEmpty && lastName.isEmpty) {
        setState(() => _errorMessage = 'Student name is required.');
        return;
      }

      Navigator.of(context).pop<Map<String, dynamic>>({
        'student_username': username,
        'first_name': firstName,
        'last_name': lastName,
        'email': email.isNotEmpty ? email : '$username@ustp.edu.ph',
        'semester_id': _selectedSemesterId,
        'year_level': _selectedYearLevel,
        'section': section,
      });
    } else {
      if (_selectedStudentId == null) {
        setState(() => _errorMessage = 'Please select a student.');
        return;
      }

      Navigator.of(context).pop<Map<String, dynamic>>({
        'student_id': _selectedStudentId,
        'semester_id': _selectedSemesterId,
        'year_level': _selectedYearLevel,
        'section': section,
      });
    }
  }

  InputDecoration _inputDec(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 18, color: _muted) : null,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _maroon, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semesters = _semestersForYear(_selectedSchoolYear);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.school_rounded, color: Color(0xFF2563EB), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _editing ? 'Edit Academic Record' : 'Add Student Record',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              fontFamily: DefensysUi.fontFamily,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _editing
                                ? 'Update student section or year level for this semester'
                                : 'Enroll a student into the semester and assign their section',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: _muted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1, color: _line),
                const SizedBox(height: 20),

                if (!_editing && widget.overrideStudentId == null) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() {
                              _isNewStudent = false;
                              _errorMessage = null;
                            }),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !_isNewStudent ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: !_isNewStudent
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  'Existing Student',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: !_isNewStudent ? FontWeight.w700 : FontWeight.w500,
                                    color: !_isNewStudent ? _maroon : _muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() {
                              _isNewStudent = true;
                              _errorMessage = null;
                            }),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _isNewStudent ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: _isNewStudent
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '+ New Student Intake',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _isNewStudent ? FontWeight.w700 : FontWeight.w500,
                                    color: _isNewStudent ? _maroon : _muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_isNewStudent && !_editing) ...[
                  TextField(
                    controller: _studentIdCtrl,
                    decoration: _inputDec(
                      'Student ID Number *',
                      hint: 'e.g. 2024-00123',
                      icon: Icons.badge_outlined,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _firstNameCtrl,
                          decoration: _inputDec(
                            'First Name *',
                            hint: 'e.g. Juan',
                            icon: Icons.person_outline_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _lastNameCtrl,
                          decoration: _inputDec(
                            'Last Name *',
                            hint: 'e.g. Dela Cruz',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _emailCtrl,
                    decoration: _inputDec(
                      'Email Address (Optional)',
                      hint: 'Leave blank to auto-set as ID@ustp.edu.ph',
                      icon: Icons.email_outlined,
                    ),
                  ),
                  const SizedBox(height: 18),
                ] else ...[
                  DropdownButtonFormField<int>(
                    initialValue: _selectedStudentId,
                    decoration: _inputDec('Select Student *', icon: Icons.person_search_rounded),
                    onChanged: (_editing || widget.overrideStudentId != null)
                        ? null
                        : (val) => setState(() => _selectedStudentId = val),
                    items: widget.students.map((st) {
                      return DropdownMenuItem<int>(
                        value: _asInt(st['id']),
                        child: Text(
                          '${st['name']} (${st['username']})',
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                ],

                // Academic Context Section
                const Text(
                  'Academic Context',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedSchoolYear,
                        decoration: _inputDec('School Year'),
                        items: widget.schoolYears.map((sy) {
                          final label = sy['label']?.toString() ?? '';
                          return DropdownMenuItem<String>(
                            value: label,
                            child: Text(label, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: _editing
                            ? null
                            : (val) {
                                setState(() {
                                  _selectedSchoolYear = val;
                                  final sems = _semestersForYear(val);
                                  _selectedSemesterId = _firstSemesterId(sems);
                                });
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('$_selectedSchoolYear-$_selectedSemesterId'),
                        initialValue: _selectedSemesterId,
                        decoration: _inputDec('Semester'),
                        items: semesters.map((sem) {
                          return DropdownMenuItem<int>(
                            value: _asInt(sem['id']),
                            child: Text(
                              sem['label']?.toString() ?? '',
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: _editing
                            ? null
                            : (val) => setState(() => _selectedSemesterId = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedYearLevel,
                        decoration: _inputDec('Year Level *'),
                        items: _yearLevels.map((yl) {
                          return DropdownMenuItem<String>(
                            value: yl,
                            child: Text(yl, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedYearLevel = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _sectionCtrl,
                        decoration: _inputDec(
                          'Section',
                          hint: 'e.g. BSIT-3A',
                          icon: Icons.meeting_room_outlined,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _ink,
                        side: const BorderSide(color: _line),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _onSave,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(_editing ? 'Update Record' : 'Enroll Student'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
