import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth_provider.dart';
import '../app/data_refresh_provider.dart';
import 'team_formation_service.dart';

/// One task snapshot for Team setup and Integration's project-manager badge.
final studentTeamTasksProvider = FutureProvider<Map<String, dynamic>>((ref) {
  final identity = ref.watch(
    authProvider.select((s) => (s.user?['id'], s.user?['role'])),
  );
  ref.watch(
    dataRefreshProvider.select(
      (s) => (s[DataArea.dashboard], s[DataArea.teams]),
    ),
  );
  if (identity.$2 != 'student') return Future.value(const {});
  return ref.watch(teamFormationServiceProvider).setupTasks();
});
