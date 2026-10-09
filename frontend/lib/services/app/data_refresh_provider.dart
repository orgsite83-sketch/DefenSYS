import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A successful write marks dependent screens for refresh on their next visit.
/// This retains their filters and drafts and does no work for hidden screens.
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
