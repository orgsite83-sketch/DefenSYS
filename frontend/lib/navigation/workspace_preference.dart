import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_provider.dart';

final workspacePreferenceProvider = FutureProvider<String?>((ref) async {
  final userId = ref.watch(authProvider.select((state) => state.user?['id']));
  return readRememberedWorkspace(userId);
});

Future<String?> readRememberedWorkspace(dynamic userId) async {
  if (userId == null) return null;
  try {
    return (await SharedPreferences.getInstance()).getString(
      'app.workspace.$userId',
    );
  } catch (_) {
    return null;
  }
}

Future<void> rememberWorkspace(WidgetRef ref, String route) async {
  final id = ref.read(authProvider).user?['id'];
  if (id == null) return;
  try {
    await (await SharedPreferences.getInstance()).setString(
      'app.workspace.$id',
      route,
    );
    ref.invalidate(workspacePreferenceProvider);
  } catch (_) {
    /* The workspace stays available without local preferences. */
  }
}
