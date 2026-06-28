/// API Configuration
/// Supports multiple IP addresses for different network environments
/// - Web on localhost uses 127.0.0.1:8000 so API calls match a local Django server
/// - Web on a public host (Kamatera / production) uses same origin, no :8000 (nginx → /api/)
/// - Android emulator: use 10.0.2.2 to reach Django on the host PC (not the LAN IP).
///   Override any host: `flutter run --dart-define=DEFENSYS_API_HOST=<your-lan-ip>`
/// - Physical phone on Wi‑Fi: set your PC LAN IP via dart-define (see DEMO_SETUP_GUIDE.md)
/// - Production mobile: `--dart-define=DEFENSYS_API_HOST=... --dart-define=DEFENSYS_API_PORT=`
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class ApiConfig {
  /// Hosts tried by [getAllPossibleUrls] for connection probing only.
  static const List<String> serverIps = ['127.0.0.1'];

  /// Default when no dart-define on mobile (use DEFENSYS_API_HOST for physical devices).
  static const String fallbackLanIp = '127.0.0.1';

  /// Android emulator loopback to the host machine (where `runserver` usually listens).
  static const String androidEmulatorHost = '10.0.2.2';

  /// Default Django dev server port (local / mobile).
  static const String basePort = '8000';

  /// Overrides [baseIp] on any platform when non-empty. Example:
  /// `flutter run --dart-define=DEFENSYS_API_HOST=192.168.1.2`
  static const String dartDefineApiHost =
      String.fromEnvironment('DEFENSYS_API_HOST', defaultValue: '');

  /// `http` or `https`. Empty = auto (https when the page is served over TLS).
  static const String dartDefineApiScheme =
      String.fromEnvironment('DEFENSYS_API_SCHEME', defaultValue: '');

  /// Port string. Default `8000` for dev. Set to empty for nginx on 80/443:
  /// `flutter build web --dart-define=DEFENSYS_API_PORT=`
  static const String dartDefineApiPort =
      String.fromEnvironment('DEFENSYS_API_PORT', defaultValue: '8000');

  /// Android: `true` uses [androidEmulatorHost] (10.0.2.2) for the **emulator** reaching Django on your PC.
  /// Default `false` uses [fallbackLanIp] for **physical devices** on Wi‑Fi / wireless debugging.
  /// Emulator: `flutter run --dart-define=DEFENSYS_ANDROID_EMULATOR=true`
  static const bool dartDefineAndroidEmulator =
      bool.fromEnvironment('DEFENSYS_ANDROID_EMULATOR', defaultValue: false);

  /// Resolved API host.
  static String get baseIp {
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1') {
        return '127.0.0.1';
      }
      if (host.isNotEmpty) {
        return Uri.base.host;
      }
    }

    if (dartDefineApiHost.isNotEmpty) {
      return dartDefineApiHost;
    }

    // Android emulator should use the host loopback alias; physical phones use LAN IP.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return dartDefineAndroidEmulator ? androidEmulatorHost : fallbackLanIp;
    }

    return fallbackLanIp;
  }

  static String get _scheme {
    if (dartDefineApiScheme.isNotEmpty) {
      return dartDefineApiScheme;
    }
    if (kIsWeb) {
      final pageScheme = Uri.base.scheme;
      if (pageScheme == 'https') return 'https';
    }
    return 'http';
  }

  /// Port used in API URLs. Empty = omit `:port` (production nginx on 80/443).
  static String get _resolvedPort {
    if (const bool.hasEnvironment('DEFENSYS_API_PORT')) {
      return const String.fromEnvironment('DEFENSYS_API_PORT');
    }
    // Production web: page and API share the same host via nginx (no :8000).
    if (kIsWeb) {
      final host = Uri.base.host.toLowerCase();
      if (host != 'localhost' && host != '127.0.0.1' && host.isNotEmpty) {
        return '';
      }
    }
    return basePort;
  }

  static String get _portSuffix {
    final port = _resolvedPort;
    if (port.isEmpty) return '';
    if (_scheme == 'https' && port == '443') return '';
    if (_scheme == 'http' && port == '80') return '';
    return ':$port';
  }

  static String get _origin => '$_scheme://$baseIp$_portSuffix';

  static String get baseUrl => '$_origin/api';

  static String get mediaUrl => _origin;

  /// Absolute URL for JWT-protected file GET (production `/api/media/files/...`).
  static String authenticatedMediaUrl(String fileRef) {
    if (fileRef.isEmpty) return fileRef;

    final parsed = Uri.tryParse(fileRef);
    if (parsed != null && parsed.hasScheme) {
      return fileRef;
    }

    var path = fileRef.startsWith('/') ? fileRef : '/$fileRef';

    if (path.startsWith('/media/')) {
      path = '/api/media/files/${path.substring('/media/'.length)}';
    } else if (!path.startsWith('/api/')) {
      final trimmed = path.startsWith('/') ? path.substring(1) : path;
      path = '/api/media/files/$trimmed';
    }

    return '$mediaUrl$path';
  }

  static String get authUrl => baseUrl;
  static String get usersUrl => '$baseUrl/users';
  static String get teamsUrl => '$baseUrl/teams';
  static String get studentRecordsUrl => '$baseUrl/users/academic-records';
  static String get teamDocumentsUrl => '$baseUrl/teams/documents';
  static String get weeklyProgressUrl => '$baseUrl/teams/weekly-progress';
  static String get rubricsUrl => '$baseUrl/grading/rubrics';
  static String get repositoryAuditUrl => '$baseUrl/repository/audit';
  static String get gradeCenterUrl => '$baseUrl/grading/grades';
  static String get digitalVaultUrl => '$baseUrl/repository/vault';
  static String get defenseStagesUrl => '$baseUrl/defense/stages';
  static String get defenseSchedulesUrl => '$baseUrl/defense/schedules';
  static String get defenseBoardUrl => '$baseUrl/defense/board';
  static String get dashboardsUrl => '$baseUrl/dashboards';
  static String get defenseMinutesUrl => '$baseUrl/defense/minutes';
  static String get userSignatureUrl => '$baseUrl/users/e-signature';

  /// WebSocket for live grading-flag updates (Daphne / ASGI).
  static Uri webSocketGradingUri(String accessToken) {
    final wsScheme = _scheme == 'https' ? 'wss' : 'ws';
    final base = '$wsScheme://$baseIp$_portSuffix/ws/grading/';
    return Uri.parse(base).replace(
      queryParameters: {'token': accessToken},
    );
  }
  static String get academicPeriodsUrl => '$baseUrl/academic-periods';
  static String get capstoneDeliverablesUrl => '$baseUrl/repository/deliverables';
  static String get curriculumAnalyticsUrl => '$baseUrl/curriculum-analytics';
  static String get notificationsUrl => '$baseUrl/notifications';

  /// Helper method to get all possible base URLs for connection testing
  static List<String> getAllPossibleUrls() {
    return serverIps.map((ip) => 'http://$ip:$basePort/api').toList();
  }
}
