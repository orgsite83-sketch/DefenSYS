import 'dart:convert';
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
    final value = (await SharedPreferences.getInstance()).getString(
      'app.workspace.$userId',
    );
    if (value == null || !value.startsWith('{')) return value;
    final data = jsonDecode(value);
    return data is Map && data['version'] == 1
        ? data['location'] as String?
        : null;
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
      jsonEncode({'version': 1, 'location': route}),
    );
    ref.invalidate(workspacePreferenceProvider);
    // Navigation immediately after a switch must see the new choice rather
    // than briefly applying the automatic phone default.
    await ref.read(workspacePreferenceProvider.future);
  } catch (_) {
    /* The workspace stays available without local preferences. */
  }
}
