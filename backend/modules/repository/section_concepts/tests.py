from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone
from rest_framework.test import APITestCase

from defense.scheduler.models import DefenseSchedule
from grading.grades.services import GradeContextService, submit_panelist_grade
from repository.deliverables import concepts
from repository.deliverables.models import ConceptRound
from repository.deliverables.services import upsert_submission, review_submission, endorse_team
from repository.deliverables import test_pit_concepts as fixtures
from student_teams.models import StudentTeam, TeamMembership
from student_teams.concept_policy import resolve_policy
from user_management.models import SectionInstructorAssignment
from user_management.academic_records.models import StudentAcademicRecord
from . import services
from .models import SectionConceptProject, SectionConceptPaper

URL = '/api/repository/section-concepts/'
User = get_user_model()


class SharedSystemConceptTests(APITestCase):
    rubric = fixtures.PitConceptTests.rubric
    data = fixtures.PitConceptTests.data
    slot = fixtures.PitConceptTests.slot
    configure = fixtures.PitConceptTests.configure

    def setUp(self):
        fixtures.PitConceptTests.setUp(self)
        self.team.section = 'BSIT-1A'
        self.team.save()
        self.pm = self.team.leader
        student = User.objects.create_user(username='shared-module-leader', role='student')
        self.module_team = StudentTeam.objects.create(name='Shared Module Team', semester=self.semester,
            section=self.team.section, year_level=self.team.year_level, level=self.team.level, leader=student)
        TeamMembership.objects.create(team=self.module_team, student=student, is_leader=True)
        for person in (self.pm, student):
            StudentAcademicRecord.objects.create(student=person, semester=self.semester,
                year_level=self.team.year_level, section=self.team.section)
        SectionInstructorAssignment.objects.create(faculty=self.first, semester=self.semester,
            year_level=self.team.year_level, section=self.team.section)
        self.project = services.configure(self.first, [self.team, self.module_team], self.event,
            {'project_manager_id': self.pm.pk, 'reviewer_id': self.first.pk})

    def titles(self, prefix='System'):
        return [{'key': key, 'title': f'{prefix} {key}'} for key in services.KEYS]

    def action(self, action, actor=None, **data):
        actor = actor or self.first
        self.client.force_authenticate(actor)
        state = services.payload(self.project, actor)
        return self.client.post(f'{URL}{self.project.pk}/', {'action': action,
            'round_id': state['round_id'], 'review_token': state['review_token'], **data}, format='json')

    def prepare_shared(self):
        services.save_system_titles(self.project, self.first, self.titles())
        for key in services.KEYS:
            paper = services.upload(self.project, self.pm, key,
                SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 shared test paper'))
            services.review(self.project, self.first, paper.pk, 'accepted')
        self.assertTrue(services.shared_clearance(services.latest(self.project)))

    def prepare_team(self, team):
        concepts.save_titles(team, self.event, self.titles('Module'), actor=self.first)
        for key in services.KEYS:
            sub = upsert_submission(team, self.event.label, 'CONCEPTS', f'{key}.pdf', '10 B', team.leader,
                file=SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 module test'), slot_key=f'{key}:paper')
            review_submission(team, self.event.label, 'CONCEPTS', 'accepted', '', self.first,
                file_id=sub.files.get(is_current=True, slot_key=f'{key}:paper').pk)
        endorse_team(team, self.event.label, self.first)

    def hearing(self, *, evaluated=True):
        self.prepare_shared()
        schedules = []
        for index, team in enumerate((self.team, self.module_team)):
            self.prepare_team(team)
            self.client.force_authenticate(self.first)
            response = self.client.post('/api/defense/schedules/', self.slot(team,
                scheduled_date=str(timezone.localdate()), start_time=f'{9 + index}:00',
                chair_panelist_id=self.panelist.pk), format='json')
            self.assertEqual(response.status_code, 201, response.data)
            schedule = DefenseSchedule.objects.filter(team=team).latest('pk')
            if evaluated:
                grade, _, _ = GradeContextService.get_or_create_for_schedule(schedule)
                submit_panelist_grade(schedule, grade,
                    [{'criterion_id': self.panel.criteria.first().pk, 'score': 8}], panelist=self.panelist)
            schedules.append(schedule)
        services.schedule_hearing(self.project, self.first, [s.pk for s in schedules])
        return schedules

    def select(self, *, actor=None, rejected=False):
        return self.action('decide', actor or self.panelist, verdict='for_redefense' if rejected else 'approved',
            remarks='Prepare replacement system proposals.' if rejected else '', concepts=[
                {'key': key, 'decision': 'rejected' if rejected else 'approved' if key == 'c2' else 'not_selected',
                 'remarks': 'Replace this system.' if rejected else ''} for key in services.KEYS])

    def test_shared_policy_has_three_modules_and_one_shared_set(self):
        for team in (self.team, self.module_team):
            policy = resolve_policy(team, self.event)
            self.assertEqual((policy['source'], policy['required_count']), ('section_system', 3))
            self.assertEqual(concepts.get_round(team, self.event).section_round_id, services.latest(self.project).pk)
        self.assertEqual(self.project.rounds.get().systems.count(), 3)

    def test_team_list_exposes_proposals_before_official_project_selection_without_writes(self):
        services.save_system_titles(self.project, self.pm, self.titles('Proposed system'))
        concepts.save_titles(self.team, self.event, self.titles('Proposed module'), actor=self.pm)
        self.team.project_title = ''
        self.team.project_pending = True
        self.team.save(update_fields=['project_title', 'project_pending'])
        before = (ConceptRound.objects.count(), SectionConceptProject.objects.count(), SectionConceptPaper.objects.count())
        self.client.force_authenticate(self.first)
        response = self.client.get('/api/teams/?workspace=operations&scope=active')
        self.assertEqual(response.status_code, 200, response.data)
        team = next(t for t in response.data['teams'] if t['id'] == self.team.pk)
        workflow = team['defense_context']['concept_workflow']
        self.assertEqual(workflow['section_project_id'], self.project.pk)
        self.assertEqual([s['title'] for s in workflow['system_concepts']],
                         [t['title'] for t in self.titles('Proposed system')])
        self.assertEqual([s['title'] for s in workflow['concepts']],
                         [t['title'] for t in self.titles('Proposed module')])
        self.assertEqual(team['project_title'], '')
        self.assertTrue(team['project_pending'])
        self.assertEqual(before, (ConceptRound.objects.count(), SectionConceptProject.objects.count(), SectionConceptPaper.objects.count()))

    def test_inline_review_readiness_requires_confirmed_names_and_all_accepted_papers(self):
        self.assertFalse(services.payload(self.project, self.first)['can_endorse'])
        services.save_system_titles(self.project, self.pm, self.titles())
        for key in services.KEYS:
            paper = services.upload(self.project, self.pm, key,
                SimpleUploadedFile(f'{key}.pdf', b'%PDF-1.4 readiness paper'))
            services.review(self.project, self.first, paper.pk, 'accepted')
        state = services.payload(self.project, self.first)
        self.assertEqual(state['review_progress'], {'required': 3, 'names_confirmed': 0,
            'papers_uploaded': 3, 'papers_accepted': 3})
        self.assertFalse(state['can_endorse'])
        services.save_system_titles(self.project, self.first, self.titles())
        self.assertTrue(services.payload(self.project, self.first)['cleared'])
        self.assertFalse(services.payload(self.project, self.pm)['can_endorse'])
        services.endorse(self.project, self.first)
        self.assertFalse(services.payload(self.project, self.first)['can_endorse'])
        row = services.latest(self.project).systems.get(key='c1').papers.get(is_current=True)
        services.review(self.project, self.first, row.pk, 'rejected', 'Clarify the system scope.')
        self.assertFalse(services.payload(self.project, self.first)['can_endorse'])

    def test_per_system_upload_permission_matches_accepted_paper_replacement_rules(self):
        state = services.payload(self.project, self.pm)
        self.assertTrue(all(s['can_upload'] for s in state['systems']))
        row = services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('p.pdf', b'%PDF-1.4'))
        services.review(self.project, self.first, row.pk, 'accepted')
        state = services.payload(self.project, self.pm)
        self.assertFalse(next(s for s in state['systems'] if s['key'] == 'c1')['can_upload'])
        self.assertTrue(next(s for s in state['systems'] if s['key'] == 'c2')['can_upload'])
        self.assertFalse(any(s['can_upload'] for s in services.payload(self.project, self.first)['systems']))
        services.review(self.project, self.first, row.pk, 'rejected', 'Clarify scope before replacing.')
        self.assertTrue(next(s for s in services.payload(self.project, self.pm)['systems']
            if s['key'] == 'c1')['can_upload'])

    def test_automatic_shared_clearance_keeps_team_endorsements_independent(self):
        self.prepare_shared()
        self.assertIsNone(services.latest(self.project).endorsed_at)
        self.assertEqual(services.task_payload(self.first), [])
        self.prepare_team(self.team)
        self.assertFalse(concepts.clearance_blocker(self.team, self.event))
        self.assertTrue(concepts.clearance_blocker(self.module_team, self.event))
        self.module_team.refresh_from_db()
        self.assertIsNone(self.module_team.ready_for_stage)

    def test_title_change_requires_new_acceptance_and_invalidates_unscheduled_team_clearance(self):
        self.prepare_shared()
        self.prepare_team(self.team)
        changed = self.titles()
        changed[0]['title'] = 'Revised system scope'
        services.save_system_titles(self.project, self.first, changed)
        round = services.latest(self.project)
        self.assertFalse(services.shared_clearance(round))
        paper = round.systems.get(key='c1').papers.get(is_current=True)
        self.assertEqual(paper.status, 'pending')
        self.assertFalse(concepts.clearance_valid(self.team, self.event))
        self.assertEqual(round.systems.get(key='c2').papers.get(is_current=True).status, 'accepted')
        services.review(self.project, self.first, paper.pk, 'accepted')
        self.assertTrue(services.shared_clearance(services.latest(self.project)))
        self.assertFalse(concepts.clearance_valid(self.team, self.event))

    def test_stale_paper_review_after_title_change_is_rejected(self):
        self.prepare_shared()
        state = services.payload(self.project, self.first)
        paper = state['systems'][0]['papers'][0]
        services.save_system_titles(self.project, self.first, self.titles('Changed'))
        self.client.force_authenticate(self.first)
        response = self.client.post(f'{URL}{self.project.pk}/', {'action': 'review',
            'round_id': state['round_id'], 'review_token': state['review_token'],
            'paper_id': paper['id'], 'status': 'accepted'}, format='json')
        self.assertEqual(response.status_code, 409)

    def test_instructor_reviews_existing_student_files_without_upload_or_remove_access(self):
        from repository.deliverables.services import stage_payload
        concepts.save_titles(self.team, self.event, self.titles('Module'), actor=self.first)
        student_state = stage_payload(self.team, self.event.label, evaluator=self.pm)
        faculty_state = stage_payload(self.team, self.event.label, evaluator=self.first)
        self.assertTrue(student_state['pre'][0]['can_upload'])
        self.assertFalse(faculty_state['pre'][0]['can_upload'])
        self.assertTrue(faculty_state['pre'][0]['can_faculty_review'])
        self.client.force_authenticate(self.first)
        data = {'team_id': self.team.pk, 'stage_label': self.event.label,
            'deliverable_id': 'CONCEPTS', 'file_name': 'module.pdf', 'slot_key': 'c1:paper'}
        self.assertEqual(self.client.post('/api/repository/deliverables/upload/', data).status_code, 403)
        self.assertEqual(self.client.post('/api/repository/deliverables/remove/', data).status_code, 403)

    def test_project_list_team_filter_requires_current_link_and_keeps_year_permissions(self):
        self.client.force_authenticate(self.first)
        self.assertEqual([p['id'] for p in self.client.get(f'{URL}?team_id={self.team.pk}').data['projects']],
                         [self.project.pk])
        self.client.force_authenticate(self.second)
        self.assertEqual(self.client.get(f'{URL}?team_id={self.team.pk}').data['projects'], [])
        self.client.force_authenticate(self.first)
        self.team.project_version += 1
        self.team.save(update_fields=['project_version'])
        self.assertEqual(self.client.get(f'{URL}?team_id={self.team.pk}').data['projects'], [])

    def test_project_manager_leader_receives_both_tasks(self):
        self.client.force_authenticate(self.pm)
        response = self.client.get('/api/teams/my-setup/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['section_tasks'][0]['role'], 'project_manager')
        self.assertTrue(response.data['teams'][0]['concept_tasks'][0]['shared_system'])

    def test_instructor_and_manager_have_different_tasks(self):
        self.assertEqual(services.task_payload(self.first)[0]['role'], 'reviewer')
        self.assertEqual(services.task_payload(self.pm)[0]['role'], 'project_manager')
        self.assertEqual(services.task_payload(self.module_team.leader), [])

    def test_only_pm_uploads_and_only_reviewer_accepts_shared_papers(self):
        with self.assertRaises(PermissionError):
            services.upload(self.project, self.module_team.leader, 'c1', SimpleUploadedFile('p.pdf', b'%PDF-1.4'))
        row = services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('p.pdf', b'%PDF-1.4'))
        self.assertEqual(self.action('review', self.pm, paper_id=row.pk, status='accepted').status_code, 403)
        self.assertEqual(self.action('review', paper_id=row.pk, status='accepted').status_code, 200)

    def test_pdf_contents_are_validated(self):
        with self.assertRaises(ValidationError):
            services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('p.pdf', b'not a pdf'))
        self.assertFalse(SectionConceptPaper.objects.exists())

    def test_student_names_require_confirmation_and_confirmed_names_are_faculty_owned(self):
        self.assertEqual(self.action('save_titles', self.pm, concepts=self.titles()).status_code, 200)
        self.assertFalse(services.latest(self.project).systems.filter(confirmed=True).exists())
        self.assertEqual(self.action('save_titles', concepts=self.titles()).status_code, 200)
        self.assertEqual(self.action('save_titles', self.pm, concepts=self.titles('Changed')).status_code, 403)
        self.assertEqual(self.action('endorse').status_code, 400)

    def test_faculty_named_mode_still_requires_three_proposals(self):
        self.project.title_mode = 'faculty_provided'
        self.project.save()
        self.assertEqual(resolve_policy(self.team, self.event)['required_count'], 3)
        with self.assertRaises(PermissionError):
            concepts.save_titles(self.team, self.event, self.titles('Student module'), actor=self.pm)
        self.assertEqual(self.action('save_titles', self.pm, concepts=self.titles()).status_code, 403)
        self.assertEqual(self.action('confirm_modules', team_id=self.team.pk, concepts=self.titles('Faculty module')).status_code, 200)
        self.assertTrue(all(c['faculty_confirmed'] for c in concepts.latest_round(self.team, self.event).concepts))

    def test_other_year_cannot_list_view_change_or_download_shared_papers(self):
        row = services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('p.pdf', b'%PDF-1.4'))
        self.client.force_authenticate(self.second)
        self.assertEqual(self.client.get(URL).data['projects'], [])
        self.assertEqual(self.client.get(f'{URL}{self.project.pk}/').status_code, 404)
        self.assertEqual(self.client.get(f'{URL}{self.project.pk}/papers/{row.pk}/').status_code, 404)
        self.assertEqual(self.client.get('/api/media/files/' + row.file.name).status_code, 404)
        self.client.force_authenticate(self.module_team.leader)
        self.assertEqual(self.client.get(f'{URL}{self.project.pk}/papers/{row.pk}/').status_code, 200)

    def test_invited_guest_can_read_shared_papers_but_cannot_write_or_decide(self):
        from user_management.models import GuestPanelistCode
        from authentication_access_control.guest_tokens import create_guest_access_token
        schedules = self.hearing()
        invitation = GuestPanelistCode.objects.create(guest_name='Invited shared panelist',
            defense_schedule=schedules[0], expires_at=timezone.now() + timedelta(days=1))
        token = create_guest_access_token(invitation)
        self.client.force_authenticate(user=None)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        response = self.client.get(f'{URL}{self.project.pk}/')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['can_upload'])
        self.assertFalse(response.data['can_review'])
        self.assertFalse(response.data['can_decide'])
        row = SectionConceptPaper.objects.filter(concept__round=services.latest(self.project)).first()
        self.assertEqual(self.client.get(f'{URL}{self.project.pk}/papers/{row.pk}/').status_code, 200)
        self.assertEqual(self.client.post(f'{URL}{self.project.pk}/', {'action': 'decide'}, format='json').status_code, 403)
        invitation.is_active = False
        invitation.save()
        self.assertEqual(self.client.get(f'{URL}{self.project.pk}/papers/{row.pk}/').status_code, 401)
        self.client.credentials()

    def test_paper_replacement_keeps_history_and_requires_fresh_review(self):
        self.prepare_shared()
        round = services.latest(self.project)
        old = SectionConceptPaper.objects.get(concept__round=round, concept__key='c1', is_current=True)
        with self.assertRaises(ValidationError):
            services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('new.pdf', b'%PDF-1.4'))
        services.review(self.project, self.first, old.pk, 'rejected', 'Expand the integration design.')
        new = services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('new.pdf', b'%PDF-1.4 replacement'))
        old.refresh_from_db()
        self.assertFalse(old.is_current)
        self.assertEqual(new.revision, 2)
        self.assertFalse(services.shared_clearance(services.latest(self.project)))
        self.assertEqual(self.action('review', paper_id=old.pk, status='accepted').status_code, 400)

    def test_stale_endorsement_request_is_rejected(self):
        self.prepare_shared()
        state = services.payload(self.project, self.first)
        services.save_system_titles(self.project, self.first, self.titles('Renamed'))
        self.client.force_authenticate(self.first)
        response = self.client.post(f'{URL}{self.project.pk}/', {'action': 'endorse',
            'round_id': state['round_id'], 'review_token': state['review_token']}, format='json')
        self.assertEqual(response.status_code, 409)

    def test_scheduling_requires_both_section_clearance_and_module_name_confirmation(self):
        concepts.save_titles(self.team, self.event, self.titles('Module'), actor=self.pm)
        self.assertIn('shared system titles', concepts.clearance_blocker(self.team, self.event))
        self.prepare_shared()
        self.assertIn('confirm all three', concepts.clearance_blocker(self.team, self.event))

    def test_shared_system_decision_requires_completed_panel_assessments(self):
        self.hearing(evaluated=False)
        self.assertEqual(self.select().status_code, 400)
        self.assertFalse(services.latest(self.project).selected_key)

    def test_chair_selects_one_system_without_approving_any_team(self):
        self.hearing()
        response = self.select()
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['selected_key'], 'c2')
        for team in (self.team, self.module_team):
            self.assertEqual(concepts.latest_round(team, self.event).verdict, '')
        self.assertEqual(self.action('decide', self.pm, concepts=[], verdict='approved').status_code, 403)

    def test_module_approval_must_match_selected_system(self):
        schedules = self.hearing()
        self.assertEqual(self.select().status_code, 200)
        self.client.force_authenticate(self.panelist)
        wrong = self.client.patch(f'/api/defense/schedules/{schedules[0].pk}/verdict/', {
            'verdict': 'approved', 'concept_decisions': [
                {'key': key, 'decision': 'approved' if key == 'c1' else 'not_selected'} for key in services.KEYS]}, format='json')
        self.assertEqual(wrong.status_code, 400, wrong.data)
        response = self.action('module_verdict', self.panelist, team_id=self.team.pk, verdict='approved')
        self.assertEqual(response.status_code, 200, response.data)
        self.team.refresh_from_db()
        self.assertEqual(self.team.project_title, 'Module c2')
        self.assertEqual(concepts.latest_round(self.module_team, self.event).verdict, '')

    def test_all_systems_rejected_opens_new_section_and_module_rounds(self):
        self.hearing()
        first = services.latest(self.project)
        response = self.select(rejected=True)
        self.assertEqual(response.status_code, 200, response.data)
        next_round = services.latest(self.project)
        self.assertEqual(next_round.number, 2)
        self.assertEqual(first.systems.count(), 3)
        self.assertFalse(services.shared_clearance(next_round))
        for team in (self.team, self.module_team):
            current = concepts.latest_round(team, self.event)
            self.assertEqual(current.section_round_id, next_round.pk)
            self.assertEqual(current.number, 2)
            self.assertTrue(all(not c['title'] for c in current.concepts))
            self.assertTrue(current.review_required)

    def test_module_only_redefense_preserves_shared_selection_and_other_team(self):
        self.hearing()
        self.assertEqual(self.select().status_code, 200)
        response = self.action('module_verdict', self.panelist, team_id=self.team.pk,
            verdict='for_redefense', remarks='Revise the appointment workflow.')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(services.latest(self.project).selected_key, 'c2')
        self.assertEqual(concepts.latest_round(self.team, self.event).number, 2)
        self.assertEqual(concepts.latest_round(self.module_team, self.event).number, 1)

    def test_scheduled_names_and_papers_are_locked(self):
        self.hearing()
        self.assertEqual(self.action('save_titles', concepts=self.titles('Changed')).status_code, 400)
        with self.assertRaises(ValidationError):
            services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('new.pdf', b'%PDF-1.4'))

    def test_audit_failure_rolls_back_title_changes(self):
        with patch('repository.section_concepts.services.audit', side_effect=RuntimeError('audit failed')):
            with self.assertRaises(RuntimeError):
                services.save_system_titles(self.project, self.first, self.titles())
        self.assertTrue(all(not s.title for s in services.latest(self.project).systems.all()))

    def test_reassignment_moves_pm_task_and_preserves_papers(self):
        services.upload(self.project, self.pm, 'c1', SimpleUploadedFile('draft.pdf', b'%PDF-1.4 draft'))
        paper_ids = list(SectionConceptPaper.objects.values_list('pk', flat=True))
        response = self.action('reassign', project_manager_id=self.module_team.leader_id, reviewer_id=self.first.pk)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(services.task_payload(self.pm), [])
        self.assertEqual(services.task_payload(self.module_team.leader)[0]['role'], 'project_manager')
        self.assertEqual(list(SectionConceptPaper.objects.values_list('pk', flat=True)), paper_ids)

    def test_shared_mode_is_not_inferred_from_an_imported_system_name(self):
        other = self.teams[1]
        self.assertIsNone(services.project_for(other, self.event))
        self.assertEqual(SectionConceptProject.objects.count(), 1)

    def test_shared_revisions_gate_team_progress_until_a_revised_paper_is_cleared(self):
        self.hearing()
        response = self.action('decide', self.panelist, verdict='approved_with_revisions',
            remarks='Clarify the shared integration design.', concepts=[
                {'key': key, 'decision': 'approved_with_revisions' if key == 'c2' else 'not_selected',
                 'remarks': 'Clarify integration.' if key == 'c2' else ''} for key in services.KEYS])
        self.assertEqual(response.status_code, 200, response.data)
        response = self.action('module_verdict', self.panelist, team_id=self.team.pk, verdict='approved')
        self.assertEqual(response.status_code, 200, response.data)
        grade = concepts.latest_round(self.team, self.event).schedule.grade_records.first()
        from grading.grades.defense_workflow import passed_and_cleared
        self.assertFalse(passed_and_cleared(grade))
        self.assertEqual(self.action('clear_revisions', remarks='Reviewed integration.').status_code, 400)
        row = services.upload(self.project, self.pm, 'c2', SimpleUploadedFile('revised.pdf', b'%PDF-1.4 revised integration'))
        services.review(self.project, self.first, row.pk, 'accepted')
        response = self.action('clear_revisions', remarks='Reviewed the revised integration design.')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(passed_and_cleared(grade))

    def test_idempotent_setup_does_not_revoke_clearance(self):
        self.prepare_shared()
        services.configure(self.first, [self.team, self.module_team], self.event,
            {'project_manager_id': self.pm.pk, 'reviewer_id': self.first.pk})
        self.assertTrue(services.shared_clearance(services.latest(self.project)))

    def test_shared_changes_revoke_unscheduled_module_clearance(self):
        self.prepare_shared()
        self.prepare_team(self.team)
        self.assertTrue(concepts.clearance_valid(self.team, self.event))
        services.save_system_titles(self.project, self.first, self.titles('Changed system'))
        self.assertFalse(concepts.clearance_valid(self.team, self.event))

    def test_completed_event_and_historical_sections_are_read_only(self):
        self.event.is_officially_complete = True
        self.event.save()
        self.project.pit_event_config = self.event
        with self.assertRaises(PermissionError):
            services.save_system_titles(self.project, self.first, self.titles())
        self.event.is_officially_complete = False
        self.event.save()
        self.semester.is_active = False
        self.semester.save()
        self.project.section.semester = self.semester
        with self.assertRaises(PermissionError):
            services.save_system_titles(self.project, self.first, self.titles())

    def test_official_completion_cannot_skip_shared_system_and_module_decisions(self):
        from grading.grades.services import update_group_settings
        with self.assertRaises(ValidationError):
            update_group_settings(semester=self.semester, scope='pit', stage_label=self.event.label,
                is_officially_complete=True, user=self.first)
        self.event.refresh_from_db()
        self.assertFalse(self.event.is_officially_complete)


