import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user/services/api_http.dart';

import 'fake_responses.dart';

/// Registers a [MockClient] for API provider tests. Call [resetApiHttpClientForTesting] in tearDown.
void installDefaultMockHttp() {
  setApiHttpClientForTesting(
    MockClient(_defaultHandler),
  );
}

Future<http.Response> _defaultHandler(http.Request request) async {
  final path = request.url.path;
  final method = request.method;

  if (path.endsWith('/login/') && method == 'POST') {
    return http.Response(loginSuccessJson, 200);
  }

  if (path.endsWith('/token/refresh/') && method == 'POST') {
    return http.Response(
      '{"access": "test-jwt-token-refreshed", "refresh": "test-refresh-token-rotated"}',
      200,
    );
  }

  if (path.endsWith('/me/') && method == 'GET') {
    return http.Response(
      '{"id": 1, "username": "admin", "role": "admin", "name": "Admin User", "facultyRoles": {}}',
      200,
    );
  }

  if (path.endsWith('/logout/') && method == 'POST') {
    return http.Response('{}', 200);
  }

  if (path.endsWith('/dashboards/admin/') && method == 'GET') {
    return http.Response(dashboardAdminJson, 200);
  }

  if (path.contains('/repository/deliverables') && method == 'GET') {
    return http.Response(deliverablesJson, 200);
  }

  if (path.contains('/weekly-progress') && method == 'GET') {
    return http.Response(weeklyProgressJson, 200);
  }

  if (path.contains('/teams/documents') && method == 'GET') {
    return http.Response(jsonEncode({'documents': [], 'count': 0}), 200);
  }

  if (path.contains('/adviser-history') && method == 'GET') {
    return http.Response(jsonEncode({'assignments': []}), 200);
  }

  final teamDetailMatch = RegExp(r'/teams/(\d+)/?$').firstMatch(path);
  if (teamDetailMatch != null && method == 'GET') {
    return http.Response(teamDetailJson, 200);
  }

  if (path.endsWith('/teams') || path.endsWith('/teams/')) {
    if (method == 'GET') {
      return http.Response(teamsListJson, 200);
    }
  }

  return http.Response(
    jsonEncode({'detail': 'Not found in mock: $method $path'}),
    404,
  );
}
