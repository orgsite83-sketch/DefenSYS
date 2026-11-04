import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import '../auth/auth_provider.dart';

final eSignatureProvider = Provider<ESignatureService>((ref) {
  return ESignatureService(ref);
});

class ESignatureService {
  final Ref _ref;

  ESignatureService(this._ref);

  AuthenticatedHttpClient get _client =>
      _ref.read(authenticatedHttpClientProvider);

  Future<bool> uploadSignature(Uint8List bytes, String filename) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.userSignatureUrl}/'),
      );

      request.files.add(
        http.MultipartFile.fromBytes('e_signature', bytes, filename: filename),
      );

      final response = await _client.sendAuthenticated(request);
      // Only the status is needed here, but drain the body so the connection
      // and shared in-flight upload guard are released on success and failure.
      await response.stream.drain<void>();
      if (response.statusCode == 200) {
        final auth = _ref.read(authProvider);
        if (auth.token != null) {
          await _ref.read(authProvider.notifier).fetchCurrentUser(auth.token!);
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteSignature() async {
    try {
      final response = await _client.delete(
        Uri.parse('${ApiConfig.userSignatureUrl}/'),
      );
      if (response.statusCode == 200) {
        final auth = _ref.read(authProvider);
        if (auth.token != null) {
          await _ref.read(authProvider.notifier).fetchCurrentUser(auth.token!);
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
