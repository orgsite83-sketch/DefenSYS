import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// User, term, flow and roster context are all part of the key.
class TeamCreationDraftStore {
  TeamCreationDraftStore(String user, String scope)
    : key = 'team_creation_v2_$user:$scope';
  final String key;
  Future<Map<String, dynamic>?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> value) async =>
      (await SharedPreferences.getInstance()).setString(key, jsonEncode(value));
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(key);
}
