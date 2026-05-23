import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

/// Thin client for mobile-only flows that are not covered by Riverpod providers.
class BridgeService {
  static Future<Map<String, String>?> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) {
      return null;
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Validates a guest panelist code (e.g. "DEF-A8X2K3") against the Django API.
  static Future<Map<String, dynamic>?> validateGuestCode(String code) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/users/guest-codes/validate/$code'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[Bridge] Could not validate guest code. $e');
    }
    return null;
  }

  /// Submits a locked peer evaluation for one teammate.
  static Future<bool> submitPeerGrade({
    required String teamId,
    required String evaluatorId,
    required String evaluateeName,
    required List<Map<String, dynamic>> breakdown,
    required double total,
    required double max,
  }) async {
    final headers = await _authHeaders();
    if (headers == null) {
      debugPrint('[Bridge] No JWT token for peer evaluation submit.');
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.gradeCenterUrl}/peer-evaluations/'),
            headers: headers,
            body: json.encode({
              'teamId': int.tryParse(teamId) ?? teamId,
              'evaluateeName': evaluateeName,
              'breakdown': breakdown,
              'total': total,
              'max': max,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        return true;
      }
      debugPrint('[Bridge] Peer evaluation failed: ${response.statusCode} ${response.body}');
    } catch (e) {
      debugPrint('[Bridge] Could not submit peer grade. $e');
    }
    return false;
  }
}
