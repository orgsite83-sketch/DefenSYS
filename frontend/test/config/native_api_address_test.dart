import 'package:defensys/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const host = String.fromEnvironment('DEFENSYS_API_HOST');
  const port = String.fromEnvironment(
    'DEFENSYS_API_PORT',
    defaultValue: '8000',
  );

  test(
    'native API endpoints use the launcher address when configured',
    () {
      for (final address in [
        ApiConfig.baseUrl,
        ApiConfig.usersUrl,
        ApiConfig.defenseSchedulesUrl,
        ApiConfig.dashboardsUrl,
      ]) {
        final uri = Uri.parse(address);
        expect(uri.host, host);
        expect(uri.port.toString(), port);
        expect(uri.scheme, 'http');
      }
    },
    skip: host.isEmpty,
  );

  test(
    'native authenticated files and live grading use the same server',
    () {
      final file = Uri.parse(
        ApiConfig.authenticatedMediaUrl('/media/team_documents/example.pdf'),
      );
      final live = ApiConfig.webSocketGradingUri('test-token');
      expect(file.host, host);
      expect(file.port.toString(), port);
      expect(file.path, '/api/media/files/team_documents/example.pdf');
      expect(live.host, host);
      expect(live.port.toString(), port);
      expect(live.scheme, 'ws');
    },
    skip: host.isEmpty,
  );
}
