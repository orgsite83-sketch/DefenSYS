import 'dart:convert';
import 'dart:typed_data';

import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_weekly_settings.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/faculty_requirements_pane.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/requirement_summary.dart';
import 'package:defensys/widgets/repository/weekly_report_collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

const _policy = <String, dynamic>{
  'enabled': true,
  'period_id': 1,
  'starts_on': '2026-01-05',
  'total_weeks': 3,
  'due_weekday': 6,
  'due_time': '23:59',
  'required_start': 1,
  'required_end': 2,
};

Map<String, dynamic> _collection({
  bool accepted = false,
  bool student = false,
}) => {
  'id': 'WPR',
  'label': 'Weekly Accomplishment Reports',
  'source': 'weekly_reports',
  'type': 'pre',
  'required': true,
  'requirement_timing': 'scheduling',
  'weekly_reporting': _policy,
  'current_week': 3,
  'completed': accepted,
  'weekly_summary': {
    'required': 2,
    'uploaded': 2,
    'accepted': accepted ? 2 : 1,
    'pending': accepted ? 0 : 1,
    'missing': 0,
    'rejected': 0,
    'late': 2,
    'overdue': 0,
  },
  'weeks': [
    for (var i = 1; i <= 3; i++)
      {
        'week_number': i,
        'required': i <= 2,
        'status': i == 1 || accepted ? 'accepted' : 'pending',
        'starts_on': '2026-01-05',
        'ends_on': '2026-01-11',
        'due_at': '2026-01-11T23:59:00+08:00',
        'timing': 'late',
        'first_submitted_at': '2026-02-01T10:00:00+08:00',
        'can_upload': student && i > 1,
        'can_review': !student,
        'report_id': i,
        'blocker': '',
        'file': {
          'id': i + 10,
          'revision': 1,
          'file_name': 'Week-$i.pdf',
          'file_url': '/api/weekly/$i.pdf',
          'uploaded_at': '2026-02-01T10:00:00+08:00',
          'feedback': '',
        },
      },
  ],
};

class _RoleAuth extends AuthNotifier {
  _RoleAuth(this.role);
  final String role;
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: {'id': 1, 'role': role, 'username': 'weekly-reviewer'},
  );
}

class _Deliverables extends CapstoneDeliverablesNotifier {
  final responses = <Map<String, dynamic>>[];
  @override
  CapstoneDeliverablesState build() =>
      const CapstoneDeliverablesState(selectedStage: 'Proposal');
  @override
  bool applyWeeklyReportResponse(Map<String, dynamic> payload) {
    responses.add(payload);
    return true;
  }
}

class _PdfPicker extends FilePicker {
  List<PlatformFile>? files;
  List<String>? extensions;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    extensions = allowedExtensions;
    return FilePickerResult(
      files ??
          [
            for (var i = 2; i <= 3; i++)
              PlatformFile(
                name: 'Week-$i.pdf',
                size: 9,
                bytes: Uint8List.fromList(utf8.encode('%PDF-test')),
              ),
          ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = _PdfPicker();
  });
  tearDown(resetApiHttpClientForTesting);

  test(
    'accepted late reports complete the collection without an attention state',
    () {
      final item = _collection(accepted: true)..['submission'] = {'files': []};
      final summary = RequirementSummary(item);
      expect(summary.progress, '2/2');
      expect(summary.acceptedFiles, 2);
      expect(summary.status, 'Accepted');
      expect(summary.needsAttention, isFalse);
      expect(summary.detail, contains('2 late'));
      expect(TeamWorkflowStatus.pendingFileReviewCount(item), 0);
    },
  );

  test(
    'weekly templates accept supported formats while retaining calendar validation',
    () {
      final template = weeklyTemplateDraft(null);
      expect(
        weeklySettingsError(_policy, template),
        contains('Attach a weekly'),
      );
      expect(
        weeklySettingsError(_policy, template, requireTemplate: false),
        isNull,
      );
      for (final extension in [
        'docx',
        'PDF',
        'xlsx',
        'png',
        'mp4',
        'mp3',
        'txt',
        'zip',
      ]) {
        template['template'] = {'original_name': 'Weekly.$extension'};
        expect(
          weeklySettingsError(_policy, template),
          isNull,
          reason: extension,
        );
      }
      template['template'] = {'original_name': 'Weekly.exe'};
      expect(weeklySettingsError(_policy, template), contains('supported'));
      template['template'] = {'original_name': 'Weekly.pdf'};
      expect(
        weeklySettingsError({..._policy, 'required_end': 4}, template),
        isNotNull,
      );
      template.addAll({
        'template_action': 'replace',
        'template_selection_name': 'Weekly.pdf',
      });
      expect(weeklySettingsError(_policy, template), contains('again'));
    },
  );