class SharedSystemGenerationTests(APITestCase):
    from student_teams import test_formation as formation_fixtures
    setUp = formation_fixtures.TeamFormationTests.setUp
    preview = formation_fixtures.TeamFormationTests.preview
    commit = formation_fixtures.TeamFormationTests.commit

    def shared(self, **changes):
        return {'project_manager_id': self.students[0].pk, 'reviewer_id': self.lead.pk,
                'title_mode': 'student_proposed', **changes}

    def test_generation_creates_one_shared_set_and_three_module_tasks_per_team(self):
        self.payload.update(sections=['BSIT-2A'], shared_system=self.shared())
        preview = self.preview()
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertFalse(SectionConceptProject.objects.exists())
        response = self.commit(preview)
        self.assertEqual(response.status_code, 201, response.data)
        project = SectionConceptProject.objects.get()
        self.assertEqual(project.team_links.count(), response.data['created_count'])
        self.assertEqual(services.latest(project).systems.count(), 3)
        for team in StudentTeam.objects.all():
            self.assertEqual(resolve_policy(team, self.event)['required_count'], 3)
        again = self.commit(preview)
        self.assertEqual(again.data['team_ids'], response.data['team_ids'])
        self.assertEqual(SectionConceptProject.objects.count(), 1)

    def test_invalid_manager_rolls_back_all_generated_teams(self):
        self.payload.update(sections=['BSIT-2A'], shared_system=self.shared(project_manager_id=self.students[-1].pk))
        preview = self.preview()
        self.assertEqual(preview.status_code, 200)
        response = self.commit(preview)
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(StudentTeam.objects.exists())
        self.assertFalse(SectionConceptProject.objects.exists())

    def test_shared_setup_is_part_of_the_signed_preview(self):
        self.payload.update(sections=['BSIT-2A'], shared_system=self.shared())
        preview = self.preview()
        self.assertEqual(preview.status_code, 200)
        response = self.commit(preview, shared_system=self.shared(title_mode='faculty_provided'))
        self.assertEqual(response.status_code, 400)
        self.assertFalse(StudentTeam.objects.exists())

    def test_cross_section_and_custom_shared_rosters_are_rejected(self):
        response = self.preview(shared_system=self.shared())
        self.assertEqual(response.status_code, 400)
        response = self.preview(sections=[], roster_mode='custom', student_ids=[self.students[0].pk], shared_system=self.shared())
        self.assertEqual(response.status_code, 400)

    def test_instructor_can_generate_shared_system_only_for_assigned_section(self):
        instructor = User.objects.create_user(username='shared-instructor', role='faculty')
        SectionInstructorAssignment.objects.create(faculty=instructor, semester=self.term,
            year_level='2nd Year', section='BSIT-2A')
        self.client.force_authenticate(instructor)
        self.payload.update(sections=['BSIT-2A'], shared_system=self.shared(reviewer_id=instructor.pk))
        preview = self.preview()
        self.assertEqual(preview.status_code, 200, preview.data)
        response = self.commit(preview)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(SectionConceptProject.objects.get().reviewer_id, instructor.pk)


