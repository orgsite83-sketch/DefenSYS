import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../../config/api_config.dart';
import 'release_model.dart';
export 'release_model.dart';

final runningReleaseProvider = FutureProvider<RunningRelease>((ref) async {
  if (kIsWeb) {
    return const RunningRelease(
      version: String.fromEnvironment(
        'DEFENSYS_RELEASE_VERSION',
        defaultValue: 'development',
      ),
      build: int.fromEnvironment('DEFENSYS_RELEASE_BUILD'),
      id: String.fromEnvironment(
        'DEFENSYS_RELEASE_ID',
        defaultValue: 'development',
      ),
      isWeb: true,
    );
  }
  final info = await PackageInfo.fromPlatform();
  return RunningRelease(
    version: info.version,
    build: int.tryParse(info.buildNumber) ?? 0,
    id: 'android-${info.buildNumber}',
    isWeb: false,
    isAndroid: defaultTargetPlatform == TargetPlatform.android,
  );
});

final releaseServiceProvider = Provider<ReleaseService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  const configured = String.fromEnvironment('DEFENSYS_RELEASE_ORIGIN');
  return ReleaseService(
    client,
    Uri.parse(ApiConfig.mediaUrl),
    downloadOrigin: configured.isEmpty ? null : Uri.parse(configured),
  );
});

final verifiedAndroidDownloadProvider = FutureProvider.family<Uri?, String>((
  ref,
  value,
) async {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      !uri.path.toLowerCase().endsWith('.apk')) {
    return null;
  }
  return await ref.read(releaseServiceProvider).verifyApk(uri) ? uri : null;
});

class ReleaseService {
  ReleaseService(this.client, this.origin, {this.downloadOrigin});
  final http.Client client;
  final Uri origin;
  final Uri? downloadOrigin;
  Future<bool> verifyApk(Uri uri) async {
    try {
      final response = await client
          .head(uri)
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200 &&
          [
            'application/vnd.android.package-archive',
            'application/octet-stream',
          ].contains(
            (response.headers['content-type'] ?? '').split(';').first,
          ) &&
          (int.tryParse(response.headers['content-length'] ?? '') ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  Future<ReleaseCatalog> fetch() async {
    if (origin.scheme != 'https') {
      throw const FormatException(
        'Release checks require the public HTTPS address.',
      );
    }
    final response = await client
        .get(
          origin
              .resolve('/releases/latest.json')
              .replace(
                queryParameters: {
                  'check': '${DateTime.now().microsecondsSinceEpoch}',
                },
              ),
          headers: {
            'Cache-Control': 'no-cache, no-store',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 65536 ||
        !(response.headers['content-type'] ?? '').toLowerCase().contains(
          'application/json',
        )) {
      throw const FormatException('Release information is unavailable.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid release information.');
    }
    final catalog = ReleaseCatalog.parse(decoded, downloadOrigin ?? origin);
    if (catalog.android != null) {
      try {
        final apk = await client
            .head(origin.resolve(catalog.android!.download!.path))
            .timeout(const Duration(seconds: 8));
        final type = (apk.headers['content-type'] ?? '').split(';').first;
        if (apk.statusCode != 200 ||
            ![
              'application/vnd.android.package-archive',
              'application/octet-stream',
            ].contains(type) ||
            int.tryParse(apk.headers['content-length'] ?? '') !=
                catalog.android!.sizeBytes) {
          return ReleaseCatalog(web: catalog.web);
        }
      } catch (_) {
        return ReleaseCatalog(web: catalog.web);
      }
    }
    return catalog;
  }
}

class UpdateState {
  const UpdateState({
    this.checking = false,
    this.catalog,
    this.current,
    this.checkedAt,
    this.error,
    this.dismissed = const {},
  });
  final bool checking;
  final ReleaseCatalog? catalog;
  final RunningRelease? current;
  final DateTime? checkedAt;
  final String? error;
  final Set<String> dismissed;
  AppRelease? get latest => current?.latest(catalog);
  bool get available => current?.newer(catalog) == true;
  bool get showPrompt => available && !dismissed.contains(latest!.id);
  bool get upToDate =>
      checkedAt != null &&
      error == null &&
      current != null &&
      current!.build > 0 &&
      latest != null &&
      !available;
}

final appUpdateProvider = NotifierProvider<AppUpdateNotifier, UpdateState>(
  AppUpdateNotifier.new,
);

class AppUpdateNotifier extends Notifier<UpdateState> {
  Future<void>? _pending;
  DateTime? _attemptedAt;
  @override
  UpdateState build() => const UpdateState();
  void dismiss() {
    if (state.latest == null) return;
    state = UpdateState(
      catalog: state.catalog,
      current: state.current,
      checkedAt: state.checkedAt,
      error: state.error,
      dismissed: {...state.dismissed, state.latest!.id},
    );
  }

  Future<void> check({bool manual = false}) {
    if (_pending != null) return _pending!;
    if (!manual &&
        _attemptedAt != null &&
        DateTime.now().difference(_attemptedAt!) < const Duration(minutes: 5)) {
      return Future.value();
    }
    _attemptedAt = DateTime.now();
    return _pending = _check(manual).whenComplete(() => _pending = null);
  }

  Future<void> _check(bool manual) async {
    state = UpdateState(
      checking: true,
      catalog: state.catalog,
      current: state.current,
      checkedAt: state.checkedAt,
      dismissed: state.dismissed,
    );
    try {
      final current = await ref.read(runningReleaseProvider.future);
      final fetched = await ref.read(releaseServiceProvider).fetch();
      if (!ref.mounted) return;
      // A delayed mirror or an attempted rollback cannot erase a newer notification.
      final old = state.catalog;
      final catalog = ReleaseCatalog(
        web: (fetched.web?.build ?? 0) < (old?.web?.build ?? 0)
            ? old?.web
            : fetched.web,
        android:
            fetched.android != null &&
                fetched.android!.build < (old?.android?.build ?? 0)
            ? old?.android
            : fetched.android,
      );
      final dismissed = {...state.dismissed};
      if (manual) dismissed.remove(current.latest(catalog)?.id);
      state = UpdateState(
        catalog: catalog,
        current: current,
        checkedAt: DateTime.now(),
        dismissed: dismissed,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = UpdateState(
        catalog: state.catalog,
        current: state.current,
        checkedAt: state.checkedAt,
        dismissed: state.dismissed,
        error: 'Could not check for updates. Try again.',
      );
    }
  }
}
