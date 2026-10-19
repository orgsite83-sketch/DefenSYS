"""Archive browsing reuses metadata within a GET and stays fresh across GETs."""
from django.contrib.auth import get_user_model
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APITestCase

from academic_period_management.models import SchoolYear, Semester
from defense.scheduler.models import PitEventDeliverable, PitEventGradingConfig
from repository.deliverables.models import DeliverableSubmission, DeliverableSubmissionFile
from student_teams.models import StudentTeam


class ArchiveReadPerformanceTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        User = get_user_model()
        cls.admin = User.objects.create_user(username='archive-admin', role='admin')
        cls.student = User.objects.create_user(username='archive-student', role='student')
        cls.leads = {}
        cls.events = {}
        cls.definitions = {}
        school_year = SchoolYear.objects.create(label='2026-2027')
        cls.semester = Semester.objects.create(
            school_year=school_year, label=Semester.FIRST, is_active=True,
        )
        for year in ('1st Year', '2nd Year', '3rd Year'):
            cls.leads[year] = User.objects.create_user(
                username=f'archive-lead-{year[0]}', role='faculty',
                is_pit_lead=True, pit_lead_year=year,
            )
            cls.events[year] = PitEventGradingConfig.objects.create(
                semester=cls.semester, year_level=year, event_name=f'{year} Showcase',
                archive_file_template='{project}.{event}.pdf',
            )
            cls.definitions[year] = PitEventDeliverable.objects.create(
                pit_event_config=cls.events[year], deliverable_id='D1', label='Manuscript',
                deliverable_type='post', file_policy={'mode': 'single'}, is_restricted=True,
            )

    def _add_submission(self, year, index):
        team = StudentTeam.objects.create(
            name=f'Archive {year} {index}', project_title=f'Project {year} {index}',
            semester=self.semester, year_level=year, leader=self.student,
            section=f'{year} Archive Section {index}',
            level={'1st Year': StudentTeam.LEVEL_1_PIT,
                   '2nd Year': StudentTeam.LEVEL_2_PIT,
                   '3rd Year': StudentTeam.LEVEL_3_PIT}[year],
        )
        submission = DeliverableSubmission.objects.create(
            team=team, stage_label=self.events[year].event_name, deliverable_id='D1', label='Manuscript',
            deliverable_type='post', status='accepted', file_name=f'paper-{index}.pdf',
        )
        # A metadata-only legacy event reference exercises the fallback lookup.
        DeliverableSubmission.objects.filter(pk=submission.pk).update(pit_event_config=None)
        DeliverableSubmissionFile.objects.create(
            submission=submission, file_name=f'paper-{index}.pdf', status='accepted',
        )
        return submission

    def _read(self, **query):
        with CaptureQueriesContext(connection) as queries:
            response = self.client.get('/api/repository/audit/', query)
        self.assertEqual(response.status_code, 200)
        return response.data, len(queries)

    def test_additional_teams_share_metadata_queries_for_admin_and_every_pit_year(self):
        for index in range(2):
            for year in self.leads:
                self._add_submission(year, index)

        users = [self.admin, *self.leads.values()]
        baseline = {}
        for user in users:
            self.client.force_authenticate(user=user)
            _, baseline[user.pk] = self._read(open_current_semester='1')

        for index in range(2, 10):
            for year in self.leads:
                self._add_submission(year, index)

        for user in users:
            with self.subTest(role=user.role, year=user.pit_lead_year):
                self.client.force_authenticate(user=user)
                payload, count = self._read(open_current_semester='1')
                self.assertLessEqual(count, baseline[user.pk])
                expected = 30 if user.role == 'admin' else 10
                self.assertEqual(payload['counts']['total'], expected)
                self.assertTrue(all(entry['is_restricted_archive'] for entry in payload['entries']))
                if user.role != 'admin':
                    self.assertEqual({entry['year_level'] for entry in payload['entries']}, {user.pit_lead_year})
                folder = payload['folder_browser']['folders'][0]
                child, child_count = self._read(folder_key=folder['key'])
                self.assertLessEqual(child_count, count)
                self.assertEqual(child['folder_browser']['folder_key'], folder['key'])

    def test_next_request_sees_configuration_file_and_lead_scope_changes(self):
        for year in self.leads:
            self._add_submission(year, 0)
        self.client.force_authenticate(user=self.leads['1st Year'])
        first, _ = self._read()
        self.assertEqual(first['entries'][0]['status'], 'Approved')
        self.assertTrue(first['entries'][0]['is_restricted_archive'])

        PitEventDeliverable.objects.filter(pk=self.definitions['1st Year'].pk).update(is_restricted=False)
        DeliverableSubmissionFile.objects.filter(submission__archive_year_level='1st Year').update(
            status='rejected', feedback='Replace this file',
        )
        updated, _ = self._read()
        self.assertFalse(updated['entries'][0]['is_restricted_archive'])
        self.assertEqual(updated['entries'][0]['status'], 'Needs Revision')
        self.assertEqual(updated['entries'][0]['feedback'], 'Replace this file')

        self.client.force_authenticate(user=self.leads['2nd Year'])
        other, _ = self._read()
        self.assertEqual({entry['year_level'] for entry in other['entries']}, {'2nd Year'})
        self.assertTrue(other['entries'][0]['is_restricted_archive'])
        self.assertEqual(other['entries'][0]['status'], 'Approved')

    def test_archive_uses_captured_definition_after_team_moves_to_another_cohort(self):
        submission = self._add_submission('1st Year', 0)
        PitEventDeliverable.objects.filter(pk=self.definitions['2nd Year'].pk).update(file_policy={})
        StudentTeam.objects.filter(pk=submission.team_id).update(
            year_level='2nd Year', level=StudentTeam.LEVEL_2_PIT,
        )
        DeliverableSubmissionFile.objects.filter(submission=submission).update(status='rejected')
        self.client.force_authenticate(user=self.leads['1st Year'])
        payload, _ = self._read()
        self.assertEqual(payload['entries'][0]['year_level'], '1st Year')
        self.assertEqual(payload['entries'][0]['status'], 'Needs Revision')
        self.assertEqual(payload['entries'][0]['pit_event_config_id'], self.events['1st Year'].pk)
