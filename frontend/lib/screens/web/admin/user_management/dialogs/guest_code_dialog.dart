import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/utils/clipboard_copy.dart';
import 'package:defensys/toasts/feedback_toast.dart';

/// Helper model for parsing and formatting rich guest panelist credentials.
class GuestPanelistInfo {
  final String displayName;
  final String? affiliation;
  final String initials;

  const GuestPanelistInfo({
    required this.displayName,
    this.affiliation,
    required this.initials,
  });

  static GuestPanelistInfo parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const GuestPanelistInfo(
        displayName: 'Guest Panelist',
        initials: 'GP',
      );
    }

    String namePart = trimmed;
    String? affiliationPart;

    final parenMatch = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(trimmed);
    if (parenMatch != null) {
      namePart = parenMatch.group(1)?.trim() ?? trimmed;
      affiliationPart = parenMatch.group(2)?.trim();
    }

    final cleanWords = namePart
        .replaceAll(
          RegExp(
            r'^(Engr\.|Dr\.|Prof\.|Arch\.|Atty\.|Mr\.|Ms\.|Hon\.)\s*',
            caseSensitive: false,
          ),
          '',
        )
        .split(RegExp(r'[, ]+'))
        .where((w) => w.isNotEmpty && !w.contains('.'))
        .toList();

    String initials = 'GP';
    if (cleanWords.length >= 2) {
      initials = '${cleanWords.first[0]}${cleanWords.last[0]}'.toUpperCase();
    } else if (cleanWords.isNotEmpty && cleanWords.first.isNotEmpty) {
      initials = cleanWords.first
          .substring(0, cleanWords.first.length.clamp(1, 2))
          .toUpperCase();
    }

    return GuestPanelistInfo(
      displayName: namePart,
      affiliation: affiliationPart,
      initials: initials,
    );
  }

  static String formatPayload({
    String? prefix,
    required String fullName,
    String? degreeSuffix,
    String? institution,
    String? almaMater,
  }) {
    final nameParts = <String>[];
    if (prefix != null && prefix.trim().isNotEmpty && prefix != 'None') {
      nameParts.add(prefix.trim());
    }
    nameParts.add(fullName.trim());
    var result = nameParts.join(' ');
    if (degreeSuffix != null && degreeSuffix.trim().isNotEmpty) {
      result = '$result, ${degreeSuffix.trim()}';
    }

    final metaParts = <String>[];
    if (institution != null && institution.trim().isNotEmpty) {
      metaParts.add(institution.trim());
    }
    if (almaMater != null && almaMater.trim().isNotEmpty) {
      metaParts.add('Alma Mater: ${almaMater.trim()}');
    }

    if (metaParts.isNotEmpty) {
      result = '$result (${metaParts.join(' · ')})';
    }
    return result;
  }
}

/// Modal dialog for generating a guest evaluator access code with verified academic credentials.
class GuestCodeGenerateDialog extends StatefulWidget {
  const GuestCodeGenerateDialog({
    super.key,
    required this.schedules,
  });

  final List<Map<String, dynamic>> schedules;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> schedules,
  }) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) => GuestCodeGenerateDialog(schedules: schedules),
    );
  }

  @override
  State<GuestCodeGenerateDialog> createState() =>
      _GuestCodeGenerateDialogState();
}

class _GuestCodeGenerateDialogState extends State<GuestCodeGenerateDialog> {
  static const _titles = ['Engr.', 'Dr.', 'Prof.', 'Arch.', 'Atty.', 'Mr.', 'Ms.', 'None'];

  String _selectedTitle = 'Engr.';
  late final TextEditingController _fullNameController;
  late final TextEditingController _degreeSuffixController;
  late final TextEditingController _institutionController;
  late final TextEditingController _almaMaterController;
  late final TextEditingController _emailController;

  String? _selectedScheduleId;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController();
    _degreeSuffixController = TextEditingController();
    _institutionController = TextEditingController();
    _almaMaterController = TextEditingController();
    _emailController = TextEditingController();

