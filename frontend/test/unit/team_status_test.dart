import 'package:defensys/screens/web/admin/defense_scheduler/models/team_status.dart';
import 'package:flutter_test/flutter_test.dart';

const stage = 'Project Proposal';

Map<String, dynamic> team({
  String progress = 'pending',
  String? requirements,
  int attempt = 1,
  bool ready = false,
  String? verdict,
}) => {
  'id': 1,
  'level': '3rd Year Capstone',
  'eligible_stages': [if (ready) stage],
  'stage_progress': {stage: progress},
  'stage_status_details': {
    stage: {
      'attempt_count': attempt,
      if (requirements != null) 'requirements_status': requirements,
    },
  },
  'stage_verdicts': {if (verdict != null) stage: verdict},
};

TeamStatus resolve(Map<String, dynamic> value) =>
    TeamStatus.fromTeam(value, stage, scope: 'capstone');

void main() {
  for (final code in [
    'awaiting_files',
    'needs_review',
    'changes_requested',
    'awaiting_endorsement',
  ]) {
    test('$code remains distinct before scheduling', () {
      final status = resolve(team(requirements: code));
      expect(status.code, code);
      expect(status.group, TeamStatusGroup.beforeScheduling);
      expect(status.nextStep, isNotEmpty);
    });
  }
  test('missing evidence does not imply pending endorsement', () {
    expect(resolve(team()).code, 'unknown');
    expect(resolve(team(requirements: 'endorsed')).code, 'scheduling_blocked');
    expect(
      resolve(team(ready: true, requirements: 'endorsed')).code,
      'ready_to_schedule',
    );
  });
  for (final code in [
    'awaiting_evaluation',
    'awaiting_verdict',
    'awaiting_concept_selection',
    'pending_post_defense',
    'grading_incomplete',
    'awaiting_completion',
    'revisions_pending',
  ]) {
    test('$code overrides historical endorsement and scheduled flags', () {
      final value = team(progress: code, ready: true)
        ..['scheduled_stages'] = [stage];
      expect(resolve(value).code, code);
      expect(resolve(value).group, TeamStatusGroup.followUp);
    });
  }
  test('re-defense preparation, readiness and next attempt are explicit', () {
    final preparing = resolve(
      team(
        progress: 'awaiting_files',
        requirements: 'awaiting_files',
        verdict: 'for_redefense',
      ),
    );
    expect(preparing.code, 'redefense_required');
    expect(preparing.nextStep, 'Team to submit the required files.');
    expect(
      resolve(team(progress: 'redefense_required', ready: true)).code,
      'ready_to_schedule_redefense',
    );
    expect(
      resolve(team(progress: 'scheduled', attempt: 2)).code,
      'redefense_scheduled',
    );
    expect(resolve(team(progress: 'scheduled', attempt: 1)).code, 'scheduled');
  });
  for (final code in ['re_demo_required', 're_demo_scheduled']) {
    test(
      '$code retains its operational status alongside an approved verdict',
      () {
        final value = team(progress: code, verdict: 'approved_with_revisions');
        expect(resolve(value).code, code);
        expect(
          resolve(value).group,
          code == 're_demo_scheduled'
              ? TeamStatusGroup.scheduled
              : TeamStatusGroup.followUp,
        );
        expect(value['stage_verdicts'][stage], 'approved_with_revisions');
      },
    );
  }
  test('completion belongs only to the selected stage', () {
    final value = team(progress: 'completed');
    expect(resolve(value).group, TeamStatusGroup.completed);
    expect(
      TeamStatus.fromTeam(value, 'Final Defense', scope: 'capstone').code,
      'unknown',
    );
  });
  test('ordinary PIT event without required files can be ready', () {
    final value = {'level': '1st Year PIT', 'year_level': '1st Year'};
    expect(
      TeamStatus.fromTeam(
        value,
        'PIT Expo',
        scope: 'pit',
        event: {
          'event_name': 'PIT Expo',
          'year_level': '1st Year',
          'deliverables': [],
        },
      ).code,
      'ready_to_schedule',
    );
  });

  test('title review stays visible before endorsement', () {
    final value = team()
      ..['concept_workflows'] = {
        stage: {
          'title_workflow_version': 2,
          'can_edit': true,
          'status': 'submitted',
          'title_status_label': 'Titles submitted',
          'next_step': 'Adviser to review the titles.',
        },
      };
    expect(resolve(value).label, 'Titles submitted');
    expect(resolve(value).nextStep, 'Adviser to review the titles.');
    value['concept_workflows'][stage]['round'] = 2;
    expect(resolve(value).code, 'redefense_required');
    expect(resolve(value).group, TeamStatusGroup.followUp);
  });

  test('PIT status membership respects year and event enrollment', () {
    final value = <String, dynamic>{
      'year_level': '1st Year',
      'stage_status_details': {'Concept Hearing': {}},
    };
    expect(
      teamMatchesStatusEvent(value, {
        'year_level': '1st Year',
        'event_name': 'Concept Hearing',
      }),
      isTrue,
    );
    expect(
      teamMatchesStatusEvent(value, {
        'year_level': '1st Year',
        'event_name': 'PIT Expo',
      }),
      isFalse,
    );
    expect(
      teamMatchesStatusEvent(value, {
        'year_level': '2nd Year',
        'event_name': 'Concept Hearing',
      }),
      isFalse,
    );
  });
}
