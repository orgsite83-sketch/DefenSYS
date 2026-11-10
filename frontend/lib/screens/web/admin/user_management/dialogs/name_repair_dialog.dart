import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/admin/user_management_provider.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

bool accountNameNeedsRepair(Map user) => RegExp(
  '[\ufffd\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]|\u00c3[\u0080-\u00bf\u2018\u2019\u201c\u201d]',
).hasMatch('${user['first_name'] ?? ''} ${user['last_name'] ?? ''}');

Future<bool?> showNameRepairDialog(
  BuildContext context,
  Map<String, dynamic> user,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => NameRepairDialog(user: user),
);

class NameRepairDialog extends ConsumerStatefulWidget {
  const NameRepairDialog({super.key, required this.user});
  final Map<String, dynamic> user;
  @override
  ConsumerState<NameRepairDialog> createState() => _NameRepairDialogState();
}

class _NameRepairDialogState extends ConsumerState<NameRepairDialog> {
  late final first = TextEditingController(
    text: '${widget.user['first_name'] ?? ''}',
  );
  late final last = TextEditingController(
    text: '${widget.user['last_name'] ?? ''}',
  );
  final source = TextEditingController();
  Map<String, dynamic>? review;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    first.dispose();
    last.dispose();
    source.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final service = ref.read(userManagementProvider.notifier);
      if (review == null) {
        final result = await service.previewNameRepair({
          'username': '${widget.user['username']}',
          'expected_role': '${widget.user['role']}',
          'first_name': first.text.trim(),
          'last_name': last.text.trim(),
          'source_filename': source.text.trim(),
        });
        if (mounted) setState(() => review = result);
      } else {
        await service.applyNameRepair('${review!['preview_token']}');
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e'.replaceFirst('Exception: ', '');
          review = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    maroonActions: true,
    child: ShadDialog(
      actionsAxis: Axis.vertical,
      constraints: const BoxConstraints(maxWidth: 540),
      title: const Text('Repair account name'),
      description: Text('Registered ID: ${widget.user['username']}'),
      actions: [
        ShadButton.outline(
          enabled: !busy,
          onPressed: () => review == null
              ? Navigator.pop(context, false)
              : setState(() => review = null),
          child: Text(review == null ? 'Cancel' : 'Back'),
        ),
        ShadButton(
          height: 0,
          enabled: !busy,
          onPressed: submit,
          child: Flexible(
            child: Text(
              busy
                  ? 'Please wait…'
                  : review == null
                  ? 'Review name repair'
                  : 'Apply reviewed name repair',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (review == null) ...[
            const Text(
              'Enter the spelling from an intact official source. This action changes name fields only.',
            ),
            const SizedBox(height: 12),
            ShadInput(
              controller: first,
              placeholder: const Text('First and middle names'),
            ),
            const SizedBox(height: 10),
            ShadInput(controller: last, placeholder: const Text('Surname')),
            const SizedBox(height: 10),
            ShadInput(
              controller: source,
              placeholder: const Text('Official source filename or reference'),
            ),
          ] else ...[
            Text('Source: ${review!['source_filename']}'),
            const SizedBox(height: 12),
            Text(
              'Before: ${review!['before']['first_name']} ${review!['before']['last_name']}',
            ),
            const SizedBox(height: 10),
            Text(
              'After: ${review!['after']['first_name']} ${review!['after']['last_name']}',
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!),
            ),
        ],
      ),
    ),
  );
}
