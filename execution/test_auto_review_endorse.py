"""No-server checks for demo review/endorsement routing and failure handling."""
from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
from io import StringIO
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from execution import auto_review_endorse as reviews


def record(**overrides):
    return {'team_id': 7, 'team_name': 'Team AlphaWave', 'project_version': 1,
            'semester_id': 2, 'workspace': 'instructor',
            'reviewer': {'id': 70, 'username': 'instructor70'}, 'problem': '', **overrides}


def context():
    return {'scope': 'pit', 'stage': 'PIT Exhibit', 'year': '1st Year', 'semester_id': 2, 'reviewers': None}


def team(**stage_overrides):
    return {'id': 7, 'semester_id': 2, 'project_version': 1,
            'selected_stage': {'stage_label': 'PIT Exhibit', 'endorsed': False,
                'endorsement_required': True, 'can_faculty_review_pre': True,
                'endorsement_review': {'can_review_and_endorse': True, 'review_token': 'signed-snapshot',
                    'files': [{'id': 'D1', 'label': 'Concept Paper', 'status': 'pending'}]},
                **stage_overrides}}


def post_row(**overrides):
    return {'id': 'D3', 'label': 'Final paper', 'type': 'post', 'required': True,
            'uploaded': True, 'can_faculty_review': True, 'file_policy': {}, 'document_slots': [],
            'submission': {'id': 91, 'status': 'pending', 'files': [
                {'id': 101, 'slot_key': 'primary', 'revision': 1, 'is_current': True,
                 'file_name': 'Final.pdf', 'file_url': '/media/final.pdf',
                 'uploaded_at': '2026-10-25T01:00:00Z', 'status': 'pending'}]}, **overrides}


def post_team(row=None, **overrides):
    return team(**{'endorsed': True, 'can_faculty_review_post': True, 'post': [row or post_row()], **overrides})


