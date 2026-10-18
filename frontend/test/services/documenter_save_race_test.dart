import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:defensys/services/pit/documenter_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';

class DelayedMinutesClient implements AuthenticatedHttpClient {
  final gets = <int, Completer<http.Response>>{};
  final patches = <int, Completer<http.Response>>{};
  final assignmentReads = <Completer<http.Response>>[];

  int scheduleId(Uri url) =>
      int.parse(url.pathSegments[url.pathSegments.length - 2]);

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) {
    if (url.path.endsWith('/my-assignments/')) {
      final pending = Completer<http.Response>();
      assignmentReads.add(pending);
      return pending.future;
    }
    return (gets[scheduleId(url)] = Completer<http.Response>()).future;
  }

  @override
  Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => (patches[scheduleId(url)] = Completer<http.Response>()).future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response detail(int id) => http.Response(
  jsonEncode({
    'schedule': {'id': id},
    'status': 'draft',
  }),
  200,
);

void main() {
  late DelayedMinutesClient client;
  late ProviderContainer container;
  setUp(() {
    client = DelayedMinutesClient();
    container = ProviderContainer(
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
  });
  tearDown(() => container.dispose());

  test('late assignment refresh cannot replace a newer queue', () async {
    final notifier = container.read(documenterProvider.notifier);
    final earlier = notifier.fetchAssignments();
    final latest = notifier.fetchAssignments();
    client.assignmentReads[1].complete(http.Response('[{"id":2}]', 200));
    await latest;
    client.assignmentReads[0].complete(http.Response('[{"id":1}]', 200));
    await earlier;
    expect(container.read(documenterProvider).assignments.single['id'], 2);
    expect(container.read(documenterProvider).isLoading, isFalse);
  });

  test('late detail response cannot reopen the previous defense', () async {
    final notifier = container.read(documenterProvider.notifier);
    final first = notifier.fetchMinutesDetail(1);
    final second = notifier.fetchMinutesDetail(2);
    client.gets[2]!.complete(detail(2));
    await second;
    client.gets[1]!.complete(detail(1));
    await first;
    expect(
      container.read(documenterProvider).activeMinutes?['schedule']['id'],
      2,
    );
    expect(container.read(documenterProvider).isLoading, isFalse);
  });

  test(
    'late autosave response leaves the newly opened defense intact',
    () async {
      final notifier = container.read(documenterProvider.notifier);
      final first = notifier.fetchMinutesDetail(1);
      client.gets[1]!.complete(detail(1));
      await first;
      final saving = notifier.autoSaveComments(1, []);
      final second = notifier.fetchMinutesDetail(2);
      client.gets[2]!.complete(detail(2));
      await second;
      client.patches[1]!.complete(detail(1));
      expect(await saving, isTrue);
      expect(
        container.read(documenterProvider).activeMinutes?['schedule']['id'],
        2,
      );
      expect(container.read(documenterProvider).isSavingAuto, isFalse);
      expect(container.read(documenterProvider).lastAutoSavedAt, isNull);
    },
  );
}
