"""Deliverable comparisons follow the team's term requirements after migration."""

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.stages.models import DefenseStage, StageDeliverable
from repository.deliverables.models import DeliverableSubmission
from student_teams.capstone_lifecycle import configured_requirements
from student_teams.models import StudentTeam, TeamStageProgress, TeamTermParticipation


class ArchiveDeliverablePhaseScopeTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        cls.admin = User.objects.create_user(username='phase-archive-admin', role='admin')
        cls.student = User.objects.create_user(username='phase-archive-student', role='student')
        past_year = SchoolYear.objects.create(label='2025-2026')
        cls.source = Semester.objects.create(school_year=past_year, label=Semester.SECOND)
        current_year = SchoolYear.objects.create(label='2026-2027')
        cls.current = Semester.objects.create(
            school_year=current_year, label=Semester.FIRST, is_active=True,
        )
        cls.stages = []
        for order, label in enumerate(('Concept Proposal', 'Project Proposal', 'Final Defense'), 1):
            stage, _ = DefenseStage.objects.update_or_create(
                label=label, defaults={'is_active': True, 'display_order': order},
            )
            for number in (1, 2):
                StageDeliverable.objects.update_or_create(
                    defense_stage=stage, deliverable_id=f'D{number}',
                    defaults={'label': f'{label} document {number}', 'required': True,
                              'deliverable_type': StageDeliverable.TYPE_PRE},
                )
            cls.stages.append(stage)
        cls.team = StudentTeam.objects.create(
            name='Continuing archive team', project_title='Continuing project',
            level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year',
            semester=cls.current, intake_semester=cls.source, leader=cls.student,
        )
        requirements = configured_requirements()
        TeamTermParticipation.objects.update_or_create(
            team=cls.team, semester=cls.source,
            defaults={'closed_at': timezone.now(), 'requirements': requirements,
                      'snapshot': {'year_level': '3rd Year', 'level': StudentTeam.LEVEL_3_CAPSTONE}},
        )
        TeamTermParticipation.objects.update_or_create(
            team=cls.team, semester=cls.current,
            defaults={'requirements': requirements,
                      'snapshot': {'inherited_stage_ids': [s.pk for s in cls.stages[:2]]}},
        )
        for stage in cls.stages:
            historical = stage != cls.stages[-1]
            DeliverableSubmission.objects.create(
                team=cls.team, stage_label=stage.label, deliverable_id='D1',
                label=f'{stage.label} document 1', deliverable_type='pre',
                file_name=f'{stage.pk}-paper.pdf',
                archive_semester=cls.source if historical else cls.current,
                archive_year_level='3rd Year' if historical else '4th Year',
                archive_team_level=StudentTeam.LEVEL_3_CAPSTONE if historical else StudentTeam.LEVEL_4_CAPSTONE,
            )

    def setUp(self):
        self.client.force_authenticate(self.admin)

    def open_path(self, *titles, **filters):
        query = {'group_by': 'deliverable', 'type': 'capstone', **filters}
        response = self.client.get('/api/repository/audit/', query)
        for title in titles:
            self.assertEqual(response.status_code, 200, response.data)
            folder = next(folder for folder in response.data['folder_browser']['folders']
                          if folder['title'] == title)
            response = self.client.get('/api/repository/audit/', {**query, 'folder_key': folder['key']})
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def test_current_term_only_compares_remaining_stage_deliverables(self):
        payload = self.open_path('2026-2027', Semester.FIRST, '4th Year')
        browser = payload['folder_browser']
        self.assertEqual([folder['title'] for folder in browser['folders']], ['Final Defense'])
        self.assertEqual(browser['file_count'], 1)
        self.assertEqual(browser['missing_count'], 1)

        payload = self.open_path('2026-2027', Semester.FIRST, '4th Year', 'Final Defense')
        folders = payload['folder_browser']['folders']
        uploaded = next(folder for folder in folders if folder['title'] == 'Final Defense document 1')
        missing = next(folder for folder in folders if folder['title'] == 'Final Defense document 2')
        self.assertEqual((uploaded['file_count'], uploaded['missing_count']), (1, 0))
        self.assertEqual((missing['file_count'], missing['missing_count']), (0, 1))

    def test_explicit_old_stage_filter_does_not_create_current_term_missing_rows(self):
        for stage in self.stages[:2]:
            with self.subTest(stage=stage.label):
                payload = self.open_path(
                    academic_year='2026-2027', semester=Semester.FIRST,
                    stage=stage.label, deliverable_id='D2',
                )
                self.assertEqual(payload['entries'], [])
                self.assertEqual(payload['folder_browser']['folders'], [])
                self.assertEqual(payload['deliverable_summary']['missing_count'], 0)

    def test_original_term_keeps_actual_concept_and_project_files(self):
        payload = self.open_path('2025-2026', Semester.SECOND, '3rd Year')
        browser = payload['folder_browser']
        self.assertEqual([folder['title'] for folder in browser['folders']],
                         ['Concept Proposal', 'Project Proposal'])
        self.assertEqual(browser['file_count'], 2)
        self.assertEqual(browser['missing_count'], 0)

    def test_already_migrated_team_uses_recorded_source_stage_clearance(self):
        # Older migrations may not have captured inherited_stage_ids explicitly.
        TeamTermParticipation.objects.filter(team=self.team, semester=self.current).update(snapshot={})
        for stage in self.stages[:2]:
            TeamStageProgress.all_objects.update_or_create(
                team=self.team, semester=self.source, defense_stage=stage,
                project_version=self.team.project_version,
                defaults={'status': TeamStageProgress.STATUS_PASSED},
            )
        payload = self.open_path('2026-2027', Semester.FIRST, '4th Year')
        self.assertEqual([folder['title'] for folder in payload['folder_browser']['folders']],
                         ['Final Defense'])
        self.assertEqual(payload['folder_browser']['missing_count'], 1)

    def test_fourth_year_new_intake_still_has_its_own_concept_requirements(self):
        newcomer = StudentTeam.objects.create(
            name='Fourth year new intake', project_title='New concept',
            level=StudentTeam.LEVEL_4_CAPSTONE, year_level='4th Year',
            semester=self.current, intake_semester=self.current, leader=self.student,
        )
        payload = self.open_path(
            '2026-2027', Semester.FIRST, '4th Year', 'Concept Proposal',
            stage='Concept Proposal', deliverable_id='D2',
        )
        self.assertEqual(payload['folder_browser']['missing_count'], 1)
        self.assertEqual({entry['team_id'] for entry in payload['entries']}, {newcomer.pk})
