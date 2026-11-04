import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import '../updates/update_activity.dart';

http.Client _apiHttpClient = _ActivityClient(http.Client());

class _ActivityClient extends http.BaseClient {
  _ActivityClient(this.inner);
  final http.Client inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final writing = ![
      'GET',
      'HEAD',
      'OPTIONS',
    ].contains(request.method.toUpperCase());
    if (!writing) return inner.send(request);
    apiWriteActivity.value++;
    try {
      final response = await inner.send(request);
      Stream<List<int>> tracked() async* {
        try {
          yield* response.stream;
        } finally {
          apiWriteActivity.value--;
        }
      }

      return http.StreamedResponse(
        tracked(),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      apiWriteActivity.value--;
      rethrow;
    }
  }

  @override
  void close() => inner.close();
}

/// Shared HTTP client for API providers (replaceable in tests).
http.Client get apiHttpClient => _apiHttpClient;

@visibleForTesting
void setApiHttpClientForTesting(http.Client client) {
  _apiHttpClient = _ActivityClient(client);
}

@visibleForTesting
void resetApiHttpClientForTesting() {
  _apiHttpClient = _ActivityClient(http.Client());
}
