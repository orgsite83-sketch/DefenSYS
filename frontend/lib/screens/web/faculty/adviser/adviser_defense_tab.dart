import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/adviser_grading_provider.dart';
import '../../../../widgets/defense/team_defense_records.dart';

class AdviserDefenseTab extends ConsumerWidget {
  const AdviserDefenseTab({
    super.key,
    required this.teamId,
    required this.selectedStage,
    this.projectVersion,
    this.semesterId,
    this.adviserName,
    this.readOnly = false,
  });

  final int teamId;
  final String selectedStage;
  final int? projectVersion, semesterId;
  final String? adviserName;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TeamDefenseRecordsView(
    teamId: teamId,
    selectedStage: selectedStage,
    projectVersion: projectVersion,
    semesterId: semesterId,
    adviserName: adviserName,
    grades: ref.watch(adviserGradingProvider).grades,
    allowAdviserReview: !readOnly,
  );
}
