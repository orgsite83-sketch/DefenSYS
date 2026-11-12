import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

String scheduleDutyLabel(String duty) => duty.startsWith('panel_')
    ? 'panel member ${int.parse(duty.split('_').last) + 1}'
    : duty;

Future<String?> showScheduleFacultyDuty(
  BuildContext context,
  Map<String, String> fields,
) => showDialog<String>(
  context: context,
  builder: (context) => DefensysShadcnScope(
    maroonActions: true,
    child: ShadDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: const Text('Review faculty'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in fields.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ShadButton.outline(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Flexible(
                  child: Text(
                    '${scheduleDutyLabel(entry.key)}: ${entry.value}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  ),
);

Future<({int id, bool equivalent})?> showScheduleFacultyReview(
  BuildContext context, {
  required String original,
  required String reason,
  required String duty,
  required List<Map<String, dynamic>> accounts,
  required int equivalentCount,
}) => showDialog<({int id, bool equivalent})>(
  context: context,
  builder: (dialogContext) => _FacultyReview(
    original: original,
    reason: reason,
    duty: duty,
    accounts: accounts,
    equivalentCount: equivalentCount,
  ),
);

class _FacultyReview extends StatefulWidget {
  const _FacultyReview({
    required this.original,
    required this.reason,
    required this.duty,
    required this.accounts,
    required this.equivalentCount,
  });
  final String original, reason, duty;
  final List<Map<String, dynamic>> accounts;
  final int equivalentCount;
  @override
  State<_FacultyReview> createState() => _FacultyReviewState();
}

class _FacultyReviewState extends State<_FacultyReview> {
  String search = '';
  bool equivalent = false;
  @override
  Widget build(BuildContext context) {
    final visible = widget.accounts
        .where(
          (a) => '${a['name']} ${a['username']}'.toLowerCase().contains(
            search.toLowerCase(),
          ),
        )
        .toList();
    return DefensysShadcnScope(
      maroonActions: true,
      neutralActionText: true,
      child: ShadDialog(
        constraints: const BoxConstraints(maxWidth: 520),
        title: Text('Select ${scheduleDutyLabel(widget.duty)} account'),
        description: Text('Uploaded: ${widget.original}\n${widget.reason}'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(
                placeholder: const Text('Search registered name or ID'),
                onChanged: (value) => setState(() => search = value),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: (visible.length * 44.0).clamp(64.0, 240.0),
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching account. Verify the official ID or ask an admin.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final account = visible[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ShadButton.ghost(
                              mainAxisAlignment: MainAxisAlignment.start,
                              onPressed: () => Navigator.pop(context, (
                                id: (account['id'] as num).toInt(),
                                equivalent: equivalent,
                              )),
                              child: Expanded(
                                child: Text(
                                  '${account['name']} · ${account['username']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (widget.equivalentCount > 1)
                ShadCheckbox(
                  value: equivalent,
                  onChanged: (value) => setState(() => equivalent = value),
                  label: Text(
                    'Apply to ${widget.equivalentCount} equivalent ${scheduleDutyLabel(widget.duty)} references',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
