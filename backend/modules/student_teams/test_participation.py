"""Approved intake and migration rules, always on Django's isolated test database."""
from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase
from rest_framework.exceptions import ValidationError

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage
from grading.grades.models import TeamGrade
from .models import StudentTeam, TeamMembership, StudentCapstoneParticipation as Participation, StudentCapstonePlacement as Placement
from .participation import confirm_roster, finalize_failed, roster_preview, validate_roster


class StudentParticipationTests(APITestCase):
    def setUp(self):
        self.admin = get_user_model().objects.create_user(username='participation-admin', role='admin')
        self.client.force_authenticate(self.admin)
        old_year = SchoolYear.objects.create(label='2025-2026')
        year = SchoolYear.objects.create(label='2026-2027')
        self.old = self.term(old_year, Semester.SECOND)
        self.first = self.term(year, Semester.FIRST)
        self.new = self.term(year, Semester.SECOND, active=True)
        DefenseStage.objects.update(is_active=False)
        self.stage = DefenseStage.objects.create(label='Configured research review', display_order=1)
        self.stage.deliverables.create(deliverable_id='PRE', label='Required research paper', deliverable_type='pre', required=True)
        self.ana = self.student('returning-ana')
        self.bea = self.student('first-bea')

    def term(self, year, label, active=False):
        return Semester.objects.create(school_year=year, label=label, is_active=active,
            starts_on='2000-01-01', ends_on='2199-12-31', capstone_peer_evaluation_enabled=False,
            capstone_adviser_grading_enabled=False, capstone_team_creation_enabled=True)

    def student(self, name):
        return get_user_model().objects.create_user(username=name, role='student')

    def team(self, term, members, name='Previous team'):
        team = StudentTeam.objects.create(name=name, level=StudentTeam.LEVEL_3_CAPSTONE,
            year_level='3rd Year', semester=term, leader=members[0], capstone_phase='active')
        for index, student in enumerate(members):
            TeamMembership.objects.create(team=team, student=student, is_leader=index == 0)
        confirm_roster(team, {s.pk for s in members}, actor=self.admin)
        return team

    def assess(self, team, verdict):
        from repository.deliverables.models import DeliverableSubmission
        DeliverableSubmission.objects.create(team=team, stage_label=self.stage.label,
            deliverable_id='PRE', label='Required research paper', deliverable_type='pre', status='accepted', file_name='paper.pdf')
        grade = TeamGrade(team=team, semester=team.semester, scope='capstone', defense_stage=self.stage,
            stage_label=self.stage.label, status='published', verdict=verdict, panel_score=85, adviser_score=85, peer_score=85)
        grade.save(clean=False)
        return grade

    def failed(self):
        old = self.team(self.old, [self.ana])
        self.assess(old, 'failed')
        finalize_failed(old, self.admin)
        return old

    def payload(self, members, name='Current team', level='3rd Year Capstone', year='3rd Year'):
        return {'name': name, 'leader_id': members[0].pk, 'member_ids': [s.pk for s in members],
            'level': level, 'year_level': year, 'section': ''}

    def enroll_current(self, *students, year='3rd Year'):
        from user_management.academic_records.models import StudentAcademicRecord
        for student in students:
            StudentAcademicRecord.objects.create(student=student, semester=self.new, year_level=year)

    def test_mixed_new_intake_counts_are_per_student(self):
        old = self.failed()
        self.enroll_current(self.ana, self.bea)
        response = self.client.post('/api/teams/', self.payload([self.ana, self.bea]), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        members = response.data['team']['members']
        self.assertEqual({m['id']: m['capstone_participation']['number'] for m in members}, {self.ana.pk: 2, self.bea.pk: 1})
        old.refresh_from_db()
        self.assertEqual(old.semester_id, self.old.pk)
        self.assertEqual(old.term_participations.get().outcome, 'failed')

    def test_enrollment_does_not_allocate_a_second_participation(self):
        self.failed()
        from user_management.academic_records.models import StudentAcademicRecord
        StudentAcademicRecord.objects.create(student=self.ana, semester=self.new, year_level='4th Year')
        self.assertEqual(Participation.objects.filter(student=self.ana).count(), 1)

    def test_preview_proposes_second_without_writing(self):
        self.failed()
        before = Participation.objects.count()
        result = roster_preview({self.ana.pk, self.bea.pk}, self.new)
        self.assertEqual({r['student_id']: r['number'] for r in result}, {self.ana.pk: 2, self.bea.pk: 1})
        self.assertEqual(Participation.objects.count(), before)

    def test_capstone_two_rejects_failed_returner_and_first_time_member(self):
        self.failed()
        self.first.is_active = True
        self.first.save()
        response = self.client.post('/api/teams/', self.payload([self.ana, self.bea], level='4th Year Capstone', year='4th Year'), format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('Capstone 1 intake', str(response.data))
        self.assertEqual(StudentTeam.objects.count(), 1)
        self.assertEqual(Participation.objects.count(), 1)

    def test_final_failure_cannot_transfer_to_another_team_in_same_intake(self):
        current = self.team(self.new, [self.ana])
        self.assess(current, 'failed')
        finalize_failed(current, self.admin)
        response = self.client.post('/api/teams/', self.payload([self.ana], name='Bypass'), format='json')
        self.assertEqual(response.status_code, 400)
        self.assertEqual(Participation.objects.count(), 1)

    def test_reconfirmation_does_not_allocate_another_number(self):
        self.failed()
        current = self.team(self.new, [self.ana, self.bea], name='Current team')
        for _ in range(2):
            confirm_roster(current, {self.ana.pk, self.bea.pk}, actor=self.admin)
        self.assertEqual(list(Participation.objects.filter(student=self.ana).values_list('number', flat=True)), [1, 2])
        self.assertEqual(Placement.objects.filter(team=current, ended_at=None).count(), 2)


    def test_old_recovery_actions_are_rejected(self):
        old = self.failed()
        grade = old.grade_records.first()
        for action in ['authorize_retake', 'authorize_new_concept', 'keep_blocked']:
            response = self.client.post(f'/api/grading/grades/{grade.pk}/workflow/', {'action': action, 'reason': 'Cannot reopen'}, format='json')
            self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(Participation.objects.get(student=self.ana).state, 'failed')

    def test_workflow_cannot_receive_retired_replacement_project_input(self):
        old = self.failed()
        grade = old.grade_records.first()
        response = self.client.post(f'/api/grading/grades/{grade.pk}/workflow/',
            {'action': 'clear_revisions', 'reason': 'Cannot restart a closed project',
             'project_title': 'Retired replacement input'}, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('Unsupported workflow field', str(response.data))

    def test_removed_returning_endpoint_is_unavailable(self):
        response = self.client.post(f'/api/academic-periods/semesters/{self.new.pk}/returning-teams/', {}, format='json')
        self.assertEqual(response.status_code, 404)

    def test_stale_project_choices_are_rejected(self):
        response = self.client.post(f'/api/academic-periods/semesters/{self.first.pk}/activate/', {'decisions': []}, format='json')
        self.assertEqual(response.status_code, 400)

    def test_history_endpoint_is_read_only_and_admin_only(self):
        self.failed()
        self.team(self.new, [self.ana], name='Current team')
        before = Participation.objects.count()
        response = self.client.get(f'/api/teams/students/{self.ana.pk}/capstone-history/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual([p['number'] for p in response.data['participations']], [1, 2])
        self.assertEqual(Participation.objects.count(), before)
        self.client.force_authenticate(self.bea)
        self.assertEqual(self.client.get(f'/api/teams/students/{self.ana.pk}/capstone-history/').status_code, 403)

    def test_normal_migration_precedes_enrollment_and_keeps_number(self):
        self.old.is_active = True
        self.old.save()
        team = self.team(self.old, [self.ana])
        self.assess(team, 'approved')
        url = f'/api/academic-periods/semesters/{self.first.pk}'
        preview = self.client.get(f'{url}/transition-preview/')
        row = preview.data['capstone_review']['teams'][0]
        self.assertTrue(row['can_include'], row)
        self.assertTrue(row['pending_enrollment'])
        response = self.client.post(f'{url}/activate/', {'preview_revision': preview.data['preview_revision']}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        team.refresh_from_db()
        self.assertEqual(team.semester_id, self.first.pk)
        self.assertEqual(Participation.objects.get(student=self.ana).number, 1)
        from user_management.academic_records.models import StudentAcademicRecord
        self.assertFalse(StudentAcademicRecord.objects.filter(student=self.ana, semester=self.first).exists())

    def test_final_failed_team_is_not_a_normal_continuation(self):
        old = self.failed()
        self.old.is_active = True
        self.old.save()
        preview = self.client.get(f'/api/academic-periods/semesters/{self.first.pk}/transition-preview/')
        row = preview.data['capstone_review']['teams'][0]
        self.assertEqual(row['destination'], 'failed_history')
        self.assertFalse(row['can_include'])

    def test_unfinished_source_endorsement_prevents_false_continuation(self):
        from .models import TeamStageProgress
        self.old.is_active = True
        self.old.save()
        team = self.team(self.old, [self.ana])
        self.assess(team, 'approved')
        following = DefenseStage.objects.create(label='Another configured stage', display_order=2)
        TeamStageProgress.objects.create(team=team, semester=self.old, defense_stage=following, status='ready')
        preview = self.client.get(f'/api/academic-periods/semesters/{self.first.pk}/transition-preview/')
        row = preview.data['capstone_review']['teams'][0]
        self.assertFalse(row['can_include'], row)
        self.assertIn(following.label, row['reason'])

    def test_returning_fourth_year_can_join_regular_capstone_one(self):
        self.failed()
        self.enroll_current(self.ana, year='4th Year')
        response = self.client.post('/api/teams/', self.payload([self.ana], level='4th Year Capstone', year='4th Year'), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['team']['year_level'], '4th Year')

    def test_mixed_official_years_share_an_intake_without_changing_enrollment(self):
        from user_management.academic_records.models import StudentAcademicRecord
        self.failed()
        StudentAcademicRecord.objects.create(student=self.ana, semester=self.new, year_level='4th Year')
        StudentAcademicRecord.objects.create(student=self.bea, semester=self.new, year_level='3rd Year')
        body = self.payload([self.ana, self.bea])
        body.pop('level')
        body.pop('year_level')
        response = self.client.post('/api/teams/', body, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Participation.objects.get(student=self.ana, intake_semester=self.new).number, 2)
        self.assertEqual(StudentAcademicRecord.objects.get(student=self.ana, semester=self.new).year_level, '4th Year')

    def test_prepared_import_accepts_returning_roster_name_and_previews_each_student(self):
        from user_management.academic_records.models import StudentAcademicRecord
        old = self.failed()
        for person, year in ((self.ana, '4th Year'), (self.bea, '3rd Year')):
            StudentAcademicRecord.objects.create(student=person, semester=self.new, year_level=year, section='BSIT-3A')
        body = {'level': '3rd Year Capstone', 'teams': [{'team_name': old.name,
            'project_title': 'Fresh project', 'section': 'BSIT-3A',
            'member_ids': [self.ana.username, self.bea.username], 'leader_id': self.ana.username}]}
        preview = self.client.post('/api/teams/generation/import/', body, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertTrue(preview.data['ready'], preview.data)
        self.assertEqual([r['number'] for r in preview.data['rows'][0]['participation_preview']], [2, 1])
        self.assertEqual(Participation.objects.count(), 1)
        result = self.client.post('/api/teams/generation/import/create/',
            {'preview_token': preview.data['preview_token']}, format='json')
        self.assertEqual(result.status_code, 201, result.data)
        self.assertEqual(Participation.objects.get(student=self.ana, intake_semester=self.new).number, 2)
        old.refresh_from_db()
        self.assertEqual(old.semester_id, self.old.pk)



    def test_transfer_within_intake_keeps_the_same_student_number(self):
        self.enroll_current(self.ana, self.bea)
        original = self.client.post('/api/teams/', self.payload([self.bea, self.ana]), format='json')
        team_id = original.data['team']['id']
        body = self.payload([self.bea])
        response = self.client.patch(f'/api/teams/{team_id}/', body, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        moved = self.client.post('/api/teams/', self.payload([self.ana], name='New placement'), format='json')
        self.assertEqual(moved.status_code, 201, moved.data)
        participation = Participation.objects.get(student=self.ana)
        self.assertEqual(participation.number, 1)
        self.assertEqual(participation.placements.count(), 2)
        self.assertEqual(participation.placements.filter(ended_at__isnull=True).count(), 1)

    def test_rollover_reconciles_migrated_section_without_moving_or_counting_again(self):
        from academic_period_management.services import switch_active_semester, build_semester_transition_preview
        from user_management.academic_records.models import StudentAcademicRecord
        from user_management.academic_records.rollover import confirm_rollover
        self.old.is_active = True
        self.old.save()
        team = self.team(self.old, [self.ana])
        self.assess(team, 'approved')
        record = StudentAcademicRecord.objects.create(student=self.ana, semester=self.old,
            year_level='3rd Year', section='BSIT-3A')
        preview = build_semester_transition_preview(self.first)
        switch_active_semester(self.first, self.admin, preview_revision=preview['preview_revision'])
        created, skipped, moved = confirm_rollover([{'record_id': record.pk, 'action': 'promote',
            'section': 'BSIT-4A'}], self.first)
        team.refresh_from_db()
        self.assertEqual((len(created), len(skipped), moved), (1, 0, 0))
        self.assertEqual(team.section, 'BSIT-4A')
        self.assertEqual(team.semester_id, self.first.pk)
        self.assertEqual(Participation.objects.get(student=self.ana).number, 1)
        self.assertEqual(team.term_participations.get(semester=self.old).snapshot['section'], '')

    def test_copy_roster_endpoint_is_unavailable(self):
        old = self.failed()
        url = f'/api/teams/{old.pk}/reuse-roster/'
        self.assertEqual(self.client.get(url).status_code, 404)
        self.assertEqual(self.client.post(url, {}, format='json').status_code, 404)
        self.assertEqual(Participation.objects.count(), 1)

    def test_import_previous_roster_is_read_only_until_commit_and_repeat_import_keeps_number(self):
        old = self.failed()
        self.enroll_current(self.ana)
        body = {'teams': [{'team_name': old.name, 'project_title': 'New intake project',
            'level': '3rd Year Capstone', 'member_ids': [self.ana.username],
            'leader_id': self.ana.username}]}
        preview = self.client.post('/api/teams/bulk-import/preview/', body, format='json')
        self.assertEqual(preview.status_code, 200, preview.data)
        self.assertTrue(preview.data['rows'][0]['ready'], preview.data)
        self.assertEqual(preview.data['rows'][0]['participation_preview'][0]['number'], 2)
        self.assertEqual(Participation.objects.count(), 1)
        for _ in range(2):
            result = self.client.post('/api/teams/bulk-import/', body, format='json')
            self.assertEqual(result.status_code, 201, result.data)
            self.assertEqual(result.data['created_count'], 1)
        self.assertEqual(Participation.objects.filter(student=self.ana).count(), 2)
        self.assertEqual(StudentTeam.objects.count(), 2)
        old.refresh_from_db()
        self.assertEqual(old.semester_id, self.old.pk)
        self.assertEqual(old.term_participations.get().outcome, 'failed')

    def test_returning_import_requires_enrollment_before_allocating_the_next_number(self):
        old = self.failed()
        body = {'teams': [{'team_name': 'New intake team', 'level': '3rd Year Capstone',
            'member_ids': [self.ana.username], 'leader_id': self.ana.username}]}
        response = self.client.post('/api/teams/bulk-import/', body, format='json')
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('returning-ana is not enrolled', str(response.data))
        self.assertEqual(Participation.objects.filter(student=self.ana).count(), 1)
        self.assertEqual(StudentTeam.objects.count(), 1)
        self.assertEqual(old.term_participations.get().outcome, 'failed')