class SharedCapstoneConceptTests(APITestCase):
    from repository.deliverables import test_submission_timing as timing_fixtures
    setUp = timing_fixtures.SubmissionTimingTests.setUp

    def project(self):
        self.team.section = 'BSIT-3A'
        self.team.save()
        self.stage.concept_config = {'enabled': True, 'required_count': 3}
        self.stage.save()
        self.paper.file_policy = {'mode': 'concepts'}
        self.paper.save()
        return services.configure(self.admin, [self.team], self.stage, {
            'project_manager_id': self.student.pk, 'reviewer_id': self.adviser.pk})

    def test_capstone_system_and_module_names_are_confirmed_by_designated_adviser(self):
        project = self.project()
        titles = [{'key': key, 'title': f'Capstone {key}'} for key in services.KEYS]
        services.save_system_titles(project, self.adviser, titles)
        services.confirm_modules(project, self.adviser, self.team.pk, titles)
        current = concepts.latest_round(self.team, self.stage)
        self.assertEqual(current.section_round_id, services.latest(project).pk)
        self.assertTrue(all(c['faculty_confirmed'] for c in current.concepts))
        self.assertEqual(resolve_policy(self.team, self.stage)['required_count'], 3)

    def test_adviser_reviews_student_papers_without_upload_access(self):
        project = self.project()
        titles = [{'key': key, 'title': f'Module {key}'} for key in services.KEYS]
        services.confirm_modules(project, self.adviser, self.team.pk, titles)
        from repository.deliverables.services import stage_payload
        item = next(d for d in stage_payload(self.team, self.stage.label, evaluator=self.adviser)['pre'] if d['id'] == 'PAPER')
        self.assertFalse(item['can_upload'])
        self.assertTrue(item['can_faculty_review'])
        self.client.force_authenticate(self.adviser)
        response = self.client.post('/api/repository/deliverables/upload/', {
            'team_id': self.team.pk, 'stage_label': self.stage.label,
            'deliverable_id': 'PAPER', 'file_name': 'paper.pdf', 'slot_key': 'c1:paper'})
        self.assertEqual(response.status_code, 403)

    def test_shared_reviewer_cannot_change_capstone_roster_or_another_advisers_modules(self):
        project = self.project()
        self.assertTrue(services.payload(project, self.adviser)['can_edit_names'])
        self.assertFalse(services.can_manage(self.adviser, project))
        SectionInstructorAssignment.objects.create(faculty=self.adviser, semester=self.semester,
            year_level=self.team.year_level, section=self.team.section)
        from rest_framework.exceptions import PermissionDenied
        with self.assertRaises(PermissionDenied):
            services.configure(self.adviser, [self.team], self.stage, {
                'project_manager_id': self.student.pk, 'reviewer_id': self.adviser.pk})
        other = User.objects.create_user(username='another-capstone-adviser', role='faculty', is_adviser=True)
        self.team.adviser = other
        self.team.save(update_fields=['adviser'])
        titles = [{'key': key, 'title': f'Module {key}'} for key in services.KEYS]
        with self.assertRaises(PermissionError):
            services.confirm_modules(project, self.adviser, self.team.pk, titles)
        services.confirm_modules(project, other, self.team.pk, titles)

    def test_completed_capstone_stage_locks_shared_mutations(self):
        from defense.stages.models import StageGradingConfig
        project = self.project()
        StageGradingConfig.objects.create(semester=self.semester, defense_stage=self.stage,
            is_officially_complete=True)
        self.assertFalse(services.payload(project, self.adviser)['can_edit_names'])
        with self.assertRaises(PermissionError):
            services.save_system_titles(project, self.adviser, [])