class ReviewEndorseTests(unittest.TestCase):
    def setUp(self):
        self.batch = Mock()
        self.batch.team.return_value = team()
        self.batch.endorse.return_value = {'team': team(endorsed=True)}

    def run_batch(self, records=None, *, dry_run=False, journal=None):
        with redirect_stdout(StringIO()):
            return reviews.run_batch(self.batch, context(), records or [record()], dry_run=dry_run, journal=journal)

    def test_dry_run_reads_the_current_snapshot_and_never_posts(self):
        journal = StringIO()
        # fsync needs a real stream in normal operation; this test collects JSON only.
        journal.fileno = lambda: 1
        with patch.object(reviews.os, 'fsync'):
            self.assertEqual(self.run_batch(dry_run=True, journal=journal), 0)
        self.batch.team.assert_called_once()
        self.batch.endorse.assert_not_called()
        logged = json.loads(journal.getvalue())
        self.assertEqual(logged['status'], 'ready')
        self.assertEqual(logged['reviewer'], record()['reviewer'])
        self.assertNotIn('signed-snapshot', journal.getvalue())

    def test_live_run_uses_the_exact_api_review_token(self):
        self.assertEqual(self.run_batch(), 0)
        self.batch.endorse.assert_called_once_with(context(), record(), 'signed-snapshot')

    def test_already_endorsed_and_not_required_teams_are_skipped(self):
        for current in [team(endorsed=True), team(endorsement_required=False)]:
            with self.subTest(current=current):
                self.batch.team.return_value = current
                self.assertEqual(self.run_batch(), 0)
        self.batch.endorse.assert_not_called()

    def test_repeat_preparation_uses_current_snapshot_instead_of_skipping_history(self):
        self.batch.team.return_value = team(endorsed=True, repeat_preparation=True)
        self.assertEqual(self.run_batch(), 0)
        self.batch.endorse.assert_called_once()

    def test_missing_rejected_locked_and_stale_stage_never_endorse(self):
        cases = [team(stage_label='Different event'), team(can_faculty_review_pre=False),
                 team(endorsement_review={'can_review_and_endorse': False, 'reason': 'Missing required files.'}),
                 team(endorsement_review={'can_review_and_endorse': True, 'review_token': ''}),
                 team(endorsement_review={'can_review_and_endorse': True, 'review_token': 'signed',
                    'files': [{'id': 'D1', 'status': 'rejected'}]})]
        for current in cases:
            with self.subTest(current=current):
                self.batch.team.return_value = current
                self.assertEqual(self.run_batch(), 2)
        self.batch.endorse.assert_not_called()

    def test_missing_or_ambiguous_assignment_blocks_before_api_reads(self):
        self.assertEqual(self.run_batch([record(reviewer=None, problem='Multiple assigned instructors.')]), 2)
        self.batch.team.assert_not_called()
        self.batch.endorse.assert_not_called()

    def test_already_accepted_files_need_no_new_review_permission(self):
        current = team(can_faculty_review_pre=False)
        current['selected_stage']['endorsement_review']['files'][0]['status'] = 'accepted'
        self.batch.team.return_value = current
        self.assertEqual(self.run_batch(), 0)

    def test_stale_snapshot_is_reported_without_post_retry(self):
        self.batch.endorse.side_effect = reviews.common.ApiError(409, 'Files changed.')
        self.assertEqual(self.run_batch(), 2)
        self.batch.endorse.assert_called_once()

    def test_authentication_and_throttle_errors_stop_the_batch(self):
        for status in [401, 429]:
            self.batch.reset_mock()
            self.batch.team.side_effect = reviews.common.ApiError(status, 'Not available.')
            self.assertEqual(self.run_batch([record(), record(team_id=8)]), 2)
            self.batch.team.assert_called_once()
            self.batch.endorse.assert_not_called()

    def test_response_must_confirm_the_target_endorsement(self):
        self.batch.endorse.return_value = {'team': team(endorsed=False)}
        self.assertEqual(self.run_batch(), 2)
        self.batch.endorse.assert_called_once()

    def test_assignment_changes_are_detected_before_post(self):
        batch = reviews.FacultyBatch('http://testserver')
        for changed in [record(project_version=2), record(reviewer={'id': 80, 'username': 'other'}),
                        record(problem='No active assigned instructor.', reviewer=None)]:
            with self.subTest(changed=changed), patch.object(reviews, 'discover_reviewers', return_value=(2, [changed])), \
                    patch.object(batch, 'client') as client:
                with self.assertRaises(reviews.common.UploadError):
                    batch.endorse(context(), record(), 'signed')
                client.assert_not_called()

    def test_requests_keep_the_assigned_workspace_and_do_not_use_admin_login(self):
        batch = reviews.FacultyBatch('http://testserver')
        client = Mock()
        client.request.return_value = {'active_semester': {'id': 2}, 'scope': 'pit',
                                       'selected_stage': 'PIT Exhibit', 'teams': [team()]}
        with patch.object(reviews, 'discover_reviewers', return_value=(2, [record()])), \
                patch.object(batch, 'client', return_value=client):
            batch.team(context(), record())
            batch.endorse(context(), record(), 'current-api-token')
        calls = client.request.call_args_list
        for call in calls:
            self.assertEqual(call.kwargs['params']['workspace'], 'instructor')
            self.assertEqual(call.kwargs['params']['scope'], 'pit')
            self.assertEqual(call.kwargs['params']['team_id'], 7)
        self.assertEqual(calls[1].kwargs['json'], {'team_id': 7, 'stage_label': 'PIT Exhibit', 'review_token': 'current-api-token'})

    def test_scope_fallback_and_changed_project_payloads_are_rejected(self):
        batch = reviews.FacultyBatch('http://testserver')
        good = {'active_semester': {'id': 2}, 'scope': 'pit', 'selected_stage': 'PIT Exhibit', 'teams': [team()]}
        for field, value in [('scope', 'capstone'), ('selected_stage', 'Other event'),
                             ('active_semester', {'id': 3}), ('teams', [])]:
            client = Mock()
            client.request.return_value = {**good, field: value}
            with self.subTest(field=field), patch.object(reviews, 'discover_reviewers', return_value=(2, [record()])), \
                    patch.object(batch, 'client', return_value=client):
                with self.assertRaises(reviews.common.UploadError):
                    batch.team(context(), record())

    def test_simple_cli_previews_or_runs_without_manifests(self):
        with tempfile.TemporaryDirectory() as directory:
            batch = Mock(base_url='http://testserver')
            with patch.object(reviews.common, 'ROOT', Path(directory)), \
                    patch.object(reviews.common, 'batch_stage', return_value='PIT Exhibit'), \
                    patch.object(reviews, 'discover_reviewers', return_value=(2, [record()])), \
                    patch.object(reviews, 'FacultyBatch', return_value=batch), \
                    patch.object(reviews, 'run_batch', return_value=0) as run, redirect_stdout(StringIO()):
                self.assertEqual(reviews.main(['--all-teams', '--year', '1', '--dry-run']), 0)
                self.assertTrue(run.call_args.kwargs['dry_run'])
                self.assertEqual(reviews.main(['--all-teams', '--year', '1']), 0)
                self.assertNotIn('dry_run', run.call_args.kwargs)
            self.assertEqual(batch.close.call_count, 2)
            self.assertFalse(list(Path(directory).rglob('*.lock')))


