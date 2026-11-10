import 'package:defensys/screens/web/admin/grade_center/grade_center_screen.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/grade_center_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '../helpers/capture_preview.dart';

class _Admin extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isRestoring: false, user: {'id': 1, 'role': 'admin'});
}

class _Stages extends DefenseStagesNotifier {
  @override
  DefenseStagesState build() => const DefenseStagesState(
    stages: [
      {'id': 34},
    ],
  );
}

class _Grades extends GradeCenterNotifier {
  @override
  GradeCenterState build() => const GradeCenterState(
    scope: 'capstone',
    activeSemester: {
      'id': 14,
      'is_active': true,
      'display_name': '1st Semester, A.Y. 2026-2027',
    },
    counts: {'filtered': 0},
    phaseStatistics: {
      'total_teams': 1,
      'fully_graded_teams': 0,
      'awaiting_panelists': 0,
    },
    capstoneWorkspace: {
      'view': 'ongoing',
      'batch_id': '12',
      'phase_semester_id': 14,
      'read_only': false,
      'batches': [
        {'value': '12', 'label': '2nd Semester, A.Y. 2025-2026'},
      ],
    },
    capstonePhases: [
      {
        'semester_id': 12,
        'phase_label': 'Capstone 1',
        'stage_count': 1,
        'read_only': true,
        'payload': {
          'active_semester': {
            'id': 12,
            'is_active': false,
            'display_name': '2nd Semester, A.Y. 2025-2026',
          },
          'grades': [
            {
              'id': 1,
              'team_id': 7,
              'scope': 'capstone',
              'stage_label': 'Project',
              'status': 'published',
              'verdict': 'approved',
            },
          ],
          'capstone_stages': [
            {
              'id': 34,
              'label': 'Project',
              'display_order': 1,
              'is_active': true,
            },
          ],
          'group_settings': {
            'capstone|Project': {
              'defense_stage_id': 34,
              'is_officially_complete': true,
            },
          },
          'counts': {'filtered': 1, 'published': 1},
        },
      },
      {
        'semester_id': 14,
        'phase_label': 'Capstone 2',
        'stage_count': 0,
        'read_only': false,
        'payload': {
          'active_semester': {
            'id': 14,
            'is_active': true,
            'display_name': '1st Semester, A.Y. 2026-2027',
          },
          'grades': [],
          'capstone_stages': [],
          'group_settings': {},
          'counts': {'filtered': 0},
        },
      },
    ],
  );
  @override
  Future<void> fetchGrades({
    String? historySemester,
    String? search,
    String? yearLevel,
    String? status,
    String? scope,
    String? successMessage,
  }) async {}
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  for (final width in [390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'grade phases remain sequential and source actions are read-only $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Uri? opened;
          final router = GoRouter(
            initialLocation: '/admin/grade-center',
            routes: [
              GoRoute(
                path: '/admin/grade-center',
                builder: (_, _) => const Scaffold(body: GradeCenterScreen()),
              ),
              GoRoute(
                path: '/admin/grade-center/events/:key',
                builder: (_, state) {
                  opened = state.uri;
                  return Scaffold(body: Text(state.uri.query));
                },
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                authProvider.overrideWith(_Admin.new),
                gradeCenterProvider.overrideWith(_Grades.new),
                defenseStagesProvider.overrideWith(_Stages.new),
              ],
              child: MaterialApp.router(
                routerConfig: router,
                theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final source = find.byKey(const ValueKey('grade-phase-12'));
          final current = find.byKey(const ValueKey('grade-phase-14'));
          expect(source, findsOneWidget);
          expect(current, findsOneWidget);
          expect(
            tester.getTopLeft(source).dy,
            lessThan(tester.getTopLeft(current).dy),
          );
          expect(
            find.descendant(of: source, matching: find.text('Reopen Stage')),
            findsNothing,
          );
          expect(
            find.descendant(of: source, matching: find.text('Mark Complete')),
            findsNothing,
          );
          expect(
            find.textContaining('Earlier phases remain available'),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('capstone-phase-12')), findsNothing);
          await capturePreview(
            tester,
            find.byType(GradeCenterScreen),
            'grade-phase-sequence-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          if (width < 700) {
            await tester.ensureVisible(
              find.descendant(of: source, matching: find.text('Project')),
            );
            await tester.pumpAndSettle();
            await capturePreview(
              tester,
              source,
              'grade-phase-source-${width.toInt()}-${dark ? 'dark' : 'light'}',
              viewport: true,
            );
          }
          expect(tester.takeException(), isNull);
          if (width > 1000) {
            await tester.tap(
              find.descendant(of: source, matching: find.text('Open grades')),
            );
            await tester.pumpAndSettle();
            final query = opened!.queryParameters;
            expect(query['semester_id'], '12');
            expect(query['defense_stage_id'], '34');
            expect(query['batch_id'], '12');
          }
        },
      );
    }
  }
}
