import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';

List<Map<String, dynamic>> sectionInstructorsForTeam(
  Map<String, dynamic> team,
) {
  final instructors = (team['instructors'] as List? ?? [])
      .whereType<Map>()
      .map((i) => Map<String, dynamic>.from(i))
      .toList();
  if (instructors.isNotEmpty) return instructors;
  final name = team['instructor_name']?.toString().trim() ?? '';
  return name.isEmpty
      ? []
      : [
          {
            'faculty_name': name,
            'section': team['section'],
            'year_level': team['year_level'],
            'semester_label': team['display_semester'] ?? team['semester'],
          },
        ];
}

Future<void> showSectionInstructorDetails(
  BuildContext context,
  List<Map<String, dynamic>> instructors,
) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close instructor details',
  barrierColor: Colors.black.withValues(alpha: 0.3),
  transitionDuration: const Duration(milliseconds: 200),
  transitionBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  ),
  pageBuilder: (context, _, _) => Align(
    alignment: Alignment.centerRight,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: 440,
        height: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Instructor details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close instructor details',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      if (instructors.isEmpty)
                        const Text('No instructor assigned.'),
                      for (final instructor in instructors) ...[
                        Text(
                          '${instructor['faculty_name']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        for (final (label, key) in [
                          ('Email', 'faculty_email'),
                          ('ID number', 'faculty_username'),
                          ('Section', 'section'),
                          ('Year level', 'year_level'),
                          ('Academic term', 'semester_label'),
                        ]) ...[
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 5),
                          SelectableText(
                            '${instructor[key] ?? '—'}'.isEmpty
                                ? '—'
                                : '${instructor[key] ?? '—'}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 18),
                        ],
                        Divider(color: DefensysTokens.borderOf(context)),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
