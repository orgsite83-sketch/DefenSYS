import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// BridgeService — Connects the Flutter app to the Python mock_server.py
///
/// This service talks to http://localhost:8080 (or 10.0.2.2:8080 on Android
/// emulator) to fetch user role data that the Admin assigned via the Web UI.
class BridgeService {
  // Web/Chrome uses localhost directly.
  // Android emulator uses 10.0.2.2 to reach localhost on the host machine.
  static String get _baseUrl {
    // Flutter web is served from mock_server.py at /app/ — same origin, no CORS issues
    if (kIsWeb) return '';
    return 'http://10.0.2.2:8080';
  }

  // Public accessor for other services
  static String get baseUrl => _baseUrl;

  /// Fetches a user profile from the Python bridge server.
  /// Returns a Map with user data including facultyRoles, or null if unreachable.
  static Future<Map<String, dynamic>?> fetchUserRole(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/users/$userId'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        debugPrint('[Bridge] Fetched role for $userId: ${data['role']}');
        return data;
      }
    } catch (e) {
      debugPrint('[Bridge] Server not reachable, using local accounts. $e');
    }
    return null;
  }

  /// Derives the DefenSYS role string from a server user profile.
  /// Returns 'Student', 'Panelist', 'DevPanelist', or 'Faculty'.
  static String deriveRole(Map<String, dynamic> serverUser) {
    final baseRole = serverUser['role'] as String? ?? '';
    final fr = serverUser['facultyRoles'] as Map<String, dynamic>?;

    if (baseRole == 'student') return 'Student';

    if (fr != null) {
      // If they have panelist access, route to panelist UI
      if (fr['panelist'] == true) return 'Panelist';
      // PIT Lead and Adviser also get panelist-style grading on mobile
      if (fr['pitLead'] == true) return 'DevPanelist';
      if (fr['adviser'] == true) return 'Panelist';
    }

    return 'Student'; // fallback
  }

  /// Validates a guest panelist code (e.g. "DEF-A8X2K3") against the Django API.
  /// Returns the guest data (including guestName) if valid, or null if invalid/expired.
  static Future<Map<String, dynamic>?> validateGuestCode(String code) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/users/guest-codes/validate/$code'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        debugPrint('[Bridge] Guest code valid: ${data['guestName']}');
        return data;
      } else {
        debugPrint('[Bridge] Guest code validation failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[Bridge] Could not validate guest code. $e');
    }
    return null;
  }

  /// Fetches the real team assignments for a panelist from the bridge server.
  /// Returns a list of assignment maps with team info, members, criteria, etc.
  static Future<List<Map<String, dynamic>>> fetchPanelistAssignments(String panelistId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/panelist-assignments/$panelistId'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        debugPrint('[Bridge] Fetched ${data.length} assignments for panelist $panelistId');
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[Bridge] Could not fetch assignments. $e');
    }
    return [];
  }

  /// Fetches student's team, schedule, grades and members from the bridge server.
  static Future<Map<String, dynamic>?> fetchStudentData(String studentId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/student-data/$studentId'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[Bridge] Could not fetch student data. $e');
    }
    return null;
  }

  /// Submits panelist grades for a team back to the bridge server.
  static Future<bool> submitGrades({
    required String teamId,
    required String panelistId,
    required List<Map<String, dynamic>> breakdown,
    required double total,
    required double max,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/submit-grades'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'teamId': teamId,
              'panelistId': panelistId,
              'breakdown': breakdown,
              'total': total,
              'max': max,
              'status': 'published',
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        debugPrint('[Bridge] Grades submitted for $teamId');
        return true;
      }
    } catch (e) {
      debugPrint('[Bridge] Could not submit grades. $e');
    }
    return false;
  }

  /// Fetches panel results for all teams this panelist graded.
  static Future<List<Map<String, dynamic>>> fetchPanelResults(String panelistId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/panel-results/$panelistId'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[Bridge] Could not fetch panel results. $e');
    }
    return [];
  }

  static Future<bool> submitPeerGrade({
    required String teamId,
    required String evaluatorId,
    required String evaluateeName,
    required List<Map<String, dynamic>> breakdown,
    required double total,
    required double max,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/submit-peer-grade'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'teamId': teamId,
              'evaluatorId': evaluatorId,
              'evaluateeName': evaluateeName,
              'breakdown': breakdown,
              'total': total,
              'max': max,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Bridge] Could not submit peer grade. $e');
    }
    return false;
  }
}
