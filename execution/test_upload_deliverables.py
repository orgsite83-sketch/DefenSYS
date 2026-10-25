"""Uploader tests require no database, credentials, server, or real submissions."""
from contextlib import redirect_stdout
from contextlib import redirect_stderr
from copy import deepcopy
from io import StringIO
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import requests

from execution import upload_deliverables as uploads


def requirement(**overrides):
    return {'id': 'D1', 'label': 'Concept Paper', 'type': 'pre', 'required': True,
            'file_format': 'pdf', 'file_policy': {}, 'document_slots': [
                {'key': 'primary', 'label': 'Concept Paper', 'file_format': 'pdf', 'required': True}],
            'can_upload': True, 'uploaded': False, 'submission': None, **overrides}


def team(row=None, **overrides):
    return {'id': 7, 'name': 'Team A', 'project_version': 1, 'semester_id': 2,
            'level': '1st Year PIT', 'year_level': '1st Year',
            'selected_stage': {'stage_label': 'PIT Exhibit', 'pre': [row or requirement()], 'post': []},
            **overrides}


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = self.root / '7' / 'D1.pdf'
        self.path.parent.mkdir()
        self.path.write_bytes(b'%PDF-1.4 sample upload')
        self.client = Mock(base_url='http://localhost:8000')
        self.client.teams.return_value = {'selected_stage': 'PIT Exhibit',
            'active_semester': {'id': 2}, 'teams': [team()]}

    def plan(self, row=None, **options):
        self.client.teams.return_value['teams'] = [team(row)]
        return uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
            files_root=self.root, team_ids=[7], **options)

    def run_plan(self, plan, current_team=None, apply=False):
        self.client.team.return_value = current_team or team()
        with redirect_stdout(StringIO()):
            code = uploads.run_plan(self.client, plan, apply=apply, journal=None)
        return code

    def test_prepare_discovers_exact_file_and_never_posts(self):
        plan = self.plan()
        self.assertEqual(plan['items'][0]['file'], '7/D1.pdf')
        self.assertEqual(plan['items'][0]['slot_key'], 'primary')
        uploads.validate_plan(plan)
        self.client.upload.assert_not_called()

    def test_preview_reads_state_and_hashes_without_uploading(self):
        self.assertEqual(self.run_plan(self.plan()), 0)
        self.client.upload.assert_not_called()

    def test_apply_uploads_actual_file_with_scope_and_target(self):
        plan = self.plan()
        self.client.upload.return_value = {'submission_id': 42}
        self.assertEqual(self.run_plan(plan, apply=True), 0)
        self.client.upload.assert_called_once_with(plan, plan['items'][0], self.path.resolve())

    def test_occupied_slots_are_preserved_including_rejected_files(self):
        plan = self.plan()
        current = team(requirement(submission={'files': [
            {'slot_key': 'primary', 'status': 'rejected', 'file_url': '/old.pdf'}]}))
        self.assertEqual(self.run_plan(plan, current, apply=True), 0)
        self.client.upload.assert_not_called()

    def test_completed_legacy_submission_is_skipped_without_local_file(self):
        plan = self.plan()
        self.path.unlink()
        current = team(requirement(can_upload=False, uploaded=True,
            submission={'file_name': 'existing.pdf', 'file_url': '/existing.pdf'}))
        self.assertEqual(self.run_plan(plan, current, apply=True), 0)
        self.client.upload.assert_not_called()

    def test_changed_term_project_scope_and_definition_are_blocked(self):
        plan = self.plan()
        for current in [team(semester_id=3), team(project_version=2), team(level='4th Year Capstone'),
                        team(requirement(label='Renamed requirement'))]:
            with self.subTest(current=current):
                self.assertEqual(self.run_plan(plan, current, apply=True), 2)
        self.client.upload.assert_not_called()

    def test_closed_window_never_attempts_upload(self):
        self.assertEqual(self.run_plan(self.plan(), team(requirement(can_upload=False)), apply=True), 2)
        self.client.upload.assert_not_called()

    def test_missing_and_outside_files_are_blocked(self):
        for relative in ['', '7/missing.pdf', '../outside.pdf']:
            plan = self.plan()
            plan['items'][0]['file'] = relative
            self.assertEqual(self.run_plan(plan, apply=True), 2)
        self.client.upload.assert_not_called()

    def test_wrong_file_extension_is_blocked(self):
        other = self.path.with_suffix('.zip')
        other.write_bytes(b'zip content')
        plan = self.plan()
        plan['items'][0]['file'] = '7/D1.zip'
        self.assertEqual(self.run_plan(plan, apply=True), 2)
        self.client.upload.assert_not_called()

    def test_pdf_is_valid_for_presentation_and_document_requirements(self):
        for file_format in ['presentation', 'document']:
            row = requirement(file_format=file_format)
            self.assertEqual(self.run_plan(self.plan(row), team(row)), 0)

    def test_duplicate_targets_are_rejected_before_any_requests(self):
        plan = self.plan()
        plan['items'].append(deepcopy(plan['items'][0]))
        with self.assertRaisesRegex(uploads.UploadError, 'Duplicate'):
            uploads.run_plan(self.client, plan, apply=True)
        self.client.team.assert_not_called()
        self.client.upload.assert_not_called()

    def test_named_and_concept_slots_use_windows_safe_paths(self):
        for mode, key in [('named', 'paper'), ('concepts', 'c1:paper')]:
            with self.subTest(mode=mode):
                row = requirement(file_policy={'mode': mode}, document_slots=[
                    {'key': key, 'file_format': 'pdf', 'required': True}])
                path = self.root / '7' / 'D1' / f'{uploads.component(key)}.pdf'
                path.parent.mkdir(exist_ok=True)
                path.write_bytes(b'pdf fixture')
                plan = self.plan(row)
                self.assertEqual(plan['items'][0]['slot_key'], key)
                self.assertEqual(plan['items'][0]['file'], path.relative_to(self.root).as_posix())
                self.assertEqual(self.run_plan(plan, team(row)), 0)

    def test_flat_folder_maps_different_files_for_every_team_in_one_plan(self):
        self.path.unlink()
        (self.root / '7__D1.pdf').write_bytes(b'Team 7 project paper')
        (self.root / '8__D1.pdf').write_bytes(b'Team 8 different project paper')
        self.client.teams.return_value['teams'] = [team(), team(id=8, name='Team B')]
        plan = uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
            files_root=self.root, all_teams=True)
        self.assertEqual([(item['team_id'], item['file']) for item in plan['items']],
                         [(7, '7__D1.pdf'), (8, '8__D1.pdf')])
        uploads.validate_plan(plan)

    def test_team_name_folders_match_deliverable_names_without_ids(self):
        for number, label in [(7, 'Team A'), (8, 'Team B')]:
            folder = self.root / label
            folder.mkdir()
            (folder / 'Concept Paper.pdf').write_bytes(f'{label} distinct paper'.encode())
        self.path.unlink()
        self.client.teams.return_value['teams'] = [team(), team(id=8, name='Team B')]
        plan = uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
            files_root=self.root, all_teams=True)
        self.assertEqual([item['file'] for item in plan['items']],
                         ['Team A/Concept Paper.pdf', 'Team B/Concept Paper.pdf'])
        uploads.validate_plan(plan)

    def test_selected_deliverable_matches_only_team_prefixes_for_the_whole_batch(self):
        first = team(name='Alpha Wave')
        second = team(id=8, name='ApexCode')
        for current in [first, second]:
            current['selected_stage']['pre'].append(requirement(id='D2', label='Pitch Deck'))
        (self.root / 'AlphaWave_Concept_Paper.pdf').write_bytes(b'Alpha Wave document')
        (self.root / 'ApexCode_Any_filename.pdf').write_bytes(b'Apex Code document')
        (self.root / 'OtherTeam_Concept_Paper.pdf').write_bytes(b'Other cohort')
        self.client.teams.return_value['teams'] = [second, first]
        plan = uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
            files_root=self.root, all_teams=True, deliverable='Concept Paper')
        self.assertEqual([(item['team_id'], item['deliverable_id'], item['file']) for item in plan['items']],
                         [(8, 'D1', 'ApexCode_Any_filename.pdf'), (7, 'D1', 'AlphaWave_Concept_Paper.pdf')])
        self.assertEqual(plan['file_matching'], 'team_filename')
        uploads.validate_plan(plan)
        self.client.upload.assert_not_called()

    def test_team_filename_matching_requires_a_full_prefix_and_never_substrings(self):
        self.client.teams.return_value['teams'] = [team(name='Alpha'), team(id=8, name='AlphaWave')]
        (self.root / 'AlphaWave.pdf').write_bytes(b'The longer team name')
        (self.root / 'Concept_Paper_Alpha.pdf').write_bytes(b'Team name in the wrong position')
        plan = uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
            files_root=self.root, all_teams=True, deliverable='D1')
        self.assertEqual([item['file'] for item in plan['items']], ['', 'AlphaWave.pdf'])

    def test_team_filename_accepts_optional_team_word_from_the_roster(self):
        for filename in ['AlphaWave_Concept_Paper.pdf', 'Team_AlphaWave_Concept_Paper.pdf']:
            with self.subTest(filename=filename):
                path = self.root / filename
                path.write_bytes(b'AlphaWave distinct paper')
                self.client.teams.return_value['teams'] = [team(name='Team AlphaWave')]
                plan = uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
                    files_root=self.root, all_teams=True, deliverable='D1')
                self.assertEqual(plan['items'][0]['file'], filename)
                path.unlink()

    def test_optional_team_word_never_resolves_ambiguous_team_identity(self):
        (self.root / 'AlphaWave_Concept_Paper.pdf').write_bytes(b'Ambiguous team paper')
        self.client.teams.return_value['teams'] = [team(name='Team AlphaWave'), team(id=8, name='AlphaWave')]
        with self.assertRaisesRegex(uploads.UploadError, 'ambiguous team'):
            uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
                files_root=self.root, all_teams=True, deliverable='D1')

    def test_team_filename_collisions_are_reported_instead_of_assigned_by_order(self):
        (self.root / 'Team_A_Paper.pdf').write_bytes(b'A document')
        for other in [team(id=8, name='TeamA'), team(id=8, name='Team A Paper')]:
            self.client.teams.return_value['teams'] = [team(), other]
            with self.subTest(other=other['name']), self.assertRaisesRegex(uploads.UploadError, 'ambiguous team'):
                uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
                    files_root=self.root, all_teams=True, deliverable='Concept Paper')

    def test_multiple_files_for_one_team_leave_single_target_unmapped(self):
        for name in ['Team_A_draft.pdf', 'Team_A_final.pdf']:
            (self.root / name).write_bytes(b'Team A document')
        plan = self.plan(deliverable='Concept Paper')
        self.assertEqual(plan['items'][0]['file'], '')
        self.assertEqual(self.run_plan(plan, apply=True), 2)
        self.client.upload.assert_not_called()

    def test_deliverable_selector_checks_configured_label_id_and_timing(self):
        for selector in ['D1', 'concept_paper']:
            self.assertEqual(self.plan(deliverable=selector)['items'][0]['deliverable_id'], 'D1')
        for selector in ['not configured', '']:
            with self.subTest(selector=selector), self.assertRaises(uploads.UploadError):
                self.plan(deliverable=selector)
        with self.assertRaisesRegex(uploads.UploadError, 'timing'):
            self.plan(deliverable='D1', timing='post')
        current = team()
        current['selected_stage']['post'] = [requirement(id='D2', type='post')]
        self.client.teams.return_value['teams'] = [current]
        with self.assertRaisesRegex(uploads.UploadError, 'exactly one'):
            uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
                files_root=self.root, all_teams=True, deliverable='Concept Paper', timing='all')

    def test_grouped_deliverable_uses_command_slot_ignoring_filename_suffix(self):
        row = requirement(file_policy={'mode': 'named'}, document_slots=[
            {'key': 'paper', 'label': 'Main paper', 'file_format': 'pdf'},
            {'key': 'notes', 'label': 'Notes', 'file_format': 'pdf'}])
        (self.root / 'Team_A_Any_name.pdf').write_bytes(b'Team A paper')
        with self.assertRaisesRegex(uploads.UploadError, '--slot'):
            self.plan(row, deliverable='Concept Paper')
        for selector in ['paper', 'main_paper']:
            plan = self.plan(row, deliverable='D1', slot=selector)
            self.assertEqual([(item['slot_key'], item['file']) for item in plan['items']],
                             [('paper', 'Team_A_Any_name.pdf')])
        for selector in ['missing', '']:
            with self.subTest(selector=selector), self.assertRaisesRegex(uploads.UploadError, '--slot'):
                self.plan(row, deliverable='D1', slot=selector)
        with self.assertRaisesRegex(uploads.UploadError, 'requires --deliverable'):
            self.plan(row, slot='paper')
        with self.assertRaisesRegex(uploads.UploadError, 'only used'):
            self.plan(deliverable='D1', slot='primary')

    def test_selected_multiple_deliverable_keeps_all_team_attachments(self):
        row = requirement(file_policy={'mode': 'multiple', 'max_files': 3}, document_slots=[])
        for name in ['Team_A_code.pdf', 'Team_A_notes.pdf']:
            (self.root / name).write_bytes(b'Attachment')
        plan = self.plan(row, deliverable='Concept Paper')
        self.assertEqual([item['file'] for item in plan['items']], ['Team_A_code.pdf', 'Team_A_notes.pdf'])
        self.assertEqual(len({item['slot_key'] for item in plan['items']}), 2)
        uploads.validate_plan(plan)

    def test_duplicate_team_names_are_never_assigned_by_sorting(self):
        (self.root / 'Team A').mkdir()
        self.client.teams.return_value['teams'] = [team(), team(id=8)]
        with self.assertRaisesRegex(uploads.UploadError, 'ambiguous'):
            uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
                files_root=self.root, all_teams=True)

    def test_deliverable_subfolder_preserves_original_arbitrary_filename(self):
        folder = self.root / 'Team A' / 'Concept Paper'
        folder.mkdir(parents=True)
        (folder / 'Our project draft.pdf').write_bytes(b'Unique team document')
        self.path.unlink()
        self.assertEqual(self.plan()['items'][0]['file'], 'Team A/Concept Paper/Our project draft.pdf')

    def test_pre_post_folders_disambiguate_repeated_deliverable_labels(self):
        self.path.unlink()
        current = team()
        current['selected_stage']['post'] = [requirement(id='D2', type='post')]
        self.client.teams.return_value['teams'] = [current]
        for timing in ['Pre', 'Post']:
            folder = self.root / 'Team A' / timing
            folder.mkdir(parents=True)
            (folder / 'Concept Paper.pdf').write_bytes(timing.encode())
        plan = uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
            files_root=self.root, all_teams=True, timing='all')
        self.assertEqual([item['file'] for item in plan['items']],
                         ['Team A/Pre/Concept Paper.pdf', 'Team A/Post/Concept Paper.pdf'])

    def test_team_requirement_slot_labels_match_concept_files(self):
        row = requirement(label='Concept Papers', file_policy={'mode': 'concepts'}, document_slots=[
            {'key': 'c1:paper', 'label': 'Concept 1 · Concept paper', 'file_format': 'pdf'}])
        folder = self.root / 'Team A' / 'Concept Papers'
        folder.mkdir(parents=True)
        (folder / 'Concept 1 - Concept paper.pdf').write_bytes(b'Concept paper')
        self.assertEqual(self.plan(row)['items'][0]['file'],
                         'Team A/Concept Papers/Concept 1 - Concept paper.pdf')

    def test_preview_displays_api_recommendation_without_renaming_local_file(self):
        row = requirement(type='post', suggested_file_name='API_Recommended_Project.pdf')
        current = team()
        current['selected_stage'].update(pre=[], post=[row])
        self.client.teams.return_value['teams'] = [current]
        plan = uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
            files_root=self.root, all_teams=True, timing='post')
        self.client.team.return_value = current
        output = StringIO()
        with redirect_stdout(output):
            self.assertEqual(uploads.run_plan(self.client, plan), 0)
        self.assertIn('API_Recommended_Project.pdf', output.getvalue())
        self.assertTrue(self.path.exists())
        self.client.upload.assert_not_called()

    def test_post_rename_uses_current_api_name_and_keeps_actual_extension(self):
        row = requirement(type='post', file_format='archive', suggested_file_name='API_Name.zip')
        path = self.path.with_suffix('.7z')
        path.write_bytes(b'Team-specific archive')
        self.path.unlink()
        plan = self.plan(row, timing='post')
        current = team({**row, 'suggested_file_name': 'Current_API_Name.zip'})
        self.client.upload.return_value = {'submission_id': 42}
        self.assertEqual(self.run_plan(plan, current, apply=True), 0)
        sent = self.client.upload.call_args.args[1]
        self.assertEqual(sent['repository_file_name'], 'Current_API_Name.7z')
        self.assertEqual(path.read_bytes(), b'Team-specific archive')
        self.assertNotIn('repository_file_name', plan['items'][0])

    def test_post_group_names_keep_document_slot_identity(self):
        row = requirement(type='post', suggested_file_name='API_Name.pdf', file_policy={'mode': 'concepts'})
        self.assertEqual(uploads.repository_file_name(row, {'slot_key': 'c1:paper'}, self.path),
                         'API_Name_c1__paper.pdf')
        self.assertEqual(uploads.repository_file_name(row, {'slot_key': 'c2:paper'}, self.path),
                         'API_Name_c2__paper.pdf')

    def test_flat_concept_slot_is_team_specific(self):
        row = requirement(file_policy={'mode': 'concepts'}, document_slots=[
            {'key': 'c1:paper', 'file_format': 'pdf'}])
        (self.root / '7__D1__c1__paper.pdf').write_bytes(b'Concept belonging to team 7')
        plan = self.plan(row)
        self.assertEqual(plan['items'][0]['file'], '7__D1__c1__paper.pdf')
        self.assertEqual(plan['items'][0]['slot_key'], 'c1:paper')

    def test_same_file_cannot_be_mapped_across_teams(self):
        plan = self.plan()
        plan['items'].append({**plan['items'][0], 'team_id': 8})
        with self.assertRaisesRegex(uploads.UploadError, 'own file'):
            uploads.validate_plan(plan)

    def test_folder_and_flat_duplicate_candidates_are_not_guessed(self):
        (self.root / '7__D1.pdf').write_bytes(b'Other team 7 version')
        self.assertEqual(self.plan()['items'][0]['file'], '')

    def test_multiple_attachments_get_stable_keys_and_rerun_skips(self):
        row = requirement(file_policy={'mode': 'multiple', 'max_files': 3}, document_slots=[])
        attachment = self.root / '7' / 'D1' / 'paper.pdf'
        attachment.parent.mkdir()
        attachment.write_bytes(b'attachment')
        plan = self.plan(row)
        self.assertEqual(plan['items'][0]['slot_key'], self.plan(row)['items'][0]['slot_key'])
        row['submission'] = {'files': [{'slot_key': plan['items'][0]['slot_key'], 'file_name': 'paper.pdf'}]}
        self.assertEqual(self.run_plan(plan, team(row), apply=True), 0)
        self.client.upload.assert_not_called()

    def test_multiple_manual_file_name_and_capacity_are_preserved(self):
        row = requirement(file_policy={'mode': 'multiple', 'max_files': 1}, document_slots=[])
        attachment = self.root / '7' / 'D1' / 'paper.pdf'
        attachment.parent.mkdir()
        attachment.write_bytes(b'attachment')
        plan = self.plan(row)
        row['submission'] = {'files': [{'slot_key': 'manual', 'file_name': 'paper.pdf'}]}
        self.assertEqual(self.run_plan(plan, team(row), apply=True), 0)
        row['submission']['files'][0]['file_name'] = 'another.pdf'
        self.assertEqual(self.run_plan(plan, team(row), apply=True), 2)
        self.client.upload.assert_not_called()

    def test_grouped_uploads_refresh_each_slot_and_later_run_only_fills_missing(self):
        row = requirement(file_policy={'mode': 'named'}, document_slots=[
            {'key': 'paper', 'file_format': 'pdf'}, {'key': 'notes', 'file_format': 'pdf'}])
        folder = self.root / '7' / 'D1'
        folder.mkdir()
        for name in ['paper.pdf', 'notes.pdf']:
            (folder / name).write_bytes(b'pdf')
        plan = self.plan(row)
        current = team(row)
        self.client.team.side_effect = lambda *_: deepcopy(current)
        def upload(_plan, item, _path):
            if item['slot_key'] == 'notes':
                raise uploads.UploadError('HTTP 400: fixture failure')
            current['selected_stage']['pre'][0]['submission'] = {'files': [{'slot_key': 'paper'}]}
            return {'submission_id': 8}
        self.client.upload.side_effect = upload
        with redirect_stdout(StringIO()):
            self.assertEqual(uploads.run_plan(self.client, plan, apply=True), 2)
        self.assertEqual(self.client.team.call_count, 2)
        self.client.upload.reset_mock(side_effect=True)
        self.client.upload.return_value = {'submission_id': 8}
        with redirect_stdout(StringIO()):
            self.assertEqual(uploads.run_plan(self.client, plan, apply=True), 0)
        self.client.upload.assert_called_once()
        self.assertEqual(self.client.upload.call_args.args[1]['slot_key'], 'notes')

    def test_missing_requested_team_and_ambiguous_files_are_not_guessed(self):
        with self.assertRaisesRegex(uploads.UploadError, 'unavailable'):
            uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
                files_root=self.root, team_ids=[99])
        self.path.with_suffix('.docx').write_bytes(b'document')
        self.assertEqual(self.plan()['items'][0]['file'], '')

    def test_system_minutes_and_waivers_are_excluded(self):
        current = team()
        current['selected_stage']['post'] = [requirement(id='MINUTES', type='post', source='defense_minutes'),
                                             requirement(id='WAIVED', type='post', is_waived=True)]
        self.client.teams.return_value['teams'] = [current]
        plan = uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit', files_root=self.root,
            all_teams=True, timing='all')
        self.assertEqual([item['deliverable_id'] for item in plan['items']], ['D1'])

    def test_apply_lock_does_not_steal_an_existing_lock(self):
        manifest = self.root / 'plan.json'
        with uploads.apply_lock(manifest):
            with self.assertRaises(uploads.UploadError):
                with uploads.apply_lock(manifest):
                    pass
        self.assertFalse(manifest.with_suffix('.json.lock').exists())

    def test_authentication_and_rate_limit_failures_stop_the_batch(self):
        for status in [401, 429]:
            plan = self.plan()
            plan['items'].append({**plan['items'][0], 'slot_key': 'other'})
            self.client.team.side_effect = uploads.ApiError(status, 'fixture error')
            self.client.team.reset_mock()
            with redirect_stdout(StringIO()):
                self.assertEqual(uploads.run_plan(self.client, plan, apply=True), 2)
            self.client.team.assert_called_once()
        self.client.upload.assert_not_called()

    def test_cli_prepare_and_default_preview_save_local_plan_and_log_only(self):
        manifest = self.root / 'plan.json'
        journal = self.root / 'results.jsonl'
        self.client.team.return_value = team()
        with patch.object(uploads, 'ApiClient', return_value=self.client), redirect_stdout(StringIO()):
            self.assertEqual(uploads.main(['prepare', '--scope', 'pit', '--stage', 'PIT Exhibit',
                '--team-id', '7', '--files-root', str(self.root), '--manifest', str(manifest)]), 0)
            self.assertEqual(uploads.main(['run', '--manifest', str(manifest), '--journal', str(journal)]), 0)
        self.client.upload.assert_not_called()
        records = [json.loads(line) for line in journal.read_text(encoding='utf-8').splitlines()]
        self.assertEqual(records[0]['status'], 'ready')
        self.assertEqual(records[0]['sha256'], uploads.file_digest(self.path))
        self.assertNotIn('Authorization', journal.read_text(encoding='utf-8'))
        self.assertEqual(json.loads(manifest.read_text(encoding='utf-8'))['scope'], 'pit')

    def test_cli_deliverable_option_prepares_team_filename_plan(self):
        manifest = self.root / 'one-deliverable.json'
        (self.root / 'Team_A_Anything.pdf').write_bytes(b'Team A document')
        with patch.object(uploads, 'ApiClient', return_value=self.client), redirect_stdout(StringIO()):
            self.assertEqual(uploads.main(['prepare', '--scope', 'pit', '--stage', 'PIT Exhibit',
                '--all-teams', '--deliverable', 'Concept Paper', '--files-root', str(self.root),
                '--manifest', str(manifest)]), 0)
        plan = json.loads(manifest.read_text(encoding='utf-8'))
        self.assertEqual(plan['items'][0]['file'], 'Team_A_Anything.pdf')
        self.client.upload.assert_not_called()

    def test_simple_command_previews_or_uploads_without_a_manifest(self):
        (self.root / 'Team_A_Anything.pdf').write_bytes(b'Team A paper')
        current = team(upload_actor={'id': 70, 'username': 'student70'})
        self.client.student_leaders = True
        self.client.teams.return_value['teams'] = [current]
        self.client.team.return_value = current
        self.client.upload.return_value = {'submission_id': 42}
        arguments = ['--all-teams', '--year', '1', '--files', str(self.root), '--deliverable', 'D1']
        with patch.object(uploads, 'ROOT', self.root), patch.object(uploads, 'batch_stage', return_value='PIT Exhibit'), \
                patch.object(uploads, 'StudentLeaderBatch', return_value=self.client), redirect_stdout(StringIO()):
            self.assertEqual(uploads.main(arguments + ['--dry-run']), 0)
            self.client.upload.assert_not_called()
            self.assertEqual(uploads.main(arguments), 0)
        self.client.upload.assert_called_once()
        self.assertEqual(self.client.upload.call_args.args[0]['upload_as'], 'student_leaders')
        self.assertEqual(self.client.upload.call_args.args[1]['file'], 'Team_A_Anything.pdf')
        self.assertFalse(list(self.root.rglob('*.json')))
        self.assertFalse(list(self.root.rglob('*.lock')))

    def test_all_pre_batch_routes_deliverable_folders_and_preserves_post_exclusion(self):
        current = team()
        current['selected_stage']['pre'].append(requirement(id='D2', label='Pitch Deck', file_format='presentation'))
        current['selected_stage']['post'] = [requirement(id='D3', label='Approved Paper', type='post')]
        for filename in ['D1/01_Team_A_Any_name.pdf', 'Pitch Deck/02_Team_A_Anything.pptx']:
            path = self.root / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'Team A distinct document')
        self.client.teams.return_value['teams'] = [current]
        plan = uploads.prepare_plan(self.client, scope='pit', stage='PIT Exhibit',
            files_root=self.root, all_teams=True, batch_folders=True)
        self.assertEqual([(item['deliverable_id'], item['file']) for item in plan['items']],
                         [('D1', 'D1/01_Team_A_Any_name.pdf'), ('D2', 'Pitch Deck/02_Team_A_Anything.pptx')])
        uploads.validate_plan(plan)

    def test_all_pre_folder_override_and_pdf_variant_select_exact_files(self):
        row = requirement(label='Cocept Paper')
        folder = self.root / 'Concept Paper'
        for filename in ['PDF/Team_A_Draft.pdf', 'Editable_DOCX/Team_A_Draft.docx']:
            path = folder / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'Sample format')
        plan = self.plan(row, batch_folders=True, folder_overrides={'d1': 'Concept Paper'})
        self.assertEqual(plan['items'][0]['file'], 'Concept Paper/PDF/Team_A_Draft.pdf')
        for mapping in [{'bad': 'Concept Paper'}, {'d1': '../outside'}]:
            with self.subTest(mapping=mapping), self.assertRaises(uploads.UploadError):
                self.plan(row, batch_folders=True, folder_overrides=mapping)

    def test_all_pre_named_document_groups_use_document_folders(self):
        row = requirement(file_policy={'mode': 'named'}, document_slots=[
            {'key': 'paper', 'label': 'Paper', 'file_format': 'pdf'},
            {'key': 'notes', 'label': 'Notes', 'file_format': 'pdf'}])
        for document in ['paper', 'notes']:
            path = self.root / 'D1' / document / 'Team_A_Anything.pdf'
            path.parent.mkdir(parents=True)
            path.write_bytes(document.encode())
        plan = self.plan(row, batch_folders=True)
        self.assertEqual([(item['slot_key'], item['file']) for item in plan['items']],
                         [('paper', 'D1/paper/Team_A_Anything.pdf'), ('notes', 'D1/notes/Team_A_Anything.pdf')])

    def test_numbered_filename_never_assigns_a_team_by_its_number(self):
        path = self.root / '07_Team_B_Concept_Paper.pdf'
        path.write_bytes(b'Team B paper')
        matches = uploads.team_filename_files(self.root, [team(), team(id=8, name='Team B')])
        self.assertEqual(matches[7], [])
        self.assertEqual(matches[8], [path])

    def test_simple_year_numbers_and_explicit_stage(self):
        for value in ['1', '1st', '1st Year']:
            self.assertEqual(uploads.year_label(value), '1st Year')
        self.assertEqual(uploads.year_label('3'), '3rd Year')
        with patch.object(uploads, 'local_read_only') as database:
            self.assertEqual(uploads.batch_stage('pit', '1st Year', 'My event'), 'My event')
        database.assert_not_called()

    def test_simple_command_reports_stage_ambiguity_and_closes_on_invalid_mapping(self):
        with patch.object(uploads, 'batch_stage', side_effect=uploads.UploadError('Choose --stage explicitly.')), \
                patch.object(uploads, 'StudentLeaderBatch') as client, redirect_stderr(StringIO()):
            self.assertEqual(uploads.main(['--all-teams', '--files', str(self.root), '--dry-run']), 1)
        client.assert_not_called()
        with patch.object(uploads, 'StudentLeaderBatch') as client, redirect_stderr(StringIO()):
            self.assertEqual(uploads.main(['--all-teams', '--files', str(self.root),
                                          '--folder', 'missing equals', '--dry-run']), 1)
        client.assert_not_called()


