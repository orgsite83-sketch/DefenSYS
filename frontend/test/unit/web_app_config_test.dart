import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/config/web_app_config.dart';
import 'package:defensys/utils/guest_invitation.dart';

void main() {
  const sharedOrigin = 'http://192.168.1.3:57583';

  test(
    'localhost redirects preserve guest codes, paths and query parameters',
    () {
      for (final host in ['localhost', '127.0.0.1', '0.0.0.0']) {
        final current = Uri.parse(
          'http://$host:57583/portal/?source=invite#/guest/evaluate?code=DEF-ABC',
        );
        expect(
          WebAppConfig.canonicalUrl(
            current,
            configuredOrigin: sharedOrigin,
          ).toString(),
          '$sharedOrigin/portal/?source=invite#/guest/evaluate?code=DEF-ABC',
        );
      }
    },
  );

  test('matching shared origin needs no redirect and cannot loop', () {
    expect(
      WebAppConfig.canonicalUrl(
        Uri.parse('$sharedOrigin/#/faculty/dashboard'),
        configuredOrigin: '$sharedOrigin/',
      ),
      isNull,
    );
  });

  test('an origin without a port replaces the previous port', () {
    expect(
      WebAppConfig.canonicalUrl(
        Uri.parse('http://localhost:57583/#/admin/users'),
        configuredOrigin: 'https://defensys.example.edu',
      ).toString(),
      'https://defensys.example.edu/#/admin/users',
    );
  });

  test('unset or malformed origins leave existing deployments alone', () {
    for (final origin in [
      '',
      '192.168.1.3:57583',
      'file:///test',
      'https://',
      'https://user:password@defensys.example',
      'https://defensys.example/other',
      'https://defensys.example?code=123',
      'https://defensys.example#/login',
    ]) {
      expect(
        WebAppConfig.canonicalUrl(
          Uri.parse('https://defensys.example/#/login'),
          configuredOrigin: origin,
        ),
        isNull,
        reason: origin,
      );
    }
  });

  test('PC aliases and phone generate the same shared invitation link', () {
    for (final host in ['localhost', '127.0.0.1', '192.168.1.3']) {
      final portal = guestPortalUrl(
        base: Uri.parse('http://$host:57583/#/admin/users'),
        webOrigin: sharedOrigin,
      );
      expect(portal, '$sharedOrigin/#/guest/evaluate');
      expect(
        guestInvitationUrl('DEF-ABC', portal: portal),
        '$sharedOrigin/#/guest/evaluate?code=DEF-ABC',
      );
    }
  });
}
