import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/utils/clipboard_copy.dart';
import 'package:defensys/widgets/feedback_toast.dart';

/// Modal dialog for requesting guest code payload generation.
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
  late final TextEditingController _guestNameController;
  late final TextEditingController _emailController;
  String? _selectedScheduleId;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _guestNameController = TextEditingController();
    _emailController = TextEditingController();
    if (widget.schedules.isNotEmpty) {
      _selectedScheduleId = widget.schedules.first['id']?.toString();
    }
  }

  @override
  void dispose() {
    _guestNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _onGenerate() {
    final name = _guestNameController.text.trim();
    final scheduleId = int.tryParse(_selectedScheduleId ?? '');

    if (name.isEmpty) {
      setState(() {
        _validationError = 'Guest panelist name is required.';
      });
      return;
    }
    if (scheduleId == null) {
      setState(() {
        _validationError = 'Select a defense schedule first.';
      });
      return;
    }

    Navigator.of(context).pop({
      'guest_name': name,
      if (_emailController.text.trim().isNotEmpty)
        'email': _emailController.text.trim(),
      'defense_schedule': scheduleId,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: DefensysUi.warningBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.key_rounded,
              color: DefensysUi.warningText,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Generate Guest Panelist Code',
                  style: TextStyle(
                    color: DefensysUi.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Create temporary access for an external panelist.',
                  style: TextStyle(
                    color: DefensysUi.warningText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1, color: Color(0xFFF4C57C)),
            const SizedBox(height: 22),
            const Text(
              'Guest Panelist Name',
              style: TextStyle(
                color: Color(0xFF374151),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _guestNameController,
              decoration: const InputDecoration(
                hintText: 'e.g. Engr. Juan Dela Cruz',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Guest Email (optional)',
              style: TextStyle(
                color: Color(0xFF374151),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'guest@example.com',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Assign to Defense Schedule',
              style: TextStyle(
                color: Color(0xFF374151),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.schedules.isEmpty)
              _dialogWarning(
                'No scheduled defenses are available yet. Create a defense schedule before generating a guest code.',
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedScheduleId,
                    hint: const Text('- Select a scheduled defense -'),
                    isExpanded: true,
                    items: widget.schedules.map((schedule) {
                      final id = schedule['id']?.toString() ?? '';
                      final label =
                          schedule['label']?.toString() ?? 'Defense Schedule #$id';
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
            if (_validationError != null) ...[
              const SizedBox(height: 12),
              _dialogWarning(_validationError!),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: widget.schedules.isEmpty ? null : _onGenerate,
          icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
          label: const Text('Generate & Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysUi.warningText,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 13,
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
        color: DefensysUi.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DefensysUi.warningBorder),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: DefensysUi.warningText,
          fontSize: 12.5,
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
    final guestName = guestCode['guest_name']?.toString() ?? 'Guest panelist';
    final schedule =
        guestCode['defense_schedule_label']?.toString() ?? 'Defense schedule';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: DefensysUi.successBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: DefensysUi.successText,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Code Generated Successfully!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DefensysUi.successText,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Share this code with the guest panelist.',
            textAlign: TextAlign.center,
            style: TextStyle(color: DefensysUi.steelGrey, fontSize: 13),
          ),
        ],
      ),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFCBD5E1),
                  style: BorderStyle.solid,
                ),
              ),
              child: SelectableText(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DefensysUi.textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'For: $guestName - Defense: $schedule',
              textAlign: TextAlign.center,
              style: const TextStyle(color: DefensysUi.steelGrey, fontSize: 12.5),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton.icon(
          onPressed: code.isEmpty ? null : () => _copyGuestCode(context, code),
          icon: const Icon(Icons.content_copy_rounded, size: 16),
          label: const Text('Copy Code'),
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysUi.techBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