class TransportTests(unittest.TestCase):
    def test_upload_sends_real_multipart_bytes_without_replacement_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'paper.pdf'
            path.write_bytes(b'%PDF sample')
            session = Mock()
            def respond(method, url, **kwargs):
                self.assertEqual((method, url), ('POST', 'http://localhost:8000' + uploads.API + 'upload/'))
                self.assertEqual(kwargs['files']['file'][1].read(), b'%PDF sample')
                self.assertEqual(kwargs['data']['slot_key'], 'c1:paper')
                self.assertEqual(kwargs['data']['file_name'], 'Recommended_Paper.pdf')
                self.assertEqual(kwargs['files']['file'][0], 'Recommended_Paper.pdf')
                self.assertNotIn('use_recommended_name', kwargs['data'])
                self.assertNotIn('file_id', kwargs['data'])
                self.assertFalse(kwargs['allow_redirects'])
                return Mock(status_code=200, json=lambda: {'submission_id': 1})
            session.request.side_effect = respond
            client = uploads.ApiClient('http://localhost:8000', session=session)
            client.upload({'scope': 'pit', 'stage': 'Exhibit'},
                {'team_id': 7, 'deliverable_id': 'D1', 'slot_key': 'c1:paper',
                 'repository_file_name': 'Recommended_Paper.pdf'}, path)

    def test_timeout_never_retries_post(self):
        session = Mock()
        session.request.side_effect = requests.Timeout()
        client = uploads.ApiClient('http://localhost:8000', session=session)
        with self.assertRaisesRegex(uploads.UploadError, 'Rerun'):
            client.request('POST', uploads.API + 'upload/')
        session.request.assert_called_once()

    def test_scope_fallback_or_changed_active_term_is_rejected(self):
        client = uploads.ApiClient('http://localhost:8000', session=Mock())
        with patch.object(client, 'request', return_value={'selected_stage': 'Other event'}):
            with self.assertRaises(uploads.UploadError):
                client.teams(scope='pit', stage='PIT Exhibit')
        with patch.object(client, 'teams', return_value={'active_semester': {'id': 3}}):
            with self.assertRaisesRegex(uploads.UploadError, 'semester changed'):
                client.team({'scope': 'pit', 'stage': 'PIT Exhibit', 'semester_id': 2}, 7)

    def test_redirects_and_errors_are_reported(self):
        for status in [302, 400, 401, 403, 429, 500]:
            session = Mock()
            session.request.return_value = Mock(status_code=status, json=lambda: {'detail': 'fixture error'})
            with self.assertRaisesRegex(uploads.UploadError, str(status)):
                uploads.ApiClient('http://localhost:8000', session=session).request('GET', uploads.API)

    def test_url_credentials_and_paths_are_rejected(self):
        for url in ['file:///secret', 'https://name:password@example.test', 'http://localhost/api/', 'http://localhost/?token=x']:
            with self.assertRaises(uploads.UploadError):
                uploads.server_url(url)

    def test_environment_token_is_used_without_login_or_credential_changes(self):
        session = Mock(headers={})
        with patch.dict('os.environ', {'TEST_UPLOAD_TOKEN': 'example-token'}):
            uploads.ApiClient('http://localhost:8000', session=session).authenticate(token_env='TEST_UPLOAD_TOKEN')
        self.assertEqual(session.headers['Authorization'], 'Bearer example-token')
        session.request.assert_not_called()


