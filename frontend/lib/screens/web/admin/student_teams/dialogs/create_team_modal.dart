import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'team_creation_dialog.dart';
import 'package:defensys/services/academic/team_formation_service.dart';

Future<void> showCreateTeamModal({
  required BuildContext context,
  required WidgetRef ref,
  required StudentTeamsState state,
  required bool isCapstoneAdmin,
  required bool isPitLeadManager,
  required String? pitLeadYear,
  VoidCallback? onBulkImport,
}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create teams'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Create manually'),
              subtitle: const Text('Choose members and a leader for one team.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            if (onBulkImport != null) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Bulk import'),
                subtitle: const Text(
                  'Import prepared team rosters and existing project information.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, 'import'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (choice == 'import') {
    onBulkImport?.call();
    return;
  }
  if (choice == 'manual') {
    await showManualCreateTeamModal(
      context: context,
      ref: ref,
      state: state,
      isCapstoneAdmin: isCapstoneAdmin,
      isPitLeadManager: isPitLeadManager,
      pitLeadYear: pitLeadYear,
    );
  }
}

Future<void> showManualCreateTeamModal({
  required BuildContext context,
  required WidgetRef ref,
  required StudentTeamsState state,
  required bool isCapstoneAdmin,
  required bool isPitLeadManager,
  required String? pitLeadYear,
}) async {
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DefensysShadcnScope(
      maroonActions: true,
      child: TeamCreationDialog(
        data: state,
        isPitLead: isPitLeadManager,
        isCapstoneAdmin: isCapstoneAdmin,
        pitLeadYear: pitLeadYear,
        loadRoster: (level, event) async {
          final data = await ref
              .read(teamFormationServiceProvider)
              .rosterOptions(level, event);
          return (data['students'] as List)
              .where((s) => s['eligible'] == true)
              .map((s) => Map<String, dynamic>.from(s as Map))
              .toList();
        },
        save: (payload) async {
          final ok = await ref
              .read(studentTeamsProvider.notifier)
              .addTeam(payload);
          return ok
              ? null
              : ref.read(studentTeamsProvider).error ??
                    'Could not add this team.';
        },
      ),
    ),
  );
}
