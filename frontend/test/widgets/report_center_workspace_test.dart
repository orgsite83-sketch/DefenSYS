import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/screens/web/admin/audit_compliance/components/audit_report_center_tab.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/services/reports_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/export/defensys_live_data_preview_pane.dart';
import 'package:defensys/widgets/export/defensys_document_sheet.dart';
import 'package:defensys/widgets/export/report_catalog.dart';
import 'package:defensys/widgets/export/report_navigation.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';
import 'audit_compliance_redesign_test.dart' show FakeAuthNotifier;

class _Periods extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() =>
      const AcademicPeriodState(activeSemester: {'id': 1});
}

class _Options extends AuthenticatedHttpClient {
  _Options(super.ref);
  final requests = <Uri>[];
  bool fail = false;

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    requests.add(url);
    if (fail) return http.Response('{"detail":"Selections unavailable"}', 503);
    if (url.path.endsWith('assessment-candidates/')) {
      final pit = url.queryParameters['scope'] == 'pit';
      final team = {
        'id': pit ? 16 : 12,
        'name': pit ? 'PIT Team' : 'Team Atlas',
        'project_title': 'Records portal',
        'year_level': pit ? '2nd Year' : '4th Year',
        'scope': pit ? 'pit' : 'capstone',
        'semester_id': int.tryParse(url.queryParameters['semester_id'] ?? '1'),
      };
      return http.Response(
        jsonEncode({
          'teams': [team],
          'students': [
            {'id': 3, 'name': 'Student Leader'},
          ],
          'student_contexts': {
            '3': {
              'contexts': [
                {'team': team},
              ],
            },
          },
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({
        'default_semester_id': 1,
        'semesters': [
          {'id': 1, 'label': 'Current semester'},
          {'id': 2, 'label': 'Previous semester'},
        ],
        'stages': [
          {'id': 7, 'label': 'Final defense', 'scope': 'capstone'},
        ],
        'pit_events': [
          {
            'id': 8,
            'label': 'PIT event',
            'scope': 'pit',
            'year_level': '2nd Year',
            'semester_id': 1,
          },
          {
            'id': 9,
            'label': 'PIT concept event',
            'scope': 'pit',
            'year_level': '3rd Year',
            'semester_id': 1,
          },
        ],
        'stage_choices': [
          {
            'value': 'Final defense',
            'label': 'Final defense',
            'scope': 'capstone',
          },
        ],
        'rubrics': [
          {
            'id': 17,
            'label': 'Final rubric',
            'scope': 'capstone',
            'semester_id': 1,
          },
        ],
        'teams': [],
        'students': [],
      }),
      200,
    );
  }
}

class _Reports extends ReportsNotifier {
  final previews = <(String, Map<String, String>)>[];
  final downloads = <(String, String, Map<String, String>)>[];

  @override
  ReportsState build() => const ReportsState();

  @override
  Future<ReportPreviewData?> fetchReportPreview({
    required String endpoint,
    required Map<String, String> queryParams,
  }) async {
    previews.add((endpoint, Map.of(queryParams)));
    return const ReportPreviewData(
      title: 'Recorded grade report',
      subtitle: '',
      generatedAt: '',
      summaryKpis: [],
      columns: [
        {'key': 'name', 'label': 'Student'},
        {'key': 'grade', 'label': 'Grade'},
      ],
      rows: [
        {'name': 'Student Leader', 'grade': 91},
      ],
      totalRows: 1,
      assessments: [
        {'id': 21, 'scope': 'capstone', 'stage_label': 'Concept Proposal'},
        {'id': 22, 'scope': 'pit', 'stage_label': 'PIT event'},
      ],
    );
  }

  @override
  Future<bool> downloadReport({
    required String endpoint,
    required Map<String, String> queryParams,
    required String defaultFilename,
    String exportFormat = 'pdf',
  }) async {
    downloads.add((endpoint, exportFormat, Map.of(queryParams)));
    return true;
  }
}

Future<(_Reports, _Options)> _pump(
  WidgetTester tester, {
  double width = 1440,
  bool dark = false,
  bool lead = false,
  Map<String, String> query = const {},
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts();
  final reports = _Reports();
  late _Options options;
  await pumpDefensysWidget(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AuditReportCenterTab(reportQuery: query),
    ),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
    overrides: [
      authProvider.overrideWith(
        () => FakeAuthNotifier(
          lead
              ? {
                  'role': 'faculty',
                  'is_pit_lead': true,
                  'pit_lead_year': '2nd Year',
                }
              : {'role': 'admin', 'first_name': 'Test', 'last_name': 'Admin'},
        ),
      ),
      academicPeriodProvider.overrideWith(_Periods.new),
      reportsProvider.overrideWith(() => reports),
      authenticatedHttpClientProvider.overrideWith(
        (ref) => options = _Options(ref),
      ),
    ],
  );
  // The landing page deliberately makes no catalog-options request.
  if (query.isEmpty) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AuditReportCenterTab)),
    );
    options = container.read(authenticatedHttpClientProvider) as _Options;
  }
  return (reports, options);
}