class StudentLeaderRoutingTests(unittest.TestCase):
    def setUp(self):
        self.records = [{'team_id': 7, 'leader_id': 70, 'username': 'student70'},
                        {'team_id': 8, 'leader_id': 80, 'username': 'student80'}]
        self.clients = {}
        def make_client(base_url):
            client = Mock(base_url=base_url)
            def teams(**kwargs):
                number = kwargs['team_id']
                return {'active_semester': {'id': 2}, 'teams': [team(id=number)]}
            client.teams.side_effect = teams
            self.clients[len(self.clients)] = client
            return client
        for target, effect in [('ApiClient', make_client),
                ('student_access_token', lambda record: f'token-{record["leader_id"]}')]:
            patched = patch.object(uploads, target, side_effect=effect)
            patched.start()
            self.addCleanup(patched.stop)
        self.batch = uploads.StudentLeaderBatch('http://localhost:8000')
        self.addCleanup(self.batch.close)

    def discovery(self, **kwargs):
        ids = kwargs.get('team_ids')
        return 2, [record for record in self.records if ids is None or record['team_id'] in ids]

    def test_discovery_uses_separate_student_tokens_and_records_every_actor(self):
        with patch.object(uploads, 'discover_student_teams', side_effect=self.discovery):
            payload = self.batch.teams(scope='pit', stage='PIT Exhibit')
        self.assertEqual([item['upload_actor'] for item in payload['teams']],
                         [{'id': 70, 'username': 'student70'}, {'id': 80, 'username': 'student80'}])
        self.clients[0].session.headers.update.assert_called_once_with({'Authorization': 'Bearer token-70'})
        self.clients[1].session.headers.update.assert_called_once_with({'Authorization': 'Bearer token-80'})
        self.clients[0].authenticate.assert_not_called()
        self.clients[1].authenticate.assert_not_called()

    def test_upload_routes_to_own_leader_and_stale_leader_is_blocked(self):
        plan = {'scope': 'pit', 'stage': 'PIT Exhibit', 'semester_id': 2,
                'uploaders': {'7': {'id': 70, 'username': 'student70'}}}
        with patch.object(uploads, 'discover_student_teams', side_effect=self.discovery):
            self.batch.upload(plan, {'team_id': 7}, Path('paper.pdf'))
            self.assertEqual(len(self.clients), 1)
            self.clients[0].upload.assert_called_once()
            self.records[0]['leader_id'] = 99
            with self.assertRaisesRegex(uploads.UploadError, 'leader changed'):
                self.batch.upload(plan, {'team_id': 7}, Path('paper.pdf'))
        self.clients[0].upload.assert_called_once()

    def test_student_plan_cannot_fall_back_to_staff_client(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = {'schema_version': 1, 'base_url': 'http://localhost:8000', 'scope': 'pit',
                    'stage': 'PIT Exhibit', 'semester_id': 2, 'files_root': str(Path(directory).resolve()),
                    'items': [], 'upload_as': 'student_leaders', 'uploaders': {}}
            with self.assertRaisesRegex(uploads.UploadError, 'student leaders'):
                uploads.run_plan(Mock(base_url='http://localhost:8000'), plan, apply=True)


if __name__ == '__main__':
    unittest.main()
