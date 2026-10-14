import 'dart:convert';

import 'package:defensys/services/network/authenticated_client.dart';
import 'package:http/http.dart' as http;

class FakePlannerClient implements AuthenticatedHttpClient {
  FakePlannerClient([this.sessions = const []]);

  final List<Map<String, dynamic>> sessions;
  final List<Uri> requested = [];

  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    requested.add(uri);
    return http.Response(jsonEncode({'sessions': sessions}), 200);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
