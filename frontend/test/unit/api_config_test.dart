import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/config/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('local browser hosts connect to Django on port 8000', () {
      for (final host in [
        'localhost',
        '127.0.0.1',
        '::1',
        '[::1]',
        '192.168.1.3',
        '10.0.0.8',
        '172.16.0.5',
        '172.31.255.4',
      ]) {
        expect(ApiConfig.defaultWebApiPortForHost(host), '8000', reason: host);
      }
    });

    test('public browser hosts retain the same-origin production API', () {
      for (final host in [
        'defensys.example.edu',
        '203.0.113.10',
        '172.15.0.5',
        '172.32.0.5',
        '192.169.1.3',
        '192.168.1.300',
        '192.168.example.edu',
      ]) {
        expect(ApiConfig.defaultWebApiPortForHost(host), '', reason: host);
      }
    });

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
      expect(ApiConfig.fallbackLanIp, '192.168.1.236');
    });
  });
}
