import 'dart:convert';
import 'dart:typed_data';

import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_weekly_settings.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/faculty_requirements_pane.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/deliverable_template.dart';
import 'package:defensys/widgets/repository/requirement_summary.dart';
import 'package:defensys/widgets/repository/weekly_report_collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';
import '../helpers/file_picker.dart';

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
        'starts_on': DateTime(
          2026,
          1,
          5 + (i - 1) * 7,
        ).toIso8601String().substring(0, 10),
        'ends_on': DateTime(
          2026,
          1,
          11 + (i - 1) * 7,
        ).toIso8601String().substring(0, 10),
        'due_at': DateTime.utc(
          2026,
          1,
          11 + (i - 1) * 7,
          15,
          59,
        ).toIso8601String(),
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
  testWidgets(
    'compact weekly settings keep the schedule when opened and closed',
    (tester) async {
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
          child: StatefulBuilder(
            builder: (context, update) => StageWeeklySettings(
              compact: true,
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
      expect(find.textContaining('Every Sunday, 11:59 PM'), findsOneWidget);
      expect(find.byKey(const ValueKey('weekly-report_count')), findsNothing);
      final expansion = find.byKey(const ValueKey('configure-weekly-reports'));
      await tester.tap(expansion);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('weekly-report_count')),
        '3',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('weekly-due-weekday-6')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monday').last);
      await tester.pumpAndSettle();
      expect(policy['due_weekday'], 0);
      expect(find.text('Mon, 5 Jan 2026'), findsOneWidget);
      await tester.ensureVisible(expansion);
      await tester.tap(expansion);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('weekly-report_count')), findsNothing);
      expect(find.textContaining('3 reports'), findsOneWidget);
      expect(find.textContaining('Every Monday'), findsOneWidget);
      expect(policy['enabled'], isTrue);
      await tester.tap(expansion);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadInput>(
              find.byKey(const ValueKey('weekly-report_count')),
            )
            .controller
            ?.text,
        '3',
      );
      expect(policy['required_end'], 3);
      expect(tester.takeException(), isNull);
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = _PdfPicker();
  });
  tearDown(resetApiHttpClientForTesting);

  test(
    'reopened weekly setup restores its saved template and draft actions',
    () {
      final attachment = {
        'id': 41,
        'original_name': 'Weekly.pdf',
        'file_url': '/weekly-template.pdf',
      };
      for (final action in [null, 'replace', 'remove']) {
        final stage = <String, dynamic>{
          'weekly_template': {
            if (action != null) 'template_action': action,
            if (action == 'replace')
              'template_selection_name': 'Replacement.docx',
          },
          'system_deliverables': [
            {'source': 'weekly_reports', 'template': attachment},
          ],
        };
        final draft = weeklyTemplateDraft(stage);
        expect(draft['template'], attachment);
        expect(draft['template_action'], action);
        expect(draft['deliverable_id'], 'WPR');
        if (action == null) expect(weeklySettingsError(_policy, draft), isNull);
        if (action == 'replace') {
          expect(draft['template_selection_name'], 'Replacement.docx');
          expect(weeklySettingsError(_policy, draft), contains('again'));
        }
        if (action == 'remove') {
          expect(
            weeklySettingsError(_policy, draft),
            contains('Attach a weekly'),
          );
        }
      }
    },
  );

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
    expect(policy['total_weeks'], 1);
    expect(find.text('1 report required \u00b7 Week 1'), findsOneWidget);
    expect(find.text('Report due'), findsOneWidget);
    expect(find.text('Last report due'), findsNothing);
    expect(find.text('Sun, 11 Jan 2026'), findsOneWidget);
    expect(find.text('11:59 PM'), findsNWidgets(2));
    expect(weeklySettingsError(policy, template), isNull);

    await tester.enterText(count, '16');
    await tester.pump();
    expect(policy['required_start'], 1);
    expect(policy['required_end'], 16);
    expect(policy['total_weeks'], 16);
    expect(tester.widget<ShadInput>(count).controller!.text, '16');
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
    expect(policy['total_weeks'], 8);
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
      expect(policy['total_weeks'], 10);
      expect(
        find.text('6 reports required \u00b7 Weeks 5\u201310'),
        findsOneWidget,
      );
      expect(policy['total_weeks'], 10);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stage report count updates its own calendar without changing its dates',
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
      expect(policy['total_weeks'], 8);
      expect(policy['required_end'], 8);
      expect(policy['starts_on'], _policy['starts_on']);
      expect(policy['due_weekday'], _policy['due_weekday']);
      expect(policy['due_time'], _policy['due_time']);
      expect(weeklySettingsError(policy, template), isNull);
      expect(
        find.byKey(const ValueKey('weekly-range-summary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new stages start without another stages calendar identity or dates',
    (tester) async {
      var policy = initialWeeklySettings(null);
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
      await tester.tap(find.byKey(const ValueKey('weekly-report-switch')));
      await tester.pump();
      expect(policy['enabled'], isTrue);
      expect(policy['total_weeks'], '');
      expect(policy['period_id'], isNull);
      expect(policy['starts_on'], isNull);
      expect(initialWeeklySettings(_policy)['period_id'], _policy['period_id']);
      expect(policy['required_start'], 1);
      expect(policy['required_end'], '');
      final count = find.byKey(const ValueKey('weekly-report_count'));
      expect(tester.widget<ShadInput>(count).controller!.text, isEmpty);
      expect(find.text('1 report required \u00b7 Week 1'), findsNothing);
      await tester.enterText(count, '1');
      await tester.pump();
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
    'fresh weekly reporting has no automatic report or calendar count',
    (tester) async {
      var policy = initialWeeklySettings(null);
      final template = weeklyTemplateDraft(null)
        ..['template'] = {'original_name': 'Weekly.pdf'};
      expect(policy['total_weeks'], isNull);
      expect(policy['required_end'], '');
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
      await tester.tap(find.byKey(const ValueKey('weekly-report-switch')));
      await tester.pump();
      final count = find.byKey(const ValueKey('weekly-report_count'));
      expect(tester.widget<ShadInput>(count).controller!.text, isEmpty);
      expect(weeklySettingsError(policy, template), isNotNull);
      for (final reports in [2, 1, 20]) {
        await tester.enterText(count, '$reports');
        await tester.pump();
        expect(policy['required_end'], reports);
        expect(policy['total_weeks'], reports);
      }
      await tester.enterText(count, '');
      await tester.pump();
      expect(policy['required_end'], '');
      expect(policy['total_weeks'], '');
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
        find.descendant(
          of: find.byKey(const ValueKey('weekly-starts_on')),
          matching: find.text('15 Jan 2026'),
        ),
        findsOneWidget,
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
        find.descendant(
          of: find.byKey(const ValueKey('weekly-due_time')),
          matching: find.text('9:30 AM'),
        ),
        findsOneWidget,
      );
      expect(find.text('9:30 AM'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 900.0, 1280.0]) {
      testWidgets('policy and one deliverable row fit $width dark=$dark', (
        tester,
      ) async {
        await loadPreviewFonts(force: true);
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
                  compact: true,
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
        await tester.tap(
          find.byKey(const ValueKey('configure-weekly-reports')),
        );
        await tester.pumpAndSettle();
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
        final fields = tester.getRect(
          find.byKey(const ValueKey('weekly-schedule-fields')),
        );
        final preview = tester.getRect(
          find.byKey(const ValueKey('weekly-schedule-preview')),
        );
        final templateRect = tester.getRect(
          find.byType(DeliverableTemplateEditor),
        );
        if (width > 600) {
          expect(preview.left, greaterThan(fields.right));
          expect(preview.top, fields.top);
        } else {
          expect(preview.top, greaterThan(fields.bottom));
        }
        expect(templateRect.top, greaterThan(preview.bottom));
        expect(templateRect.top, greaterThan(fields.bottom));
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
        await loadPreviewFonts(force: true);
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
        expect(find.text('2 reports required'), findsOneWidget);
        expect(find.text('Proposal · Weeks 1–2'), findsOneWidget);
        expect(find.byType(ShadSelect<bool>), findsNothing);
        expect(find.text('Week-3.pdf'), findsNothing);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('weekly-details-capture')),
          'weekly-details-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
      });
    }
  }

  for (final start in [1, 5]) {
    for (final role in ['faculty', 'student']) {
      testWidgets('$role sees only the two required weeks starting at $start', (
        tester,
      ) async {
        final narrow = start == 5;
        final size = Size(narrow ? 320 : 1280, 1100);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await loadPreviewFonts(force: true);
        final data = _collection()
          ..['template'] = {
            'original_name': 'Weekly-template.pdf',
            'file_url': '/weekly-template.pdf',
          }
          ..['weekly_summary'] = {
            'required': 2,
            'uploaded': 0,
            'accepted': 0,
            'pending': 0,
            'missing': 2,
            'rejected': 0,
            'late': 0,
            'overdue': 0,
          }
          ..['weeks'] = [
            for (var week = 1; week <= 16; week++)
              {
                'week_number': week,
                'required': week >= start && week < start + 2,
                'starts_on': DateTime(
                  2026,
                  10,
                  25,
                ).add(Duration(days: (week - 1) * 7)).toIso8601String(),
                'ends_on': DateTime(
                  2026,
                  10,
                  31,
                ).add(Duration(days: (week - 1) * 7)).toIso8601String(),
                'due_at': DateTime.utc(
                  2026,
                  10,
                  25,
                  15,
                  59,
                ).add(Duration(days: (week - 1) * 7)).toIso8601String(),
                'status': 'missing',
                'timing': 'upcoming',
                'can_upload': role == 'student',
                'can_review': false,
              },
          ];
        setApiHttpClientForTesting(
          MockClient((_) async => http.Response(jsonEncode(data), 200)),
        );
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('weekly-stage-scope-capture'),
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(narrow ? 1.25 : 1),
              ),
              child: Material(
                color: AppTheme.theme.scaffoldBackgroundColor,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: WeeklyReportCollection(
                    teamId: 8,
                    stageLabel: 'Concept Proposal',
                    item: data,
                  ),
                ),
              ),
            ),
          ),
          overrides: [authProvider.overrideWith(() => _RoleAuth(role))],
        );
        final overview = role == 'faculty' ? findsOneWidget : findsNothing;
        expect(find.text('2 reports required'), overview);
        expect(find.text('0/2 accepted'), overview);
        expect(
          find.text('Concept Proposal · Weeks $start–${start + 1}'),
          overview,
        );
        expect(find.text('Upcoming'), findsNWidgets(2));
        expect(find.text('Week $start'), findsOneWidget);
        expect(find.text('Week ${start + 1}'), findsOneWidget);
        expect(find.text('Week ${start + 2}'), findsNothing);
        expect(find.text('Week 16'), findsNothing);
        expect(find.byType(ShadSelect<bool>), findsNothing);
        expect(find.text('All reporting weeks'), findsNothing);
        expect(find.byType(ShadSwitch), findsNothing);
        expect(
          find.text('Download template'),
          role == 'student' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('weekly-stage-scope-capture')),
          'weekly-stage-scope-$role-${size.width.toInt()}',
        );
        if (role == 'student') {
          final upload = find.widgetWithText(ShadButton, 'Upload').first;
          await tester.ensureVisible(upload);
          await tester.tap(upload);
          await tester.pumpAndSettle();
          final pickers = tester.widgetList<ShadSelect<int>>(
            find.byType(ShadSelect<int>),
          );
          expect(pickers, hasLength(2));
          for (final picker in pickers) {
            expect(
              picker.options!.whereType<ShadOption<int>>().map(
                (option) => option.value,
              ),
              orderedEquals([start, start + 1]),
            );
          }
          expect(tester.takeException(), isNull);
        }
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

  for (final status in ['missing', 'pending', 'rejected']) {
    testWidgets('a $status week uploads directly to the clicked week', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final picker = TestFilePicker()
        ..result = FilePickerResult([
          PlatformFile(
            name: 'Week-99.pdf',
            size: 9,
            bytes: Uint8List.fromList(utf8.encode('%PDF-test')),
          ),
        ]);
      FilePicker.platform = picker;
      final data = _collection(student: true);
      final week = (data['weeks'] as List).first as Map;
      week['can_upload'] = true;
      week['status'] = status;
      if (status == 'missing') week.remove('file');
      final notifier = _Deliverables();
      final posted = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(data), 200);
          }
          posted.add(request.body);
          week['status'] = 'pending';
          week['file'] = {
            'id': 21,
            'revision': 2,
            'file_name': 'Week-99.pdf',
            'file_url': '/weekly/1.pdf',
            'uploaded_at': '2026-02-01T10:00:00+08:00',
          };
          return http.Response(jsonEncode({'collection': data}), 201);
        }),
      );
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: WeeklyReportCollection(
            teamId: 8,
            stageLabel: 'Proposal',
            semesterId: 4,
            projectVersion: 2,
            item: data,
          ),
        ),
        overrides: [
          authProvider.overrideWith(() => _RoleAuth('student')),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      final button = status == 'missing'
          ? find.widgetWithText(ShadButton, 'Upload').first
          : status == 'pending'
          ? find.text('Submit new version').first
          : find.text('Upload revision');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(picker.extensions, ['pdf']);
      expect(posted, hasLength(1));
      expect(posted.single, contains('name="week_number"\r\n\r\n1'));
      expect(posted.single, contains('name="team_id"\r\n\r\n8'));
      expect(posted.single, contains('name="semester_id"\r\n\r\n4'));
      expect(posted.single, contains('name="project_version"\r\n\r\n2'));
      expect(posted.single, contains('Week-99.pdf'));
      expect(find.text('Upload weekly reports'), findsNothing);
      expect(find.byType(ShadSelect<int>), findsNothing);
      expect(find.text('Upload reports'), findsNothing);
      expect(find.text('Week-99.pdf'), findsOneWidget);
      expect(notifier.responses, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('weekly picker cancel and upload failure allow a direct retry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final picker = TestFilePicker();
    FilePicker.platform = picker;
    final data = _collection(student: true);
    final posted = <String>[];
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(data), 200);
        }
        posted.add(request.body);
        return posted.length == 1
            ? http.Response('{"detail":"Please retry this report."}', 400)
            : http.Response(jsonEncode({'collection': data}), 201);
      }),
    );
    final notifier = _Deliverables();
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: WeeklyReportCollection(
          teamId: 8,
          stageLabel: 'Proposal',
          item: data,
        ),
      ),
      overrides: [
        authProvider.overrideWith(() => _RoleAuth('student')),
        capstoneDeliverablesProvider.overrideWith(() => notifier),
      ],
    );
    await tester.tap(find.text('Submit new version').first);
    await tester.pumpAndSettle();
    expect(posted, isEmpty);
    picker.result = FilePickerResult([
      PlatformFile(name: 'Wrong.docx', size: 3, bytes: Uint8List(3)),
    ]);
    await tester.tap(find.text('Submit new version').first);
    await tester.pumpAndSettle();
    expect(posted, isEmpty);
    expect(find.textContaining('non-empty PDF'), findsOneWidget);
    picker.result = FilePickerResult([
      PlatformFile(
        name: 'Signed.pdf',
        size: 9,
        bytes: Uint8List.fromList(utf8.encode('%PDF-test')),
      ),
    ]);
    await tester.tap(find.text('Submit new version').first);
    await tester.pumpAndSettle();
    expect(posted, hasLength(1));
    expect(find.textContaining('Please retry this report.'), findsOneWidget);
    expect(find.text('Upload reports'), findsNothing);
    await tester.tap(find.text('Submit new version').first);
    await tester.pumpAndSettle();
    expect(posted, hasLength(2));
    expect(posted.last, contains('name="week_number"\r\n\r\n2'));
    expect(find.textContaining('Please retry this report.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
      // Both selected PDFs belong to this stage's three required weeks.
      final collection = _collection(student: true)
        ..['weekly_reporting'] = {..._policy, 'required_end': 3};
      for (final week in collection['weeks'] as List) {
        week['required'] = true;
      }
      (collection['weekly_summary'] as Map).addAll(<String, int>{
        'required': 3,
        'uploaded': 3,
        'pending': 2,
        'late': 3,
      });
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(collection), 200);
          }
          posted.add(request.body);
          if (posted.length == 2) {
            return http.Response('{"detail":"Please retry Week 3."}', 400);
          }
          return http.Response(jsonEncode({'collection': collection}), 201);
        }),
      );
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: WeeklyReportCollection(
            teamId: 8,
            stageLabel: 'Proposal',
            item: collection,
          ),
        ),
        overrides: [
          authProvider.overrideWith(() => _RoleAuth('student')),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      expect(find.text('Upload PDFs'), findsNothing);
      await tester.tap(find.text('Submit new version').first);
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
