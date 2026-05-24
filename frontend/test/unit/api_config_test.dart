import 'package:flutter_test/flutter_test.dart';
import 'package:user/config/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('baseUrl includes api path and port', () {
      expect(ApiConfig.baseUrl, contains('/api'));
      expect(ApiConfig.baseUrl, contains(ApiConfig.basePort));
    });

    test('teamsUrl is under baseUrl', () {
      expect(ApiConfig.teamsUrl, startsWith(ApiConfig.baseUrl));
      expect(ApiConfig.teamsUrl, endsWith('/teams'));
    });

    test('getAllPossibleUrls returns one entry per server IP', () {
      final urls = ApiConfig.getAllPossibleUrls();

      expect(urls.length, ApiConfig.serverIps.length);
      expect(urls.first, contains('http://'));
    });

    test('serverIps defaults to localhost only', () {
      expect(ApiConfig.serverIps, ['127.0.0.1']);
      expect(ApiConfig.fallbackLanIp, '127.0.0.1');
    });
  });
}
