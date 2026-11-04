import 'dart:async';
import 'dart:convert';
import 'package:defensys/services/updates/update_service.dart';
import 'package:defensys/services/updates/update_activity.dart';
import 'package:defensys/services/network/api_http.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> metadata({int build = 2, bool android = false}) => {
  'schema_version': 1,
  'web': {'version': '1.0.1', 'build': build, 'release_id': 'web-$build'},
  'android': android
      ? {
          'available': true,
          'version': '1.0.1',
          'build': build,
          'application_id': 'com.example.user',
          'download_url':
              'https://defensys.site/releases/android/app-1-$build.apk',
          'sha256': 'a' * 64,
          'size_bytes': 10,
        }
      : {'available': false},
};
const running = RunningRelease(
  version: '1.0.0',
  build: 1,
  id: 'web-1',
  isWeb: true,
);

void main() {
  test(
    'www page checks its own origin while accepting the configured canonical APK origin',
    () async {
      final requests = <http.Request>[];
      final service = ReleaseService(
        MockClient((request) async {
          requests.add(request);
          return request.method == 'HEAD'
              ? http.Response(
                  '',
                  200,
                  headers: {
                    'content-type': 'application/vnd.android.package-archive',
                    'content-length': '10',
                  },
                )
              : http.Response(
                  jsonEncode(metadata(android: true)),
                  200,
                  headers: {'content-type': 'application/json'},
                );
        }),
        Uri.parse('https://www.defensys.site'),
        downloadOrigin: Uri.parse('https://defensys.site'),
      );
      final catalog = await service.fetch();
      expect(catalog.android, isNotNull);
      expect(
        requests.every((request) => request.url.host == 'www.defensys.site'),
        isTrue,
      );
      expect(catalog.android!.download!.host, 'defensys.site');
    },
  );
  test(
    'release parsing compares numeric channel builds and rejects foreign APK URLs',
    () {
      final data = metadata(android: true);
      final catalog = ReleaseCatalog.parse(
        data,
        Uri.parse('https://defensys.site'),
      );
      expect(running.newer(catalog), isTrue);
      expect(
        const RunningRelease(
          version: '9.9.9',
          build: 20,
          id: 'web-20',
          isWeb: true,
        ).newer(catalog),
        isFalse,
      );
      (data['android'] as Map)['download_url'] = 'https://evil.example/app.apk';
      expect(
        () => ReleaseCatalog.parse(data, Uri.parse('https://defensys.site')),
        throwsFormatException,
      );
      expect(
        () => ReleaseCatalog.parse({
          'schema_version': 2,
        }, Uri.parse('https://defensys.site')),
        throwsFormatException,
      );
    },
  );
  test('HTML and missing APKs never become published downloads', () async {
    final html = ReleaseService(
      MockClient(
        (_) async => http.Response(
          '<html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
      Uri.parse('https://defensys.site'),
    );
    await expectLater(html.fetch(), throwsFormatException);
    final service = ReleaseService(
      MockClient(
        (request) async => request.method == 'HEAD'
            ? http.Response(
                '<html>',
                200,
                headers: {'content-type': 'text/html', 'content-length': '6'},
              )
            : http.Response(
                jsonEncode(metadata(android: true)),
                200,
                headers: {'content-type': 'application/json'},
              ),
      ),
      Uri.parse('https://defensys.site'),
    );
    final catalog = await service.fetch();
    expect(catalog.web, isNotNull);
    expect(catalog.android, isNull);
  });
  test(
    'checks deduplicate; Later preserves dismissal until a new build; old mirrors are ignored',
    () async {
      var count = 0, build = 2;
      final gate = Completer<void>();
      final client = MockClient((_) async {
        count++;
        await gate.future;
        return http.Response(
          jsonEncode(metadata(build: build)),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final container = ProviderContainer(
        overrides: [
          runningReleaseProvider.overrideWith((_) async => running),
          releaseServiceProvider.overrideWithValue(
            ReleaseService(client, Uri.parse('https://defensys.site')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(appUpdateProvider.notifier);
      final first = notifier.check();
      final second = notifier.check(manual: true);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([first, second]);
      expect(count, 1);
      expect(container.read(appUpdateProvider).showPrompt, isTrue);
      notifier.dismiss();
      expect(container.read(appUpdateProvider).showPrompt, isFalse);
      await notifier.check();
      expect(count, 1);
      build = 1;
      await notifier.check(manual: true);
      expect(container.read(appUpdateProvider).latest!.build, 2);
      build = 3;
      await notifier.check(manual: true);
      expect(container.read(appUpdateProvider).showPrompt, isTrue);
    },
  );
  test(
    'write guard lasts through response stream consumption and releases on error',
    () async {
      final body = StreamController<List<int>>();
      setApiHttpClientForTesting(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(body.stream, 200),
        ),
      );
      addTearDown(resetApiHttpClientForTesting);
      final response = await apiHttpClient.send(
        http.Request('POST', Uri.parse('https://defensys.site/api/test')),
      );
      expect(apiWriteActivity.value, 1);
      final done = response.stream.toBytes();
      body.add([1, 2]);
      await body.close();
      await done;
      expect(apiWriteActivity.value, 0);
      setApiHttpClientForTesting(
        MockClient((_) async => throw Exception('offline')),
      );
      await expectLater(
        apiHttpClient.post(Uri.parse('https://defensys.site/api/test')),
        throwsException,
      );
      expect(apiWriteActivity.value, 0);
    },
  );
}
