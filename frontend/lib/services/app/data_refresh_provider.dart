import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A successful write refreshes the visible dependent section and marks hidden
/// sections for their next visit, retaining filters and drafts.
enum DataArea {
  dashboard,
  academicPeriods,
  users,
  academicRecords,
  teams,
  grades,
  rubrics,
  defenseStages,
  scheduler,
  defenseBoard,
  analytics,
  audit,
  repository,
  deliverables,
  adviserGrades,
  weeklyReports,
  documenter,
}

final dataRefreshProvider =
    NotifierProvider<DataRefreshNotifier, Map<DataArea, int>>(
      DataRefreshNotifier.new,
    );

class DataRefreshNotifier extends Notifier<Map<DataArea, int>> {
  @override
  Map<DataArea, int> build() => const {};

  void markChanged(Iterable<DataArea> areas) {
    final next = Map<DataArea, int>.from(state);
    for (final area in areas.toSet()) {
      next[area] = (next[area] ?? 0) + 1;
    }
    state = next;
  }
}
