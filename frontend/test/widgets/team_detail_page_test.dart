import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:defensys/screens/web/admin/team_detail_page.dart';
import 'package:defensys/services/team_detail_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/proposal_title_summary.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _FakeTeamDetailNotifier extends TeamDetailNotifier {
  _FakeTeamDetailNotifier() : super(1);

  @override
  TeamDetailState build() {
    return TeamDetailState(
      team: {
        'id': 1,
        'name': 'Team CodeLearners',
        'project_title': 'Smart Campus Navigator',
        'year_level': '3rd Year',
        'level': '3rd Year Capstone',
        'status': 'Pending',
        'member_ids': [10, 11],
        'leader_id': 10,
      },
      students: [
        {'id': 10, 'name': 'Carlos Reyes', 'username': '4081'},
        {'id': 11, 'name': 'Maria Santos', 'username': '4082'},
      ],
      statuses: const ['Pending', 'Approved'],
    );
  }

  @override
  Future<void> load() async {}
}

void main() {
  for (final width in [1440.0, 650.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Overview presents imported and pending proposals inside the project card at $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadPreviewFonts(force: true);
          await pumpDefensysWidget(
            tester,
            TeamDetailPage(
              teamId: 1,
              canManage: false,
              isPitLead: false,
              onBack: () {},
            ),
            overrides: [
              teamDetailProvider(
                1,
              ).overrideWith(_FakeProposalTeamDetailNotifier.new),
            ],
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          );
          final card = find.byKey(
            const ValueKey('team-project-information-card'),
          );
          expect(
            find.descendant(of: card, matching: find.text('Concept proposals')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: card,
              matching: find.text('Smart Campus Navigator'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: card, matching: find.text('Pending proposal')),
            findsNWidgets(2),
          );
          expect(
            find.descendant(
              of: card,
              matching: find.byType(ProposalTitleProgressBadge),
            ),
            findsOneWidget,
          );
          expect(find.text('Smart Campus Navigator'), findsOneWidget);
          expect(
            find.text('Concept selection · 1 of 3 titles provided'),
            findsOneWidget,
          );
          expect(find.text('1 of 3 titles provided'), findsOneWidget);
          expect(find.byType(EditableText), findsNothing);
          await capturePreview(
            tester,
            card,
            'team-overview-concepts-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('approved concept retains the selected project presentation', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      TeamDetailPage(
        teamId: 1,
        canManage: false,
        isPitLead: false,
        onBack: () {},
      ),
      overrides: [
        teamDetailProvider(
          1,
        ).overrideWith(() => _FakeProposalTeamDetailNotifier(approved: true)),
      ],
    );
    expect(find.text('Smart Campus Navigator'), findsNWidgets(2));
    expect(find.byType(ProposalTitleSummary), findsNothing);
    expect(find.text('Concept proposals'), findsNothing);
  });

  testWidgets('TeamDetailPage opens in read-only view with Edit team button', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 1200,
        height: 800,
        child: TeamDetailPage(
          teamId: 1,
          canManage: true,
          isPitLead: false,
          onBack: () {},
        ),
      ),
      overrides: [
        teamDetailProvider(1).overrideWith(_FakeTeamDetailNotifier.new),
      ],
    );

    expect(find.text('Team CodeLearners'), findsWidgets);
    expect(find.text('Edit team'), findsOneWidget);
    expect(find.text('Save Changes'), findsNothing);

    await tester.tap(find.text('Edit team'));
    await tester.pumpAndSettle();

    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('TeamDetailPage shows overview tabs', (tester) async {
    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 1200,
        height: 800,
        child: TeamDetailPage(
          teamId: 1,
          canManage: false,
          isPitLead: false,
          onBack: () {},
        ),
      ),
      overrides: [
        teamDetailProvider(1).overrideWith(_FakeTeamDetailNotifier.new),
      ],
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Weekly Reports'), findsOneWidget);
    expect(find.text('Deliverables'), findsOneWidget);
    expect(find.text('Team Documents'), findsOneWidget);
    expect(find.text('ACADEMIC PROGRESS'), findsOneWidget);
  });

  testWidgets('TeamDetailPage shows PIT overview tabs', (tester) async {
    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 1200,
        height: 800,
        child: TeamDetailPage(
          teamId: 1,
          canManage: false,
          isPitLead: false,
          onBack: () {},
        ),
      ),
      overrides: [
        teamDetailProvider(1).overrideWith(_FakePitTeamDetailNotifier.new),
      ],
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Grades & Events'), findsOneWidget);
    expect(find.text('Deliverables'), findsOneWidget);
    expect(find.text('Weekly Reports'), findsNothing);
    expect(find.text('Team Documents'), findsNothing);
    expect(find.text('Elena Reyes'), findsOneWidget);
    expect(find.text('View instructor details'), findsNothing);
  });

  testWidgets(
    'TeamDetailPage Deliverables tab only shows 1st year events for 1st year PIT team',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 1200,
          height: 800,
          child: TeamDetailPage(
            teamId: 2,
            canManage: false,
            isPitLead: false,
            onBack: () {},
          ),
        ),
        overrides: [
          teamDetailProvider(
            2,
          ).overrideWith(_FakeFirstYearPitTeamDetailNotifier.new),
        ],
      );

      // Switch to Deliverables tab
      await tester.tap(find.text('Deliverables'));
      await tester.pumpAndSettle();

      expect(find.text('1st Year Concept Pitch'), findsWidgets);
      expect(find.text('2nd Year Architecture Pitch'), findsNothing);
    },
  );

  for (final role in ['admin', 'faculty']) {
    testWidgets(
      'team summary opens the $role evaluation with finalized grades locked',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/$role/student-teams/1',
          routes: [
            GoRoute(
              path: '/$role/student-teams/1',
              builder: (_, _) => TeamDetailPage(
                teamId: 1,
                canManage: false,
                isPitLead: role == 'faculty',
                onBack: () {},
              ),
            ),
            GoRoute(
              path: '/$role/grade-center/grades/:id',
              builder: (_, state) => Scaffold(
                body: Text(
                  'Evaluation ${state.pathParameters['id']} locked=${state.uri.queryParameters['locked']}',
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await pumpDefensysWidget(
          tester,
          MaterialApp.router(routerConfig: router),
          overrides: [
            teamDetailProvider(
              1,
            ).overrideWith(_FakeGradedTeamDetailNotifier.new),
          ],
        );
        await tester.ensureVisible(find.text('View evaluation details'));
        await tester.tap(find.text('View evaluation details'));
        await tester.pumpAndSettle();
        expect(find.text('Evaluation 7 locked=1'), findsOneWidget);
        expect(router.state.uri.queryParameters['fromTeam'], '1');
        // Cross-section navigation switches branches rather than pushing onto
        // the team page. The evaluation route owns the explicit return link.
        router.go('/$role/student-teams/1');
        await tester.pumpAndSettle();
        expect(find.text('ACADEMIC PROGRESS'), findsOneWidget);
      },
    );
  }
}

class _FakeProposalTeamDetailNotifier extends _FakeTeamDetailNotifier {
  _FakeProposalTeamDetailNotifier({this.approved = false});
  final bool approved;

  @override
  TeamDetailState build() {
    final original = super.build();
    return original.copyWith(
      team: {
        ...original.team!,
        'project_pending': false,
        'defense_context': {
          'current_stage': 'Concept Proposal',
          'concept_workflow': {
            'enabled': true,
            'status': approved ? 'approved' : 'concepts_needed',
            'concepts': [
              for (var i = 1; i <= 3; i++)
                {'key': 'c$i', 'title': i == 1 ? 'Smart Campus Navigator' : ''},
            ],
          },
        },
      },
    );
  }
}

class _FakeGradedTeamDetailNotifier extends _FakeTeamDetailNotifier {
  @override
  TeamDetailState build() => super.build().copyWith(
    grades: const [
      {
        'id': 7,
        'stage_label': 'Concept Proposal',
        'final_grade': '89.25',
        'is_officially_complete': true,
        'status': 'published',
        'verdict': 'approved',
      },
    ],
  );
}

class _FakeFirstYearPitTeamDetailNotifier extends TeamDetailNotifier {
  _FakeFirstYearPitTeamDetailNotifier() : super(2);

  @override
  TeamDetailState build() {
    return TeamDetailState(
      team: {
        'id': 2,
        'name': 'Team CyberShield',
        'project_title': 'Secure Vault Authentication Gateway',
        'year_level': '1st Year',
        'level': '1st Year PIT',
        'status': 'Approved',
        'member_ids': [10],
        'leader_id': 10,
      },
      students: [
        {'id': 10, 'name': 'Lucas Alcantara', 'username': '4081'},
      ],
      statuses: const ['Pending', 'Approved'],
      deliverableTeam: {
        'id': 2,
        'name': 'Team CyberShield',
        'current_stage': '1st Year Concept Pitch',
        'stages': [
          {
            'stage_label': '1st Year Concept Pitch',
            'deliverables_configured': true,
            'deliverables': [
              {
                'id': '1',
                'label': 'Draft Concept Paper & System Case Study',
                'required': true,
                'type': 'pre',
                'uploaded': true,
              },
            ],
          },
        ],
      },
      // Simulate backend having returned multiple years in stageOptions
      stageOptions: const [
        '1st Year Concept Pitch',
        '2nd Year Architecture Pitch',
      ],
    );
  }

  @override
  Future<void> load() async {}
}

class _FakePitTeamDetailNotifier extends TeamDetailNotifier {
  _FakePitTeamDetailNotifier() : super(1);

  @override
  TeamDetailState build() {
    return TeamDetailState(
      team: {
        'id': 1,
        'name': 'Team CodeLearners',
        'project_title': 'Smart Campus Navigator',
        'year_level': '3rd Year',
        'level': '3rd Year PIT',
        'instructor_name': 'Elena Reyes',
        'status': 'Approved',
        'member_ids': [10, 11],
        'leader_id': 10,
      },
      students: [
        {'id': 10, 'name': 'Carlos Reyes', 'username': '4081'},
        {'id': 11, 'name': 'Maria Santos', 'username': '4082'},
      ],
      statuses: const ['Pending', 'Approved'],
      deliverableTeam: {
        'id': 1,
        'name': 'Team CodeLearners',
        'stages': [
          {
            'stage_label': '3rd Year Expo',
            'deliverables_configured': true,
            'deliverables': [
              {
                'id': '1',
                'label': 'Diagram',
                'required': true,
                'type': 'pre',
                'uploaded': true,
                'submission': {
                  'id': 1,
                  'file_name': 'Diagram.pdf',
                  'uploaded_by_name': 'Carlos Reyes',
                  'file_url': '/media/deliverables/Diagram.pdf',
                },
              },
            ],
          },
        ],
      },
      stageOptions: const ['3rd Year Expo'],
    );
  }

  @override
  Future<void> load() async {}
}
