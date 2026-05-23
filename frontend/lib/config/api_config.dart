/// API Configuration
/// Supports multiple IP addresses for different network environments
/// - Web on localhost uses 127.0.0.1 so API calls match a local Django server
/// - Web opened via a LAN hostname uses that same host for the API
/// - Android emulator: use 10.0.2.2 to reach Django on the host PC (not the LAN IP).
///   Override any host: `flutter run --dart-define=DEFENSYS_API_HOST=192.168.1.67`
/// - Physical phone on Wi‑Fi: either
///   `flutter run --dart-define=DEFENSYS_ANDROID_EMULATOR=false` (uses [fallbackLanIp]), or
///   `flutter run --dart-define=DEFENSYS_API_HOST=192.168.1.67`
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class ApiConfig {
  // List of possible server IPs (add your network IPs here)
  static const List<String> serverIps = [
    '192.168.1.67', // Current network IP
    '10.0.22.97', // Alternative network IP
    '10.60.121.199', // Another network IP
    '127.0.0.1', // Localhost fallback
  ];

  /// PC LAN IP when testing from a **physical** device on the same Wi‑Fi (not used on Android emulator by default).
  static const String fallbackLanIp = '192.168.1.67';

  /// Android emulator loopback to the host machine (where `runserver` usually listens).
  static const String androidEmulatorHost = '10.0.2.2';

  static const String basePort = '8000';

  /// Overrides [baseIp] on any platform when non-empty. Example:
  /// `flutter run --dart-define=DEFENSYS_API_HOST=192.168.1.2`
  static const String dartDefineApiHost =
      String.fromEnvironment('DEFENSYS_API_HOST', defaultValue: '');

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

  static String get baseUrl => 'http://$baseIp:$basePort/api';

  static String get mediaUrl => 'http://$baseIp:$basePort';

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
  static String get academicPeriodsUrl => '$baseUrl/academic-periods';
  static String get capstoneDeliverablesUrl => '$baseUrl/repository/deliverables';
  static String get curriculumAnalyticsUrl => '$baseUrl/curriculum-analytics';

  /// Helper method to get all possible base URLs for connection testing
  static List<String> getAllPossibleUrls() {
    return serverIps.map((ip) => 'http://$ip:$basePort/api').toList();
  }
}
