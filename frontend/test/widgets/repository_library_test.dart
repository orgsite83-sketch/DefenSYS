import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:defensys/screens/app/student/repository_tab.dart';
import 'package:defensys/screens/app/student/repository/library_search_screen.dart';
import 'package:defensys/screens/app/student/repository/library_project_screen.dart';
import 'package:defensys/screens/app/student/repository/repository_entry_view.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/repository_provider.dart';
import 'package:defensys/services/repository_review_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/library_activity_panel.dart';
import 'package:defensys/widgets/repository/library_components.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';

final _entries = [
  for (final item in [
    (
      'wards',
      'Hospital Management System — Wards Module',
      'concept',
      'Concept Paper',
    ),
    (
      'wards',
      'Hospital Management System — Wards Module',
      'chapters',
      'Chapters 1–3',
    ),
    ('records', 'Digital Patient Records', 'concept', 'Concept Paper'),
    ('records', 'Digital Patient Records', 'poster', 'Poster'),
  ])
    <String, dynamic>{
      'id': '${item.$1}-${item.$3}',
      'project_key': item.$1,
      'team_id': item.$1,
      'project_title': item.$2,
      'display_title': item.$2,
      'document_kind': item.$3,
      'document_label': item.$4,
      'file_name': '${item.$3}.pdf',
      'file_url': '/media/${item.$3}.pdf',
      'team_name': item.$1 == 'wards' ? 'Team MedWards' : 'Team MedRecord',
      'type': 'capstone',
      'academic_year': '2026–2027',
      'stage': 'Concept Proposal',
      'overview_label': 'Background of the Study',
      'overview_text':
          'Staff coordinate patient admissions and bed availability across the hospital wards.',
      'overview_source': item.$4,
    },
];

class _Repository extends RepositoryNotifier {
  @override
  RepositoryState build() => RepositoryState(entries: _entries);
  @override
  Future<void> fetchForStudent({String? search}) async {}
}

class _Auth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: {'id': 7, 'username': 'student-7', 'role': 'student'},
  );
}

void main() {
  final requests = <Uri>[];
  bool cleared = false;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests.clear();
    cleared = false;
    setApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/shelf/')) {
          if (request.method == 'DELETE') {
            cleared = true;
            return http.Response('{"success":true}', 200);
          }
          return http.Response(
            jsonEncode({
              'recent': cleared ? [] : [_entries.first],
              'saved': [_entries.first],
              'activity': [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({
            'entries': [_entries.first, _entries[2]],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  });
  tearDown(resetApiHttpClientForTesting);
  Future<void> show(
    WidgetTester tester, {
    Widget child = const RepositoryTab(),
    double width = 390,
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts(force: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWith(_Repository.new),
          authProvider.overrideWith(_Auth.new),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          home: RepaintBoundary(
            key: const ValueKey('preview'),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> browseConcepts(WidgetTester tester) async {
    await tester.tap(find.byType(LibraryBrowsePicker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concept Papers').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'users can browse concept papers across projects and search that stage',
    (tester) async {
      await show(tester);
      expect(find.byType(LibraryEntryTile), findsNWidgets(2));
      await browseConcepts(tester);
      expect(find.text('CONCEPT PAPER'), findsNWidgets(2));
      expect(find.text('CHAPTERS 1–3'), findsNothing);
      expect(find.text('POSTER'), findsNothing);
      await tester.tap(find.byTooltip('Output details').first);
      await tester.pumpAndSettle();
      expect(find.text('Read document'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Remove saved output'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search concept papers…'));
      await tester.pumpAndSettle();
      expect(find.byType(LibrarySearchScreen), findsOneWidget);
      expect(find.text('2 results'), findsOneWidget);
      expect(
        requests.any(
          (uri) => uri.queryParameters['document_kind'] == 'concept',
        ),
        isTrue,
      );
      await tester.enterText(find.byType(EditableText), 'hospital');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        requests.any(
          (uri) =>
              uri.queryParameters['search'] == 'hospital' &&
              uri.queryParameters['document_kind'] == 'concept',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('concept cards fit 320px in ${dark ? 'dark' : 'light'} mode', (
      tester,
    ) async {
      await show(tester, width: 320, dark: dark);
      await browseConcepts(tester);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('preview')),
        'repository-concepts-${dark ? 'dark' : 'light'}',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'project and profile fit 320px in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await show(
          tester,
          width: 320,
          dark: dark,
          child: LibraryProjectScreen(
            project: LibraryProject.group(
              _entries.map(VaultEntry.fromJson).toList(),
            ).first,
          ),
        );
        expect(find.text('Source: Chapters 1–3'), findsOneWidget);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('preview')),
          'repository-project-${dark ? 'dark' : 'light'}',
        );
        expect(tester.takeException(), isNull);
        await show(
          tester,
          width: 320,
          dark: dark,
          child: const SingleChildScrollView(child: LibraryActivityPanel()),
        );
        await capturePreview(
          tester,
          find.byKey(const ValueKey('preview')),
          'repository-profile-${dark ? 'dark' : 'light'}',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('output details fit 320px in ${dark ? 'dark' : 'light'} mode', (
      tester,
    ) async {
      await show(
        tester,
        width: 320,
        dark: dark,
        child: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showRepositoryEntryDetails(
              context,
              ref,
              VaultEntry.fromJson(_entries.first),
            ),
            child: const Text('Open details'),
          ),
        ),
      );
      await tester.tap(find.text('Open details'));
      await tester.pumpAndSettle();
      expect(find.text('Read document'), findsOneWidget);
      expect(find.text('Background of the Study'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('clearing recent history preserves saved outputs', (
    tester,
  ) async {
    await show(
      tester,
      child: const SingleChildScrollView(child: LibraryActivityPanel()),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryActivityPanel)),
    );
    expect(
      find.text('Recently opened'),
      findsOneWidget,
      reason:
          '${container.read(repositoryLibraryActivityProvider)}; requests: $requests',
    );
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your reading history is clear'),
      findsOneWidget,
      reason:
          'cleared=$cleared; ${container.read(repositoryLibraryActivityProvider)}; requests: $requests',
    );
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(
      find.text(_entries.first['display_title'] as String),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