class PostReviewTests(unittest.TestCase):
    def setUp(self):
        self.context = {**context(), 'timing': 'post', 'deliverable': None}
        self.batch = Mock()
        self.batch.team.return_value = post_team()
        self.batch.accept_post.return_value = {'team': post_team()}

    def run_batch(self, *, dry_run=False):
        with redirect_stdout(StringIO()):
            return reviews.run_batch(self.batch, self.context, [record()], dry_run=dry_run)

    def test_post_preview_and_live_do_not_endorse_already_endorsed_team(self):
        self.assertEqual(self.run_batch(dry_run=True), 0)
        self.batch.accept_post.assert_not_called()
        self.assertEqual(self.run_batch(), 0)
        self.batch.accept_post.assert_called_once()
        self.assertEqual(self.batch.accept_post.call_args.args[2]['file_id'], 101)
        self.batch.endorse.assert_not_called()

    def test_accepted_file_is_skipped_while_pending_optional_attachment_is_reviewed(self):
        row = post_row(file_policy={'mode': 'named'})
        row['submission']['status'] = 'accepted'
        paper = row['submission']['files'][0]
        paper['status'] = 'accepted'
        row['submission']['files'].append({**paper, 'id': 102, 'slot_key': 'notes',
                                          'file_name': 'Notes.pdf', 'status': 'pending'})
        self.batch.team.return_value = post_team(row)
        self.assertEqual(self.run_batch(), 0)
        self.assertEqual(self.batch.accept_post.call_count, 1)
        self.assertEqual(self.batch.accept_post.call_args.args[2]['file_id'], 102)

    def test_rejected_replacement_and_incomplete_requirements_are_not_accepted(self):
        rows = [post_row(uploaded=False), post_row(submission={'status': 'rejected',
                'files': post_row()['submission']['files']}), post_row(submission={
                **post_row()['submission'], 'file_replacement_unlocked': True})]
        for row in rows:
            with self.subTest(row=row):
                self.batch.team.return_value = post_team(row)
                self.assertEqual(self.run_batch(), 2)
        self.batch.accept_post.assert_not_called()
        self.batch.endorse.assert_not_called()

    def test_missing_required_blocks_but_missing_optional_and_waived_skip(self):
        for row, code in [(post_row(submission=None), 2),
                          (post_row(required=False, submission=None), 0),
                          (post_row(is_waived=True, submission=None), 0)]:
            with self.subTest(row=row):
                self.batch.team.return_value = post_team(row)
                self.assertEqual(self.run_batch(), code)
        self.batch.accept_post.assert_not_called()

    def test_post_permissions_and_system_owned_rows_are_respected(self):
        for current in [post_team(can_faculty_review_post=False), post_team(post_row(can_faculty_review=False))]:
            self.batch.team.return_value = current
            self.assertEqual(self.run_batch(), 2)
        self.batch.team.return_value = post_team(post_row(source='defense_minutes'))
        self.assertEqual(self.run_batch(), 0)
        self.batch.accept_post.assert_not_called()

    def test_specific_post_deliverable_selector_does_not_include_other_requirements(self):
        current = post_team()
        current['selected_stage']['post'].append(post_row(id='D4', label='Source code'))
        self.batch.team.return_value = current
        self.context['deliverable'] = 'D4'
        self.assertEqual(self.run_batch(), 0)
        self.assertEqual(self.batch.accept_post.call_args.args[2]['deliverable_id'], 'D4')

    def test_history_is_not_reviewed_and_invalid_version_ids_block(self):
        row = post_row()
        row['submission']['files'][0]['is_current'] = False
        self.batch.team.return_value = post_team(row)
        self.assertEqual(self.run_batch(), 2)
        row['submission']['files'][0].update(is_current=True, id=None)
        self.assertEqual(self.run_batch(), 2)
        self.batch.accept_post.assert_not_called()

    def test_post_http_failure_is_not_retried_and_throttle_stops_other_files(self):
        self.batch.accept_post.side_effect = reviews.common.ApiError(429, 'Rate limit.')
        current = post_team()
        current['selected_stage']['post'].append(post_row(id='D4'))
        self.batch.team.return_value = current
        self.assertEqual(self.run_batch(), 2)
        self.batch.accept_post.assert_called_once()

    def test_refresh_detects_replacement_or_definition_changes_before_post(self):
        batch = reviews.FacultyBatch('http://testserver')
        target = reviews.post_actions(self.context, post_team())[0]
        changed_file = post_row()
        changed_file['submission']['files'][0]['id'] = 102
        for changed in [post_team(changed_file), post_team(post_row(label='New required paper'))]:
            with self.subTest(changed=changed), patch.object(batch, 'team', return_value=changed), \
                    patch.object(batch, 'client') as client:
                with self.assertRaises(reviews.common.UploadError):
                    batch.accept_post(self.context, record(), target)
                client.assert_not_called()

    def test_file_accepted_between_reads_is_preserved(self):
        batch = reviews.FacultyBatch('http://testserver')
        target = reviews.post_actions(self.context, post_team())[0]
        accepted = post_row()
        accepted['submission']['files'][0]['status'] = 'accepted'
        with patch.object(batch, 'team', return_value=post_team(accepted)), patch.object(batch, 'client') as client:
            self.assertIsNone(batch.accept_post(self.context, record(), target))
        client.assert_not_called()

    def test_post_request_targets_exact_file_in_existing_review_api(self):
        batch = reviews.FacultyBatch('http://testserver')
        target = reviews.post_actions(self.context, post_team())[0]
        accepted = post_row()
        accepted['submission']['files'][0]['status'] = 'accepted'
        client = Mock()
        client.request.return_value = {'team': post_team(accepted)}
        with patch.object(batch, 'team', return_value=post_team()), \
                patch.object(batch, 'current_record', return_value=record()), patch.object(batch, 'client', return_value=client):
            batch.accept_post(self.context, record(), target)
        call = client.request.call_args
        self.assertEqual(call.args, ('POST', reviews.common.API + 'review/'))
        self.assertEqual(call.kwargs['params']['workspace'], 'instructor')
        self.assertEqual(call.kwargs['json']['file_id'], 101)
        self.assertEqual(call.kwargs['json']['status'], 'accepted')
        self.assertFalse(call.kwargs['json']['clear_defense_revisions'])
        self.assertNotIn('review_token', call.kwargs['json'])

    def test_legacy_primary_upload_is_rechecked_and_reviewed_without_file_id(self):
        legacy = post_row(submission={'id': 91, 'status': 'pending', 'files': [],
            'file_url': '/media/legacy.pdf', 'file_name': 'Legacy.pdf', 'uploaded_at': '2026-10-25T01:00:00Z'})
        target = reviews.post_actions(self.context, post_team(legacy))[0]
        accepted = deepcopy(legacy)
        accepted['submission']['status'] = 'accepted'
        batch = reviews.FacultyBatch('http://testserver')
        client = Mock()
        client.request.return_value = {'team': post_team(accepted)}
        with patch.object(batch, 'team', return_value=post_team(legacy)), \
                patch.object(batch, 'current_record', return_value=record()), patch.object(batch, 'client', return_value=client):
            batch.accept_post(self.context, record(), target)
        self.assertNotIn('file_id', client.request.call_args.kwargs['json'])

    def test_cli_passes_post_timing_and_deliverable_to_runner(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(reviews.common, 'ROOT', Path(directory)), \
                patch.object(reviews.common, 'batch_stage', return_value='PIT Exhibit'), \
                patch.object(reviews, 'discover_reviewers', return_value=(2, [record()])), \
                patch.object(reviews, 'FacultyBatch', return_value=Mock(base_url='http://testserver')), \
                patch.object(reviews, 'run_batch', return_value=0) as run, redirect_stdout(StringIO()):
            self.assertEqual(reviews.main(['--all-teams', '--year', '1', '--timing', 'post',
                                          '--deliverable', 'D3', '--dry-run']), 0)
        self.assertEqual(run.call_args.args[1]['timing'], 'post')
        self.assertEqual(run.call_args.args[1]['deliverable'], 'D3')


if __name__ == '__main__':
    unittest.main()
