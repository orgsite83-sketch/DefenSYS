import 'package:flutter/material.dart';
import 'package:defensys/services/academic/team_formation_service.dart';

Future<bool?> reviewCurrentRoster(
  BuildContext context,
  TeamFormationService service,
  String year,
  String section,
) async {
  final data = await service.currentRoster(year, section);
  if (!context.mounted) return false;
  final selected = Set<int>.from(data['roster']?['team_ids'] ?? []);
  final teams = (data['teams'] as List)
      .map((t) => Map<String, dynamic>.from(t))
      .toList();
  var saving = false;
  String? error;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Current roster · $section'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose this section’s current teams. Unstarted events follow this roster automatically. Existing event work keeps its saved membership.',
                ),
                const SizedBox(height: 16),
                for (final team in teams)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(team['id']),
                    title: Text('${team['name']}'),
                    subtitle: Text(
                      '${(team['members'] as List).length} members · ${team['event_name'] ?? 'Current roster'}',
                    ),
                    onChanged: saving
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              selected.add(team['id']);
                            } else {
                              selected.remove(team['id']);
                            }
                          }),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving || selected.isEmpty
                ? null
                : () async {
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await service.selectCurrentRoster({
                        'year_level': year,
                        'section': section,
                        'revision': data['roster']?['revision'],
                        'team_ids': selected.toList(),
                      });
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        setState(() {
                          saving = false;
                          error = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Save current roster'),
          ),
        ],
      ),
    ),
  );
}