Future<void> _group(WidgetTester tester, String id) async {
  final finder = find.byKey(ValueKey('report-group-$id'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String key, String label) async {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is ShadSelect<String> && widget.key.toString().contains('$key:'),
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _openPopup(WidgetTester tester, String reportId) async {
  final card = find.byKey(ValueKey('open-report-$reportId'));
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

void main() {
  test('Every report belongs to exactly one task group', () {
    final ids = ReportNavigation.groups
        .expand((group) => group.reportIds)
        .toList();
    expect(ids.toSet().length, ids.length);
    expect(
      ids.toSet(),
      ReportCatalog.reports.map((report) => report.id).toSet(),
    );
  });

  testWidgets('The entire category card is clickable without an Open action', (
    tester,
  ) async {
    final (reports, options) = await _pump(tester);
    for (final group in ReportNavigation.groups) {
      expect(find.text(group.title), findsOneWidget);
    }
    expect(find.text('Open'), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    final card = find.byKey(const ValueKey('report-group-grades'));
    await tester.tapAt(tester.getRect(card).bottomRight - const Offset(6, 6));
    await tester.pumpAndSettle();
    expect(find.text('Student grade list'), findsOneWidget);
    expect(find.text('Student report card'), findsOneWidget);
    expect(find.text('Grade summaries'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(reports.previews, isEmpty);
    expect(options.requests, isEmpty);
    await capturePreview(
      tester,
      find.byType(AuditReportCenterTab),
      'report-center-grade-cards',
      viewport: true,
    );
  });

  testWidgets('Space and Enter activate the category and report cards', (
    tester,
  ) async {
    await _pump(tester);
    Focus.of(tester.element(find.text('Grades'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Student grade list'), findsOneWidget);
    Focus.of(tester.element(find.text('Student grade list'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets(
    'A report card opens the shared popup with its filters and preview',
    (tester) async {
      final (reports, _) = await _pump(tester);
      await capturePreview(
        tester,
        find.byType(AuditReportCenterTab),
        'report-center-home',
        viewport: true,
      );
      await _group(tester, 'grades');
      final card = find.byKey(
        const ValueKey('open-report-student-grade-masterlist'),
      );
      await tester.tapAt(tester.getRect(card).bottomRight - const Offset(6, 6));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(DefensysDocumentSheet), findsOneWidget);
      expect(find.text('Choose records'), findsOneWidget);
      expect(reports.previews.last.$1, 'grade-masterlist/');
      expect(reports.previews.last.$2['semester_id'], '1');
      expect(reports.previews.last.$2['coverage'], 'semester');
      expect(find.byKey(const ValueKey('report-filename')), findsNothing);
      await capturePreview(
        tester,
        find.byType(Dialog),
        'report-center-popup',
        viewport: true,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('report-more-options')),
      );
      await tester.tap(find.byKey(const ValueKey('report-more-options')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Signature blocks off'));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Dialog),
        'report-center-export-options',
        viewport: true,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.byKey(const ValueKey('open-report-student-grade-masterlist')),
        findsOneWidget,
      );
    },
  );

  for (final format in ['pdf', 'xlsx']) {
    testWidgets(
      'A $format download closes the popup and returns to report cards',
      (tester) async {
        final (reports, _) = await _pump(tester);
        await _group(tester, 'grades');
        await _openPopup(tester, 'student-grade-masterlist');
        await tester.tap(find.byKey(ValueKey('report-download-$format')));
        await tester.pumpAndSettle();
        expect(reports.downloads.last.$2, format);
        expect(reports.downloads.last.$3['semester_id'], '1');
        expect(find.byType(Dialog), findsNothing);
        expect(
          find.byKey(const ValueKey('open-report-student-grade-masterlist')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'Program and period selections carry between compatible report popups',
    (tester) async {
      final (reports, options) = await _pump(tester);
      await _group(tester, 'grades');
      await _openPopup(tester, 'team-grade-masterlist');
      await _select(tester, 'semester_id', 'Previous semester');
      await _select(tester, 'scope', 'PIT');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await _openPopup(tester, 'team-grade');
      final candidates = options.requests
          .where((uri) => uri.path.endsWith('assessment-candidates/'))
          .last;
      expect(candidates.queryParameters['semester_id'], '2');
      expect(candidates.queryParameters['scope'], 'pit');
      await _select(tester, 'team_id', 'PIT Team — Records portal');
      expect(reports.previews.last.$1, 'team-grade/16/');
      expect(reports.previews.last.$2['coverage'], 'latest');
      await _select(tester, 'coverage', 'All recorded assessments');
      expect(reports.previews.last.$2['coverage'], 'all');
      await _select(tester, 'coverage', 'PIT · PIT event');
      expect(reports.previews.last.$2['grade_id'], '22');
    },
  );

  testWidgets(
    'Student report cards require a student and clear it when the period changes',
    (tester) async {
      final (reports, _) = await _pump(tester);
      await _group(tester, 'grades');
      await _openPopup(tester, 'individual-grade');
      expect(reports.previews, isEmpty);
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('report-download-pdf')),
            )
            .onPressed,
        isNull,
      );
      await _select(tester, 'student_id', 'Student Leader');
      expect(reports.previews.last.$1, 'individual-grade/3/');
      final requests = reports.previews.length;
      await _select(tester, 'semester_id', 'Previous semester');
      expect(reports.previews.length, requests);
      expect(find.byType(DefensysDocumentSheet), findsNothing);
      expect(
        tester
            .widget<ShadButton>(
              find.byKey(const ValueKey('report-download-pdf')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'PIT Lead card visibility and popup resets retain the assigned scope',
    (tester) async {
      final (reports, _) = await _pump(tester, lead: true);
      await _group(tester, 'grades');
      expect(
        find.byKey(const ValueKey('open-report-capstone-grade-sheet')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('open-report-pit-grade-sheet')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('report-back')));
      await tester.pumpAndSettle();
      await _group(tester, 'people');
      expect(
        find.byKey(const ValueKey('open-report-user-directory')),
        findsNothing,
      );
      await _openPopup(tester, 'team-roster');
      expect(reports.previews.last.$2['scope'], 'pit');
      expect(reports.previews.last.$2['year_level'], '2nd Year');
      await tester.ensureVisible(find.text('Reset selections'));
      await tester.tap(find.text('Reset selections'));
      await tester.pumpAndSettle();
      expect(reports.previews.last.$2['year_level'], '2nd Year');
      expect(find.text('Capstone'), findsNothing);
    },
  );

  testWidgets(
    'Search uses original report names and opens a report card popup',
    (tester) async {
      final (reports, _) = await _pump(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('report-search')),
          matching: find.byType(EditableText),
        ),
        'Concept Project Register',
      );
      await tester.pumpAndSettle();
      expect(find.text('Concept decisions & intake roster'), findsOneWidget);
      expect(find.text('Open report'), findsNothing);
      await _openPopup(tester, 'concept-projects');
      expect(reports.previews.last.$1, 'concept-projects/');
    },
  );

  testWidgets('Grade summary formats are available as report cards', (
    tester,
  ) async {
    await _pump(tester);
    await _group(tester, 'grades');
    for (final id in [
      'capstone-grade-sheet',
      'pit-grade-sheet',
      'semester-grades',
    ]) {
      expect(find.byKey(ValueKey('open-report-$id')), findsOneWidget);
    }
    expect(find.text('More reports'), findsNothing);
  });

  testWidgets(
    'A single-report category also shows its report card before opening the popup',
    (tester) async {
      final (reports, options) = await _pump(tester);
      await _group(tester, 'schedules');
      expect(
        find.byKey(const ValueKey('open-report-defense-schedules')),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(options.requests, isEmpty);
      await _openPopup(tester, 'defense-schedules');
      expect(reports.previews.last.$1, 'defense-schedules/');
    },
  );

  testWidgets('A historical deep link opens its popup with the exact record', (
    tester,
  ) async {
    final (reports, options) = await _pump(
      tester,
      query: {
        'report': 'team-grade',
        'team_id': '16',
        'scope': 'pit',
        'semester_id': '2',
        'coverage': 'specific',
        'grade_id': '22',
      },
    );
    expect(find.byType(Dialog), findsOneWidget);
    expect(reports.previews.last.$1, 'team-grade/16/');
    expect(reports.previews.last.$2['semester_id'], '2');
    expect(reports.previews.last.$2['grade_id'], '22');
    expect(
      options.requests
          .where((uri) => uri.path.endsWith('assessment-candidates/'))
          .last
          .queryParameters['semester_id'],
      '2',
    );
  });

  testWidgets('Selection errors can be retried inside the popup', (
    tester,
  ) async {
    final (reports, options) = await _pump(tester);
    options.fail = true;
    await _group(tester, 'grades');
    await _openPopup(tester, 'student-grade-masterlist');
    expect(find.text('Selections unavailable'), findsOneWidget);
    expect(reports.previews, isEmpty);
    options.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(DefensysDocumentSheet), findsOneWidget);
  });

  testWidgets('The intake roster remains Excel only in the popup', (
    tester,
  ) async {
    final (reports, _) = await _pump(tester);
    await _group(tester, 'projects');
    await _openPopup(tester, 'concept-projects');
    await _select(tester, 'scope', 'PIT');
    await _select(tester, 'year_level', '3rd Year');
    await _select(tester, 'pit_event_config_id', 'PIT concept event');
    await _select(tester, 'layout', 'Capstone intake roster (Excel)');
    expect(find.byKey(const ValueKey('report-download-pdf')), findsNothing);
    expect(reports.previews.last.$2['layout'], 'roster');
    expect(reports.previews.last.$2['include_history'], '0');
  });

  for (final width in [390.0, 900.0]) {
    testWidgets('Clickable cards and popup fit $width in dark mode', (
      tester,
    ) async {
      await _pump(tester, width: width, dark: true);
      expect(tester.takeException(), isNull);
      await _group(tester, 'grades');
      expect(tester.takeException(), isNull);
      await _openPopup(tester, 'student-grade-masterlist');
      for (final key in ['report-more-filters', 'report-more-options']) {
        final trigger = find.byKey(ValueKey(key));
        await tester.ensureVisible(trigger);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Signature blocks off'));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Dialog),
        'report-center-settings-dark-${width.toInt()}',
        viewport: true,
      );
      if (width < 820) {
        await tester.tap(find.widgetWithText(Tab, 'Preview'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(DefensysLiveDataPreviewPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