    if (widget.schedules.isNotEmpty) {
      _selectedScheduleId = widget.schedules.first['id']?.toString();
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _degreeSuffixController.dispose();
    _institutionController.dispose();
    _almaMaterController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String get _computedFormattedName {
    final name = _fullNameController.text.trim();
    if (name.isEmpty) return 'Guest Panelist';
    return GuestPanelistInfo.formatPayload(
      prefix: _selectedTitle,
      fullName: name,
      degreeSuffix: _degreeSuffixController.text.trim(),
      institution: _institutionController.text.trim(),
      almaMater: _almaMaterController.text.trim(),
    );
  }

  String get _selectedScheduleLabel {
    if (_selectedScheduleId == null) return 'No schedule selected';
    try {
      final schedule = widget.schedules.firstWhere(
        (s) => s['id']?.toString() == _selectedScheduleId,
      );
      return schedule['label']?.toString() ?? 'Defense Schedule #$_selectedScheduleId';
    } catch (_) {
      return 'Defense Schedule #$_selectedScheduleId';
    }
  }

  void _onGenerate() {
    final name = _fullNameController.text.trim();
    final scheduleId = int.tryParse(_selectedScheduleId ?? '');

    if (name.isEmpty) {
      setState(() {
        _validationError = 'Please enter the guest panelist full name.';
      });
      return;
    }
    if (scheduleId == null) {
      setState(() {
        _validationError = 'Please select a defense schedule for this panelist.';
      });
      return;
    }

    final formattedName = GuestPanelistInfo.formatPayload(
      prefix: _selectedTitle,
      fullName: name,
      degreeSuffix: _degreeSuffixController.text.trim(),
      institution: _institutionController.text.trim(),
      almaMater: _almaMaterController.text.trim(),
    );

    Navigator.of(context).pop({
      'guest_name': formattedName,
      if (_emailController.text.trim().isNotEmpty)
        'email': _emailController.text.trim(),
      'defense_schedule': scheduleId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = GuestPanelistInfo.parse(_computedFormattedName);

    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Color(0xFFB45309),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Generate Guest Panelist Pass',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Create temporary evaluation access with academic credentials',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 18),

              // Title / Honorific Selector
              const Text(
                'HONORIFIC / TITLE',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _titles.map((title) {
                  final isSelected = _selectedTitle == title;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedTitle = title;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFB45309) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFB45309) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected ? Colors.white : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Full Name & Degree Suffix Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FULL NAME (REQUIRED)',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _fullNameController,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: 'e.g. Juan Dela Cruz',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DEGREE SUFFIX (OPTIONAL)',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _degreeSuffixController,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'e.g. M.S.IT, PECE',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Current Institution / Workplace
              const Text(
                'CURRENT INSTITUTION / WORKPLACE (OPTIONAL)',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _institutionController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. DOST Region X / Xavier University - Ateneo',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Alma Mater / Educational Background
              const Text(
                'ALMA MATER / EDUCATIONAL BACKGROUND (OPTIONAL)',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _almaMaterController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. M.S. UP Diliman (USTP Alumnus)',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Guest Email & Schedule Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PANELIST EMAIL (OPTIONAL)',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'guest@example.com',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ASSIGN DEFENSE SCHEDULE',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (widget.schedules.isEmpty)
                          _dialogWarning('No scheduled defenses available.')
                        else
                          Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedScheduleId,
                                hint: const Text('- Select Schedule -', style: TextStyle(fontSize: 12.5)),
                                isExpanded: true,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF0F172A),
                                  fontFamily: DefensysUi.fontFamily,
                                ),
                                items: widget.schedules.map((schedule) {
                                  final id = schedule['id']?.toString() ?? '';
                                  final label = schedule['label']?.toString() ?? 'Schedule #$id';
                                  return DropdownMenuItem(
                                    value: id,
                                    child: Text(label, overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedScheduleId = value;
                                    _validationError = null;
                                  });
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Live Evaluator Badge Preview Card
              const Text(
                'LIVE EVALUATOR ACCESS PASS PREVIEW',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Center(
                        child: Text(
                          info.initials,
                          style: const TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  info.displayName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: const Color(0xFFA7F3D0)),
                                ),
                                child: const Text(
                                  'Guest Panelist',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF047857),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            info.affiliation != null && info.affiliation!.isNotEmpty
                                ? info.affiliation!
                                : 'External Evaluator',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Scope: $_selectedScheduleLabel',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_validationError != null) ...[
                const SizedBox(height: 12),
                _dialogWarning(_validationError!),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
        ),
        ElevatedButton.icon(
          onPressed: widget.schedules.isEmpty ? null : _onGenerate,
          icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
          label: const Text('Generate & Save Pass'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFB45309),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dialogWarning(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB45309),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Modal dialog for displaying a generated guest code to the user.
class GeneratedGuestCodeDialog extends StatelessWidget {
  const GeneratedGuestCodeDialog({
    super.key,
    required this.guestCode,
  });

  final Map<String, dynamic> guestCode;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> guestCode,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => GeneratedGuestCodeDialog(guestCode: guestCode),
    );
  }

  Future<void> _copyGuestCode(BuildContext context, String code) async {
    final copied = await copyTextToClipboard(code);
    if (copied && context.mounted) {
      showSuccessToast(
        context,
        'Guest panelist code copied to clipboard!',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = guestCode['code']?.toString() ?? '';
    final rawName = guestCode['guest_name']?.toString() ?? 'Guest panelist';
    final info = GuestPanelistInfo.parse(rawName);
    final schedule =
        guestCode['defense_schedule_label']?.toString() ?? 'Defense schedule';

    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      title: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF047857),
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Guest Pass Generated!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Share this access token with the external panelist.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Code Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Column(
                children: [
                  const Text(
                    'TEMPORARY ACCESS CODE',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Evaluator Summary Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        info.initials,
                        style: const TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (info.affiliation != null && info.affiliation!.isNotEmpty)
                          Text(
                            info.affiliation!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          schedule,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton.icon(
          onPressed: code.isEmpty ? null : () => _copyGuestCode(context, code),
          icon: const Icon(Icons.content_copy_rounded, size: 16),
          label: const Text('Copy Access Code'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF334155),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
