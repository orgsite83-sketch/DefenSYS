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
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/models/library_filters.dart';
import 'package:defensys/widgets/repository/library_activity_panel.dart';
import 'package:defensys/widgets/repository/library_components.dart';
import 'package:defensys/widgets/repository/library_discovery.dart';
import 'package:defensys/widgets/branding/defensys_mobile_brand.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import 'package:defensys/widgets/shadcn/defensys_workflow_widgets.dart';

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
      'library_tags': {
        'subject': [
          {'id': 'health-wellbeing', 'label': 'Health & Wellbeing'},
        ],
        'technology': [
          {
            'id': item.$1 == 'wards' ? 'web' : 'mobile',
            'label': item.$1 == 'wards'
                ? 'Web Applications'
                : 'Mobile Applications',
            'status': 'proposed',
          },
        ],
        'language': [
          {
            'id': item.$1 == 'wards' ? 'python' : 'dart',
            'label': item.$1 == 'wards' ? 'Python' : 'Dart',
            'status': 'proposed',
          },
        ],
      },
      'topics': [
        item.$1 == 'wards'
            ? (item.$3 == 'concept' ? 'healthcare' : 'wards')
            : 'data',
      ],
    },
];

final _pitEntry = <String, dynamic>{
  'id': 'campus-poster',
  'project_key': 'campus',
  'team_id': 'campus',
  'display_title': 'Campus Attendance',
  'document_kind': 'poster',
  'document_label': 'Poster',
  'file_name': 'campus_poster.pdf',
  'team_name': 'Team Campus',
  'type': 'pit',
  'academic_year': '2025–2026',
  'topics': ['campus'],
  'library_tags': {
    'subject': [
      {'id': 'education', 'label': 'Education'},
    ],
    'technology': [],
    'language': [],
  },
};

