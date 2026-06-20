import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user/screens/web/admin/team_detail_page.dart';
import 'package:user/services/team_detail_provider.dart';

import '../helpers/pump_app.dart';

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
  });
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
                }
              }
            ]
          }
        ]
      },
      stageOptions: const ['3rd Year Expo'],
    );
  }

  @override
  Future<void> load() async {}
}