  testWidgets('weekly setup picks a PDF using the shared template formats', (
    tester,
  ) async {
    final picker = _PdfPicker()
      ..files = [
        PlatformFile(
          name: 'Weekly.pdf',
          size: 9,
          bytes: Uint8List.fromList(utf8.encode('%PDF-test')),
        ),
      ];
    FilePicker.platform = picker;
    final template = weeklyTemplateDraft(null);
    await tester.binding.setSurfaceSize(const Size(1280, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, update) => StageWeeklySettings(
            value: Map<String, dynamic>.from(_policy),
            template: template,
            enabled: true,
            onChanged: (_) {},
            onTemplateChanged: () => update(() {}),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Upload template'));
    await tester.tap(find.text('Upload template'));
    await tester.pumpAndSettle();
    expect(
      picker.extensions,
      containsAll([
        'docx',
        'pdf',
        'pptx',
        'xlsx',
        'png',
        'mp4',
        'mp3',
        'txt',
        'zip',
      ]),
    );
    expect(find.text('Weekly.pdf'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(weeklySettingsError(_policy, template), isNull);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(weeklySettingsError(_policy, template), contains('Attach a weekly'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('one report count sets both week endpoints automatically', (
    tester,
  ) async {
    var policy = {
      ..._policy,
      'period_id': null,
      'total_weeks': 16,
      'required_start': 1,
      'required_end': 8,
    };
    final template = weeklyTemplateDraft(null)
      ..['template'] = {'original_name': 'Weekly.docx'};
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, update) => StageWeeklySettings(
            value: policy,
            template: template,
            enabled: true,
            onChanged: (value) => update(() => policy = value),
            onTemplateChanged: () {},
          ),
        ),
      ),
      overrides: authTestOverrides(),
    );
    final count = find.byKey(const ValueKey('weekly-report_count'));
    expect(find.text('First required week'), findsNothing);
    expect(find.text('Last required week'), findsNothing);
    expect(find.byKey(const ValueKey('weekly-required_start')), findsNothing);
    expect(
      find.text('8 reports required \u00b7 Weeks 1\u20138'),
      findsOneWidget,
    );

    await tester.enterText(count, '1');
    await tester.pump();
    expect(policy['required_start'], 1);
    expect(policy['required_end'], 1);
    expect(find.text('1 report required \u00b7 Week 1'), findsOneWidget);
    expect(find.text('Report due'), findsOneWidget);
    expect(find.text('Last report due'), findsNothing);
    expect(find.text('Sun, 11 Jan 2026'), findsOneWidget);
    expect(find.text('11:59 PM \u00b7 Philippine time'), findsOneWidget);
    expect(weeklySettingsError(policy, template), isNull);

    await tester.enterText(count, '16');
    await tester.pump();
    expect(policy['required_start'], 1);
    expect(policy['required_end'], 16);
    expect(tester.widget<TextFormField>(count).controller!.text, '16');
    expect(
      find.text('16 reports required \u00b7 Weeks 1\u201316'),
      findsOneWidget,
    );
    expect(weeklySettingsError(policy, template), isNull);

    await tester.enterText(count, '');
    await tester.pump();
    expect(find.text('Enter a number from 1 to 53.'), findsOneWidget);
    expect(find.byKey(const ValueKey('weekly-range-summary')), findsNothing);
    await tester.enterText(count, '8');
    await tester.pump();
    expect(policy['required_end'], 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved week numbering survives the simplified report-count form',
    (tester) async {
      var policy = {
        ..._policy,
        'total_weeks': 16,
        'required_start': 5,
        'required_end': 8,
      };
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, update) => StageWeeklySettings(
              value: policy,
              template: weeklyTemplateDraft(null),
              enabled: true,
              onChanged: (value) => update(() => policy = value),
              onTemplateChanged: () {},
            ),
          ),
        ),
        overrides: authTestOverrides(),
      );
      final count = find.byKey(const ValueKey('weekly-report_count'));
      final first = find.byKey(const ValueKey('weekly-required_start'));
      expect(
        find.text('4 reports required \u00b7 Weeks 5\u20138'),
        findsOneWidget,
      );
      expect(first, findsNothing);
      expect(find.text('More options'), findsNothing);
      expect(find.text('Fewer options'), findsNothing);
      await tester.enterText(count, '6');
      await tester.pump();
      expect(policy['required_start'], 5);
      expect(policy['required_end'], 10);
      expect(policy['total_weeks'], 16);
      expect(
        find.text('6 reports required \u00b7 Weeks 5\u201310'),
        findsOneWidget,
      );
      expect(policy['total_weeks'], 16);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a report count cannot silently resize an existing shared calendar',
    (tester) async {
      var policy = Map<String, dynamic>.from(_policy);
      final template = weeklyTemplateDraft(null)
        ..['template'] = {'original_name': 'Weekly.docx'};
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, update) => StageWeeklySettings(
              value: policy,
              template: template,
              enabled: true,
              onChanged: (value) => update(() => policy = value),
              onTemplateChanged: () {},
            ),
          ),
        ),
        overrides: authTestOverrides(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('weekly-report_count')),
        '8',
      );
      await tester.pump();
      expect(policy['total_weeks'], 3);
      expect(
        find.text('This saved schedule supports up to 3 reports.'),
        findsOneWidget,
      );
      expect(weeklySettingsError(policy, template), isNotNull);
      expect(find.byKey(const ValueKey('weekly-range-summary')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new stages inherit a one-week calendar with flexible template guidance',
    (tester) async {
      var policy = initialWeeklySettings(null, [
        {
          'weekly_reporting': {..._policy, 'total_weeks': 1, 'required_end': 1},
        },
      ]);
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, update) => StageWeeklySettings(
              value: policy,
              template: weeklyTemplateDraft(null),
              enabled: true,
              onChanged: (value) => update(() => policy = value),
              onTemplateChanged: () {},
            ),
          ),
        ),
        overrides: authTestOverrides(),
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(policy['enabled'], isTrue);
      expect(policy['total_weeks'], 1);
      expect(policy['required_start'], 1);
      expect(policy['required_end'], 1);
      expect(find.text('1 report required \u00b7 Week 1'), findsOneWidget);
      expect(
        find.text('Word document (.docx) \u00b7 Up to 20 MB'),
        findsNothing,
      );
      expect(find.textContaining('Documents, media or ZIP'), findsOneWidget);
      expect(find.textContaining('Report template'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date and time pickers keep readable values and API date formats',
    (tester) async {
      await loadPreviewFonts();
      var policy = Map<String, dynamic>.from(_policy);
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, update) => StageWeeklySettings(
              value: policy,
              template: weeklyTemplateDraft(null),
              enabled: true,
              onChanged: (value) => update(() => policy = value),
              onTemplateChanged: () {},
            ),
          ),
        ),
        overrides: authTestOverrides(),
      );
      await tester.tap(find.byKey(const ValueKey('weekly-starts_on')));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(DatePickerDialog),
        'weekly-calendar-picker-light',
        viewport: true,
      );
      await tester.tap(find.text('15'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(policy['starts_on'], '2026-01-15');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('weekly-starts_on')),
            )
            .controller!
            .text,
        '15 Jan 2026',
      );

      await tester.tap(find.byKey(const ValueKey('weekly-due_time')));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(TimePickerDialog),
        'weekly-clock-picker-light',
        viewport: true,
      );
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final inputs = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(inputs.first, '9');
      await tester.enterText(inputs.last, '30');
      await tester.tap(find.text('AM'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(policy['due_time'], '09:30');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('weekly-due_time')),
            )
            .controller!
            .text,
        '9:30 AM',
      );
      expect(find.text('9:30 AM · Philippine time'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [390.0, 1280.0]) {
      testWidgets('policy and one deliverable row fit $width dark=$dark', (
        tester,
      ) async {
        await loadPreviewFonts();
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var policy = Map<String, dynamic>.from(_policy);
        final template = weeklyTemplateDraft(null)
          ..['template'] = {
            'original_name': 'Weekly.pdf',
            'byte_size': 2048,
            'file_url': '/template.pdf',
          };
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: const ValueKey('weekly-policy-capture'),
              child: StatefulBuilder(
                builder: (context, update) => StageWeeklySettings(
                  value: policy,
                  template: template,
                  enabled: true,
                  onChanged: (value) => update(() => policy = value),
                  onTemplateChanged: () {},
                ),
              ),
            ),
          ),
          overrides: authTestOverrides(),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(find.text('Weekly reports required'), findsOneWidget);
        expect(find.text('Week 1 starts on'), findsOneWidget);
        for (final removed in [
          'More options',
          'Fewer options',
          'Start with week',
          'Weeks in the semester calendar',
        ]) {
          expect(find.text(removed), findsNothing);
        }
        expect(
          find.textContaining('Uses the shared semester calendar'),
          findsNothing,
        );
        expect(find.text('Schedule preview'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('weekly-policy-capture')),
          'weekly-policy-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );

        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('weekly-table-capture'),
            child: Material(
              color: dark
                  ? AppTheme.mistDarkTheme.scaffoldBackgroundColor
                  : AppTheme.theme.scaffoldBackgroundColor,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: FacultyRequirementsPane(
                  items: [_collection()],
                  buildRequirement: (_) =>
                      const Text('Weekly collection details'),
                ),
              ),
            ),
          ),
          overrides: authTestOverrides(),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(find.text('Weekly Accomplishment Reports'), findsOneWidget);
        expect(find.text('1 deliverables'), findsOneWidget);
        expect(find.text('Week 1'), findsNothing);
        expect(find.text('Before endorsement'), findsOneWidget);
        if (width > 600) {
          for (final label in [
            'Deliverable',
            'Timing',
            'Uploaded',
            'Status',
            'Action',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
        }
        await capturePreview(
          tester,
          find.byKey(const ValueKey('weekly-table-capture')),
          'weekly-table-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
        await tester.tap(find.text('Weekly Accomplishment Reports'));
        await tester.pumpAndSettle();
        expect(find.text('Weekly collection details'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('weekly collection details fit $width dark=$dark', (
        tester,
      ) async {
        await loadPreviewFonts();
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        setApiHttpClientForTesting(
          MockClient(
            (request) async => http.Response(jsonEncode(_collection()), 200),
          ),
        );
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('weekly-details-capture'),
            child: Material(
              color: dark
                  ? AppTheme.mistDarkTheme.scaffoldBackgroundColor
                  : AppTheme.theme.scaffoldBackgroundColor,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: WeeklyReportCollection(
                  teamId: 8,
                  stageLabel: 'Proposal',
                  item: _collection(),
                ),
              ),
            ),
          ),
          overrides: [authProvider.overrideWith(() => _RoleAuth('faculty'))],
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(find.text('Accept'), findsOneWidget);
        expect(find.text('View PDF'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('weekly-details-capture')),
          'weekly-details-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
      });
    }
  }

  testWidgets(
    'adviser accepts the current PDF version without a saved e-signature',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Map? decision;
      final notifier = _Deliverables();
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(_collection()), 200);
          }
          decision = jsonDecode(request.body) as Map;
          return http.Response(
            jsonEncode({'collection': _collection(accepted: true)}),
            200,
          );
        }),
      );
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: WeeklyReportCollection(
            teamId: 8,
            stageLabel: 'Proposal',
            item: _collection(),
          ),
        ),
        overrides: [
          authProvider.overrideWith(() => _RoleAuth('faculty')),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      expect(find.text('Week 1'), findsOneWidget);
      expect(find.text('Week-3.pdf'), findsNothing);
      expect(find.text('Accept'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.textContaining('physical adviser signature'), findsOneWidget);
      await tester.tap(find.text('Accept report'));
      await tester.pumpAndSettle();
      expect(decision?['version_id'], 12);
      expect(decision?['status'], 'accepted');
      expect(find.text('2/2 accepted'), findsOneWidget);
      expect(find.text('Late'), findsNWidgets(2));
      expect(notifier.responses, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'batch upload preserves successes and retries only failed weeks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final previousPicker = FilePicker.platform;
      FilePicker.platform = _PdfPicker();
      addTearDown(() => FilePicker.platform = previousPicker);
      final posted = <String>[];
      final notifier = _Deliverables();
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(_collection(student: true)), 200);
          }
          posted.add(request.body);
          if (posted.length == 2) {
            return http.Response('{"detail":"Please retry Week 3."}', 400);
          }
          return http.Response(
            jsonEncode({'collection': _collection(student: true)}),
            201,
          );
        }),
      );
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: WeeklyReportCollection(
            teamId: 8,
            stageLabel: 'Proposal',
            item: _collection(student: true),
          ),
        ),
        overrides: [
          authProvider.overrideWith(() => _RoleAuth('student')),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      await tester.tap(find.text('Upload PDFs'));
      await tester.pumpAndSettle();
      expect(find.text('Week-2.pdf'), findsWidgets);
      await tester.tap(find.text('Upload reports'));
      await tester.pumpAndSettle();
      expect(posted, hasLength(2));
      expect(find.text('Uploaded'), findsOneWidget);
      expect(find.textContaining('Please retry Week 3'), findsOneWidget);
      await tester.tap(find.text('Retry remaining'));
      await tester.pumpAndSettle();
      expect(posted, hasLength(3));
      expect(posted[0], contains('Week-2.pdf'));
      expect(posted[1], contains('Week-3.pdf'));
      expect(posted[2], contains('Week-3.pdf'));
      expect(find.text('Uploaded'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
