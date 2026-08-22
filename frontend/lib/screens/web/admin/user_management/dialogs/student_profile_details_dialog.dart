import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/admin/user_management_provider.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/confirm_dialog.dart';

/// Unified Dialog for viewing and editing a student's personal details,
/// current academic enrollment, and historical semester records in place.
class StudentProfileDetailsDialog extends ConsumerStatefulWidget {
  const StudentProfileDetailsDialog({
    super.key,
    required this.record,
    required this.schoolYears,
    required this.activeSemester,
    this.initialHistory = const [],
    this.initialIsEditing = false,
  });

  final Map<String, dynamic> record;
  final List<Map<String, dynamic>> schoolYears;
  final Map<String, dynamic>? activeSemester;
  final List<Map<String, dynamic>> initialHistory;
  final bool initialIsEditing;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> record,
    required List<Map<String, dynamic>> schoolYears,
    required Map<String, dynamic>? activeSemester,
    List<Map<String, dynamic>> initialHistory = const [],
    bool initialIsEditing = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StudentProfileDetailsDialog(
        record: record,
        schoolYears: schoolYears,
        activeSemester: activeSemester,
        initialHistory: initialHistory,
        initialIsEditing: initialIsEditing,
      ),
    );
  }

  @override
  ConsumerState<StudentProfileDetailsDialog> createState() =>
      _StudentProfileDetailsDialogState();
}