class _Repository extends RepositoryNotifier {
  @override
  RepositoryState build() => RepositoryState(entries: [..._entries, _pitEntry]);
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
            'entries': [..._entries, _pitEntry].where((json) {
              final entry = VaultEntry.fromJson(json);
              final params = request.url.queryParameters;
              final selection = LibraryFilterSelection(
                year: params['academic_year'] ?? '',
                subjects: (params['subject'] ?? '')
                    .split(',')
                    .where((id) => id.isNotEmpty)
                    .toSet(),
                technologies: (params['technology'] ?? '')
                    .split(',')
                    .where((id) => id.isNotEmpty)
                    .toSet(),
                languages: (params['language'] ?? '')
                    .split(',')
                    .where((id) => id.isNotEmpty)
                    .toSet(),
              );
              final kind = params['document_kind'] ?? '';
              return selection.matches(entry) &&
                  ((params['type'] ?? '').isEmpty ||
                      params['type'] == entry.type) &&
                  (kind.isEmpty ||
                      kind == entry.outputKind ||
                      (kind == 'documents' && entry.isDocument)) &&
                  ((params['search'] ?? '').isEmpty ||
                      entry.displayTitle.toLowerCase().contains(
                        params['search']!.toLowerCase(),
                      ));
            }).toList(),
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
    bool mobileShell = false,
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
            child: Scaffold(
              appBar: mobileShell
                  ? AppBar(
                      backgroundColor: dark
                          ? DefensysTokens.mistSurface
                          : DefensysTokens.surface,
                      leading: const Icon(Icons.menu),
                      title: const DefensysMobileBrand(),
                      actions: const [
                        Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.notifications_none,
                          ),
                        ),
                      ],
                    )
                  : null,
              body: child,
              bottomNavigationBar: mobileShell
                  ? NavigationBar(
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.folder),
                          label: 'Repository',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.person),
                          label: 'Profile',
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseTrack(WidgetTester tester, String track) async {
    await tester.tap(find.textContaining('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All tracks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(track).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show collection'));
    await tester.pumpAndSettle();
  }

  Future<void> browseConcepts(WidgetTester tester) async {
    await tester.tap(find.text('Browse all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concept Papers'));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'collection puts projects before filters at $width dark=$dark',
        (tester) async {
          await show(tester, width: width, dark: dark, mobileShell: true);
          await tester.tap(find.text('All projects'));
          await tester.pumpAndSettle();
          expect(find.byType(WorkflowSelect), findsNothing);
          expect(
            tester.getTopLeft(find.byType(LibraryEntryTile).first).dy,
            lessThan(420),
          );
          expect(find.textContaining('Filters'), findsOneWidget);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('preview')),
            'repository-collection-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.textContaining('Filters'));
          await tester.pumpAndSettle();
          expect(find.byType(WorkflowSelect), findsNWidgets(3));
          expect(find.text('Track'), findsOneWidget);
          expect(find.text('Deliverable'), findsOneWidget);
          expect(find.text('Sort'), findsOneWidget);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('preview')),
            'repository-filter-panel-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('collection filters apply and reset track deliverable and sort together', (tester) async {
    await show(tester);
    await tester.tap(find.text('All projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All tracks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Capstone').last);
    await tester.pumpAndSettle();
    final deliverable = tester.widgetList<WorkflowSelect>(find.byType(WorkflowSelect))
        .firstWhere((select) => select.label == 'Deliverable');
    final key = deliverable.options.keys.firstWhere((key) => key.isNotEmpty);
    await tester.tap(find.text('All deliverables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(deliverable.options[key]!).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Recently added'));
    await tester.tap(find.text('Recently added'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title A–Z').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show collection'));
    await tester.pumpAndSettle();
    expect(find.text('Capstone collection'), findsOneWidget);
    expect(find.text('Filters (3)'), findsOneWidget);
    await tester.tap(find.text('Filters (3)'));
    await tester.pumpAndSettle();
    final selects = tester.widgetList<WorkflowSelect>(find.byType(WorkflowSelect));
    expect(selects.firstWhere((select) => select.label == 'Track').value, 'capstone');
    expect(selects.firstWhere((select) => select.label == 'Deliverable').value, key);
    expect(selects.firstWhere((select) => select.label == 'Sort').value, 'title');
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show collection'));
    await tester.pumpAndSettle();
    expect(find.text('All projects'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.byType(LibraryEntryTile), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'project navigation keeps workspace bars and returns to the library',
    (tester) async {
      await show(tester, mobileShell: true);
      expect(find.text('Capstone'), findsOneWidget);
      expect(find.text('PIT Projects'), findsOneWidget);
      final card = find.byType(LibraryEntryTile).first;
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryProjectScreen), findsOneWidget);
      expect(find.byType(DefensysMobileBrand), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      final header = tester.widget<AppBar>(
        find.descendant(
          of: find.byType(LibraryProjectScreen),
          matching: find.byType(AppBar),
        ),
      );
      final context = tester.element(find.byType(LibraryProjectScreen));
      expect(header.backgroundColor, DefensysTokens.surfaceOf(context));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryProjectScreen), findsNothing);
      expect(find.byType(LibraryEntryTile), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'project sections use configured deliverables across file formats',
    (tester) async {
      final materials = [
        for (final item in [
          ('one', 'design.pdf', 'package', 'Prototype package'),
          ('two', 'walkthrough.mp4', 'package', 'Prototype package'),
          ('three', 'research.pdf', 'research', 'Research study'),
          ('four', 'legacy.pdf', '', ''),
        ])
          VaultEntry.fromJson({
            ..._entries.first,
            'id': item.$1,
            'file_name': item.$2,
            'deliverable_key': item.$3,
            'deliverable_group_label': item.$4,
          }),
      ];
      await show(
        tester,
        width: 390,
        child: LibraryProjectScreen(
          project: LibraryProject('wards', materials),
        ),
      );
      expect(find.text('Prototype package (2)'), findsOneWidget);
      expect(find.text('Research study (1)'), findsOneWidget);
      expect(find.text('Other materials (1)'), findsOneWidget);
      expect(find.text('design.pdf'), findsOneWidget);
      expect(find.text('walkthrough.mp4'), findsOneWidget);
      expect(find.text('research.pdf'), findsNothing);
      await tester.ensureVisible(find.text('Research study (1)'));
      await tester.tap(find.text('Research study (1)'));
      await tester.pumpAndSettle();
      expect(find.text('research.pdf'), findsOneWidget);
      expect(find.text('walkthrough.mp4'), findsNothing);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('preview')),
        'repository-deliverables-light',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'topic opens one card per project and project retains its materials',
    (tester) async {
      await show(tester);
      final row = find.byKey(const ValueKey('library-topic-health-wellbeing'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('Health & Wellbeing'), findsNWidgets(2));
      expect(find.text('2 projects'), findsOneWidget);
      expect(find.byType(LibraryEntryTile), findsNWidgets(2));
      final project = find.byWidgetPredicate(
        (widget) =>
            widget is LibraryEntryTile && widget.entry.groupingKey == 'records',
      );
      await tester.ensureVisible(project);
      await tester.tap(project);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryProjectScreen), findsOneWidget);
      expect(find.text('Research materials (2)'), findsOneWidget);
      expect(find.text('View poster'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('branded mobile repository fits $width dark=$dark', (
        tester,
      ) async {
        await show(tester, width: width, dark: dark, mobileShell: true);
        expect(find.byType(DefensysMobileBrand), findsOneWidget);
        expect(find.text('DefenSYS'), findsOneWidget);
        for (final label in ['Browse all', 'All projects']) {
          final element = tester.element(find.text(label));
          expect(
            tester.widget<Text>(find.text(label)).style?.color ??
                DefaultTextStyle.of(element).style.color,
            DefensysTokens.textPrimaryOf(element),
          );
        }
        final topic = tester.element(find.text('Health & Wellbeing'));
        expect(
          tester.widget<Text>(find.text('Health & Wellbeing')).style?.color,
          DefensysTokens.textPrimaryOf(topic),
        );
        await capturePreview(
          tester,
          find.byKey(const ValueKey('preview')),
          'repository-mobile-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'users can browse concept papers across projects and search that stage',
    (tester) async {
      await show(tester);
      expect(
        find.byKey(const ValueKey('library-topic-health-wellbeing')),
        findsOneWidget,
      );
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

  testWidgets(
    'collections use live projects and My shelf opens saved outputs',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('All projects'));
      await tester.pumpAndSettle();
      await chooseTrack(tester, 'PIT');
      await tester.pumpAndSettle();
      expect(find.text('PIT collection'), findsOneWidget);
      expect(find.byType(LibraryEntryTile), findsOneWidget);
      expect(find.text('Campus Attendance'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('My reading shelf'));
      await tester.pumpAndSettle();
      expect(find.text('My reading shelf'), findsOneWidget);
      expect(find.text('Saved outputs'), findsOneWidget);
      expect(
        find.text(_entries.first['display_title'] as String),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filter drafts can be dismissed and matching projects keep all outputs',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Browse all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryEntryTile), findsNWidgets(3));
      await tester.tap(find.textContaining('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(LibraryFilterPanel),
          matching: find.text('SY 2025–2026'),
        ),
      );
      await tester.tap(find.byTooltip('Close panel'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryEntryTile), findsNWidgets(3));
      await tester.tap(find.textContaining('Filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-filter-subject-health-wellbeing')),
      );
      await tester.tap(
        find.byKey(const ValueKey('library-filter-subject-health-wellbeing')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-filter-technology-web')),
      );
      await tester.tap(
        find.byKey(const ValueKey('library-filter-technology-web')),
      );
      await tester.tap(find.text('Show collection'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryEntryTile), findsOneWidget);
      await tester.tap(find.byType(LibraryEntryTile));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryProjectScreen), findsOneWidget);
      expect(find.text('Research materials (2)'), findsOneWidget);
      expect(find.text('Read document'), findsNWidgets(2));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryEntryTile), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(InputChip),
          matching: find.text('Health & Wellbeing'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('collection search retains type, year and structured subjects', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('All projects'));
    await tester.pumpAndSettle();
    await chooseTrack(tester, 'PIT');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(LibraryFilterPanel),
        matching: find.text('SY 2025–2026'),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('library-filter-subject-education')),
    );
    await tester.tap(
      find.byKey(const ValueKey('library-filter-subject-education')),
    );
    await tester.tap(find.text('Show collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search projects, teams, topics…'));
    await tester.pumpAndSettle();
    final screen = tester.widget<LibrarySearchScreen>(
      find.byType(LibrarySearchScreen),
    );
    expect(screen.type, 'pit');
    expect(screen.selection.year, '2025–2026');
    expect(screen.selection.subjects, {'education'});
    expect(
      requests.any(
        (uri) =>
            uri.queryParameters['type'] == 'pit' &&
            uri.queryParameters['academic_year'] == '2025–2026' &&
            uri.queryParameters['subject'] == 'education',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'subject, technology and language selections reach the search API together',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Browse all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('healthcare · 1'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-filter-subject-health-wellbeing')),
      );
      await tester.tap(
        find.byKey(const ValueKey('library-filter-subject-health-wellbeing')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-filter-technology-web')),
      );
      await tester.tap(
        find.byKey(const ValueKey('library-filter-technology-web')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-filter-language-dart')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-filter-language-python')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-filter-language-python')),
      );
      await tester.tap(
        find.byKey(const ValueKey('library-filter-language-python')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show collection'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryEntryTile), findsOneWidget);
      await tester.tap(find.text('Search projects, teams, topics…'));
      await tester.pumpAndSettle();
      expect(
        requests.any(
          (uri) =>
              uri.queryParameters['subject'] == 'health-wellbeing' &&
              uri.queryParameters['technology'] == 'web' &&
              uri.queryParameters['language'] == 'python',
        ),
        isTrue,
      );
      expect(find.text('1 results'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'option search preserves selections and Reset restores all options',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Browse all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-filter-subject-health-wellbeing')),
      );
      await tester.tap(
        find.byKey(const ValueKey('library-filter-subject-health-wellbeing')),
      );
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byKey(const ValueKey('library-filter-search')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(search, 'Python');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-filter-technology-web')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-filter-language-python')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('library-filter-language-python')),
      );
      await tester.tap(
        find.byKey(const ValueKey('library-filter-language-python')),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(find.text('All research'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('library-filter-technology-web')),
        findsOneWidget,
      );
      expect(find.text('3 projects match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('filter action remains above the phone keyboard', (tester) async {
    await show(tester, width: 320);
    await tester.tap(find.text('Browse all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Filters'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.text('Show collection')).dy,
      lessThan(580),
    );
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets(
        'library discovery fits $width in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          await show(tester, width: width, dark: dark);
          final name = 'library-${width.toInt()}-${dark ? 'dark' : 'light'}';
          await capturePreview(
            tester,
            find.byKey(const ValueKey('preview')),
            '$name-home',
          );
          await tester.tap(find.text('Browse all'));
          await tester.pumpAndSettle();
          await capturePreview(
            tester,
            find.byKey(const ValueKey('preview')),
            '$name-directory',
          );
          await tester.tap(find.text('Projects'));
          await tester.pumpAndSettle();
          await capturePreview(
            tester,
            find.byKey(const ValueKey('preview')),
            '$name-collection',
          );
          await tester.tap(find.byTooltip('Compact list'));
          await tester.pumpAndSettle();
          await capturePreview(
            tester,
            find.byKey(const ValueKey('preview')),
            '$name-list',
          );
          await tester.tap(find.textContaining('Filters'));
          await tester.pumpAndSettle();
          await capturePreview(
            tester,
            find.byKey(const ValueKey('preview')),
            '$name-filters',
            viewport: true,
          );
          if (width == 1280 && !dark) {
            await tester.tap(
              find.byKey(
                const ValueKey('library-filter-subject-health-wellbeing'),
              ),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const ValueKey('library-filter-technology-web')),
            );
            await tester.tap(
              find.byKey(const ValueKey('library-filter-technology-web')),
            );
            await tester.pumpAndSettle();
            await capturePreview(
              tester,
              find.byKey(const ValueKey('preview')),
              'library-filters-selected-desktop',
              viewport: true,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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
