import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Human feedback from one hearing, separate from next-attempt preparation.
class PanelRecommendations extends StatelessWidget {
  const PanelRecommendations({
    super.key,
    this.notes = '',
    this.concepts = const [],
  });

  final String notes;
  final List<Map<String, dynamic>> concepts;

  factory PanelRecommendations.fromStage(Map<String, dynamic> stage) {
    final workflow = stage['concept_workflow'] as Map? ?? const {};
    final grade = stage['grade'] as Map? ?? const {};
    final schedule = stage['schedule'] as Map? ?? const {};
    final history =
        (workflow['history'] ?? stage['hearing_history']) as List? ?? [];
    final rounds = history.whereType<Map>().toList()
      ..sort(
        (a, b) => (int.tryParse('${b['round']}') ?? 0).compareTo(
          int.tryParse('${a['round']}') ?? 0,
        ),
      );
    final scheduleId =
        schedule['id'] ?? schedule['schedule_id'] ?? grade['schedule_id'];
    final round = scheduleId == null
        ? rounds.firstOrNull
        : rounds
              .where((row) => '${row['schedule_id']}' == '$scheduleId')
              .firstOrNull;
    final gradeMatches =
        scheduleId == null ||
        grade['schedule_id'] == null ||
        '${grade['schedule_id']}' == '$scheduleId';
    return PanelRecommendations(
      notes:
          '${(gradeMatches ? grade['verdict_remarks'] : null) ?? round?['remarks'] ?? ''}',
      concepts: (round?['concepts'] as List? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final general = notes.trim();
    final specific = concepts.where((concept) {
      final feedback = '${concept['remarks'] ?? ''}'.trim();
      return feedback.isNotEmpty && feedback != general;
    }).toList();
    if (general.isEmpty && specific.isEmpty) return const SizedBox.shrink();
    final body = TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 13,
      height: 1.45,
      color: DefensysTokens.textSecondaryOf(context),
    );
    return DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Panel recommendations',
              style: body.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (general.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(general, style: body),
            ],
            for (var i = 0; i < specific.length; i++) ...[
              const SizedBox(height: 12),
              Text(
                '${specific[i]['title'] ?? ''}'.trim().isEmpty
                    ? 'Concept ${i + 1}'
                    : '${specific[i]['title']}',
                style: body.copyWith(
                  color: DefensysTokens.textPrimaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text('${specific[i]['remarks']}'.trim(), style: body),
            ],
          ],
        ),
      ),
    );
  }
}
