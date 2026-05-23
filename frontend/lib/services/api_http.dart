import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

http.Client _apiHttpClient = http.Client();

/// Shared HTTP client for API providers (replaceable in tests).
http.Client get apiHttpClient => _apiHttpClient;

@visibleForTesting
void setApiHttpClientForTesting(http.Client client) {
  _apiHttpClient = client;
}

@visibleForTesting
void resetApiHttpClientForTesting() {
  _apiHttpClient = http.Client();
}
