from datetime import date, time
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import DefenseSchedule, PanelistEvaluationDraft
from defense.stages.models import DefenseStage
from defense.stages.serializers import StageDeliverableSerializer
from grading.grades.models import TeamGrade, StudentStageGrade
from grading.rubrics.models import Rubric
from repository.deliverables.models import DeliverableSubmission
from repository.section_concepts.models import SharedDeliverableSet, SharedDeliverableFile
from student_teams.models import StudentTeam, TeamStageProgress, SectionAssignment
from defense.shared_deliverables import validate_shared_deliverables


@override_settings(PASSWORD_HASHERS=['django.contrib.auth.hashers.MD5PasswordHasher'])
class StageConfigurationIntegrityTests(APITestCase):
    def setUp(self):
        users = get_user_model()
        self.admin = users.objects.create_user(username='integrity-admin', role='admin', is_staff=True)
        self.student = users.objects.create_user(username='integrity-student', role='student')
        self.panelist = users.objects.create_user(username='integrity-panelist', role='faculty')
        self.semester = Semester.objects.create(school_year=SchoolYear.objects.create(label='2026-2027'),
                                               label=Semester.FIRST, is_active=True)
        self.stage = DefenseStage.objects.create(label='Integrity Stage', display_order=4, qualifying_score=75)
        self.team = StudentTeam.objects.create(name='Integrity Team', project_title='Integrity Project',
            semester=self.semester, year_level='3rd Year', level=StudentTeam.LEVEL_3_CAPSTONE, leader=self.student)
        self.used = self.stage.deliverables.create(deliverable_id='D1', label='Manuscript', required=True)
        self.unused = self.stage.deliverables.create(deliverable_id='D2', label='Unused Requirement', required=True)
        self.url = f'/api/defense/stages/{self.stage.pk}/'
        self.client.force_authenticate(self.admin)

    def submission(self):
        return DeliverableSubmission.objects.create(team=self.team, stage_label=self.stage.label,
            deliverable_id=self.used.deliverable_id, label=self.used.label, deliverable_type='pre',
            file='deliverables/original.pdf', file_name='original.pdf', extracted_text='Evidence')

    def schedule(self):
        return DefenseSchedule.objects.create(team=self.team, defense_stage=self.stage, semester=self.semester,
            scheduled_date=date(2026, 10, 27), start_time=time(9), slot_duration=60, room='Integrity Room')

    def row(self, requirement):
        return dict(StageDeliverableSerializer(requirement).data)

    def grade(self, **fields):
        return TeamGrade.objects.create(team=self.team, semester=self.semester, defense_stage=self.stage,
                                       stage_label=self.stage.label, **fields)

    def test_scheduled_endorsed_stage_can_add_edit_delete_unused_requirements(self):
        self.schedule()
        progress, _ = TeamStageProgress.objects.update_or_create(team=self.team, semester=self.semester,
            defense_stage=self.stage, defaults={'status': TeamStageProgress.STATUS_READY})
        self.team.ready_for_stage = self.stage.label
        self.team.save(update_fields=['ready_for_stage'])
        response = self.client.get(self.url)
        self.assertFalse(response.data['stage']['is_locked'])
        self.assertTrue(response.data['stage']['structure_locked'])
        self.assertFalse(response.data['stage']['can_delete'])
        added = self.client.post(self.url + 'deliverables/', {
            'deliverable_id': 'D3', 'label': 'Presentation', 'deliverable_type': 'pre'}, format='json')
        self.assertEqual(added.status_code, 201, added.data)
        updated = self.client.patch(self.url + f'deliverables/{self.unused.pk}/',
                                    {'label': 'Revised Requirement'}, format='json')
        self.assertEqual(updated.status_code, 200, updated.data)
        deleted = self.client.delete(self.url + f'deliverables/{self.unused.pk}/')
        self.assertEqual(deleted.status_code, 204)
        progress.refresh_from_db()
        self.team.refresh_from_db()
        self.assertEqual(progress.status, TeamStageProgress.STATUS_READY)
        self.assertEqual(self.team.ready_for_stage, self.stage.label)

    def test_submitted_requirement_is_locked_but_unused_requirements_remain_editable(self):
        self.submission()
        response = self.client.get(self.url)
        rows = {row['id']: row for row in response.data['stage']['deliverables']}
        self.assertTrue(rows[self.used.pk]['has_data'])
        self.assertTrue(rows[self.used.pk]['is_locked'])
        self.assertFalse(rows[self.unused.pk]['is_locked'])
        for field, value in [('label', 'Changed'), ('deliverable_id', 'RENAMED'),
                             ('required', False), ('file_policy', {'mode': 'multiple'})]:
            response = self.client.patch(self.url + f'deliverables/{self.used.pk}/', {field: value}, format='json')
            self.assertEqual(response.status_code, 400, (field, response.data))
        self.assertEqual(self.client.delete(self.url + f'deliverables/{self.used.pk}/').status_code, 409)
        response = self.client.patch(self.url + f'deliverables/{self.unused.pk}/', {'label': 'New name'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(DeliverableSubmission.all_objects.count(), 1)

    def test_bulk_save_preserves_used_requirement_and_accepts_new_requirement_after_scheduling(self):
        self.submission()
        self.schedule()
        unused = {**self.row(self.unused), 'label': 'Slides'}
        response = self.client.patch(self.url, {'deliverables': [self.row(self.used), unused,
            {'deliverable_id': 'D3', 'label': 'Demo video', 'deliverable_type': 'pre'}]}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.used.refresh_from_db()
        self.assertEqual(self.used.label, 'Manuscript')
        self.assertEqual(self.stage.deliverables.count(), 3)

    def test_bulk_removal_or_rename_of_used_requirement_is_atomic(self):
        self.submission()
        for rows in (
            [{**self.row(self.unused), 'label': 'Would change'}],
            [{**self.row(self.used), 'deliverable_id': 'NEW'}, self.row(self.unused)],
        ):
            response = self.client.patch(self.url, {'deliverables': rows}, format='json')
            self.assertEqual(response.status_code, 400, response.data)
            self.unused.refresh_from_db()
            self.assertEqual(self.unused.label, 'Unused Requirement')
            self.assertEqual(self.stage.deliverables.count(), 2)
        self.assertEqual(DeliverableSubmission.all_objects.count(), 1)

    def test_archived_project_submission_and_file_history_still_protect_requirement(self):
        submission = self.submission()
        submission.files.create(slot_key='primary', file='deliverables/prior.pdf',
            file_name='prior.pdf', extracted_text='Previous evidence', revision=1, is_current=False)
        DeliverableSubmission.all_objects.filter(pk=submission.pk).update(file='', file_name='')
        StudentTeam.objects.filter(pk=self.team.pk).update(project_version=2)
        self.assertFalse(DeliverableSubmission.objects.filter(pk=submission.pk).exists())
        self.assertEqual(self.client.delete(self.url + f'deliverables/{self.used.pk}/').status_code, 409)
        self.assertEqual(self.client.delete(self.url).status_code, 409)
        self.assertTrue(submission.files.exists())

    def test_stage_with_submissions_cannot_be_renamed_or_deleted_without_grades(self):
        self.submission()
        response = self.client.patch(self.url, {'label': 'Renamed'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(self.client.delete(self.url).status_code, 409)
        self.assertTrue(DefenseStage.objects.filter(pk=self.stage.pk).exists())

    def test_empty_pending_grade_scaffold_does_not_lock_configuration(self):
        self.grade()
        response = self.client.get(self.url)
        self.assertFalse(response.data['stage']['is_locked'])
        response = self.client.patch(self.url + f'deliverables/{self.unused.pk}/', {'label': 'Allowed'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)

    def test_zero_pending_score_locks_all_configuration_including_outcome_policy(self):
        self.grade(panel_score=Decimal('0'))
        self.assertTrue(self.client.get(self.url).data['stage']['is_locked'])
        for payload in ({'qualifying_score': 80}, {'score_carryover': 'retain'},
                        {'description': 'Changed'}, {'deliverables': []}):
            response = self.client.patch(self.url, payload, format='json')
            self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(self.client.post(self.url + 'deliverables/', {
            'deliverable_id': 'D3', 'label': 'Blocked'}, format='json').status_code, 400)
        self.assertEqual(self.client.patch(self.url + 'grading-config/', {
            'panel_weight': 60, 'adviser_weight': 20, 'peer_weight': 20}, format='json').status_code, 400)
        self.assertEqual(self.client.delete(self.url + f'deliverables/{self.unused.pk}/').status_code, 400)
        self.assertEqual(self.client.delete(self.url).status_code, 409)

    def test_saved_zero_draft_locks_configuration_but_empty_draft_does_not(self):
        draft = PanelistEvaluationDraft.objects.create(schedule=self.schedule(), panelist=self.panelist,
            context_signature='integrity', submissions=[{'criteria_scores': []}])
        self.assertFalse(self.client.get(self.url).data['stage']['is_locked'])
        draft.submissions = [{'criteria_scores': [{'criterion_id': 1, 'score': 0}]}]
        draft.save()
        self.assertTrue(self.client.get(self.url).data['stage']['is_locked'])
        response = self.client.patch(self.url + f'deliverables/{self.unused.pk}/', {'label': 'Blocked'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)

    def test_individual_score_and_old_project_grades_lock_stage(self):
        grade = self.grade()
        StudentStageGrade.objects.create(team_grade=grade, student=self.student, adviser_score=0)
        StudentTeam.objects.filter(pk=self.team.pk).update(project_version=2)
        self.assertFalse(TeamGrade.objects.filter(pk=grade.pk).exists())
        self.assertTrue(self.client.get(self.url).data['stage']['is_locked'])

    def shared(self):
        definitions = validate_shared_deliverables([
            {'deliverable_id': 'SHARED_D1', 'label': 'Shared manuscript', 'deliverable_type': 'pre',
             'required': True, 'file_format': 'pdf', 'file_policy': {}},
            {'deliverable_id': 'SHARED_D2', 'label': 'Unused shared file', 'deliverable_type': 'pre',
             'required': True, 'file_format': 'pdf', 'file_policy': {}},
        ], {})
        self.stage.shared_deliverables = definitions
        self.stage.save(update_fields=['shared_deliverables'])
        section = SectionAssignment.objects.create(section='Integrity Section', semester=self.semester,
            year_level=self.team.year_level, project_manager=self.student)
        captured = SharedDeliverableSet.objects.create(section=section, defense_stage=self.stage,
            identity='integrity', requirements=definitions, project_manager=self.student)
        SharedDeliverableFile.objects.create(submission_set=captured, deliverable_id='SHARED_D1',
            slot_key='primary', file='shared/original.pdf', file_name='original.pdf', file_size=10,
            is_current=False, uploaded_by=self.student)
        return definitions, captured

    def test_shared_file_history_protects_only_used_requirement_and_late_additions_reach_existing_sets(self):
        definitions, captured = self.shared()
        response = self.client.get(self.url)
        rows = response.data['stage']['shared_deliverables']
        self.assertTrue(rows[0]['is_locked'])
        self.assertFalse(rows[1]['is_locked'])
        changed = [definitions[0], {**definitions[1], 'label': 'Updated shared file'},
            {'deliverable_id': 'SHARED_D3', 'label': 'New shared file', 'deliverable_type': 'pre'}]
        response = self.client.patch(self.url, {'shared_deliverables': changed}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        captured.refresh_from_db()
        self.assertEqual([row['label'] for row in captured.requirements],
                         ['Shared manuscript', 'Updated shared file', 'New shared file'])
        response = self.client.patch(self.url, {'shared_deliverables': changed[1:]}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(SharedDeliverableFile.objects.count(), 1)

    def test_linked_shared_upload_also_locks_its_team_requirement(self):
        definitions, captured = self.shared()
        definitions[0]['team_deliverable_id'] = self.used.deliverable_id
        self.stage.shared_deliverables = definitions
        self.stage.save(update_fields=['shared_deliverables'])
        self.assertTrue(self.row(self.used)['has_data'])
        response = self.client.patch(self.url + f'deliverables/{self.used.pk}/', {'label': 'Blocked'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(self.client.delete(self.url + f'deliverables/{self.used.pk}/').status_code, 409)

    def test_direct_edits_and_deletion_sync_an_unused_linked_shared_requirement(self):
        definitions, captured = self.shared()
        definitions[1]['team_deliverable_id'] = self.unused.deliverable_id
        self.stage.shared_deliverables = definitions
        self.stage.save(update_fields=['shared_deliverables'])
        response = self.client.patch(self.url + f'deliverables/{self.unused.pk}/', {'label': 'Renamed unused'}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.stage.refresh_from_db()
        captured.refresh_from_db()
        self.assertEqual(self.stage.shared_deliverables[1]['label'], 'Renamed unused')
        self.assertEqual(captured.requirements[1]['label'], 'Renamed unused')
        response = self.client.delete(self.url + f'deliverables/{self.unused.pk}/')
        self.assertEqual(response.status_code, 204, getattr(response, 'data', None))
        self.stage.refresh_from_db()
        captured.refresh_from_db()
        self.assertEqual([row['deliverable_id'] for row in self.stage.shared_deliverables], ['SHARED_D1'])
        self.assertEqual([row['deliverable_id'] for row in captured.requirements], ['SHARED_D1'])

    def test_saved_score_also_locks_attached_rubrics_without_a_schedule(self):
        rubric = Rubric.objects.create(name='Protected rubric', semester=self.semester,
            scope='capstone', evaluation_type='panel', defense_stage=self.stage, status='published')
        self.grade(adviser_score=0)
        response = self.client.get(f'/api/grading/rubrics/{rubric.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data['rubric']['is_locked'])
        response = self.client.patch(f'/api/grading/rubrics/{rubric.pk}/', {
            'name': 'Changed rubric', 'scope': 'capstone', 'semester_id': self.semester.pk,
            'defense_stage_id': self.stage.pk, 'evaluation_type': 'panel',
            'criteria': [{'name': 'Criterion', 'weight': 100}],
        }, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        response = self.client.delete(f'/api/grading/rubrics/{rubric.pk}/')
        self.assertEqual(response.status_code, 400, response.data)