class _StudentProfileDetailsDialogState
    extends ConsumerState<StudentProfileDetailsDialog> {
  static const _maroon = DefensysUi.primaryMaroon;
  static const _muted = DefensysUi.steelGrey;
  static const _line = Color(0xFFE5E7EB);
  static const _ink = DefensysUi.textDark;
  static const _cardBg = Color(0xFFF9FAFB);
  static const String _addCustomSectionValue = '__ADD_CUSTOM_SECTION__';

  static const List<String> _yearLevels = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
  ];

  late bool _isEditing;
  bool _isSaving = false;
  String? _errorMessage;

  late Map<String, dynamic> _currentRecord;
  late Map<String, dynamic> _studentUser;
  late List<Map<String, dynamic>> _history;
  final Set<String> _customSections = {};

  // Controllers for editing
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _emailCtrl;

  late bool _isActive;
  String? _selectedSchoolYear;
  int? _selectedSemesterId;
  String _selectedYearLevel = '1st Year';
  String? _selectedSection;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.initialIsEditing;
    _currentRecord = Map<String, dynamic>.from(widget.record);
    _history = List<Map<String, dynamic>>.from(widget.initialHistory);

    final username = _currentRecord['student_username']?.toString() ?? '';
    final studentName = _currentRecord['student_name']?.toString() ?? username;
    final studentEmail = _currentRecord['student_email']?.toString() ?? '';
    final studentId = _currentRecord['student_id'];

    final users = ref.read(userManagementProvider).users;
    try {
      final existing = users.firstWhere(
        (u) =>
            (studentId != null && u['id'] == studentId) ||
            u['username'] == username,
      );
      _studentUser = Map<String, dynamic>.from(existing);
    } catch (_) {
      _studentUser = {
        if (studentId != null) 'id': studentId,
        'username': username,
        'first_name': _currentRecord['first_name'] ??
            (studentName.contains(' ')
                ? studentName.split(' ').first
                : studentName),
        'last_name': _currentRecord['last_name'] ??
            (studentName.contains(' ')
                ? studentName.split(' ').skip(1).join(' ')
                : ''),
        'name': studentName,
        'email': studentEmail,
        'role': 'student',
        'is_active': _currentRecord['is_active'] != false,
      };
    }

    _firstNameCtrl = TextEditingController(
      text: _studentUser['first_name']?.toString() ?? '',
    );
    _lastNameCtrl = TextEditingController(
      text: _studentUser['last_name']?.toString() ?? '',
    );
    _emailCtrl = TextEditingController(
      text: _studentUser['email']?.toString() ?? studentEmail,
    );

    _isActive = _studentUser['is_active'] != false;
    _selectedSchoolYear = _currentRecord['school_year']?.toString() ??
        widget.activeSemester?['school_year']?.toString();
    _selectedSemesterId = _asInt(_currentRecord['semester_id']) ??
        _asInt(widget.activeSemester?['id']);

    final recYearLevel = _currentRecord['year_level']?.toString();
    _selectedYearLevel = (_yearLevels.contains(recYearLevel))
        ? recYearLevel!
        : _yearLevels.first;

    final rawSection = _currentRecord['section']?.toString().trim();
    final available = _getSectionsForYearLevel(_selectedYearLevel);
    if (rawSection != null &&
        rawSection.isNotEmpty &&
        rawSection.toUpperCase() != 'BSIT') {
      _selectedSection = rawSection;
    } else {
      _selectedSection = available.isNotEmpty ? available.first : null;
    }

    // Load history if not initially provided
    if (_history.isEmpty && username.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final fetched = await ref
            .read(studentAcademicRecordsProvider.notifier)
            .fetchStudentHistory(username);
        if (mounted) {
          setState(() {
            _history = fetched;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
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
          return list
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      }
    }
    return [];
  }

  List<String> _getSectionsForYearLevel(String yearLevel) {
    final sections = <String>{};

    // 1. Gather all actual sections from student academic records matching this year level
    final records = ref.read(studentAcademicRecordsProvider).records;
    for (final r in records) {
      if (r['year_level']?.toString().trim() == yearLevel.trim()) {
        final sec = r['section']?.toString().trim();
        if (sec != null && sec.isNotEmpty && sec.toUpperCase() != 'BSIT') {
          sections.add(sec);
        }
      }
    }

    // 2. Gather all actual sections from faculty instructor assignments matching this year level
    final users = ref.read(userManagementProvider).users;
    for (final u in users) {
      final assignments = u['instructor_assignments'] as List?;
      if (assignments != null) {
        for (final a in assignments) {
          if (a is Map) {
            final yl = a['year_level']?.toString().trim();
            final sec = a['section']?.toString().trim();
            if (yl == yearLevel.trim() &&
                sec != null &&
                sec.isNotEmpty &&
                sec.toUpperCase() != 'BSIT') {
              sections.add(sec);
            }
          }
        }
      }
    }

    // 3. Incorporate any custom sections added during this session
    for (final cs in _customSections) {
      sections.add(cs);
    }

    // 4. Ensure current selected section is present if valid
    final current = _currentRecord['section']?.toString().trim();
    if (current != null && current.isNotEmpty && current.toUpperCase() != 'BSIT') {
      sections.add(current);
    }

    final sorted = sections.toList()..sort();
    return sorted;
  }

  Future<void> _handleAddNewSection(String yearLevel) async {
    final yearNum = yearLevel.contains('1')
        ? '1'
        : yearLevel.contains('2')
            ? '2'
            : yearLevel.contains('3')
                ? '3'
                : '4';

    final textCtrl = TextEditingController(text: 'BSIT-$yearNum');
    final newSection = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.add_circle_outline_rounded, color: _maroon, size: 20),
            SizedBox(width: 8),
            Text(
              'Add New Section',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the section code for $yearLevel (e.g. BSIT-${yearNum}E, BSCS-${yearNum}A):',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Section Code',
                hintText: 'e.g. BSIT-${yearNum}E',
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = textCtrl.text.trim().toUpperCase();
              if (val.isNotEmpty && val != 'BSIT') {
                Navigator.of(ctx).pop(val);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: _maroon),
            child: const Text('Add Section'),
          ),
        ],
      ),
    );

    if (newSection != null && newSection.isNotEmpty) {
      setState(() {
        _customSections.add(newSection);
        _selectedSection = newSection;
      });
    }
  }

  void _resetEditControllers() {
    _firstNameCtrl.text = _studentUser['first_name']?.toString() ?? '';
    _lastNameCtrl.text = _studentUser['last_name']?.toString() ?? '';
    _emailCtrl.text = _studentUser['email']?.toString() ?? '';
    _isActive = _studentUser['is_active'] != false;
    _selectedSchoolYear = _currentRecord['school_year']?.toString();
    _selectedSemesterId = _asInt(_currentRecord['semester_id']);
    final recYearLevel = _currentRecord['year_level']?.toString();
    _selectedYearLevel = (_yearLevels.contains(recYearLevel))
        ? recYearLevel!
        : _yearLevels.first;
    final rawSection = _currentRecord['section']?.toString().trim();
    final available = _getSectionsForYearLevel(_selectedYearLevel);
    _selectedSection = (rawSection != null && rawSection.toUpperCase() != 'BSIT')
        ? rawSection
        : (available.isNotEmpty ? available.first : null);
    _errorMessage = null;
  }

  Future<void> _handleResetPassword() async {
    final username = _studentUser['username']?.toString() ??
        _currentRecord['student_username']?.toString() ??
        '';
    final name = (_studentUser['name']?.toString().trim().isNotEmpty == true)
        ? _studentUser['name']
        : '${_studentUser['first_name'] ?? ''} ${_studentUser['last_name'] ?? ''}'
            .trim();
    final displayName = name.isNotEmpty ? name : username;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset Password?',
      message:
          'Reset password for $displayName to their default ID number ($username)?',
      confirmLabel: 'Reset Password',
    );
    if (confirmed == true && mounted) {
      final id = _studentUser['id'] ?? _currentRecord['student_id'];
      if (id != null) {
        final userId = id is int ? id : int.parse(id.toString());
        await ref
            .read(userManagementProvider.notifier)
            .resetUserPassword(userId);
        if (mounted) {
          showSuccessToast(
              context, 'Password reset to default ID number ($username).');
        }
      }
    }
  }


  Future<void> _handleDeleteStudentAccount() async {
    final username = _studentUser['username']?.toString() ??
        _currentRecord['student_username']?.toString() ??
        '';
    final name = (_studentUser['name']?.toString().trim().isNotEmpty == true)
        ? _studentUser['name']
        : '${_studentUser['first_name'] ?? ''} ${_studentUser['last_name'] ?? ''}'
            .trim();
    final displayName = name.isNotEmpty ? name : username;

    final id = _studentUser['id'] ?? _currentRecord['student_id'];
    if (id == null) return;
    final userId = id is int ? id : int.parse(id.toString());

    final confirmed = await showDestructiveTypeConfirmDialog(
      context,
      title: 'Delete Student Account?',
      message:
          'You are about to permanently delete the student account for $displayName (ID: $username). All active and past academic enrollment records and team memberships for this student will be permanently deleted.',
      matchTarget: username,
      confirmLabel: 'Permanently Delete Account',
      warningBanner:
          'This action cannot be undone. Once deleted, the student credentials, course enrollments, and associated records will be removed.',
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(userManagementProvider.notifier)
          .deleteUser(userId);

      if (success && mounted) {
        showSuccessToast(
            context, 'Student account for $displayName has been deleted.');
        ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
        ref.read(userManagementProvider.notifier).fetchUsers();
        Navigator.of(context).pop();
      } else if (mounted) {
        final err = ref.read(userManagementProvider).error ??
            'Failed to delete student account.';
        setState(() {
          _errorMessage = err;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    setState(() {
      _errorMessage = null;
      _isSaving = true;
    });

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final section = (_selectedSection ?? '').trim();

    if (firstName.isEmpty && lastName.isEmpty) {
      setState(() {
        _errorMessage = 'Student name cannot be empty.';
        _isSaving = false;
      });
      return;
    }

    if (section.isEmpty || section.toUpperCase() == 'BSIT') {
      setState(() {
        _errorMessage = 'Please select a valid section.';
        _isSaving = false;
      });
      return;
    }

    final username = _studentUser['username']?.toString() ??
        _currentRecord['student_username']?.toString() ??
        '';
    final studentId = _studentUser['id'] ?? _currentRecord['student_id'];

    // 1. Update personal details
    final userPayload = {
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'role': _studentUser['role']?.toString() ?? 'student',
      'is_active': _isActive,
    };

    bool userSuccess = true;
    if (studentId != null) {
      final id = studentId is int ? studentId : int.parse(studentId.toString());
      userSuccess = await ref
          .read(userManagementProvider.notifier)
          .updateUser(id, userPayload);
    }

    // 2. Update academic details
    final recordId = _currentRecord['id'];
    final academicPayload = {
      if (studentId != null) 'student_id': studentId,
      if (username.isNotEmpty) 'student_username': username,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'year_level': _selectedYearLevel,
      'section': section,
      if (_selectedSemesterId != null) 'semester_id': _selectedSemesterId,
    };

    bool academicSuccess = true;
    if (recordId != null) {
      final id = recordId is int ? recordId : int.parse(recordId.toString());
      academicSuccess = await ref
          .read(studentAcademicRecordsProvider.notifier)
          .updateRecord(id, academicPayload);
    }

    if (!mounted) return;

    if (userSuccess && academicSuccess) {
      // Sync local state
      setState(() {
        _studentUser['first_name'] = firstName;
        _studentUser['last_name'] = lastName;
        _studentUser['name'] = '$firstName $lastName'.trim();
        _studentUser['email'] = email;
        _studentUser['is_active'] = _isActive;

        _currentRecord['first_name'] = firstName;
        _currentRecord['last_name'] = lastName;
        _currentRecord['student_name'] = '$firstName $lastName'.trim();
        _currentRecord['student_email'] = email;
        _currentRecord['year_level'] = _selectedYearLevel;
        _currentRecord['section'] = section;
        _currentRecord['school_year'] = _selectedSchoolYear;
        _currentRecord['semester_id'] = _selectedSemesterId;

        final sems = _semestersForYear(_selectedSchoolYear);
        final semMatch = sems.firstWhere(
          (s) => _asInt(s['id']) == _selectedSemesterId,
          orElse: () => <String, dynamic>{},
        );
        if (semMatch.isNotEmpty) {
          _currentRecord['semester'] =
              semMatch['label'] ?? semMatch['display_name'];
        }

        _isEditing = false;
        _isSaving = false;
      });

      showSuccessToast(context, 'Student details updated successfully.');

      // Refresh providers
      ref.read(studentAcademicRecordsProvider.notifier).fetchRecords();
      ref.read(userManagementProvider.notifier).fetchUsers();

      // Refresh history in background
      if (username.isNotEmpty) {
        final updatedHistory = await ref
            .read(studentAcademicRecordsProvider.notifier)
            .fetchStudentHistory(username);
        if (mounted) {
          setState(() {
            _history = updatedHistory;
          });
        }
      }
    } else {
      final recordError = ref.read(studentAcademicRecordsProvider).error;
      final userError = ref.read(userManagementProvider).error;
      setState(() {
        _isSaving = false;
        _errorMessage = recordError ??
            userError ??
            'Failed to update student details. Please verify your inputs.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentName = (_studentUser['name']?.toString().trim().isNotEmpty ==
            true)
        ? _studentUser['name']
        : '${_studentUser['first_name'] ?? ''} ${_studentUser['last_name'] ?? ''}'
            .trim();
    final username = _studentUser['username']?.toString() ??
        _currentRecord['student_username']?.toString() ??
        '';
    final displayName = currentName.isNotEmpty ? currentName : username;
    final currentEmail = _studentUser['email']?.toString() ??
        _currentRecord['student_email']?.toString() ??
        'No email provided';
    final isStudentActive = _studentUser['is_active'] != false;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _maroon.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.school_rounded, color: _maroon, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Student Profile & Enrollment',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'View and manage student personal information and academic standing',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 20, color: _muted),
            tooltip: 'Close',
          ),
        ],
      ),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // Student Top Summary Banner
              _buildStudentHeaderBanner(
                displayName: displayName,
                username: username,
                email: currentEmail,
                isActive: isStudentActive,
              ),

              const SizedBox(height: 20),

              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Color(0xFFDC2626), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Mode-Driven Body (View Mode vs. In-Place Edit Mode)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isEditing
                    ? _buildEditModeContent()
                    : _buildViewModeContent(),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      actions: _buildDialogActions(),
    );
  }

  // --- Student Top Summary Banner ---
  Widget _buildStudentHeaderBanner({
    required String displayName,
    required String username,
    required String email,
    required bool isActive,
  }) {
    final initials = displayName.trim().isNotEmpty
        ? displayName
            .trim()
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0])
            .take(2)
            .join()
            .toUpperCase()
        : 'ST';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _maroon.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: _maroon.withValues(alpha: 0.25)),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _maroon,
                    ),
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
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildActiveBadge(isActive),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.badge_outlined,
                                size: 13, color: _muted),
                            const SizedBox(width: 4),
                            Text(
                              'ID: $username',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.mail_outline_rounded,
                                size: 13, color: _muted),
                            const SizedBox(width: 4),
                            Text(
                              email,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildActiveBadge(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: active ? const Color(0xFF166534) : const Color(0xFF991B1B),
        ),
      ),
    );
  }

  // --- View Mode Content ---
  Widget _buildViewModeContent() {
    final yearLevel = _currentRecord['year_level']?.toString() ?? '1st Year';
    final section = _currentRecord['section']?.toString().isNotEmpty == true
        ? _currentRecord['section']
        : 'No Section Assigned';
    final schoolYear = _currentRecord['school_year']?.toString() ?? '—';
    final semester = _currentRecord['semester']?.toString() ?? '—';
    final instructor = _currentRecord['instructor_name']?.toString();
    final firstName = _studentUser['first_name']?.toString() ?? '—';
    final lastName = _studentUser['last_name']?.toString() ?? '—';

    return Column(
      key: const ValueKey('view_mode'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two-Column Grid: Personal Details + Academic Details
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 560;
            if (isNarrow) {
              return Column(
                children: [
                  _buildPersonalDetailsCard(firstName, lastName),
                  const SizedBox(height: 14),
                  _buildAcademicDetailsCard(
                      schoolYear, semester, yearLevel, section, instructor),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildPersonalDetailsCard(firstName, lastName),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _buildAcademicDetailsCard(
                      schoolYear, semester, yearLevel, section, instructor),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        // Enrollment History Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, size: 16, color: _maroon),
                const SizedBox(width: 6),
                const Text(
                  'ENROLLMENT HISTORY',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: _muted,
                  ),
                ),
              ],
            ),
            if (_history.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${_history.length} terms',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        _buildHistoryList(),
      ],
    );
  }

  Widget _buildPersonalDetailsCard(String firstName, String lastName) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 15, color: _maroon),
              const SizedBox(width: 6),
              const Text(
                'Personal Profile',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('First Name', firstName),
          const SizedBox(height: 8),
          _buildInfoRow('Last Name', lastName),
          const SizedBox(height: 8),
          _buildInfoRow(
            'Account Role',
            'Student',
            badgeColor: const Color(0xFFEFF6FF),
            badgeTextColor: const Color(0xFF1D4ED8),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicDetailsCard(
    String schoolYear,
    String semester,
    String yearLevel,
    String section,
    String? instructor,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.school_outlined, size: 15, color: _maroon),
                  const SizedBox(width: 6),
                  const Text(
                    'Academic Standing',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Active Term',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('School Year', '$schoolYear · $semester'),
          const SizedBox(height: 8),
          _buildInfoRow(
            'Year Level',
            yearLevel,
            badgeColor: const Color(0xFFDCFCE7),
            badgeTextColor: const Color(0xFF166534),
          ),
          const SizedBox(height: 8),
          _buildInfoRow('Section', section),
          if (instructor != null && instructor.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow('Instructor', instructor),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    Color? badgeColor,
    Color? badgeTextColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: badgeColor != null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeTextColor ?? _ink,
                      ),
                    ),
                  ),
                )
              : Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        child: const Center(
          child: Text(
            'No prior enrollment history records found.',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: _line),
        itemBuilder: (_, i) {
          final item = _history[i];
          final isCurrent = item['id'] == _currentRecord['id'];
          final termYearLevel = item['year_level']?.toString() ?? '—';
          final termSY = item['school_year']?.toString() ?? '';
          final termSem = item['semester']?.toString() ?? '';
          final termSec = item['section']?.toString().isNotEmpty == true
              ? item['section']
              : 'No Section';
          final termInstructor = item['instructor_name']?.toString();

          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isCurrent
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                termYearLevel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isCurrent ? const Color(0xFF166534) : _ink,
                ),
              ),
            ),
            title: Text(
              '$termSY · $termSem',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
            subtitle: Text(
              'Section: $termSec${termInstructor != null ? ' • Instructor: $termInstructor' : ''}',
              style: const TextStyle(fontSize: 11.5, color: _muted),
            ),
            trailing: isCurrent
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'Active Term',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF166534),
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }

  // --- In-Place Edit Mode Content ---
  Widget _buildEditModeContent() {
    final username = _studentUser['username']?.toString() ??
        _currentRecord['student_username']?.toString() ??
        '';
    final studentName = (_studentUser['name']?.toString().trim().isNotEmpty == true)
        ? _studentUser['name']
        : '${_studentUser['first_name'] ?? ''} ${_studentUser['last_name'] ?? ''}'
            .trim();
    final displayName = studentName.isNotEmpty ? studentName : username;
    final semesters = _semestersForYear(_selectedSchoolYear);
    final sectionOptions = _getSectionsForYearLevel(_selectedYearLevel);
    final currentSectionVal = (sectionOptions.contains(_selectedSection))
        ? _selectedSection
        : (sectionOptions.isNotEmpty ? sectionOptions.first : null);

    return Column(
      key: const ValueKey('edit_mode'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Edit Mode Header Notice
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Row(
            children: [
              Icon(Icons.edit_note_rounded,
                  color: Color(0xFF1D4ED8), size: 18),
              SizedBox(width: 8),
              Text(
                'Editing Student Profile & Academic Record',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // Section 1: Edit Personal Information
        const Text(
          'PERSONAL INFORMATION',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: _muted,
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _buildFormField(
                controller: _firstNameCtrl,
                label: 'First Name *',
                icon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormField(
                controller: _lastNameCtrl,
                label: 'Last Name *',
                icon: Icons.person_outline_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _buildFormField(
          controller: _emailCtrl,
          label: 'USTP Email Address',
          icon: Icons.alternate_email_rounded,
        ),
        const SizedBox(height: 12),

        // Account Active Switch Tile
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account Status',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  Text(
                    'Active accounts can sign in and participate in capstone defenses',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
              Switch(
                value: _isActive,
                activeThumbColor: _maroon,
                onChanged: (val) {
                  setState(() => _isActive = val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Password & Credentials Reset Tile (Edit Mode)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Password & Credentials',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reset password for $displayName to their default ID number ($username).',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _handleResetPassword,
                icon: const Icon(Icons.lock_reset_rounded, size: 14),
                label: const Text('Reset Password'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB45309),
                  side: const BorderSide(color: Color(0xFFFDE68A)),
                  backgroundColor: const Color(0xFFFFFBEB),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),


        const SizedBox(height: 24),

        // Section 2: Edit Academic Enrollment Record
        const Text(
          'ACADEMIC ENROLLMENT STANDING',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: _muted,
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _buildDropdownField<String>(
                label: 'School Year',
                value: _selectedSchoolYear,
                items: widget.schoolYears
                    .map((sy) => DropdownMenuItem<String>(
                          value: sy['label']?.toString(),
                          child: Text(sy['label']?.toString() ?? '',
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedSchoolYear = val;
                    final nextSems = _semestersForYear(val);
                    _selectedSemesterId = nextSems.isNotEmpty
                        ? _asInt(nextSems.first['id'])
                        : null;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDropdownField<int>(
                label: 'Semester',
                value: _selectedSemesterId,
                items: semesters
                    .map((s) => DropdownMenuItem<int>(
                          value: _asInt(s['id']),
                          child: Text(
                            s['display_name'] ?? s['label'] ?? '',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: (val) {
                  setState(() => _selectedSemesterId = val);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildDropdownField<String>(
                label: 'Year Level *',
                value: _selectedYearLevel,
                items: _yearLevels
                    .map((lvl) => DropdownMenuItem<String>(
                          value: lvl,
                          child: Text(lvl, style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedYearLevel = val;
                      final newSections = _getSectionsForYearLevel(val);
                      if (_selectedSection == null ||
                          !newSections.contains(_selectedSection)) {
                        _selectedSection =
                            newSections.isNotEmpty ? newSections.first : null;
                      }
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDropdownField<String>(
                key: ValueKey(
                    'section_dropdown_${_selectedYearLevel}_${sectionOptions.length}_$_selectedSection'),
                label: 'Section *',
                value: currentSectionVal,
                items: [
                  ...sectionOptions.map((sec) => DropdownMenuItem<String>(
                        value: sec,
                        child: Text(sec, style: const TextStyle(fontSize: 13)),
                      )),
                  DropdownMenuItem<String>(
                    value: _addCustomSectionValue,
                    child: const Row(
                      children: [
                        Icon(Icons.add_circle_outline_rounded,
                            size: 15, color: _maroon),
                        SizedBox(width: 6),
                        Text(
                          '+ Add New Section...',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _maroon,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val == _addCustomSectionValue) {
                    _handleAddNewSection(_selectedYearLevel);
                  } else if (val != null) {
                    setState(() => _selectedSection = val);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(fontSize: 13, color: _ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: _muted),
        prefixIcon: icon != null
            ? Icon(icon, size: 16, color: _muted)
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      ),
    );
  }

  Widget _buildDropdownField<T>({
    Key? key,
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      items: items,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: _ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: _muted),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      ),
    );
  }

  // --- Dialog Footer Actions ---
  List<Widget> _buildDialogActions() {
    if (_isEditing) {
      return [
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _isSaving ? null : _handleDeleteStudentAccount,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                tooltip: 'Delete Account',
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  backgroundColor: const Color(0xFFFEF2F2),
                  side: const BorderSide(color: Color(0xFFFECACA)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () {
                            setState(() {
                              _resetEditControllers();
                              _isEditing = false;
                            });
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _muted,
                      side: const BorderSide(color: _line),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _handleSave,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 16),
                    label: Text(_isSaving ? 'Saving...' : 'Save Changes',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _maroon,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ];
    }

    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        style: TextButton.styleFrom(
          foregroundColor: _muted,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        ),
        child: const Text('Close',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      FilledButton.icon(
        onPressed: () {
          setState(() {
            _resetEditControllers();
            _isEditing = true;
          });
        },
        icon: const Icon(Icons.edit_outlined, size: 15),
        label: const Text('Edit Details',
            style: TextStyle(fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: _maroon,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    ];
  }
}
