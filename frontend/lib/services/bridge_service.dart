import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';
import 'session_expired.dart';

/// Thin client for mobile-only flows that are not covered by Riverpod providers.
class BridgeService {
  /// Exchanges a guest code for a short-lived access JWT and user payload.
  static Future<Map<String, dynamic>?> exchangeGuestCode(String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/users/guest-codes/exchange/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'code': code.trim().toUpperCase()}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Bridge] Could not exchange guest code. $e');
      }
    }
    return null;
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
      if (kDebugMode) {
        debugPrint('[Bridge] Could not validate guest code. $e');
      }
    }
    return null;
  }

  /// Submits a locked peer evaluation for one teammate.
  static Future<bool> submitPeerGrade({
    required AuthenticatedHttpClient httpClient,
    required String teamId,
    required String evaluatorId,
    required String evaluateeName,
    required List<Map<String, dynamic>> breakdown,
    required double total,
    required double max,
  }) async {
    try {
      final response = await httpClient.post(
        Uri.parse('${ApiConfig.gradeCenterUrl}/peer-evaluations/'),
        body: json.encode({
          'teamId': int.tryParse(teamId) ?? teamId,
          'evaluateeName': evaluateeName,
          'breakdown': breakdown,
          'total': total,
          'max': max,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      }
      if (kDebugMode) {
        debugPrint(
          '[Bridge] Peer evaluation failed: ${response.statusCode} ${response.body}',
        );
      }
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Bridge] Could not submit peer grade. $e');
      }
    }
    return false;
  }
}
